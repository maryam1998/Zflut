import '../data/paid_content.dart';
import '../usage/pro_status.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/slang_topics.dart';
import '../constants/vocab_topics.dart';
import '../data/word_asset_loader.dart';
import '../models/daily_word.dart';
import '../models/filter_state.dart';
import 'words_filter_provider.dart';

/// منبع‌های داده‌ی جدا برای تب‌های «اسلنگ» و «Vocabulary in Use»
/// (قبلاً هر دو لیست «لغات روزمره» را نشان می‌دادند).
/// فایل‌ها با scripts/convert-data.mjs از hope_data/*.js ساخته می‌شوند.
Future<List<DailyWord>> _loadWords(String asset, String paidList) =>
    loadWordsAsset(asset, paidList: paidList);

// 💎 فایلِ داخلِ اپ فقط ۳۰ لغتِ رایگان دارد؛ Pro بقیه را از Worker (کش‌شده) می‌گیرد
final slangWordsProvider = FutureProvider<List<DailyWord>>((ref) {
  ref.watch(isProProvider);
  ref.watch(paidRevisionProvider);
  return _loadWords('assets/data/slang_words.json', 'slang');
});

final vocabInUseWordsProvider = FutureProvider<List<DailyWord>>((ref) {
  ref.watch(isProProvider);
  ref.watch(paidRevisionProvider);
  return _loadWords('assets/data/vocab_in_use_words.json', 'vocab');
});

List<DailyWord> _applyFilter(List<DailyWord> all, WordsFilterState f) {
  final q = f.query.trim().toLowerCase();
  if (f.levels.isEmpty && q.isEmpty) return all;
  return all.where((w) {
    if (!f.matchesLevel(w.level)) return false;
    if (q.isNotEmpty &&
        !w.en.toLowerCase().contains(q) &&
        !w.fa.contains(q)) {
      return false;
    }
    return true;
  }).toList(growable: false);
}

/// موضوع‌های انتخاب‌شده در «Slang» (خالی = همه)
final slangTopicProvider = StateProvider<Set<String>>((ref) => const <String>{});

final filteredSlangWordsProvider = Provider<List<DailyWord>>((ref) {
  final all = ref.watch(slangWordsProvider).valueOrNull ?? const <DailyWord>[];
  final base = _applyFilter(all, ref.watch(wordsFilterProvider));
  final sel = ref.watch(slangTopicProvider);
  if (sel.isEmpty) return base;
  return base.where((w) => sel.contains(w.category)).toList(growable: false);
});

/// موضوع‌های اصلیِ انتخاب‌شده در «Vocabulary in Use» (خالی = همه)
final vocabTopicProvider = StateProvider<Set<String>>((ref) => const <String>{});

/// دسته‌ی ریزِ انتخاب‌شده داخلِ موضوع (null = همه‌ی دسته‌های آن موضوع)
final vocabCategoryProvider = StateProvider<String?>((ref) => null);

final filteredVocabInUseWordsProvider = Provider<List<DailyWord>>((ref) {
  final all =
      ref.watch(vocabInUseWordsProvider).valueOrNull ?? const <DailyWord>[];
  var base = _applyFilter(all, ref.watch(wordsFilterProvider));
  final sel = ref.watch(vocabTopicProvider);
  if (sel.isEmpty) return base;
  final cat = ref.watch(vocabCategoryProvider);
  // دسته‌ی ریز فقط وقتی دقیقاً یک موضوع انتخاب شده معنی دارد
  if (sel.length == 1 && cat != null) {
    final t = vocabTopicByKey(sel.first);
    if (t != null && t.categories.contains(cat)) {
      return base.where((w) => w.category == cat).toList(growable: false);
    }
  }
  final set = <String>{};
  for (final k in sel) {
    final t = vocabTopicByKey(k);
    if (t != null) set.addAll(t.categories);
  }
  return base.where((w) => set.contains(w.category)).toList(growable: false);
});
