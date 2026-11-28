// 📁 مسیر: lib/core/translate/ai_first_translator.dart
//
// ترجمه‌ی تب مکالمه (Talk) — با «قانونِ طلاییِ هزینه». (نامِ فایل/کلاس برای سازگاری مانده؛ دیگر «اول AI» نیست.)
// ترتیب (هر مرحله جواب داد، همان‌جا تمام و هیچ AIای صدا زده نمی‌شود):
//
//   ۱. 📌 ترجمه‌ی قفل‌شده‌ی کاربر (↻) همیشه مقدم است.
//   ۲. 📦 ترجمه‌ی آماده‌ی داخلِ اپ (bundled) و 💾 کشِ گوشی (نهایی، یا سالمِ غیرمشکوک).
//   ۳. 🗄️ کشِ مشترکِ سرور (D1): اگر کاربرِ دیگری قبلاً گرفته → رایگان.
//   ۴. 📚 معنیِ آماده‌ی داده‌های اپ (known).
//   ۵. 🆓 ML Kit روی گوشی ← مترجمِ آنلاینِ رایگان؛ اگر خروجی سالم بود همان نهایی است (بدونِ AI).
//   ۶. 🕵️ فقط اگر اصطلاح (Idiom) بود یا فیلترها (looksLikelyMistranslated / looksSuspiciousDeep / نمره‌ی کیفیت)
//      مشکوک تشخیص دادند → پیش‌نویسِ رایگان با «draft» به Worker (DeepSeek) فرستاده می‌شود تا بازبینی/اصلاح کند؛
//      Worker نتیجه را در D1 برای همه نگه می‌دارد. تا رسیدنِ جواب پیش‌نویس نشان داده می‌شود (نمره‌ی ۰ هرگز).
//   ✖️ اگر هیچ پیش‌نویسِ رایگانی نبود (مثلاً مدلِ ML Kit هنوز دانلود نشده) AI صدا زده نمی‌شود؛
//      «نبودِ پیش‌نویس ≠ مشکوک». چند بار در پس‌زمینه دوباره امتحان می‌شود؛ کاربر هم با ↻ می‌تواند AI بخواهد.
//
// این فایل فقط از API عمومیِ TranslationService / SharedTranslations / TranslationCacheDb استفاده می‌کند
// و به هیچ بخشِ دیگری دست نمی‌زند. بقیه‌ی تب‌ها مثل قبل کار می‌کنند.

import 'dart:async';
import 'dart:math' show Random;

import 'package:dio/dio.dart';

import '../auth/worker_auth.dart';
import '../storage/translation_cache_db.dart';
import 'back_translate_check.dart';
import 'bundled_translations.dart';
import 'romanization.dart';
import 'known_translations.dart';
import 'shared_translations.dart';
import 'translate_hints.dart';
import 'translation_service.dart';

const int _kMaxChars = 300; // سقفِ Worker برای /api/translate-text
const int _kAiConcurrency = 4; // هم‌زمانیِ درخواست‌های AI از این گوشی
const int _kProvConcurrency = 3; // هم‌زمانیِ ترجمه‌ی موقت (ML Kit/آنلاین)
const Duration _kGrace = Duration(milliseconds: 1000); // تا این‌قدر منتظرِ کش/AI؛ بعد پیش‌نویسِ خوب نشان داده می‌شود
const int _kBatchMax = 20; // حداکثر متن در یک درخواستِ /api/translate-batch
const Duration _kReviewWindow = Duration(milliseconds: 400); // پنجره‌ی جمع‌کردنِ مشکوک‌ها برای بازبینیِ دسته‌ای
const Duration _kBatchWindow = Duration(milliseconds: 80); // جمع‌کردنِ درخواست‌های هم‌زمان
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

// وقتی هیچ پیش‌نویسِ رایگانی نبود: فقط مسیرِ رایگان (کشِ مشترک + ML Kit/آنلاین) دوباره امتحان می‌شود، نه AI
const List<Duration> _kFreeRetryDelays = <Duration>[
  Duration(seconds: 4),
  Duration(seconds: 12),
  Duration(seconds: 40),
  Duration(seconds: 120),
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

final Random _rnd = Random();

/// ±۲۰٪ پراکندگی تا با هجومِ کاربرها همه‌ی گوشی‌ها همزمان retry نکنند.
Duration _jitter(Duration d) {
  final f = 0.8 + _rnd.nextDouble() * 0.4;
  return Duration(milliseconds: (d.inMilliseconds * f).round());
}

/// 🚦 نمره‌ی کیفیتِ ترجمه‌ی موقت (ML Kit/آنلاین): ۲ = خوب، ۱ = متوسط (فقط اگر چیزِ بهتری نرسید)، ۰ = خراب (هرگز).
int _provisionalGrade(String src, String out, String to) {
  final s = src.trim();
  final o = out.trim();
  if (o.isEmpty) return 0;
  final srcWords = s.split(RegExp(r'\s+')).length;
  // مقصدِ غیرلاتین ولی خروجی عمدتاً لاتین = ترجمه‌نشده/نیمه‌کاره
  if (_kNonLatinTargets.contains(to) && srcWords >= 2) {
    final letters = RegExp(r'\p{L}', unicode: true).allMatches(o).length;
    final latin = RegExp(r'[A-Za-z]').allMatches(o).length;
    if (letters > 0 && latin / letters > 0.5) return 0;
  }
  // خروجیِ تکراریِ بی‌معنی («the the the …»)
  final ow = o.split(RegExp(r'\s+'));
  if (ow.length >= 6 && ow.toSet().length * 3 <= ow.length) return 0;
  var grade = 2;
  // نسبتِ طولِ مشکوک (برای متن‌های بلندتر؛ CJK کوتاه‌تر است)
  const cjk = {'zh', 'ja', 'ko'};
  if (s.length >= 20 && !cjk.contains(to)) {
    final r = o.length / s.length;
    if (r < 0.35 || r > 3.5) grade = 1;
  }
  // عددهای متن باید در خروجی بمانند (فقط مقصدِ لاتین؛ فارسی/عربی ارقام را عوض می‌کنند)
  if (!_kNonLatinTargets.contains(to)) {
    for (final m in RegExp(r'\d+').allMatches(s)) {
      if (!o.contains(m.group(0)!)) grade = 1;
    }
  }
  return grade;
}

class _BatchItem {
  _BatchItem(this.job, this.completer);
  final _Job job;
  final Completer<String?> completer;
}

class _BatchGroup {
  _BatchGroup(this.base, this.from, this.to);
  final String base;
  final String from;
  final String to;
  final List<_BatchItem> items = <_BatchItem>[];
  Timer? timer;
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
  String? draft; // پیش‌نویسِ رایگانِ مشکوک که برای بازبینی با AI (DeepSeek) فرستاده می‌شود
  String? softDraft; // پیش‌نویسِ «متوسط» (نمره‌ی ۱) — فقط اگر چیزِ بهتری نرسید نشان داده می‌شود
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

  // «نشانه‌ی مشکوکِ برگشتی»: ترجمه‌ی رایگان در چکِ برگشتی رد شد (تا AI بازبینی نکرده نهایی حساب نشود)
  static String _btBadMarker(String from, String to, String text) =>
      '__btbad__::${from.isEmpty ? 'auto' : from}>$to::$text';

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
    if (db.isReady) {
      final pin = svc.pinned(text, to);
      if (pin != null && pin.trim().isNotEmpty) {
        return (text: pin.trim(), isFinal: true);
      }
    }
    // 📦 ترجمه‌ی آماده‌ی داخلِ اپ (محتوای رایگان) — نهایی؛ بدونِ D1 و AI
    final bundled = BundledTranslations.get(text, from, to);
    if (bundled != null && bundled.trim().isNotEmpty) {
      return (text: bundled.trim(), isFinal: true);
    }
    if (!db.isReady) return null;
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
    // 💸 ترجمه‌ی رایگانِ سالم و غیرمشکوک (و نه اصطلاح) نهایی است؛ AI فقط برای مشکوک‌ها
    return (
      text: t,
      isFinal: !needsAiReview(text, t, from, to) &&
          db.peek(_btBadMarker(from, to, text)) == null
    );
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
    unawaited(BundledTranslations.ensureLoaded());
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
    await BundledTranslations.ensureLoaded();
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

    // ۳: کشِ مشترک (D1) — رایگان
    try {
      final shared =
          await SharedTranslations.fetchOne(j.base, j.from, j.to, j.text);
      if (shared != null && _good(j, shared)) {
        await _commit(j, shared.trim());
        _emit(j, shared.trim(), true);
        return;
      }
    } catch (_) {}

    // ۴: معنیِ آماده‌ی داده‌های اپ (known) — بدونِ AI (در کش نوشته نمی‌شود تا با آپدیتِ داده‌ها کهنه نماند)
    final known = (KnownTranslations.get(j.text, j.from, j.to) ?? '').trim();
    if (known.isNotEmpty && textMatchesScript(known, j.to)) {
      _emit(j, known, true);
      return;
    }

    // ۵: ML Kit / مترجمِ آنلاینِ رایگان. سالم = نهایی (بدونِ AI)؛ مشکوک/اصطلاح = برای بازبینیِ AI.
    String? draft;
    var healthy = false;
    Future<bool> tryFree() async {
      final pv = await _provisional(j); // نمره‌ی ۲ (خوب) یا null
      if (pv != null) {
        draft = pv;
        healthy = !needsAiReview(j.text, pv, j.from, j.to);
        // 🔁 غربالگریِ رایگانِ برگشتی (ML Kit روی گوشی): سالم‌به‌نظر ولی معنی‌اش با برگشت عوض می‌شود → مشکوک
        if (healthy && await backTranslationLooksBroken(j.text, pv, j.from, j.to)) {
          healthy = false;
          unawaited(TranslationCacheDb.instance.put(_btBadMarker(j.from, j.to, j.text), '1'));
        }
        return true;
      }
      if (j.softDraft != null) {
        draft = j.softDraft; // نمره‌ی ۱ (متوسط) = مشکوک
        healthy = false;
        return true;
      }
      return false;
    }

    if (!await tryFree()) {
      // هیچ پیش‌نویسِ رایگانی نیست → AI نه؛ فقط مسیرِ رایگان را چند بار دوباره امتحان کن
      var tries = 0;
      while (j.listeners.isNotEmpty && tries < _kFreeRetryDelays.length) {
        await Future<void>.delayed(_jitter(_kFreeRetryDelays[tries]));
        tries++;
        if (j.listeners.isEmpty) break;
        final sh = await _pollShared(j);
        if (sh != null) {
          await _commit(j, sh);
          _emit(j, sh, true);
          return;
        }
        if (await tryFree()) break;
        // بعد از اولین شکست رابط «ترجمه نشد + ↻» نشان می‌دهد؛ تلاشِ رایگان بی‌صدا ادامه دارد
        if (tries == 1 && j.latest == null) _giveUp(j);
      }
    }
    final d = draft;
    if (d == null) {
      if (j.latest == null) _giveUp(j);
      return;
    }
    if (healthy) {
      await j.svc.cachePut(j.text, j.from, j.to, d);
      _emit(j, d, true);
      return;
    }

    // ۶: مشکوک/اصطلاح → فقط همین‌ها به Worker (DeepSeek) با پیش‌نویس می‌روند
    j.draft = d;
    var aiDone = false;
    // پنجره‌ی ۴۰۰ms: مشکوک‌های یک صفحه (که با فاصله‌ی کمی از ML Kit می‌رسند) در «یک» درخواست جمع می‌شوند
    final aiFut = _askAi(j, window: _kReviewWindow)
        .then<String?>((v) => v, onError: (_) => null);
    unawaited(aiFut.whenComplete(() => aiDone = true));
    if (j.latest == null) {
      await Future.any<void>(<Future<void>>[
        aiFut.then((_) {}),
        Future<void>.delayed(_kGrace),
      ]);
      if (!aiDone && j.latest == null) _emit(j, d, false);
    }

    var ai = await aiFut;
    if (ai != null) {
      await _commit(j, ai);
      _emit(j, ai, true);
      return;
    }

    // AI جواب نداد (چه دیر، چه «سریع و با خطا / مکثِ سهمیه»): همین حالا ML Kit/آنلاین.
    // (قبلاً اگر AI سریع خطا می‌داد این مرحله رد می‌شد و «ترجمه نشد» می‌آمد.)
    await _showDraft(j);

    // 🔁 تلاش‌های خودکارِ پس‌زمینه (فقط تا وقتی کسی منتظرِ این ترجمه است).
    // وقتی AI برسد، ترجمه‌ی موقت بی‌صدا جایگزین می‌شود؛ نیازی به دکمه‌ی رفرش نیست.
    var attempt = 0; // فقط تلاش‌های واقعیِ AI را می‌شمارد
    var provTries = 0; // تلاشِ ترجمه‌ی موقت در زمانِ مکث
    var rounds = 0;
    // 🔁 تا وقتی کسی منتظرِ این ترجمه است، تلاش ادامه دارد (بعد از جدول، هر ۱۰ دقیقه)
    while (true) {
      if (j.invalid >= 2) break;
      if (j.listeners.isEmpty) break;

      if (_paused()) {
        // سهمیه/سرور فعلاً جواب نمی‌دهد: AI را نمی‌زنیم، فقط ترجمه‌ی موقت را تازه می‌کنیم
        final left = _pauseLeftMs();
        final nap = j.latest == null
            ? Duration(seconds: left > 30000 ? 30 : (left ~/ 1000) + 1)
            : Duration(
                milliseconds: left + 500 > 300000 ? 300000 : left + 500);
        await Future<void>.delayed(_jitter(nap));
        if (j.listeners.isEmpty) break;
        // کشِ مشترک سهمیه‌ی AI نمی‌خواهد → حتی در مکث هم چک می‌شود (جایگزینیِ سریعِ ترجمه‌ی موقت)
        final sh = await _pollShared(j);
        if (sh != null) {
          await _commit(j, sh);
          _emit(j, sh, true);
          return;
        }
        if (j.latest == null && provTries < 6) {
          provTries++;
          await _showDraft(j);
          rounds++;
          if (rounds >= 2 && j.latest == null) _giveUp(j);
        }
        continue;
      }

      await Future<void>.delayed(_jitter(attempt < _kRetryDelays.length
          ? _kRetryDelays[attempt]
          : const Duration(minutes: 10)));
      attempt++;
      if (j.listeners.isEmpty) break;
      // اول کشِ مشترک (رایگان)، بعد AI
      final sh = await _pollShared(j);
      if (sh != null) {
        await _commit(j, sh);
        _emit(j, sh, true);
        return;
      }
      ai = await _askAi(j);
      if (ai != null) {
        await _commit(j, ai);
        _emit(j, ai, true);
        return;
      }
      // هنوز چیزی برای نشان‌دادن نیست؟ دوباره ترجمه‌ی موقت (مثلاً مدل ML Kit تازه دانلود شده)
      await _showDraft(j);
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
        final g = _provisionalGrade(j.text, r, j.to);
        if (g == 0) return null; // خراب → هرگز
        if (g == 1) {
          j.softDraft = r; // متوسط → فقط اگر چیزِ بهتری نرسید
          return null;
        }
        return r;
      } catch (_) {
        return null;
      }
    }).timeout(const Duration(seconds: 14), onTimeout: () => null);
  }

  /// 🗄️ بازخوانیِ رایگانِ کشِ مشترک (بدونِ مصرفِ سهمیه‌ی AI). اگر کاربرِ دیگری در این فاصله ترجمه‌ی معتبر
  /// را به کش رسانده باشد، همان را برمی‌گرداند؛ وگرنه null.
  static Future<String?> _pollShared(_Job j) async {
    try {
      final shared = await SharedTranslations.fetchOne(
          j.base, j.from, j.to, j.text,
          force: true);
      if (shared != null && _good(j, shared)) return shared.trim();
    } catch (_) {}
    return null;
  }

  /// نشان‌دادنِ بهترین پیش‌نویسِ موجود: اول «خوب»، وگرنه «متوسط»؛ «خراب» هرگز.
  static Future<void> _showDraft(_Job j) async {
    if (j.latest != null) return;
    final prov = await _provisional(j);
    if (j.latest != null) return;
    if (prov != null) {
      _emit(j, prov, false);
    } else if (j.softDraft != null) {
      _emit(j, j.softDraft!, false);
    }
  }

  static String _clean(String s) => s
      .replaceAll(RegExp("^[\"'«»“”]+|[\"'«»“”\\s]+\$"), '')
      .trim();

  /// یک درخواست به /api/translate-text (Worker اول D1 را می‌بیند، بعد AI می‌زند و برای همه ذخیره می‌کند).
  // ═══════════════ 📦 دسته‌ایِ AI ═══════════════
  // درخواست‌های هم‌زمانِ AI (لغاتِ یک صفحه، جمله‌های یک داستان/زیرنویس) ۸۰ms جمع و تا ۲۰ تایی در «یک» درخواستِ
  // /api/translate-batch فرستاده می‌شوند (هزینه‌ی توکن ~۳ تا ۵ برابر کمتر؛ Worker کش‌ها را همان‌جا جواب می‌دهد).
  // تک‌درخواست یا Workerِ قدیمی (۴۰۴) = همان مسیرِ تک‌به‌تکِ قبلی. موردِ نامعتبرِ دسته → یک‌بار تک‌به‌تک.
  static final Map<String, _BatchGroup> _groups = <String, _BatchGroup>{};
  static bool _batchOff = false;

  static Future<String?> _askAi(_Job j, {Duration window = _kBatchWindow}) {
    if (_paused()) return Future<String?>.value(null);
    if (_batchOff) return _askSingle(j);
    final key = '${j.base}|${j.from.isEmpty ? 'auto' : j.from}|${j.to}';
    final g = _groups.putIfAbsent(key, () => _BatchGroup(j.base, j.from, j.to));
    final c = Completer<String?>();
    g.items.add(_BatchItem(j, c));
    if (g.items.length >= _kBatchMax) {
      g.timer?.cancel();
      g.timer = null;
      unawaited(_flushGroup(key));
    } else {
      g.timer ??= Timer(window, () => unawaited(_flushGroup(key)));
    }
    return c.future;
  }

  static Future<void> _flushGroup(String key) async {
    final g = _groups.remove(key);
    if (g == null) return;
    g.timer?.cancel();
    final items = g.items;
    void done(_BatchItem it, String? v) {
      if (!it.completer.isCompleted) it.completer.complete(v);
    }

    void single(_BatchItem it) {
      unawaited(_askSingle(it.job).then((v) => done(it, v), onError: (_) => done(it, null)));
    }

    try {
      if (items.length == 1 || _batchOff) {
        items.forEach(single);
        return;
      }
      final res = await _askBatch(g, items);
      if (res == null) {
        if (_batchOff) {
          items.forEach(single); // Workerِ قدیمی: تک‌به‌تک
        } else {
          for (final it in items) {
            done(it, null);
          }
        }
        return;
      }
      for (var i = 0; i < items.length; i++) {
        final v = i < res.length ? res[i] : null;
        if (v != null) {
          done(items[i], v);
        } else if (items[i].job.invalid < 2) {
          single(items[i]); // نامعتبر/ردشده در دسته → یک‌بار تک‌به‌تک
        } else {
          done(items[i], null);
        }
      }
    } catch (_) {
      for (final it in items) {
        done(it, null);
      }
    }
  }

  static String? _acceptAi(_Job j, dynamic out) {
    if (out is! String) return null;
    final cleaned = _clean(stripAIReasoning(out));
    if (cleaned.isEmpty ||
        looksLikeAIReasoning(cleaned) ||
        looksLikeGuardOutput(cleaned) ||
        !_good(j, cleaned)) {
      j.invalid++;
      return null;
    }
    return cleaned;
  }

  static Future<List<String?>?> _askBatch(
      _BatchGroup g, List<_BatchItem> items) {
    if (_paused()) return Future<List<String?>?>.value(null);
    return _aiGate.run<List<String?>?>(() async {
      if (_paused()) return null;
      try {
        final res = await _dio
            .post(
              '${g.base}/api/translate-batch',
              data: {
                'items': [for (final it in items) it.job.text.trim()],
                // 🕵️ پیش‌نویس‌های مشکوکِ رایگان برای بازبینیِ DeepSeek ('' = بدونِ پیش‌نویس)
                if (items.any((it) => (it.job.draft ?? '').trim().isNotEmpty))
                  'drafts': [for (final it in items) (it.job.draft ?? '').trim()],
                // 🎓 سطحِ جمله و خطِ قبلیِ مکالمه (اختیاری؛ '' = ندارد)
                if (items.any((it) => TranslateHints.level(it.job.text).isNotEmpty))
                  'levels': [for (final it in items) TranslateHints.level(it.job.text)],
                if (items.any((it) => TranslateHints.context(it.job.text).isNotEmpty))
                  'contexts': [for (final it in items) TranslateHints.context(it.job.text)],
                if (items.any((it) => TranslateHints.next(it.job.text).isNotEmpty))
                  'nexts': [for (final it in items) TranslateHints.next(it.job.text)],
                'source_lang_code': g.from.isEmpty ? 'auto' : g.from,
                'target_lang_code': g.to,
                ...Romanization.nativeField, // 🔤
              },
              options: Options(
                contentType: 'application/json',
                sendTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 35),
              ),
            )
            .timeout(const Duration(seconds: 40));
        final st = res.statusCode ?? 0;
        if (st >= 200 && st < 300) {
          final data = res.data;
          final arr = data is Map ? data['results'] : null;
          if (arr is! List || arr.length != items.length) {
            _badCall();
            return null;
          }
          Romanization.ingestBatch(g.to, data); // 🔤 romans
          _okCall();
          return <String?>[
            for (var i = 0; i < items.length; i++) _acceptAi(items[i].job, arr[i]),
          ];
        }
        if (st == 404 || st == 405) {
          _batchOff = true; // Workerِ قدیمی
          return null;
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

  // ═══════════════ 🧩 دسته‌ایِ AI برای مثال‌ها ═══════════════
  /// ترجمه‌ی «یک مثالِ مشکوک» با AI از مسیرِ دسته‌ای: درخواست‌های هم‌زمانِ مثال‌ها (تا [window]) جمع و
  /// تا ۲۰ تا در «یک» درخواستِ /api/translate-batch فرستاده می‌شوند. null = ترجمه نشد
  /// (خطا، سهمیه، مکث، خروجیِ نامعتبر) و تصمیمش با صدازننده است. کش‌گذاری با صدازننده است.
  static Future<String?> askAiBatched({
    required TranslationService svc,
    required String base,
    required String text,
    required String from,
    required String to,
    Duration window = const Duration(milliseconds: 400),
  }) async {
    final t = text.trim();
    if (t.isEmpty || t.length > _kStoryItemMax || _paused()) return null;
    if (!_kWorkerLangs.contains(to)) return null;
    if (from.isNotEmpty && from != 'auto' && !_kWorkerLangs.contains(from)) {
      return null;
    }
    try {
      if (t.length > _kMaxChars) {
        // مسیرِ تک‌درخواستِ قدیمی سقفِ ۳۰۰ دارد؛ متنِ بلند مستقیم به مسیرِ دسته‌ای می‌رود
        final r = await translateStoryBatch(
            base: base, from: from, to: to, texts: [t]);
        return r.isEmpty ? null : r.first;
      }
      return await _askAi(
          _Job('ex|$from>$to|$t', svc, base, t, from, to),
          window: window);
    } catch (_) {
      return null;
    }
  }

  // ═══════════════ 📖 دسته‌ایِ AI برای پاراگراف‌های داستان ═══════════════
  // پاراگراف‌های (مشکوکِ) داستان که تا ۲۰۰۰ کاراکترند، در گروه‌های حداکثر ۳۰۰۰ کاراکتر/۲۰ تایی
  // با «یک» درخواستِ /api/translate-batch ترجمه می‌شوند. خروجی هم‌طولِ ورودی است؛
  // null = این مورد ترجمه نشد (طولِ بیش‌ازحد، رد شدن، خطا، مکث) و تصمیمش با صدازننده است.
  // کیفیتِ نهایی را صدازننده می‌سنجد؛ اینجا فقط خروجیِ استدلال/گارد حذف می‌شود.
  static const int _kStoryItemMax = 2000;
  static const int _kStoryPiece = 1500; // پاراگرافِ بلندتر از سقف به تکه‌هایی تا این اندازه شکسته می‌شود
  static const int _kStoryChunkChars = 3000;
  static const Set<String> _kNoSpaceJoin = {'zh', 'ja'};

  /// شکستنِ متنِ بلند به تکه‌های ≤ ~۱۵۰۰ کاراکتر، سرِ پایانِ جمله (و در نهایت سرِ فاصله).
  /// هیچ کاراکتری گم نمی‌شود: join همان متن را می‌دهد.
  static List<String> _splitLong(String t) {
    const ends = '.!?؟。…';
    final sents = <String>[];
    var start = 0;
    for (var i = 0; i < t.length; i++) {
      final ch = t[i];
      final atEnd = i + 1 >= t.length;
      if (ends.contains(ch) &&
          (atEnd || ch == '。' || t[i + 1] == ' ' || t[i + 1] == '\n')) {
        sents.add(t.substring(start, i + 1).trim());
        start = i + 1;
      }
    }
    if (start < t.length) sents.add(t.substring(start).trim());

    final pieces = <String>[];
    var cur = '';
    void flushCur() {
      if (cur.isNotEmpty) {
        pieces.add(cur);
        cur = '';
      }
    }

    for (final s0 in sents) {
      var sent = s0;
      if (sent.isEmpty) continue;
      while (sent.length > _kStoryItemMax) {
        flushCur();
        var cut = sent.lastIndexOf(' ', _kStoryPiece);
        if (cut < _kStoryPiece ~/ 2) cut = _kStoryPiece;
        pieces.add(sent.substring(0, cut).trim());
        sent = sent.substring(cut).trim();
      }
      if (sent.isEmpty) continue;
      if (cur.isNotEmpty && cur.length + 1 + sent.length > _kStoryPiece) {
        flushCur();
      }
      cur = cur.isEmpty ? sent : '$cur $sent';
    }
    flushCur();
    return pieces;
  }

  static Future<List<String?>> translateStoryBatch({
    required String base,
    required String from,
    required String to,
    required List<String> texts,
  }) async {
    final out = List<String?>.filled(texts.length, null);
    if (texts.isEmpty || _paused() || _batchOff) return out;
    if (!_kWorkerLangs.contains(to)) return out;
    if (from.isNotEmpty && from != 'auto' && !_kWorkerLangs.contains(from)) {
      return out;
    }

    // ۱) پاراگراف‌های بلند → تکه‌ها (هر تکه یک مورد در دسته)
    final flat = <String>[]; // متنِ هر مورد
    final owner = <int>[]; // این مورد مالِ کدام پاراگراف است
    for (var i = 0; i < texts.length; i++) {
      final t = texts[i].trim();
      if (t.isEmpty) continue;
      final parts = t.length <= _kStoryItemMax ? <String>[t] : _splitLong(t);
      for (final p in parts) {
        if (p.isEmpty) continue;
        flat.add(p);
        owner.add(i);
      }
    }

    // ۲) گروه‌بندی بر اساسِ تعداد و مجموعِ کاراکتر
    final chunks = <List<int>>[];
    var cur = <int>[];
    var acc = 0;
    for (var i = 0; i < flat.length; i++) {
      final len = flat[i].length;
      if (cur.isNotEmpty &&
          (cur.length >= _kBatchMax || acc + len > _kStoryChunkChars)) {
        chunks.add(cur);
        cur = <int>[];
        acc = 0;
      }
      cur.add(i);
      acc += len;
    }
    if (cur.isNotEmpty) chunks.add(cur);

    final flatOut = List<String?>.filled(flat.length, null);
    for (final idxs in chunks) {
      if (_paused() || _batchOff) break;
      final res = await _askStoryChunk(
          base, from, to, [for (final i in idxs) flat[i]]);
      if (res == null) continue;
      for (var k = 0; k < idxs.length; k++) {
        flatOut[idxs[k]] = res[k];
      }
    }

    // ۳) سرِ هم کردنِ تکه‌ها؛ اگر حتی یک تکه نیامد، کلِ آن پاراگراف null می‌ماند
    final sep = _kNoSpaceJoin.contains(to) ? '' : ' ';
    final bucket = <int, List<String?>>{};
    for (var i = 0; i < flat.length; i++) {
      bucket.putIfAbsent(owner[i], () => <String?>[]).add(flatOut[i]);
    }
    bucket.forEach((o, parts) {
      if (parts.isNotEmpty && parts.every((x) => x != null && x.isNotEmpty)) {
        out[o] = parts.join(sep);
      }
    });
    return out;
  }

  static Future<List<String?>?> _askStoryChunk(
      String base, String from, String to, List<String> items) {
    return _aiGate.run<List<String?>?>(() async {
      if (_paused()) return null;
      try {
        final res = await _dio
            .post(
              '$base/api/translate-batch',
              data: {
                'items': items,
                'source_lang_code': from.isEmpty ? 'auto' : from,
                'target_lang_code': to,
              },
              options: Options(
                contentType: 'application/json',
                sendTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 45),
              ),
            )
            .timeout(const Duration(seconds: 50));
        final st = res.statusCode ?? 0;
        if (st >= 200 && st < 300) {
          final data = res.data;
          final arr = data is Map ? data['results'] : null;
          if (arr is! List || arr.length != items.length) {
            _badCall();
            return null;
          }
          _okCall();
          return <String?>[
            for (final v in arr)
              () {
                if (v is! String) return null;
                final c = _clean(stripAIReasoning(v));
                if (c.isEmpty ||
                    looksLikeAIReasoning(c) ||
                    looksLikeGuardOutput(c)) {
                  return null;
                }
                return c;
              }(),
          ];
        }
        if (st == 404 || st == 405) {
          _batchOff = true; // Workerِ قدیمی
          return null;
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

  /// یک درخواست به /api/translate-text (تک‌به‌تک).
  static Future<String?> _askSingle(_Job j) {
    if (_paused()) return Future<String?>.value(null);
    return _aiGate.run<String?>(() async {
      if (_paused()) return null;
      try {
        final res = await _dio
            .post(
              '${j.base}/api/translate-text',
              data: {
                'text': j.text.trim(),
                if ((j.draft ?? '').trim().isNotEmpty) 'draft': j.draft!.trim(),
                // 🎓 سطحِ جمله و خطِ قبلیِ مکالمه (اختیاری)
                if (TranslateHints.level(j.text).isNotEmpty) 'level': TranslateHints.level(j.text),
                if (TranslateHints.context(j.text).isNotEmpty) 'context': TranslateHints.context(j.text),
                if (TranslateHints.next(j.text).isNotEmpty) 'next': TranslateHints.next(j.text),
                'source_lang_code': j.from.isEmpty ? 'auto' : j.from,
                'target_lang_code': j.to,
                ...Romanization.nativeField, // 🔤
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
          Romanization.ingestSingle(j.to, data); // 🔤 roman
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
