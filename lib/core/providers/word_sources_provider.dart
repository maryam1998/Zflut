import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/vocab_topics.dart';
import '../data/word_asset_loader.dart';
import '../models/daily_word.dart';
import '../models/filter_state.dart';
import 'words_filter_provider.dart';

/// منبع‌های داده‌ی جدا برای تب‌های «اسلنگ» و «Vocabulary in Use»
/// (قبلاً هر دو لیست «لغات روزمره» را نشان می‌دادند).
/// فایل‌ها با scripts/convert-data.mjs از hope_data/*.js ساخته می‌شوند.
Future<List<DailyWord>> _loadWords(String asset) => loadWordsAsset(asset);

final slangWordsProvider = FutureProvider<List<DailyWord>>(
    (ref) => _loadWords('assets/data/slang_words.json'));

final vocabInUseWordsProvider = FutureProvider<List<DailyWord>>(
    (ref) => _loadWords('assets/data/vocab_in_use_words.json'));

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

final filteredSlangWordsProvider = Provider<List<DailyWord>>((ref) {
  final all = ref.watch(slangWordsProvider).valueOrNull ?? const <DailyWord>[];
  return _applyFilter(all, ref.watch(wordsFilterProvider));
});

/// موضوعِ اصلیِ انتخاب‌شده در «Vocabulary in Use» (null = همه)
final vocabTopicProvider = StateProvider<String?>((ref) => null);

/// دسته‌ی ریزِ انتخاب‌شده داخلِ موضوع (null = همه‌ی دسته‌های آن موضوع)
final vocabCategoryProvider = StateProvider<String?>((ref) => null);

final filteredVocabInUseWordsProvider = Provider<List<DailyWord>>((ref) {
  final all =
      ref.watch(vocabInUseWordsProvider).valueOrNull ?? const <DailyWord>[];
  var base = _applyFilter(all, ref.watch(wordsFilterProvider));
  final topic = vocabTopicByKey(ref.watch(vocabTopicProvider));
  if (topic == null) return base;
  final cat = ref.watch(vocabCategoryProvider);
  if (cat != null && topic.categories.contains(cat)) {
    return base.where((w) => w.category == cat).toList(growable: false);
  }
  final set = topic.categories.toSet();
  return base.where((w) => set.contains(w.category)).toList(growable: false);
});
