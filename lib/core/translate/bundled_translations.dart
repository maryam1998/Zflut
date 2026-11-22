// 📁 مسیر: lib/core/translate/bundled_translations.dart
//
// ترجمه‌های «داخلِ اپ» برای محتوای رایگان (جمله‌های Talk، لغاتِ رایگان و مثال‌هایشان) به همه‌ی زبان‌ها.
// فایل: assets/data/free_translations.json — ترجمه‌ها با مدلِ قوی از قبل ساخته شده‌اند،
// پس بدونِ شبکه، بدونِ AI و بدونِ کشِ D1 فوراً نمایش داده می‌شوند.
// (ترجمه‌ی قفل‌شده‌ی کاربر همچنان مقدم است؛ این‌ها فقط جای ترجمه‌ی ماشینی/AI را می‌گیرند.)

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class BundledTranslations {
  BundledTranslations._();

  static const String _asset = 'assets/data/free_translations.json';
  static Map<String, Map<String, String>> _m = {};
  static Future<void>? _loading;
  static bool _loaded = false;

  /// بعد از پایانِ بارگذاری (حتی اگر فایل نبود) true می‌شود.
  static bool get isLoaded => _loaded;

  static String _norm(String s) {
    var t = s
        .replaceAll('\u2019', "'")
        .replaceAll('\u2018', "'")
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    t = t.replaceAll(RegExp(r'[.!?…]+$'), '').trim();
    return t;
  }

  /// یک‌بار بارگذاری می‌شود؛ چندبار صدا زدن مشکلی ندارد.
  static Future<void> ensureLoaded() => _loading ??= _load();

  static Future<void> _load() async {
    try {
      final raw = await rootBundle.loadString(_asset);
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final t = (j['t'] as Map<String, dynamic>?) ?? const {};
      final m = <String, Map<String, String>>{};
      t.forEach((en, v) {
        final per = <String, String>{};
        (v as Map<String, dynamic>).forEach((lang, s) {
          final x = (s as String).trim();
          if (x.isNotEmpty) per[lang] = x;
        });
        m[_norm(en)] = per;
      });
      _m = m;
    } catch (_) {
      _m = {}; // نبودنِ فایل فقط یعنی «ترجمه‌ی آماده‌ای نیست»
    } finally {
      _loaded = true;
    }
  }

  /// خواندنِ همگام. فقط برای مبدأ انگلیسی (en/auto/خالی).
  static String? get(String text, String from, String to) {
    if (_m.isEmpty) return null;
    if (from.isNotEmpty && from != 'auto' && from != 'en') return null;
    final per = _m[_norm(text)];
    return per?[to];
  }
}
