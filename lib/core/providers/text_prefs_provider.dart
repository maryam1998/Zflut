import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/text_prefs.dart';
import '../storage/local_storage.dart';
import '../storage/prefs_keys.dart';

class TextPrefsNotifier extends StateNotifier<TargetTextPrefs> {
  final LocalStorage _storage;

  TextPrefsNotifier(this._storage)
      : super(TargetTextPrefs.fromJson(
          _storage.readJson(PrefsKeys.targetTextPrefs),
        ));

  Future<void> _persist(TargetTextPrefs next) async {
    state = next;
    await _storage.writeJson(PrefsKeys.targetTextPrefs, next.toJson());
  }

  Future<void> setScale(int scale) =>
      _persist(TargetTextPrefs(scale: scale.clamp(50, 250), bold: state.bold));

  Future<void> setBold(TargetBoldMode mode) =>
      _persist(TargetTextPrefs(scale: state.scale, bold: mode));
}

final textPrefsProvider =
    StateNotifierProvider<TextPrefsNotifier, TargetTextPrefs>((ref) {
  return TextPrefsNotifier(ref.watch(localStorageProvider));
});
