// 📁 مسیر: lib/core/translate/romanization.dart
//
// 🔤 رومی‌سازی (خوانشِ لاتین) برای ترجمه‌های هندی، چینی، ژاپنی، کره‌ای و روسی.
//
// دو منبع دارد:
//   ۱) assets/data/free_romanization.json — برای محتوای ثابتِ اپ (خروجیِ scripts/romanize-static.py)
//   ۲) فیلدِ roman (تک) / romans (دسته‌ای) در پاسخِ Worker — برای ترجمه‌های زنده؛ در حافظه + SharedPreferences می‌ماند
//
// کلیدِ جستجو «زبان + خودِ متنِ ترجمه‌شده» است (نه متنِ انگلیسی)؛ پس اگر کاربر ترجمه را با ↻ عوض کند،
// رومی‌سازیِ قدیمی خودبه‌خود کنار می‌رود و رومی‌سازیِ اشتباه نشان داده نمی‌شود.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

class Romanization {
  Romanization._();

  /// زبان‌هایی که رومی‌سازی دارند.
  static const Set<String> langs = {'hi', 'zh', 'ja', 'ko', 'ru'};

  static const String _assetRoman = 'assets/data/free_romanization.json';
  static const String _assetTr = 'assets/data/free_translations.json';
  static const String _prefsKey = 'roman_cache_v1';
  static const int _maxEntries = 3000;

  /// زبانِ بومیِ کاربر. با تغییرِ انتخابِ زبان به‌روز می‌شود (language_selection_provider.dart).
  /// اگر زبانِ مقصد همین باشد رومی‌سازی نشان داده نمی‌شود.
  static String nativeCode = '';

  /// فیلدی که به بدنه‌ی درخواست‌های Worker اضافه می‌شود: `...Romanization.nativeField`
  static Map<String, String> get nativeField =>
      nativeCode.isEmpty ? const <String, String>{} : {'native_lang_code': nativeCode};

  static final Map<String, Map<String, String>> _byEnglish = {};
  static final Map<String, String> _byTranslated = {}; // «lang|متنِ ترجمه» ← رومی (ثابت)
  static final Map<String, String> _mem = <String, String>{}; // پاسخ‌های Worker (به ترتیبِ تازگی)
  static Future<void>? _loading;
  static bool _loaded = false;
  static Timer? _saveTimer;

  static bool get isLoaded => _loaded;

  static String _normEn(String s) {
    var t = s
        .replaceAll('\u2019', "'")
        .replaceAll('\u2018', "'")
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    t = t.replaceAll(RegExp(r'[.!?…]+$'), '').trim();
    return t;
  }

  static String _key(String lang, String text) {
    final t = text
        .replaceAll(RegExp('[\u2066-\u2069]'), '')
        .replaceAll(RegExp("^[\"'«»“”\\s]+|[\"'«»“”\\s]+\$"), '')
        .replaceAll(RegExp(r'\s+'), ' ');
    return '$lang|$t';
  }

  /// یک‌بار بارگذاری می‌شود؛ چندبار صدا زدن مشکلی ندارد. نبودنِ فایل فقط یعنی «رومی‌سازیِ آماده‌ای نیست».
  static Future<void> ensureLoaded() => _loading ??= _load();

  static Future<void> _load() async {
    try {
      final raw = await rootBundle.loadString(_assetRoman);
      final j = jsonDecode(raw);
      final r = j is Map ? j['r'] : null;
      if (r is Map) {
        r.forEach((en, v) {
          if (v is! Map) return;
          final per = <String, String>{};
          v.forEach((l, s) {
            if (l is String && s is String && s.trim().isNotEmpty) {
              per[l] = s.trim();
            }
          });
          if (per.isNotEmpty) _byEnglish[_normEn(en.toString())] = per;
        });
      }
      // فهرستِ معکوس: متنِ ترجمه‌شده ← رومی (از روی free_translations.json)
      if (_byEnglish.isNotEmpty) {
        try {
          final jt = jsonDecode(await rootBundle.loadString(_assetTr));
          final t = jt is Map ? jt['t'] : null;
          if (t is Map) {
            t.forEach((en, v) {
              final per = _byEnglish[_normEn(en.toString())];
              if (per == null || v is! Map) return;
              per.forEach((lang, rom) {
                final tr = v[lang];
                if (tr is String && tr.trim().isNotEmpty) {
                  _byTranslated[_key(lang, tr)] = rom;
                }
              });
            });
          }
        } catch (_) {}
      }
    } catch (_) {
      // فایل نبود/خراب بود → فقط رومی‌سازیِ Worker
    }
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString(_prefsKey);
      if (s != null && s.isNotEmpty) {
        final m = jsonDecode(s);
        if (m is Map) {
          m.forEach((k, v) {
            if (k is String && v is String && !_mem.containsKey(k)) _mem[k] = v;
          });
        }
      }
    } catch (_) {}
    _loaded = true;
  }

  /// خوانشِ لاتینِ [text] (ترجمه به [lang]) یا null. همگام است.
  static String? lookup(String lang, String text, {String? native}) {
    if (!langs.contains(lang)) return null;
    if (lang == (native ?? nativeCode)) return null; // زبانِ خودش را می‌خواند
    final t = text.trim();
    if (t.isEmpty) return null;
    final k = _key(lang, t);
    final r = _mem[k] ?? _byTranslated[k];
    if (r == null || r.trim().isEmpty) return null;
    return r;
  }

  /// پاسخِ /api/translate-text: {text, roman?}
  static void ingestSingle(String lang, dynamic data) {
    if (data is! Map) return;
    _put(lang, data['text'], data['roman']);
  }

  /// پاسخِ /api/translate-batch: {results:[...], romans?:[...]} (هم‌طول)
  static void ingestBatch(String lang, dynamic data) {
    if (data is! Map) return;
    final res = data['results'];
    final rom = data['romans'];
    if (res is! List || rom is! List || res.length != rom.length) return;
    for (var i = 0; i < res.length; i++) {
      _put(lang, res[i], rom[i]);
    }
  }

  static void _put(String lang, dynamic text, dynamic roman) {
    if (!langs.contains(lang) || text is! String || roman is! String) return;
    final r = roman.trim();
    if (r.isEmpty || text.trim().isEmpty) return;
    final k = _key(lang, text);
    _mem.remove(k);
    _mem[k] = r;
    while (_mem.length > _maxEntries) {
      _mem.remove(_mem.keys.first);
    }
    _scheduleSave();
  }

  static void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 3), () async {
      try {
        final p = await SharedPreferences.getInstance();
        await p.setString(_prefsKey, jsonEncode(_mem));
      } catch (_) {}
    });
  }
}
