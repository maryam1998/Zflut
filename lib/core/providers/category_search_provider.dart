import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/daily_word.dart';
import '../models/filter_state.dart';
import 'word_sources_provider.dart';
import 'words_filter_provider.dart';

/// 🔎 نتیجه‌ی جستجو روی «همه‌ی دسته‌ها» (فقط فیلترِ سطح + متنِ جستجو؛ بدونِ فیلترِ دسته).
/// وقتی کاربر در تبِ Slang / Vocab in use چیزی جستجو می‌کند، شبکه‌ی دسته‌ها کنار می‌رود
/// و نتیجه‌ها از همه‌ی دسته‌ها نشان داده می‌شود.
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

final slangSearchAllProvider = Provider<List<DailyWord>>((ref) {
  final all = ref.watch(slangWordsProvider).valueOrNull ?? const <DailyWord>[];
  return _applyFilter(all, ref.watch(wordsFilterProvider));
});

final vocabSearchAllProvider = Provider<List<DailyWord>>((ref) {
  final all =
      ref.watch(vocabInUseWordsProvider).valueOrNull ?? const <DailyWord>[];
  return _applyFilter(all, ref.watch(wordsFilterProvider));
});
