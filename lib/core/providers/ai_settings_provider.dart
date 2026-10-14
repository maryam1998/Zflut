import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/local_storage.dart';
import '../translate/translation_service.dart';

const String _kBackendUrlKey = 'phrasebook-backend-url';

class AiSettingsNotifier extends StateNotifier<AiSettings> {
  final SharedPreferences _prefs;

  AiSettingsNotifier(this._prefs)
      : super(AiSettings(backendUrl: _prefs.getString(_kBackendUrlKey) ?? ''));

  Future<void> setBackendUrl(String url) async {
    final clean = url.trim().replaceAll(RegExp(r'/+$'), '');
    await _prefs.setString(_kBackendUrlKey, clean);
    state = AiSettings(backendUrl: clean);
  }
}

final aiSettingsProvider =
    StateNotifierProvider<AiSettingsNotifier, AiSettings>((ref) {
  return AiSettingsNotifier(ref.watch(sharedPrefsProvider));
});
