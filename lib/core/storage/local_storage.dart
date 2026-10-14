import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'prefs_keys.dart';

/// لایه‌ی نازک روی SharedPreferences که JSON encode/decode و پیش‌فرض‌ها را
/// یک‌جا انجام می‌دهد. پوشش IndexedDB در فازهای بعدی با drift/isar اضافه می‌شود.
class LocalStorage {
  final SharedPreferences _sp;
  LocalStorage(this._sp);

  Map<String, dynamic> readJson(String key) {
    final raw = _sp.getString(key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> writeJson(String key, Map<String, dynamic> value) {
    return _sp.setString(key, jsonEncode(value));
  }

  String? readString(String key) => _sp.getString(key);
  Future<void> writeString(String key, String value) => _sp.setString(key, value);

  bool containsKey(String key) => _sp.containsKey(key);
  Future<void> remove(String key) => _sp.remove(key);
}

/// این provider در main.dart با نمونه‌ی واقعی override می‌شود.
final sharedPrefsProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPrefsProvider must be overridden in main()');
});

final localStorageProvider = Provider<LocalStorage>((ref) {
  return LocalStorage(ref.watch(sharedPrefsProvider));
});

/// دسترسی مستقیم به کلیدهای prefs (فقط برای خوانایی).
class PrefsKeysRef {
  static const String appPrefs = PrefsKeys.appPrefs;
  static const String textPrefs = PrefsKeys.targetTextPrefs;
  static const String voicePrefs = PrefsKeys.voicePrefs;
}
