import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/language_selection.dart';
import '../storage/local_storage.dart';
import '../storage/prefs_keys.dart';

class LanguageSelectionNotifier extends StateNotifier<LanguageSelection> {
  final LocalStorage _storage;

  LanguageSelectionNotifier(this._storage) : super(_read(_storage));

  static LanguageSelection _read(LocalStorage s) {
    final json = s.readJson(PrefsKeys.languageSelection);
    return LanguageSelection.fromJson(json);
  }

  Future<void> _persist(LanguageSelection next) async {
    state = next;
    await _storage.writeJson(PrefsKeys.languageSelection, next.toJson());
  }

  /// زبان مادری — تک‌انتخابی.
  Future<void> setNative(String code) =>
      _persist(state.copyWith(native: code));

  /// تاگل یک زبان مقصد.
  Future<void> toggleTarget(String code) {
    final list = [...state.targets];
    if (list.contains(code)) {
      // همیشه حداقل یک زبان مقصد بمونه.
      if (list.length > 1) list.remove(code);
    } else {
      list.add(code);
    }
    return _persist(state.copyWith(targets: list));
  }

  /// حذف صریح یک زبان مقصد (از X چیپ).
  Future<void> removeTarget(String code) {
    final list = [...state.targets]..remove(code);
    if (list.isEmpty) list.add('en');
    return _persist(state.copyWith(targets: list));
  }

  /// جابجایی ترتیب زبان‌های مقصد (drag).
  Future<void> reorderTargets(int oldIndex, int newIndex) {
    final list = [...state.targets];
    if (newIndex > oldIndex) newIndex -= 1;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    return _persist(state.copyWith(targets: list));
  }
}

final languageSelectionProvider =
    StateNotifierProvider<LanguageSelectionNotifier, LanguageSelection>((ref) {
  return LanguageSelectionNotifier(ref.watch(localStorageProvider));
});

/// نگاشت کد → نام فارسی.
String langFaName(String code) {
  switch (code) {
    case 'fa': return 'فارسی';
    case 'en': return 'انگلیسی';
    case 'ar': return 'عربی';
    case 'de': return 'آلمانی';
    case 'es': return 'اسپانیایی';
    case 'fr': return 'فرانسوی';
    case 'it': return 'ایتالیایی';
    case 'ru': return 'روسی';
    case 'tr': return 'ترکی';
    case 'hi': return 'هندی';
    case 'zh': return 'چینی';
    case 'ja': return 'ژاپنی';
    case 'ko': return 'کره‌ای';
    default:   return code.toUpperCase();
  }
}
