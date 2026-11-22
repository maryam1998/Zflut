// 📁 مسیر: lib/core/translate/ai_first_translator.dart
//
// ترجمه‌ی «اول AI» برای تب مکالمه (Talk). کاربر هیچ‌چیز متوجه نمی‌شود:
//
//   ۱. 📌 ترجمه‌ی قفل‌شده‌ی کاربر (↻) همیشه مقدم است.
//   ۲. 💾 اگر ترجمه‌ی AI قبلاً روی همین گوشی ذخیره شده («نشانه‌ی نهایی») → همان، بدون شبکه
//      (بعد از آپدیت اپ هم می‌ماند؛ در همان دیتابیسِ کشِ ترجمه است).
//   ۳. 🗄️ کشِ مشترکِ سرور (D1): اگر کاربرِ دیگری قبلاً گرفته → رایگان و بدون AI.
//   ۴. 🤖 AI (/api/translate-text؛ Worker خودش نتیجه را در D1 برای همه ذخیره می‌کند).
//   ۵. ⏱️ اگر AI تا ~۰٫۹ ثانیه جواب نداد، موقتاً ML Kit/آنلاین نشان داده می‌شود؛
//      وقتی AI رسید بی‌صدا جایگزین می‌شود. اگر AI خطا داد، در پس‌زمینه خودکار دوباره تلاش می‌شود.
//
// این فایل فقط از API عمومیِ TranslationService / SharedTranslations / TranslationCacheDb استفاده می‌کند
// و به هیچ بخشِ دیگری دست نمی‌زند. بقیه‌ی تب‌ها مثل قبل کار می‌کنند.

import 'dart:async';

import 'package:dio/dio.dart';

import '../auth/worker_auth.dart';
import '../storage/translation_cache_db.dart';
import 'shared_translations.dart';
import 'translation_service.dart';

const int _kMaxChars = 300; // سقفِ Worker برای /api/translate-text
const int _kAiConcurrency = 4; // هم‌زمانیِ درخواست‌های AI از این گوشی
const int _kProvConcurrency = 3; // هم‌زمانیِ ترجمه‌ی موقت (ML Kit/آنلاین)
const Duration _kGrace = Duration(milliseconds: 900);
// تلاش‌های خودکارِ پس‌زمینه: اول سریع (کاربر منتظر است)، بعد کم‌کم کندتر
const List<Duration> _kRetryDelays = <Duration>[
  Duration(seconds: 3),
  Duration(seconds: 8),
  Duration(seconds: 20),
  Duration(seconds: 45),
  Duration(seconds: 90),
  Duration(minutes: 3),
  Duration(minutes: 6),
  Duration(minutes: 10),
];

// ─── پاک‌سازیِ ترجمه‌ی موقت (ML Kit / MyMemory) ───
// MyMemory گاهی «&#10;» و «&quot;» برمی‌گرداند یا جمله‌ی بی‌ربطِ دیگری (مثلاً از ترجمه‌ی کاربران).
String _decodeEntities(String s) {
  String once(String x) {
    var t = x.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final c = int.tryParse(m[1]!);
      return (c == null || c <= 0 || c > 0x10FFFF) ? ' ' : String.fromCharCode(c);
    });
    t = t.replaceAllMapped(RegExp(r'&#[xX]([0-9a-fA-F]+);'), (m) {
      final c = int.tryParse(m[1]!, radix: 16);
      return (c == null || c <= 0 || c > 0x10FFFF) ? ' ' : String.fromCharCode(c);
    });
    return t
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&');
  }

  return once(once(s)); // دوبار: «&amp;#10;» هم درست شود
}

String _tidy(String s) =>
    _decodeEntities(s).replaceAll(RegExp(r'\s+'), ' ').trim();

const Set<String> _kNonLatinTargets = {
  'fa', 'ar', 'hi', 'zh', 'ko', 'ru', 'ja',
};

// واژه‌های بزرگ‌حرفی که نامِ شخص نیستند و در زبانِ مقصد عوض می‌شوند
const Set<String> _kNotNames = {
  'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday',
  'january', 'february', 'march', 'april', 'may', 'june', 'july', 'august',
  'september', 'october', 'november', 'december',
  'english', 'spanish', 'french', 'german', 'italian', 'persian', 'iran',
  'iranian', 'american', 'british', 'turkish', 'arabic', 'chinese', 'japanese',
  'korean', 'russian', 'hindi', 'spain', 'france', 'germany', 'italy', 'turkey',
  'china', 'japan', 'korea', 'russia', 'india', 'england', 'mexico', 'egypt',
  'christmas', 'thanks', 'please', 'sorry', 'hello', 'good', 'nice', 'happy',
  'welcome', 'excuse', 'goodbye', 'yes', 'what', 'where', 'when', 'who', 'why',
  'how', 'the', 'this', 'that', 'let', 'don', 'mr', 'mrs', 'ms', 'dr',
};

String _plain(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[àáâãäå]'), 'a')
    .replaceAll(RegExp('[èéêë]'), 'e')
    .replaceAll(RegExp('[ìíîï]'), 'i')
    .replaceAll(RegExp('[òóôõö]'), 'o')
    .replaceAll(RegExp('[ùúûü]'), 'u')
    .replaceAll('ñ', 'n')
    .replaceAll('ç', 'c')
    .replaceAll('ı', 'i')
    .replaceAll('ş', 's')
    .replaceAll('ğ', 'g');

/// نام‌های خاصِ وسطِ جمله («Lisa»، «Sam») باید در ترجمه‌ی لاتین‌نویس بمانند؛
/// وگرنه معمولاً یک جمله‌ی بی‌ربط از ترجمه‌ی کاربرانِ MyMemory است.
bool _namesKept(String src, String out, String to) {
  if (_kNonLatinTargets.contains(to)) return true;
  final o = _plain(out);
  for (final m in RegExp(r"[A-Za-z][A-Za-z'’-]*").allMatches(src)) {
    final w = m.group(0)!;
    if (w.length < 3 || w.toUpperCase() == w) continue;
    final c = w.codeUnitAt(0);
    if (c < 65 || c > 90) continue; // بزرگ‌حرف نیست
    final before = src.substring(0, m.start).trimRight();
    if (before.isEmpty) continue; // اولِ جمله
    if ('.!?¿¡:;'.contains(before[before.length - 1])) continue;
    final lw = w.toLowerCase().replaceAll(RegExp("['’-].*\$"), '');
    if (lw.length < 3 || _kNotNames.contains(lw)) continue;
    final stem = _plain(lw.length > 4 ? lw.substring(0, 4) : lw);
    if (!o.contains(stem)) return false;
  }
  return true;
}

const Set<String> _kWorkerLangs = {
  'fa', 'en', 'it', 'hi', 'tr', 'ar', 'es', 'de', 'fr', 'zh', 'ko', 'ru', 'ja',
};

/// صفِ ساده با سقفِ هم‌زمانی (به ترتیبِ ورود)
class _Gate {
  _Gate(this.limit);
  final int limit;
  int _active = 0;
  final List<Completer<void>> _q = <Completer<void>>[];

  Future<T> run<T>(Future<T> Function() fn) async {
    if (_active < limit) {
      _active++;
    } else {
      final c = Completer<void>();
      _q.add(c);
      await c.future; // اسلات از نفرِ قبلی منتقل می‌شود
    }
    try {
      return await fn();
    } finally {
      if (_q.isNotEmpty) {
        _q.removeAt(0).complete();
      } else {
        _active--;
      }
    }
  }
}

class _Listener {
  _Listener(this.onValue, this.onGiveUp);
  final void Function(String text, bool isFinal) onValue;
  final void Function() onGiveUp;
}

class _Job {
  _Job(this.key, this.svc, this.base, this.text, this.from, this.to);
  final String key;
  final TranslationService svc;
  final String base;
  final String text;
  final String from;
  final String to;
  final List<_Listener> listeners = <_Listener>[];
  String? latest;
  bool latestFinal = false;
  bool gaveUp = false;
  int invalid = 0; // چند بار AI خروجیِ نامعتبر داد (بیش از ۲ بار → دیگر تلاش نکن)
}

class AiFirstTranslator {
  AiFirstTranslator._();

  static final Dio _dio = _makeDio();
  static Dio _makeDio() {
    final d = Dio(BaseOptions(validateStatus: (_) => true));
    d.interceptors.add(WorkerAuthInterceptor(d));
    return d;
  }

  static final _Gate _aiGate = _Gate(_kAiConcurrency);
  static final _Gate _provGate = _Gate(_kProvConcurrency);
  static final Map<String, _Job> _jobs = <String, _Job>{};

  // ─── مکثِ سراسری وقتی سرور/سهمیه جواب نمی‌دهد (ترجمه‌ی موقت ادامه دارد) ───
  static int _pausedUntil = 0;
  static int _fails = 0;
  static bool _paused() =>
      DateTime.now().millisecondsSinceEpoch < _pausedUntil;
  static int _pauseLeftMs() {
    final left = _pausedUntil - DateTime.now().millisecondsSinceEpoch;
    return left > 0 ? left : 0;
  }

  static void _pause(Duration d) {
    final u = DateTime.now().millisecondsSinceEpoch + d.inMilliseconds;
    if (u > _pausedUntil) _pausedUntil = u;
  }

  static void _okCall() => _fails = 0;
  static void _badCall() {
    _fails++;
    if (_fails >= 3) {
      _fails = 0;
      _pause(const Duration(seconds: 60));
    }
  }

  // ─── «نشانه‌ی نهایی»: این ترجمه از AI/کشِ مشترک آمده و دیگر جایگزین نمی‌شود ───
  static String _marker(String from, String to, String text) =>
      '__aifinal__::${from.isEmpty ? 'auto' : from}>$to::$text';

  static bool _eligible(String text, String from, String to) {
    final t = text.trim();
    if (t.isEmpty || t.length > _kMaxChars) return false;
    if (!_kWorkerLangs.contains(to)) return false;
    if (from.isNotEmpty && from != 'auto' && !_kWorkerLangs.contains(from)) {
      return false;
    }
    return true;
  }

  /// خواندنِ همگام (برای نمایشِ فوریِ ردیف). null = هنوز چیزی نیست.
  static ({String text, bool isFinal})? peek(
      TranslationService svc, String text, String from, String to) {
    final db = TranslationCacheDb.instance;
    if (!db.isReady) return null;
    final pin = svc.pinned(text, to);
    if (pin != null && pin.trim().isNotEmpty) {
      return (text: pin.trim(), isFinal: true);
    }
    final c = svc.peekCached(text, from, to);
    if (c == null || c.trim().isEmpty) return null;
    final fin = db.peek(_marker(from, to, text)) != null;
    if (fin) return (text: c.trim(), isFinal: true);
    // ترجمه‌ی موقتیِ قدیمی (ML Kit/MyMemory) ممکن است خراب ذخیره شده باشد → تمیز یا حذف
    final t = _tidy(c);
    if (t.isEmpty ||
        t.toLowerCase() == text.trim().toLowerCase() ||
        !_namesKept(text, t, to)) {
      return null;
    }
    return (text: t, isFinal: false);
  }

  /// شروع/پیوستن به ترجمه‌ی یک متن. نتیجه همیشه ناهمگام (microtask) تحویل داده می‌شود.
  /// onValue(text, isFinal): ممکن است اول موقتی (isFinal=false) و بعد نهایی (true) بیاید.
  /// onGiveUp: هیچ ترجمه‌ای (حتی موقت) به دست نیامد؛ کار در پس‌زمینه ادامه دارد و اگر رسید onValue صدا می‌خورد.
  /// خروجی: تابعِ لغو (در dispose صدا بزن).
  static void Function() watch({
    required TranslationService svc,
    required AiSettings ai,
    required String text,
    required String from,
    required String to,
    required void Function(String text, bool isFinal) onValue,
    required void Function() onGiveUp,
  }) {
    final l = _Listener(onValue, onGiveUp);
    final key = '${from.isEmpty ? 'auto' : from}>$to|$text';

    var job = _jobs[key];
    if (job == null) {
      job = _Job(key, svc, ai.baseUrl, text, from, to);
      job.listeners.add(l);
      _jobs[key] = job;
      unawaited(_run(job));
    } else {
      job.listeners.add(l);
      final j = job;
      scheduleMicrotask(() {
        if (!j.listeners.contains(l)) return;
        if (j.latest != null) {
          l.onValue(j.latest!, j.latestFinal);
        } else if (j.gaveUp) {
          l.onGiveUp();
        }
      });
    }
    final jobRef = job;
    return () => jobRef.listeners.remove(l);
  }

  // ═══════════════════════════════════════════════════════════════
  static void _emit(_Job j, String t, bool fin) {
    j.latest = t;
    j.latestFinal = fin;
    for (final l in List<_Listener>.of(j.listeners)) {
      try {
        l.onValue(t, fin);
      } catch (_) {}
    }
  }

  static bool _good(_Job j, String t) {
    final s = t.trim();
    if (s.isEmpty) return false;
    return !looksLikelyMistranslated(j.text, s, j.to, sourceLang: j.from);
  }

  /// ذخیره‌ی ترجمه‌ی نهایی: کش (اگر قفل‌شده نبود) + نشانه‌ی نهایی
  static Future<void> _commit(_Job j, String t) async {
    await j.svc.cachePut(j.text, j.from, j.to, t);
    await TranslationCacheDb.instance.put(_marker(j.from, j.to, j.text), '1');
  }

  static Future<void> _run(_Job j) async {
    try {
      await _run0(j);
    } catch (_) {
      // هر خطای پیش‌بینی‌نشده فقط یعنی «چیزی پیدا نشد»
      if (j.latest == null) _giveUp(j);
    } finally {
      _jobs.remove(j.key);
    }
  }

  static void _giveUp(_Job j) {
    if (j.gaveUp) return;
    j.gaveUp = true;
    for (final l in List<_Listener>.of(j.listeners)) {
      try {
        l.onGiveUp();
      } catch (_) {}
    }
  }

  static Future<void> _run0(_Job j) async {
    await TranslationCacheDb.instance.ready;
    // دیگر یک microtask فاصله: اولین تحویل همیشه ناهمگام است
    await Future<void>.value();

    // متنِ بلند/زبانِ پشتیبانی‌نشده در Worker → همان مسیرِ عادیِ اپ (بدون تغییر)
    if (!_eligible(j.text, j.from, j.to)) {
      final r = (await j.svc.translate(
        text: j.text,
        targetLang: j.to,
        sourceLang: j.from,
        aiSettings: AiSettings(backendUrl: j.base),
      ))
          .trim();
      if (r.isNotEmpty && r.toLowerCase() != j.text.trim().toLowerCase()) {
        _emit(j, r, true);
      } else {
        _giveUp(j);
      }
      return;
    }

    // ۱ و ۲: قفل‌شده / نهایی روی گوشی
    final p = peek(j.svc, j.text, j.from, j.to);
    if (p != null) {
      _emit(j, p.text, p.isFinal);
      if (p.isFinal) return;
    }

    // ۳ و ۴: کشِ مشترک (D1) و بعد AI
    var aiDone = false;
    Future<String?> aiPath() async {
      try {
        final shared = await SharedTranslations.fetchOne(
            j.base, j.from, j.to, j.text);
        if (shared != null && _good(j, shared)) return shared.trim();
        return await _askAi(j);
      } catch (_) {
        return null;
      }
    }

    final aiFut = aiPath();
    unawaited(aiFut.whenComplete(() => aiDone = true));

    // ۵: اگر چیزی برای نشان‌دادن نداریم و AI دیر کرد → ترجمه‌ی موقت
    if (j.latest == null) {
      await Future.any<void>(<Future<void>>[
        aiFut.then((_) {}),
        Future<void>.delayed(_kGrace),
      ]);
      if (!aiDone) {
        final prov = await _provisional(j);
        if (prov != null && !aiDone && j.latest == null) {
          _emit(j, prov, false);
        }
      }
    }

    var ai = await aiFut;
    if (ai != null) {
      await _commit(j, ai);
      _emit(j, ai, true);
      return;
    }

    // AI جواب نداد (چه دیر، چه «سریع و با خطا / مکثِ سهمیه»): همین حالا ML Kit/آنلاین.
    // (قبلاً اگر AI سریع خطا می‌داد این مرحله رد می‌شد و «ترجمه نشد» می‌آمد.)
    if (j.latest == null) {
      final prov = await _provisional(j);
      if (prov != null && j.latest == null) _emit(j, prov, false);
    }

    // 🔁 تلاش‌های خودکارِ پس‌زمینه (فقط تا وقتی کسی منتظرِ این ترجمه است).
    // وقتی AI برسد، ترجمه‌ی موقت بی‌صدا جایگزین می‌شود؛ نیازی به دکمه‌ی رفرش نیست.
    var attempt = 0; // فقط تلاش‌های واقعیِ AI را می‌شمارد
    var provTries = 0; // تلاشِ ترجمه‌ی موقت در زمانِ مکث
    var rounds = 0;
    while (attempt < _kRetryDelays.length) {
      if (j.invalid >= 2) break;
      if (j.listeners.isEmpty) break;

      if (_paused()) {
        // سهمیه/سرور فعلاً جواب نمی‌دهد: AI را نمی‌زنیم، فقط ترجمه‌ی موقت را تازه می‌کنیم
        final left = _pauseLeftMs();
        final nap = j.latest == null
            ? Duration(seconds: left > 30000 ? 30 : (left ~/ 1000) + 1)
            : Duration(
                milliseconds: left + 500 > 300000 ? 300000 : left + 500);
        await Future<void>.delayed(nap);
        if (j.listeners.isEmpty) break;
        if (j.latest == null && provTries < 6) {
          provTries++;
          final prov = await _provisional(j);
          if (prov != null && j.latest == null) _emit(j, prov, false);
          rounds++;
          if (rounds >= 2 && j.latest == null) _giveUp(j);
        }
        continue;
      }

      await Future<void>.delayed(_kRetryDelays[attempt]);
      attempt++;
      if (j.listeners.isEmpty) break;
      ai = await _askAi(j);
      if (ai != null) {
        await _commit(j, ai);
        _emit(j, ai, true);
        return;
      }
      // هنوز چیزی برای نشان‌دادن نیست؟ دوباره ترجمه‌ی موقت (مثلاً مدل ML Kit تازه دانلود شده)
      if (j.latest == null) {
        final prov = await _provisional(j);
        if (prov != null && j.latest == null) _emit(j, prov, false);
      }
      rounds++;
      // بعد از دو دورِ ناموفق، رابط «ترجمه نشد» نشان می‌دهد؛ ولی تلاش ادامه دارد
      // و اگر چیزی رسید خودکار جایگزین می‌شود.
      if (rounds >= 2 && j.latest == null) _giveUp(j);
    }
    if (j.latest == null) _giveUp(j);
  }

  /// ترجمه‌ی موقت: ML Kit روی گوشی، بعد مترجم آنلاین (بدون AI).
  /// نتیجه توسط خودِ سرویس در کشِ عادی هم ذخیره می‌شود، ولی «نشانه‌ی نهایی» ندارد.
  static Future<String?> _provisional(_Job j) {
    return _provGate.run<String?>(() async {
      try {
        final r = _tidy(await j.svc.translateNetwork(
          text: j.text,
          targetLang: j.to,
          sourceLang: j.from,
          aiSettings: null,
        ));
        if (r.isEmpty || r.toLowerCase() == j.text.trim().toLowerCase()) {
          return null; // سرویس‌ها نتوانستند (برگرداندنِ خودِ متن)
        }
        if (!_good(j, r) || !_namesKept(j.text, r, j.to)) return null;
        return r;
      } catch (_) {
        return null;
      }
    }).timeout(const Duration(seconds: 14), onTimeout: () => null);
  }

  static String _clean(String s) => s
      .replaceAll(RegExp("^[\"'«»“”]+|[\"'«»“”\\s]+\$"), '')
      .trim();

  /// یک درخواست به /api/translate-text (Worker اول D1 را می‌بیند، بعد AI می‌زند و برای همه ذخیره می‌کند).
  static Future<String?> _askAi(_Job j) {
    if (_paused()) return Future<String?>.value(null);
    return _aiGate.run<String?>(() async {
      if (_paused()) return null;
      try {
        final res = await _dio
            .post(
              '${j.base}/api/translate-text',
              data: {
                'text': j.text.trim(),
                'source_lang_code': j.from.isEmpty ? 'auto' : j.from,
                'target_lang_code': j.to,
              },
              options: Options(
                contentType: 'application/json',
                sendTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 25),
              ),
            )
            .timeout(const Duration(seconds: 30));
        final st = res.statusCode ?? 0;
        if (st >= 200 && st < 300) {
          final data = res.data;
          final out = data is Map ? data['text'] : null;
          if (out is! String) {
            _badCall();
            return null;
          }
          final cleaned = _clean(stripAIReasoning(out));
          if (cleaned.isEmpty ||
              looksLikeAIReasoning(cleaned) ||
              looksLikeGuardOutput(cleaned) ||
              !_good(j, cleaned)) {
            // خروجیِ نامعتبر: حداکثر دو بار دیگر امتحان می‌شود (هر بار ممکن است مدلِ دیگری جواب بدهد)
            j.invalid++;
            _okCall();
            return null;
          }
          _okCall();
          return cleaned;
        }
        if (st == 429) {
          final code = res.data is Map ? res.data['code']?.toString() : null;
          _pause(code == 'daily_feature_limit'
              ? const Duration(minutes: 60)
              : const Duration(minutes: 5));
          return null;
        }
        if (st == 402) {
          _pause(const Duration(minutes: 60));
          return null;
        }
        _badCall();
        return null;
      } catch (_) {
        _badCall();
        return null;
      }
    });
  }
}
