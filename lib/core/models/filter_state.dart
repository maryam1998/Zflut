import 'package:flutter/foundation.dart';

import '../../l10n/app_localizations.dart';

enum SortMode {
  defaultOrder,   // پیش‌فرض
  alphabetical,   // الفبایی
  byLevel,        // بر اساس سطح
  recent,         // اخیراً
}

extension SortModeX on SortMode {
  String get faLabel {
    switch (this) {
      case SortMode.defaultOrder: return 'پیش‌فرض';
      case SortMode.alphabetical: return 'الفبایی';
      case SortMode.byLevel:      return 'سطح (A→C)';
      case SortMode.recent:       return 'اخیراً اضافه‌شده';
    }
  }
}

extension SortModeL10n on SortMode {
  /// برچسبِ محلی‌شده (فارسی/انگلیسی/...) بر اساس زبانِ رابط
  String label(AppLocalizations L) {
    switch (this) {
      case SortMode.defaultOrder: return L.sort_default;
      case SortMode.alphabetical: return L.sort_name_asc;
      case SortMode.byLevel:      return L.sort_level_asc;
      case SortMode.recent:       return L.sort_recent;
    }
  }
}

@immutable
class WordsFilterState {
  /// سطح‌های انتخاب‌شده — خالی = «همه سطوح»؛ وگرنه هر تعداد از A1..C2
  final Set<String> levels;

  /// متن جستجو (خالی = بدون فیلتر)
  final String query;

  /// حالت مرتب‌سازی
  final SortMode sort;

  const WordsFilterState({
    this.levels = const <String>{},
    this.query = '',
    this.sort = SortMode.defaultOrder,
  });

  /// آیا سطحِ [l] با فیلترِ فعلی می‌خواند؟ (فیلتر خالی = همه)
  bool matchesLevel(String l) => levels.isEmpty || levels.contains(l);

  /// امضای متنیِ سطح‌ها (برای تشخیصِ تغییر)
  String get levelsSig => (levels.toList()..sort()).join(',');

  WordsFilterState copyWith({
    Set<String>? levels,
    String? query,
    SortMode? sort,
  }) {
    return WordsFilterState(
      levels: levels ?? this.levels,
      query: query ?? this.query,
      sort: sort ?? this.sort,
    );
  }
}
