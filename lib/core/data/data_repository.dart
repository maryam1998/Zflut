import '../models/filter_state.dart';
import '../models/word_entry.dart';

/// مخزن داده‌ها — فعلاً خالی. در فاز بعد با خواندن JSON از assets پر می‌شود.
///
/// ساختار داده‌ی آینده:
///   assets/data/words.json       → لیست WordEntry
///   assets/data/conversations.json
///   assets/data/vocab_in_use.json
///   assets/data/slang.json
class DataRepository {
  DataRepository._();
  static final DataRepository instance = DataRepository._();

  List<WordEntry> _words = const [];
  bool _loaded = false;

  bool get isLoaded => _loaded;
  int get wordsCount => _words.length;

  /// این تابع بعداً از rootBundle می‌خواند.
  Future<void> load() async {
    // TODO(data): rootBundle.loadString('assets/data/words.json')
    // _words = ...;
    _loaded = true;
  }

  /// فیلتر کردن روی لیست فعلی.
  List<WordEntry> filterWords(WordsFilterState filter) {
    var list = [..._words];

    // سطح
    if (filter.level != 'all') {
      list = list.where((w) => w.level == filter.level).toList();
    }

    // جستجو
    if (filter.query.trim().isNotEmpty) {
      final q = filter.query.trim().toLowerCase();
      list = list.where((w) =>
          w.en.toLowerCase().contains(q) ||
          w.fa.contains(q) ||
          w.translations.values.any((t) => t.toLowerCase().contains(q))
      ).toList();
    }

    // مرتب‌سازی
    switch (filter.sort) {
      case SortMode.defaultOrder:
        break;
      case SortMode.alphabetical:
        list.sort((a, b) => a.en.compareTo(b.en));
        break;
      case SortMode.byLevel:
        list.sort((a, b) => a.level.compareTo(b.level));
        break;
      case SortMode.recent:
        break;
    }

    return list;
  }
}
