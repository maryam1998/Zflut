import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/language_selection.dart';
import '../storage/local_storage.dart';
import '../storage/prefs_keys.dart';

class LanguageSelectionNotifier extends StateNotifier<LanguageSelection> {
  final LocalStorage _storage;

  LanguageSelectionNotifier(this._storage)
      : super(_read(_storage));

  static LanguageSelection _read(LocalStorage s) {
    final json = s.readJson(PrefsKeys.languageSelection);
    return LanguageSelection.fromJson(json);
  }

  Future<void> _persist(LanguageSelection next) async {
    state = next;
    await _storage.writeJson(PrefsKeys.languageSelection, next.toJson());
  }

  Future<void> setNative(String code) =>
      _persist(state.copyWith(native: code));

  Future<void> setPrimaryTarget(String code) =>
      _persist(state.copyWith(targets: [code]));

  Future<void> toggleTarget(String code) {
    final list = [...state.targets];
    if (list.contains(code)) {
      if (list.length > 1) list.remove(code);
    } else {
      list.add(code);
    }
    return _persist(state.copyWith(targets: list));
  }
}

final languageSelectionProvider =
    StateNotifierProvider<LanguageSelectionNotifier, LanguageSelection>((ref) {
  return LanguageSelectionNotifier(ref.watch(localStorageProvider));
});
