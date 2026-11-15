// 📁 مسیر: lib/core/translate/shared_translations.dart
//
// کشِ مشترکِ ترجمه‌های «اصلاح‌شده» بین همه‌ی کاربران (سمتِ Worker: /api/tr-share).
//  • fetchMany: چند جمله را یک‌جا از کشِ مشترک می‌پرسد (یک درخواست برای هر ۴۰ مورد)
//  • share: ترجمه‌ای که کاربر با ↻ اصلاح کرده را برای بقیه ذخیره می‌کند
// هیچ‌کدام exception نمی‌دهند؛ هر خطا = «چیزی پیدا نشد» و مسیرِ عادیِ ترجمه ادامه می‌یابد.
// همان سقفِ ۳۰۰ نویسه‌ی کشِ مشترکِ قبلی: متنِ بلندِ کاربر هرگز به سرور نمی‌رود.

import 'dart:async';

import 'package:dio/dio.dart';

import '../auth/worker_auth.dart';
import 'translation_service.dart' show looksLikelyMistranslated;

const int _kMaxChars = 300;
const int _kBatch = 40;

class SharedTranslations {
  SharedTranslations._();

  static final Dio _dio = _make();

  static Dio _make() {
    final d = Dio(BaseOptions(
      validateStatus: (_) => true,
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 8),
      sendTimeout: const Duration(seconds: 6),
    ));
    d.interceptors.add(WorkerAuthInterceptor(d));
    return d;
  }

  // اگر سرور/شبکه پشتِ‌هم خراب بود چند دقیقه صدا نزن (ترجمه را کند نکند)
  static int _fails = 0;
  static int _pausedUntil = 0;

  static bool _paused() =>
      DateTime.now().millisecondsSinceEpoch < _pausedUntil;

  static void _ok() => _fails = 0;

  static void _bad() {
    _fails++;
    if (_fails >= 2) {
      _pausedUntil =
          DateTime.now().millisecondsSinceEpoch + 2 * 60 * 1000;
      _fails = 0;
    }
  }

  static bool eligible(String text) {
    final t = text.trim();
    return t.isNotEmpty && t.length <= _kMaxChars;
  }

  static String _src(String from) => from.isEmpty ? 'auto' : from;

  /// متنِ اصلی ← ترجمه، فقط برای مواردی که در کشِ مشترک بودند.
  static Future<Map<String, String>> fetchMany(
    String baseUrl,
    String from,
    String to,
    List<String> texts,
  ) async {
    final out = <String, String>{};
    if (to.isEmpty || _paused()) return out;
    final list = texts.where(eligible).toSet().toList();
    for (var i = 0; i < list.length; i += _kBatch) {
      if (_paused()) break;
      final chunk = list.sublist(
          i, i + _kBatch > list.length ? list.length : i + _kBatch);
      try {
        final res = await _dio.post(
          '$baseUrl/api/tr-share',
          data: {
            'op': 'get',
            'source_lang_code': _src(from),
            'target_lang_code': to,
            'items': [for (final t in chunk) {'text': t.trim()}],
          },
          options: Options(contentType: 'application/json'),
        ).timeout(const Duration(seconds: 10));
        final status = res.statusCode ?? 0;
        if (status < 200 || status >= 300) {
          _bad();
          continue;
        }
        _ok();
        final data = res.data;
        final results = data is Map ? data['results'] : null;
        if (results is! List) continue;
        for (var k = 0; k < chunk.length && k < results.length; k++) {
          final r = results[k];
          if (r is! String) continue;
          final tr = r.trim();
          final src = chunk[k].trim();
          if (tr.isEmpty || tr.toLowerCase() == src.toLowerCase()) continue;
          if (looksLikelyMistranslated(src, tr, to, sourceLang: from)) {
            continue;
          }
          out[chunk[k]] = tr;
        }
      } catch (_) {
        _bad();
      }
    }
    return out;
  }

  /// ذخیره‌ی ترجمه‌ی اصلاح‌شده برای بقیه (fire-and-forget).
  static void share(
      String baseUrl, String text, String from, String to, String tr) {
    final src = text.trim();
    final t = tr.trim();
    if (!eligible(src) || t.isEmpty || to.isEmpty || _paused()) return;
    if (t.toLowerCase() == src.toLowerCase()) return;
    if (looksLikelyMistranslated(src, t, to, sourceLang: from)) return;
    unawaited(() async {
      try {
        final res = await _dio.post(
          '$baseUrl/api/tr-share',
          data: {
            'op': 'put',
            'source_lang_code': _src(from),
            'target_lang_code': to,
            'text': src,
            'translation': t,
          },
          options: Options(contentType: 'application/json'),
        ).timeout(const Duration(seconds: 10));
        final status = res.statusCode ?? 0;
        if (status >= 200 && status < 300) {
          _ok();
        } else if (status >= 500 || status == 401) {
          _bad();
        }
      } catch (_) {
        _bad();
      }
    }());
  }
}
