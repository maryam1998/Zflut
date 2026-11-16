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

  static void _noteMiss(String from, String to, String t) {
    if (_missed.length > 5000) _missed.clear();
    _missed.add(_mk(from, to, t));
  }

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

  // مواردی که در این نشست در کشِ مشترک نبودند؛ دوباره نپرس
  static final Set<String> _missed = {};
  static String _mk(String from, String to, String t) =>
      '${_src(from)}>$to|${t.trim()}';

  // 📦 درخواست‌های هم‌زمانِ تک‌متنی (لغت‌های یک صفحه) ۴۰ میلی‌ثانیه جمع و در «یک» درخواستِ /api/tr-share فرستاده می‌شوند
  // (هر درخواستِ Worker یک ردیفِ نوشتنِ D1 برای شمارنده‌ی سهمیه مصرف می‌کند؛ دسته‌ای = ارزان‌تر).
  static final Map<String, _PendingBatch> _pending = {};

  /// یک متن (برای مسیرِ عمومیِ ترجمه در همه‌ی تب‌ها). null = نبود/نشد.
  static Future<String?> fetchOne(
      String baseUrl, String from, String to, String text) {
    final t = text.trim();
    if (!eligible(t) || !RegExp(r'\p{L}', unicode: true).hasMatch(t)) {
      return Future<String?>.value(null);
    }
    if (_missed.contains(_mk(from, to, t))) return Future<String?>.value(null);
    final key = '$baseUrl|${_src(from)}|$to';
    final b = _pending.putIfAbsent(key, () => _PendingBatch(baseUrl, from, to));
    final c = Completer<String?>();
    b.waiters.putIfAbsent(t, () => <Completer<String?>>[]).add(c);
    if (b.waiters.length >= _kBatch) {
      b.timer?.cancel();
      unawaited(_flush(key));
    } else {
      b.timer ??= Timer(const Duration(milliseconds: 40), () => _flush(key));
    }
    return c.future;
  }

  static Future<void> _flush(String key) async {
    final b = _pending.remove(key);
    if (b == null) return;
    b.timer?.cancel();
    var found = <String, String>{};
    try {
      found = await fetchMany(b.baseUrl, b.from, b.to, b.waiters.keys.toList(),
          quick: true);
    } catch (_) {}
    for (final e in b.waiters.entries) {
      final v = found[e.key];
      for (final c in e.value) {
        if (!c.isCompleted) c.complete(v);
      }
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
    List<String> texts, {
    bool quick = false,
  }) async {
    final out = <String, String>{};
    if (to.isEmpty || _paused()) return out;
    final list = texts
        .where(eligible)
        .where((t) => !_missed.contains(_mk(from, to, t)))
        .toSet()
        .toList();
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
        ).timeout(Duration(seconds: quick ? 3 : 10));
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
          final src = chunk[k].trim();
          if (r is! String) {
            _noteMiss(from, to, src);
            continue;
          }
          final tr = r.trim();
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
    _missed.remove(_mk(from, to, src));
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

class _PendingBatch {
  _PendingBatch(this.baseUrl, this.from, this.to);
  final String baseUrl;
  final String from;
  final String to;
  final Map<String, List<Completer<String?>>> waiters = {};
  Timer? timer;
}
