import '../usage/free_limit.dart';
import '../usage/pro_status.dart' show ProStatus;
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import '../auth/worker_auth.dart';
import '../native/native_bridge.dart';
import '../storage/translation_cache_db.dart';
import 'shared_translations.dart';

// ═══════════════════════════════════════════════════════════════════
// Translation Service — پورتِ دقیقِ translateService.js + callAI.js وب‌اپ
//
// زنجیره (دقیقاً مثل وب):
//   1. کش محلی (با چکِ looksLikelyMistranslated موقع خواندن)
//   2. صفِ سراسری (۱۰ کار هم‌زمان) + سقفِ زمانیِ ۱۵ ثانیه از لحظه‌ی «اجرا»
//   3. ۴ سرویس رایگان به‌صورت موازی (Google → MyMemory → Lingva → Libre)
//      با circuit breaker (۴ شکست پشت‌سرهم = ۴۵ ثانیه کنار)
//   4. کنترل کیفیت رایگان؛ فقط اگر مشکوک بود (یا forceVerify) → تأیید با AI
//   5. آخرین چاره: ترجمه با بک‌اند AI (Cloudflare Worker /api/generate)
// ═══════════════════════════════════════════════════════════════════

/// همان DEFAULT_BACKEND_URL وب‌اپ (app/ai/callAI.js)
const String kDefaultBackendUrl =
    'https://phrasebook-api.maryam-s-sharifiyan.workers.dev';

/// false = انتشار تجاری: سرویس‌های غیررسمی (Google gtx / Lingva / LibreTranslate عمومی) خاموش‌اند. true = مثل قبل.
const bool kAllowUnofficialTranslators = false;

const int _kProviderFailThreshold = 4;
const int _kProviderBlockMs = 45 * 1000;
const int kGlobalTranslateConcurrency = 10;
const int _kHardTimeoutMs = 15000;
const int _kProviderTimeoutMs = 6000;
const int _kAiTimeoutMs = 10000;

/// نام انگلیسی زبان — برای پرامپت AI (همان englishLangName وب)
const Map<String, String> _englishNames = {
  'fa': 'Persian', 'en': 'English', 'it': 'Italian', 'hi': 'Hindi',
  'tr': 'Turkish', 'ar': 'Arabic', 'es': 'Spanish', 'de': 'German',
  'fr': 'French', 'zh': 'Chinese', 'ko': 'Korean', 'ru': 'Russian',
  'ja': 'Japanese',
};

String englishLangName(String code) => _englishNames[code] ?? code;

/// بازه‌ی یونیکد رسم‌الخط هر زبان — برای تشخیص «اصلاً ترجمه نشده»
final Map<String, RegExp> _scriptRegex = {
  'fa': RegExp(r'[\u0600-\u06FF]'),
  'ar': RegExp(r'[\u0600-\u06FF]'),
  'ru': RegExp(r'[\u0400-\u04FF]'),
  'zh': RegExp(r'[\u4E00-\u9FFF]'),
  'ja': RegExp(r'[\u3040-\u30FF\u4E00-\u9FFF]'),
  'ko': RegExp(r'[\uAC00-\uD7AF]'),
};

/// آیا متن به رسم‌الخطِ زبانِ [lang] است؟ (برای زبان‌های لاتین همیشه true —
/// تشخیصِ اسپانیایی از انگلیسی ممکن نیست). مثلاً معنیِ اسپانیاییِ یک لغتِ
/// شخصی نباید به‌عنوان ترجمه‌ی فارسی نشان داده شود.
bool textMatchesScript(String text, String lang) {
  final re = _scriptRegex[lang];
  if (re == null) {
    // زبان‌های لاتین (انگلیسی، اسپانیایی، ...): تشخیصِ زبان از روی حروف ممکن
    // نیست، ولی متنی که بیشترِ حروفش فارسی/عربی/سیریلیک/چینی/... است قطعاً
    // ترجمه‌ی این زبان نیست (مثلاً معنیِ فارسیِ ذخیره‌شده نباید در ردیفِ EN بنشیند).
    if (_latinLangs.contains(lang)) {
      final foreign = _foreignScriptRe.allMatches(text).length;
      if (foreign == 0) return true;
      final latin = RegExp(r'[A-Za-z\u00C0-\u024F]').allMatches(text).length;
      return latin >= foreign;
    }
    return true;
  }
  return re.hasMatch(text);
}

const Set<String> _latinLangs = {'en', 'es', 'de', 'fr', 'it', 'tr'};

final RegExp _foreignScriptRe = RegExp(
    r'[\u0400-\u04FF\u0590-\u05FF\u0600-\u06FF\u0900-\u097F\u3040-\u30FF\u4E00-\u9FFF\uAC00-\uD7AF]');

/// AI به‌جای ترجمه «فکر کردنش» را برگردانده؟
final RegExp aiReasoningRe = RegExp(
  r"(thinking process|here'?s a thinking|analy[sz]e the (request|text|input)|\*\*\s*analy[sz]e|\bconstraint\s*:|the user wants me to|let me (read|think|analy[sz]e|re-?read)|<\/?think(ing)?>|^\s*okay,? (so|let'?s|the user))",
  caseSensitive: false,
  multiLine: true,
);

bool looksLikeAIReasoning(String text) {
  if (text.isEmpty) return false;
  if (aiReasoningRe.hasMatch(text)) return true;
  final boldCount = RegExp(r'\*\*').allMatches(text).length;
  return boldCount >= 4 && RegExp(r'(^|\n|\s)\d\.\s').hasMatch(text);
}

/// خروجیِ مدل‌های «گارد/ایمنی» یا امتناع (مثلاً «User Safety: safe») که به‌جای
/// ترجمه برمی‌گردند — ترجمه حساب نمی‌شوند.
final RegExp _guardOutputRe = RegExp(
  r"^\s*(user\s+|assistant\s+)?safety\s*:|^\s*(safe|unsafe)\s*$|^\s*(i'?m sorry,? (but )?i (can'?t|cannot)|as an ai\b|sorry, i can'?t (help|assist|translate))",
  caseSensitive: false,
  multiLine: true,
);

bool looksLikeGuardOutput(String text) {
  final t = text.trim();
  return t.isNotEmpty && _guardOutputRe.hasMatch(t);
}

/// برچسبِ مدل‌های گارد («User Safety: unsafe» / «Safety Categories: …») — جواب نیست.
/// اگر Workerِ قدیمی این خروجی را فیلتر نکند، اینجا جلوی نمایشش گرفته می‌شود.
final RegExp _aiGuardRe = RegExp(
  r'^\s*((user|assistant)\s+)?safety(\s+categories)?\s*:|^\s*(safe|unsafe)\s*$',
  caseSensitive: false,
  multiLine: true,
);

/// <think>…</think> و مانندش را برمی‌دارد
String stripAIReasoning(String text) {
  return text
      .replaceAll(
          RegExp(r'<think(ing)?>[\s\S]*?<\/think(ing)?>', caseSensitive: false),
          '')
      .replaceAll(RegExp(r'<think(ing)?>[\s\S]*$', caseSensitive: false), '')
      .trim();
}

/// لغت‌های هم‌شکل بین زبان‌های لاتین (hospital ← es، hotel، animal، ...): ترجمه‌ی درست
/// عیناً همان لغت است و نباید «ترجمه نشده» حساب شود. فقط وقتی که یک مترجمِ واقعی
/// (ML Kit / سرویس) همین نتیجه را داده، یا از کشِ دائمی آمده باشد تأیید می‌شود؛
/// تا شکستِ کاملِ ترجمه (که خودِ متن برمی‌گردد) سالم به‌نظر نیاید.
final Set<String> _confirmedSame = {};

String _sameKey(String src, String target) =>
    '$target|${src.trim().toLowerCase()}';

bool _latinPair(String from, String to) =>
    _latinLangs.contains(to) && _latinLangs.contains(from);

/// اگر [out] عیناً [src] است و جفت‌زبان لاتین است، به‌عنوانِ «ترجمه‌ی هم‌شکلِ درست» ثبت می‌شود.
/// strict=true (خروجیِ سرویس‌های آنلاین): فقط یک کلمه‌ی ساده. ML Kit قابل‌اعتماد است (strict=false).
void _markCognate(String src, String out, String target, String source,
    {bool strict = true}) {
  final a = src.trim();
  final b = out.trim();
  if (a.isEmpty || a.toLowerCase() != b.toLowerCase()) return;
  if (!_latinPair(source, target) || source == target) return;
  if (a.length > 40) return;
  if (strict &&
      (a.length < 3 || RegExp(r'[\s\d]').hasMatch(a))) {
    return;
  }
  _confirmedSame.add(_sameKey(a, target));
}

/// 📌 «bye» را مترجم‌های ماشینی گاهی «بیا» (فعلِ come) ترجمه می‌کنند؛ ترجمه‌ی درستش «خداحافظ» است.
/// ۱) خودِ کلمه (bye / bye-bye / goodbye) بدون رفتن سراغ هیچ مترجم/کشی؛
/// ۲) جمله‌هایی که bye دارند (مثلاً «Bye, Anna!») اگر «بیا» در خروجی آمده بود، اصلاح می‌شود.
String? _hardcodedFarewell(String text, String from, String to) {
  if (to != 'fa') return null;
  if (from.isNotEmpty && from != 'en' && from != 'auto') return null;
  final k = text
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s\-]+'), ' ')
      .replaceAll(RegExp(r'[.!?…]+$'), '')
      .trim();
  if (k == 'bye' || k == 'bye bye' || k == 'byebye' || k == 'goodbye') {
    return text.trim().endsWith('!') ? 'خداحافظ!' : 'خداحافظ';
  }
  return null;
}

String _fixFarewell(String src, String from, String to, String out) {
  if (to != 'fa' || out.isEmpty) return out;
  if (from.isNotEmpty && from != 'en' && from != 'auto') return out;
  if (!RegExp(r'\bbye\b', caseSensitive: false).hasMatch(src)) return out;
  if (RegExp(r'\bcome\b', caseSensitive: false).hasMatch(src)) return out;
  return out.replaceAll(
      RegExp(r'(?<![\u0600-\u06FF])بیا(?![\u0600-\u06FF])'), 'خداحافظ');
}

/// 🎭 اصطلاح/عبارتِ ثابتِ معروف که مترجم‌های ماشینی کلمه‌به‌کلمه ترجمه می‌کنند
/// (مثلاً «See you later, alligator!» ← «به‌زودی می‌بینمت، تمساح!»). فقط برای فعال‌کردنِ بازبینیِ AI.
final RegExp _idiomRe = RegExp(
  r'\b(see you later,?\s+alligator|in a while,?\s+crocodile|after a while,?\s+crocodile'
  r'|break a leg|raining cats and dogs|piece of cake|kick the bucket|spill the beans'
  r'|under the weather|an arm and a leg|bite the bullet|once in a blue moon|hit the sack)\b',
  caseSensitive: false,
);

bool _looksIdiomatic(String text) => _idiomRe.hasMatch(text);

/// کنترل کیفیتِ سبک — همان looksLikelyMistranslated وب
bool looksLikelyMistranslated(
  String sourceText,
  String draft,
  String targetLang, {
  String sourceLang = 'auto',
}) {
  final src = sourceText.trim();
  final out = draft.trim();
  if (out.isEmpty) return true;
  if (looksLikeAIReasoning(out)) return true;
  if (looksLikeGuardOutput(out)) return true;

  // خروجی عیناً همان متن مبدأ است
  if (sourceLang.isNotEmpty &&
      sourceLang != 'auto' &&
      sourceLang != targetLang &&
      out.toLowerCase() == src.toLowerCase() &&
      !_confirmedSame.contains(_sameKey(src, targetLang))) {
    return true;
  }

  // رسم‌الخط زبان مقصد در خروجی نیست
  final re = _scriptRegex[targetLang];
  if (re != null && src.length > 1 && !re.hasMatch(out)) return true;

  // منبع یک «کلمه‌ی تکی» است ولی خروجی یک جمله‌ی بلند (مثلاً MyMemory برای
  // «put» یک جمله‌ی بی‌ربط برمی‌گرداند) → مشکوک
  if (src.isNotEmpty && !RegExp(r'\s').hasMatch(src)) {
    final outWords = out.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    if (outWords > 4) return true;
  }

  // نسبت طولِ غیرعادی
  final ratio = out.length / (src.isEmpty ? 1 : src.length);
  if (src.length > 3 && (ratio < 0.25 || ratio > 3.5)) return true;

  return false;
}

// ═══════════════════════════════════════════════════════════════════
// 🔍 بازبینیِ خودکارِ عمیق (فقط Pro): چکِ رایگان و همگام که «ترجمه‌ی مشکوک» را تشخیص می‌دهد.
// ترجمه‌ی سالم هرگز به AI نمی‌رود؛ مشکوک‌ها یک بار بازبینی و در کش (محلی + مشترک) ذخیره می‌شوند.
// ═══════════════════════════════════════════════════════════════════
const Set<String> _deepNonLatin = {
  'fa', 'ar', 'ur', 'he', 'ru', 'uk', 'bg', 'el', 'hi', 'bn', 'th', 'zh',
  'ja', 'ko',
};
const Set<String> _deepCjk = {'zh', 'ja', 'ko', 'th'};

bool _deepReviewOn(AiSettings? ai) => ai != null && ProStatus.isPro;

bool looksSuspiciousDeep(String src, String draft, String from, String to) {
  final s0 = src.trim();
  final d = draft.trim();
  if (s0.isEmpty || d.isEmpty) return false;

  // ۱. کلمه‌های لاتینِ ترجمه‌نشده در زبانِ مقصدِ غیرلاتین (نام‌های خاصِ مبدأ مجازند)
  if (_deepNonLatin.contains(to)) {
    final srcWords = RegExp(r'[A-Za-z]{3,}')
        .allMatches(s0)
        .map((m) => m.group(0)!.toLowerCase())
        .toSet();
    final latin = RegExp(r'[A-Za-z]{3,}')
        .allMatches(d)
        .map((m) => m.group(0)!.toLowerCase())
        .where((w) => !srcWords.contains(w))
        .length;
    final total = d.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    if (latin >= 2 && total > 0 && latin / total > 0.3) return true;
  }

  // ۲. نسبتِ طولِ مشکوک (برای CJK/تایی معنی ندارد)
  if (s0.length >= 40 && !_deepCjk.contains(to) && !_deepCjk.contains(from)) {
    final ratio = d.length / s0.length;
    if (ratio < 0.45 || ratio > 2.6) return true;
  }

  // ۳. جمله‌های جاافتاده (ترجمه‌ی بریده)
  final enders = RegExp(r'[.!?؟…]+');
  final sc = enders.allMatches(s0).length;
  if (sc >= 3 && enders.allMatches(d).length < sc * 0.5) return true;

  // ۴. تکرارِ حلقه‌ای (۴ توکنِ مساویِ پشت‌سرهم)
  final toks = d.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  var run = 1;
  for (var i = 1; i < toks.length; i++) {
    run = toks[i] == toks[i - 1] ? run + 1 : 1;
    if (run >= 4) return true;
  }
  return false;
}

String _stripQuotes(String s) =>
    s.replaceAll(RegExp("^[\"'«»]+|[\"'«».\\s]+\$"), '').trim();

// ═══════════════════════════════════════════════════════════════════
// Circuit breaker (سراسری)
// ═══════════════════════════════════════════════════════════════════
// 🚩 «تلاش شد» (Flag) با تاریخ انقضا — روی دیسک (همان دیتابیسِ کشِ ترجمه) ذخیره می‌شود،
// پس بعد از بستن و باز کردنِ اپ هم زمان‌بندی حفظ می‌شود.
//   شکستِ اول → ۲ ساعت؛ اگر بعد از انقضا دوباره شکست خورد → ۲۴ ساعت.
//   Flag دائمی نمی‌شود: هر بار که منقضی شد یک شانسِ دیگر داده می‌شود (با همان ۲۴ ساعت).
//   موفقیت → Flag و شمارنده‌ی شکست‌ها پاک می‌شود.
class RetryFlag {
  RetryFlag._();

  static const String _prefix = '__retryflag__::'; // با کلیدِ ترجمه‌ها (مبدأ::مقصد::متن) قاطی نمی‌شود
  static const int firstMs = 2 * 60 * 60 * 1000; // ۲ ساعت
  static const int repeatMs = 24 * 60 * 60 * 1000; // ۲۴ ساعت

  /// کلیدِ کوتاه و پایدار برای هر متن (متنِ بلند مستقیم کلید نمی‌شود).
  static String keyFor(String kind, String text, [String extra = '']) {
    var h1 = 0x811c9dc5;
    var h2 = 5381;
    for (final c in text.codeUnits) {
      h1 = ((h1 ^ c) * 0x01000193) & 0xFFFFFFFF;
      h2 = ((h2 * 33) + c) & 0xFFFFFFFF;
    }
    return '$kind|$extra|${h1.toRadixString(16)}${h2.toRadixString(16)}|${text.length}';
  }

  /// [until, count] یا null
  static List<int>? _read(String key) {
    final v = TranslationCacheDb.instance.peek('$_prefix$key');
    if (v == null || v.isEmpty) return null;
    final parts = v.split('|');
    if (parts.length != 2) return null;
    final u = int.tryParse(parts[0]);
    final c = int.tryParse(parts[1]);
    if (u == null || c == null) return null;
    return [u, c];
  }

  /// هنوز در بازه‌ی «تلاش شد» هستیم؟ (منقضی شده → false؛ شمارنده می‌ماند تا شکستِ بعدی طولانی‌تر ثبت شود)
  static bool blocked(String key) {
    final f = _read(key);
    if (f == null) return false;
    return DateTime.now().millisecondsSinceEpoch < f[0];
  }

  /// ثبتِ شکست: بار اول ۲ ساعت، دفعه‌های بعد ۲۴ ساعت.
  static void failed(String key) {
    final n = (_read(key)?[1] ?? 0) + 1;
    final ms = n <= 1 ? firstMs : repeatMs;
    final until = DateTime.now().millisecondsSinceEpoch + ms;
    unawaited(TranslationCacheDb.instance.put('$_prefix$key', '$until|$n'));
  }

  /// موفقیت: Flag پاک می‌شود (مقدارِ خالی = بدونِ Flag).
  static void succeeded(String key) {
    if (_read(key) == null) return;
    unawaited(TranslationCacheDb.instance.put('$_prefix$key', ''));
  }
}

// ─── ML Kit (آفلاین، روی گوشی) — اولین مرحله‌ی زنجیره‌ی شبکه ───
const int _kSharedMaxChars = 300;         // سقفِ کشِ مشترک (همان سقفِ Worker): متنِ بلندِ کاربر هرگز به کش نمی‌رود
const int _kMlKitMaxChars = 400;            // متن بلندتر: AI/MyMemory کیفیت بهتری دارد
const int _kMlKitRetryAfterMs = 60 * 1000;  // بعد از شکستِ دانلود، یک دقیقه دوباره تلاش نکن
final Set<String> _mlReady = {};            // جفت‌زبان‌هایی که مدلشان روی گوشی هست
final Set<String> _mlDownloading = {};
final Map<String, int> _mlRetryAt = {};

final Map<String, int> _providerFailCounts = {};
final Map<String, int> _providerBlockedUntil = {};

bool _isProviderBlocked(String name) {
  final until = _providerBlockedUntil[name];
  if (until == null) return false;
  if (DateTime.now().millisecondsSinceEpoch < until) return true;
  _providerBlockedUntil.remove(name);
  _providerFailCounts[name] = 0;
  return false;
}

void _reportProviderOutcome(String name, bool succeeded) {
  if (succeeded) {
    _providerFailCounts[name] = 0;
    _providerBlockedUntil.remove(name);
    return;
  }
  final count = (_providerFailCounts[name] ?? 0) + 1;
  _providerFailCounts[name] = count;
  if (count >= _kProviderFailThreshold) {
    _providerBlockedUntil[name] =
        DateTime.now().millisecondsSinceEpoch + _kProviderBlockMs;
  }
}

// ═══════════════════════════════════════════════════════════════════
// صفِ سراسریِ هم‌زمانی
// ═══════════════════════════════════════════════════════════════════
int _activeJobs = 0;
final List<_Job> _queue = [];

class _Job {
  final Future<dynamic> Function() fn;
  final Completer<dynamic> completer = Completer<dynamic>();
  _Job(this.fn);
}

void _runNextJob() {
  if (_activeJobs >= kGlobalTranslateConcurrency) return;
  if (_queue.isEmpty) return;
  final job = _queue.removeAt(0);
  _activeJobs++;
  () async {
    try {
      final v = await job.fn();
      if (!job.completer.isCompleted) job.completer.complete(v);
    } catch (e, st) {
      if (!job.completer.isCompleted) job.completer.completeError(e, st);
    } finally {
      _activeJobs--;
      _runNextJob();
    }
  }();
}

Future<String> _queueJob(Future<String> Function() fn) {
  final job = _Job(fn);
  _queue.add(job);
  _runNextJob();
  return job.completer.future.then((v) => v as String);
}

/// اجرای تسک‌های async با سقفِ هم‌زمانی (همان runWithConcurrencyLimit وب)
Future<List<R>> runWithConcurrencyLimit<T, R>(
  List<T> items,
  int limit,
  Future<R> Function(T item, int index) worker,
) async {
  final results = List<R?>.filled(items.length, null);
  var nextIndex = 0;
  Future<void> runNext() async {
    while (nextIndex < items.length) {
      final i = nextIndex++;
      results[i] = await worker(items[i], i);
    }
  }

  final n = items.isEmpty ? 0 : (limit < 1 ? 1 : (limit > items.length ? items.length : limit));
  await Future.wait(List.generate(n, (_) => runNext()));
  return results.cast<R>();
}

// ═══════════════════════════════════════════════════════════════════
// تنظیمات AI
// ═══════════════════════════════════════════════════════════════════
class AiSettings {
  final String backendUrl;
  const AiSettings({required this.backendUrl});

  /// دقیقاً مثل callAI وب: اگر خالی بود از DEFAULT_BACKEND_URL استفاده کن.
  String get baseUrl {
    final clean = backendUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return clean.isEmpty ? kDefaultBackendUrl : clean;
  }
}

/// آخرین دلیلِ فنیِ خطای AI (برای نمایش زیرِ پیامِ خطا و عیب‌یابی).
String kLastAiError = '';

class _AiBackendError implements Exception {
  final String message;
  _AiBackendError(this.message);
  @override
  String toString() => 'ai-backend-error: $message';
}

// ═══════════════════════════════════════════════════════════════════
// Main service
// ═══════════════════════════════════════════════════════════════════
class TranslationService {
  TranslationService()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(milliseconds: _kProviderTimeoutMs),
          receiveTimeout: const Duration(milliseconds: _kProviderTimeoutMs),
        )),
        _aiDio = Dio(BaseOptions(
          // پاسخ‌های غیر 2xx را خودمان بررسی می‌کنیم (برای 429 و ...)
          validateStatus: (_) => true,
        )) {
    // 🔐 هدرِ X-App-Token برای Worker (و تازه‌سازیِ خودکار با 401)
    _aiDio.interceptors.add(WorkerAuthInterceptor(_aiDio));
  }

  final Dio _dio;
  final Dio _aiDio;

  // ─── کش دائمی (حافظه + دیتابیس: IndexedDB روی وب / فایل روی موبایل) ───
  // کلید دقیقاً مثل وب: source::target::text — نگاه کن به TranslationCacheDb
  final TranslationCacheDb _db = TranslationCacheDb.instance;

  String _cacheKey(String text, String from, String to) =>
      '${from.isEmpty ? 'auto' : from}::$to::$text';

  Future<String?> _cacheGet(String text, String from, String to) {
    final v = _db.get(_cacheKey(text, from, to));
    return v.then((s) {
      if (s == null || s.isEmpty) return null;
      // مقدارِ هم‌شکلِ ذخیره‌شده فقط بعد از تأییدِ یک مترجمِ واقعی در کش نوشته شده
      _markCognate(text, s, to, from, strict: false);
      return s;
    });
  }

  /// خواندنِ سریع و همگام از کش (برای اسکرولِ روان: بدون await و بدون فلیکر).
  /// فقط اگر مقدارِ کش‌شده از کنترل کیفیت رد شود برمی‌گرداند؛ وگرنه null.
  String? peekCached(String text, String from, String to) {
    if (text.trim().isEmpty || to.isEmpty) return null;
    final pin = pinned(text, to);
    if (pin != null) return pin;
    final hard = _hardcodedFarewell(text, from, to);
    if (hard != null) return hard;
    final v = _db.peek(_cacheKey(text, from, to));
    if (v == null || v.isEmpty) return null;
    _markCognate(text, v, to, from, strict: false);
    return looksLikelyMistranslated(text, v, to, sourceLang: from)
        ? null
        : _fixFarewell(text, from, to, v);
  }

  // ═══ 📌 ترجمه‌های «قفل‌شده» (اصلاحِ دستیِ کاربر با دکمه‌ی ↻) ═══
  // مستقل از زبانِ مبدأ ذخیره می‌شوند و هیچ مسیرِ خودکاری (کنترل کیفیت، ML Kit،
  // بازبینیِ AI، ترجمه‌ی داستان، کشِ مشترک) حق ندارد جایگزینشان کند؛ فقط ↻ی بعدیِ خودِ کاربر.
  // کلیدِ قفل «نرمال‌شده» است: حروفِ بزرگ/کوچک، فاصله‌ی اضافه، نقطه و علائمِ نگارشی، و
  // نوعِ آپوستروف فرقی نمی‌کند؛ پس «Hello, world!» و «hello world» یک ترجمه‌ی قفل‌شده دارند.
  static String _normPin(String text) {
    var t = text
        .replaceAll('\u2019', "'")
        .replaceAll('\u2018', "'")
        .replaceAll('\u200c', ' ')
        .replaceAll(RegExp('[\u200b\u200d\u200e\u200f\u2066-\u2069]'), '')
        .toLowerCase();
    t = t.replaceAll(RegExp(r"[^\p{L}\p{N}']+", unicode: true), ' ').trim();
    t = t.replaceAll(RegExp(r"^'+|'+$"), '').replaceAll(RegExp(r"\s+'|'\s+"), ' ').trim();
    return t.isEmpty ? text.trim() : t;
  }

  String _pinKey(String text, String to) => '__pin__::$to::${_normPin(text)}';
  String _legacyPinKey(String text, String to) =>
      '__pin__::$to::${text.trim()}';

  /// خواندنِ همگامِ ترجمه‌ی قفل‌شده (null = نیست).
  String? pinned(String text, String to) {
    var v = _db.peek(_pinKey(text, to));
    if (v == null || v.isEmpty) v = _db.peek(_legacyPinKey(text, to));
    if (v == null || v.isEmpty) return null;
    _trustPinned(text, v, to);
    return v;
  }

  /// ترجمه‌ی قفل‌شده قبلاً کنترل کیفیت را رد کرده؛ اگر هم‌شکلِ متن است (cognate)
  /// بعد از ری‌استارتِ اپ هم نباید «ترجمه‌نشده» حساب شود (علامتِ cognate فقط در حافظه بود).
  void _trustPinned(String text, String v, String to) {
    if (text.trim().toLowerCase() == v.trim().toLowerCase()) {
      _confirmedSame.add(_sameKey(text, to));
    }
  }

  Future<String?> _pinnedAsync(String text, String to) async {
    var v = await _db.get(_pinKey(text, to));
    if (v == null || v.isEmpty) v = await _db.get(_legacyPinKey(text, to));
    if (v == null || v.isEmpty) return null;
    _trustPinned(text, v, to);
    return v;
  }

  /// قفل کردنِ ترجمه + نوشتنِ همان در کلیدِ عادی (برای بقیه‌ی خواننده‌های کش).
  Future<void> pinPut(String text, String from, String to, String value) async {
    final v = value.trim();
    if (v.isEmpty) return;
    await _db.put(_pinKey(text, to), v);
    await _db.put(_cacheKey(text, from, to), v);
  }

  /// ذخیره در کشِ دائمی (اگر ترجمه‌ی قفل‌شده دارد، دست نمی‌زند)
  Future<void> cachePut(
      String text, String from, String to, String value) async {
    if (await _pinnedAsync(text, to) != null) return;
    await _db.put(_cacheKey(text, from, to), value);
  }

  /// تعدادِ ترجمه‌های ذخیره‌شده روی دستگاه
  int get cachedCount => _db.count;

  // ═══════════════════════════════════════════════════════════════
  // API اصلی — معادلِ translateFree وب
  // ═══════════════════════════════════════════════════════════════
  Future<String> translate({
    required String text,
    required String targetLang,
    String sourceLang = 'auto',
    AiSettings? aiSettings,
    bool forceVerify = false,
  }) async {
    if (text.trim().isEmpty || targetLang.isEmpty) return text;
    if (sourceLang.isNotEmpty &&
        sourceLang != 'auto' &&
        sourceLang == targetLang) {
      return text;
    }
    // 📌 ترجمه‌ی اصلاح‌شده‌ی کاربر همیشه مقدم است (بدون کنترل کیفیت و بدون شبکه)
    final pin = await _pinnedAsync(text, targetLang);
    if (pin != null) return pin;

    final hardFarewell = _hardcodedFarewell(text, sourceLang, targetLang);
    if (hardFarewell != null) return hardFarewell;

    // ۱. کش — با چکِ کیفیت؛ کشِ مشکوک نادیده گرفته می‌شود
    final cached = await _cacheGet(text, sourceLang, targetLang);
    if (cached != null &&
        !looksLikelyMistranslated(text, cached, targetLang,
            sourceLang: sourceLang)) {
      return _fixFarewell(text, sourceLang, targetLang, cached);
    }

    // ۱.۵ کشِ مشترکِ همه‌ی کاربرها (ترجمه‌های اصلاح‌شده) — رایگان و سریع؛ نتیجه روی گوشی هم ذخیره می‌شود
    final base = aiSettings?.baseUrl ?? kDefaultBackendUrl;
    final shared =
        await SharedTranslations.fetchOne(base, sourceLang, targetLang, text);
    if (shared != null) {
      await cachePut(text, sourceLang, targetLang, shared);
      return _fixFarewell(text, sourceLang, targetLang, shared);
    }

    // ۲. صفِ سراسری؛ تایمر ۱۵ثانیه‌ای فقط از لحظه‌ی «اجرا» شروع می‌شود
    return _queueJob(() {
      final done = Completer<String>();
      final timer = Timer(const Duration(milliseconds: _kHardTimeoutMs), () {
        if (!done.isCompleted) done.complete(text);
      });
      translateNetwork(
        text: text,
        targetLang: targetLang,
        sourceLang: sourceLang,
        aiSettings: aiSettings,
        forceVerify: forceVerify,
      ).then((v) {
        if (!done.isCompleted) done.complete(v);
      }).catchError((_) {
        if (!done.isCompleted) done.complete(text);
      }).whenComplete(timer.cancel);
      return done.future;
    });
  }

  /// ترجمه‌ی دوباره (رفرش): بدون کش → دوباره سراغ مترجم‌های رایگان؛ اگر نتیجه
  /// مشکوک بود (یا عیناً همان ترجمه‌ی قبلی بود) یک AI به‌عنوان ناظر بررسی/اصلاح
  /// می‌کند؛ اگر باز هم نشد، آخرین چاره ترجمه‌ی مستقیم با AI. سقفِ زمانیِ کل
  /// ۲۵ ثانیه است تا دکمه هیچ‌وقت گیر نکند.
  Future<String> retranslate({
    required String text,
    required String targetLang,
    String sourceLang = 'en',
    AiSettings? aiSettings,
    String? previous,
  }) async {
    final hard = _hardcodedFarewell(text, sourceLang, targetLang);
    if (hard != null) return hard;
    final r = await _retranslate0(
      text: text,
      targetLang: targetLang,
      sourceLang: sourceLang,
      aiSettings: aiSettings,
      previous: previous,
    );
    final out = _fixFarewell(text, sourceLang, targetLang, r);
    // 📌 نتیجه‌ی ↻ برای همیشه روی دستگاه قفل می‌شود (حتی بعد از بستن/آپدیتِ برنامه)
    final o = out.trim();
    if (o.isNotEmpty &&
        o.toLowerCase() != text.trim().toLowerCase() &&
        !looksLikelyMistranslated(text, o, targetLang,
            sourceLang: sourceLang)) {
      await pinPut(text, sourceLang, targetLang, o);
      SharedTranslations.share(aiSettings?.baseUrl ?? kDefaultBackendUrl, text,
          sourceLang, targetLang, o);
    }
    return out;
  }

  Future<String> _retranslate0({
    required String text,
    required String targetLang,
    String sourceLang = 'en',
    AiSettings? aiSettings,
    String? previous,
  }) async {
    if (text.trim().isEmpty) return text;
    final ai = aiSettings;
    final prev = previous?.trim();

    bool bad(String r) =>
        r.trim().isEmpty ||
        looksLikelyMistranslated(text, r, targetLang, sourceLang: sourceLang);
    bool same(String r) =>
        prev != null && prev.isNotEmpty && r.trim() == prev;

    Future<String> run() async {
      // ۰. ML Kit (فقط برای تشخیصِ لغتِ هم‌شکل مثل hospital؛ نتیجه‌اش جایگزین نمی‌شود)
      try {
        final ml = await _viaMlKit(text, targetLang, sourceLang);
        if (ml != null) {
          _markCognate(text, ml, targetLang, sourceLang, strict: false);
        }
      } catch (_) {}

      // ۱. مترجم‌های رایگان (بدون کش)
      final providers = _freeProviders();
      var result = '';
      try {
        final winner =
            await _raceProviders(providers, text, targetLang, sourceLang);
        result = winner?.result ?? '';
        if (result.isNotEmpty) {
          _markCognate(text, result, targetLang, sourceLang);
        }
      } catch (_) {}

      // ۲. ناظر AI: فقط اگر مشکوک بود یا همان ترجمه‌ی قبلی تکرار شد
      if (ai != null && result.trim().isNotEmpty &&
          (bad(result) || same(result))) {
        result = await _verifyWithAI(text, targetLang, result, ai);
      }
      if (result.trim().isNotEmpty && !bad(result) && !same(result)) {
        await cachePut(text, sourceLang, targetLang, result);
        SharedTranslations.share(ai?.baseUrl ?? kDefaultBackendUrl, text,
            sourceLang, targetLang, result);
        return result;
      }

      // ۳. آخرین چاره: ترجمه‌ی مستقیم با AI
      if (ai != null) {
        try {
          final r = await translateViaAI(text, targetLang, sourceLang, ai,
              useShared: false);
          if (!bad(r)) {
            await cachePut(text, sourceLang, targetLang, r);
            SharedTranslations.share(ai.baseUrl, text, sourceLang, targetLang, r);
            return r;
          }
        } catch (_) {}
      }
      // اگر ترجمه‌ی سالمی هست (حتی تکراری) همان را بده؛ وگرنه متن اصلی
      return (result.trim().isNotEmpty && !bad(result)) ? result : text;
    }

    try {
      return await run().timeout(const Duration(seconds: 25));
    } catch (_) {
      return text;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // زنجیره‌ی شبکه — معادلِ translateFreeNetwork وب
  // ═══════════════════════════════════════════════════════════════
  Future<String> translateNetwork({
    required String text,
    required String targetLang,
    required String sourceLang,
    AiSettings? aiSettings,
    bool forceVerify = false,
  }) async {
    final hard = _hardcodedFarewell(text, sourceLang, targetLang);
    if (hard != null) return hard;
    final r = await _translateNetwork0(
      text: text,
      targetLang: targetLang,
      sourceLang: sourceLang,
      aiSettings: aiSettings,
      forceVerify: forceVerify,
    );
    return _fixFarewell(text, sourceLang, targetLang, r);
  }

  Future<String> _translateNetwork0({
    required String text,
    required String targetLang,
    required String sourceLang,
    AiSettings? aiSettings,
    bool forceVerify = false,
  }) async {
    // ۰. ML Kit روی گوشی: آنی، رایگان، بدون سقف و بدون هزینه‌ی Worker. اگر مدل آماده نبود
    //    دانلود در پس‌زمینه شروع می‌شود و همین‌بار از مسیر معمولِ زیر ترجمه می‌شود.
    String? mlDraft; // نتیجه‌ی ML Kit که مشکوکِ عمیق بود؛ اگر هیچ‌چیز بهتر نشد همین برمی‌گردد
    if (!forceVerify) {
      final ml = await _viaMlKit(text, targetLang, sourceLang);
      if (ml != null) {
        _markCognate(text, ml, targetLang, sourceLang, strict: false);
      }
      if (ml != null &&
          ml.trim().isNotEmpty &&
          !(aiSettings != null && _looksIdiomatic(text)) &&
          !looksLikelyMistranslated(text, ml, targetLang,
              sourceLang: sourceLang)) {
        if (_deepReviewOn(aiSettings) &&
            looksSuspiciousDeep(text, ml, sourceLang, targetLang)) {
          mlDraft = ml.trim();
        } else {
          await cachePut(text, sourceLang, targetLang, ml.trim());
          return ml.trim();
        }
      }
    }

    final providers =
        _freeProviders().where((p) => !_isProviderBlocked(p.name)).toList();

    final winner = await _raceProviders(providers, text, targetLang, sourceLang);

    if (winner != null) {
      var result = winner.result;
      _markCognate(text, result, targetLang, sourceLang);

      // فقط اگر مشکوک بود (یا forceVerify) با AI بررسی/اصلاح کن
      var aiFixed = false;
      if (aiSettings != null &&
          (forceVerify ||
              _looksIdiomatic(text) ||
              looksLikelyMistranslated(text, result, targetLang,
                  sourceLang: sourceLang) ||
              (_deepReviewOn(aiSettings) &&
                  looksSuspiciousDeep(
                      text, result, sourceLang, targetLang)))) {
        final before = result;
        result = await _verifyWithAI(text, targetLang, result, aiSettings);
        aiFixed = result.trim() != before.trim();
      }

      // اگر بعد از اصلاح هم مشکوک بود کش نکن — برو سراغ AI
      if (!looksLikelyMistranslated(text, result, targetLang,
          sourceLang: sourceLang)) {
        _reportProviderOutcome(winner.provider.name, true);
        await cachePut(text, sourceLang, targetLang, result);
        // 🗄️ اصلاحِ AI (هزینه داشت) برای بقیه‌ی کاربرها هم ذخیره شود تا دوباره AI صدا زده نشود
        if (aiFixed && aiSettings != null) {
          SharedTranslations.share(
              aiSettings.baseUrl, text, sourceLang, targetLang, result);
        }
        return result;
      }
    }

    // آخرین چاره: بک‌اند AI — این نتیجه هم از فیلتر کیفیت رد می‌شود
    final aiKey = RetryFlag.keyFor('ai', text, '$sourceLang>$targetLang');
    if (aiSettings != null && !RetryFlag.blocked(aiKey)) {
      try {
        final result =
            await translateViaAI(text, targetLang, sourceLang, aiSettings);
        if (result.trim().isNotEmpty &&
            !looksLikelyMistranslated(text, result, targetLang,
                sourceLang: sourceLang)) {
          RetryFlag.succeeded(aiKey);
          await cachePut(text, sourceLang, targetLang, result);
          return result;
        }
      } catch (_) {}
      RetryFlag.failed(aiKey);
    }

    if (mlDraft != null && mlDraft.isNotEmpty) {
      await cachePut(text, sourceLang, targetLang, mlDraft);
      return mlDraft;
    }
    return text; // هیچ سرویسی جواب نداد → متن اصلی (تا برنامه نیفتد)
  }

  /// دانلودِ مدلِ ML Kit در پس‌زمینه (Wi‑Fi و داده‌ی موبایل). هرگز خطا پرتاب نمی‌کند.
  Future<void> _mlDownload(String key, String source, String target) async {
    try {
      await NativeBridge.instance
          .mlkitDownload(src: source, tgt: target, wifiOnly: false);
      _mlReady.add(key);
    } catch (_) {
      _mlRetryAt[key] =
          DateTime.now().millisecondsSinceEpoch + _kMlKitRetryAfterMs;
    } finally {
      _mlDownloading.remove(key);
    }
  }

  /// ترجمه با ML Kit. null = استفاده نشد (iOS/وب، زبان نامشخص، جفت‌زبان پشتیبانی‌نشده، مدل هنوز دانلود نشده، یا خطا).
  /// دانلودِ مدل خودکار و بدون قید Wi‑Fi (داده‌ی موبایل هم) در پس‌زمینه شروع می‌شود.
  Future<String?> _viaMlKit(String text, String target, String source) async {
    try {
      final n = NativeBridge.instance;
      if (!n.isSupported) return null;
      if (source.isEmpty || source == 'auto' || source == target) return null;
      if (text.length > _kMlKitMaxChars) return null;
      final key = '$source>$target';

      if (!_mlReady.contains(key)) {
        final retryAt = _mlRetryAt[key];
        if (retryAt != null &&
            DateTime.now().millisecondsSinceEpoch < retryAt) {
          return null;
        }
        if (_mlDownloading.contains(key)) return null;
        final st = await n
            .mlkitStatus(src: source, tgt: target)
            .timeout(const Duration(seconds: 4));
        if (st['supported'] != true) return null;
        if (st['ready'] == true) {
          _mlReady.add(key);
        } else {
          if (st['downloading'] != true) {
            _mlDownloading.add(key);
            unawaited(_mlDownload(key, source, target));
          }
          return null;
        }
      }

      final r = await n
          .mlkitTranslate(text: text, src: source, tgt: target)
          .timeout(const Duration(seconds: 5));
      final t = r['text'];
      return t is String ? t : null;
    } catch (_) {
      return null;
    }
  }

  /// سرویس‌های آنلاینِ رایگان. در حالتِ تجاری (kAllowUnofficialTranslators=false) فقط MyMemory (API رسمی با سقف) می‌ماند؛
  /// google(gtx)/lingva غیررسمی‌اند و libre عمومی کلید می‌خواهد. بقیه‌ی زنجیره (کش، AI) بدون تغییر است.
  List<_Provider> _freeProviders() => <_Provider>[
        if (kAllowUnofficialTranslators) _Provider('google', _viaGoogle),
        _Provider('mymemory', _viaMyMemory),
        if (kAllowUnofficialTranslators) _Provider('lingva', _viaLingva),
        if (kAllowUnofficialTranslators) _Provider('libre', _viaLibre),
      ];

  /// مسابقه‌ی مترجم‌ها: اولین نتیجه‌ی «سالم» برنده است. اگر نتیجه‌ای از کنترل
  /// کیفیت رد شد (مثلاً جوابِ بی‌ربطِ MyMemory برای یک کلمه) فعلاً نگه داشته
  /// می‌شود و منتظرِ بقیه می‌مانیم؛ فقط اگر هیچ‌کدام سالم نبود همان اولی برمی‌گردد.
  Future<_Winner?> _raceProviders(
    List<_Provider> providers,
    String text,
    String targetLang,
    String sourceLang,
  ) {
    if (providers.isEmpty) return Future<_Winner?>.value(null);

    final completer = Completer<_Winner?>();
    var remaining = providers.length;
    var settled = false;
    _Winner? fallback;

    for (final p in providers) {
      Future<String?> f;
      try {
        f = p.call(text, targetLang, sourceLang);
      } catch (e) {
        f = Future.error(e);
      }
      f.then((result) {
        if (result != null && result.trim().isNotEmpty) {
          final good = !looksLikelyMistranslated(text, result, targetLang,
              sourceLang: sourceLang);
          if (good) {
            if (!settled) {
              settled = true;
              completer.complete(_Winner(result, p));
            }
          } else {
            fallback ??= _Winner(result, p);
          }
        } else {
          _reportProviderOutcome(p.name, false);
        }
      }).catchError((_) {
        _reportProviderOutcome(p.name, false);
      }).whenComplete(() {
        remaining--;
        if (remaining == 0 && !settled && !completer.isCompleted) {
          settled = true;
          completer.complete(fallback);
        }
      });
    }
    return completer.future;
  }

  // ═══════════════════════════════════════════════════════════════
  // Providers
  // ═══════════════════════════════════════════════════════════════
  dynamic _json(dynamic data) {
    if (data is String) {
      try {
        return jsonDecode(data);
      } catch (_) {
        return null;
      }
    }
    return data;
  }

  Future<String?> _viaGoogle(String text, String target, String source) async {
    final url =
        'https://translate.googleapis.com/translate_a/single?client=gtx&sl=${source.isEmpty ? 'auto' : source}&tl=$target&dt=t&q=${Uri.encodeComponent(text)}';
    final res = await _dio
        .get(url)
        .timeout(const Duration(milliseconds: _kProviderTimeoutMs));
    final data = _json(res.data);
    if (data is! List || data.isEmpty) throw Exception('google-empty-response');
    final chunks = data[0];
    if (chunks is! List || chunks.isEmpty) {
      throw Exception('google-empty-response');
    }
    return chunks
        .whereType<List>()
        .map((c) => (c.isNotEmpty && c[0] != null) ? c[0].toString() : '')
        .join();
  }

  Future<String?> _viaMyMemory(
      String text, String target, String source) async {
    final sl = (source == 'auto' || source.isEmpty) ? 'en' : source;
    final url =
        'https://api.mymemory.translated.net/get?q=${Uri.encodeComponent(text)}&langpair=$sl|$target';
    final res = await _dio
        .get(url)
        .timeout(const Duration(milliseconds: _kProviderTimeoutMs));
    final data = _json(res.data);
    if (data is! Map) throw Exception('mymemory-shape');
    final rd = data['responseData'];
    final translated =
        (rd is Map ? rd['translatedText']?.toString() : null) ?? '';
    if (translated.isEmpty) throw Exception('mymemory-empty-response');
    if (RegExp(r'^(PLEASE SELECT|INVALID |NO TRANSLATION|AMOUNT OF WORDS)',
            caseSensitive: false)
        .hasMatch(translated.trim())) {
      throw Exception('mymemory-api-error: $translated');
    }
    return translated;
  }

  Future<String?> _viaLingva(String text, String target, String source) async {
    final url =
        'https://lingva.ml/api/v1/${source.isEmpty ? 'auto' : source}/$target/${Uri.encodeComponent(text)}';
    final res = await _dio
        .get(url)
        .timeout(const Duration(milliseconds: _kProviderTimeoutMs));
    final data = _json(res.data);
    if (data is! Map) throw Exception('lingva-shape');
    final t = data['translation']?.toString() ?? '';
    if (t.isEmpty) throw Exception('lingva-empty-response');
    return t;
  }

  Future<String?> _viaLibre(String text, String target, String source) async {
    final res = await _dio
        .post(
          'https://libretranslate.de/translate',
          data: {
            'q': text,
            'source': source.isEmpty ? 'auto' : source,
            'target': target,
            'format': 'text',
          },
          options: Options(contentType: 'application/json'),
        )
        .timeout(const Duration(milliseconds: _kProviderTimeoutMs));
    final data = _json(res.data);
    if (data is! Map) throw Exception('libre-shape');
    final t = data['translatedText']?.toString() ?? '';
    if (t.isEmpty) throw Exception('libre-empty-response');
    return t;
  }

  // ═══════════════════════════════════════════════════════════════
  // callAI — پورتِ دقیقِ app/ai/callAI.js (retry، 429، timeout، کفِ توکن)
  // ═══════════════════════════════════════════════════════════════
  static const String _aiNetMsg =
      "The AI isn't responding. Check your internet connection and try again.";

  Future<String> callAI({
    required String prompt,
    int? maxTokens,
    int retries = 2,
    required AiSettings settings,
    int timeoutMs = _kAiTimeoutMs,
    // 💎 نسخه‌ی رایگان: نامِ بخش (برای سقفِ «کل عمر») — null = شمرده نمی‌شود (مثلاً ترجمه)
    String? feature,
    String? useId,
    // false = پنجره‌ی «سقف تمام شد» خودکار نشان داده نشود (مثلاً ساختِ خودکارِ مثال)
    bool reportLimit = true,
  }) async {
    final url = '${settings.baseUrl}/api/generate';
    final fUseId = feature == null ? null : (useId ?? FreeLimit.newUseId());
    final tokens = (maxTokens ?? 300).clamp(64, 8192).toInt();
    final body = {'prompt': prompt, 'maxTokens': tokens};

    for (var attempt = 0;; attempt++) {
      try {
        final res = await _aiDio
            .post(
              url,
              data: body,
              options: Options(
                contentType: 'application/json',
                headers: {
                  if (feature != null) 'X-Feature': feature,
                  if (fUseId != null) 'X-Use-Id': fUseId,
                },
                sendTimeout: Duration(milliseconds: timeoutMs),
                receiveTimeout: Duration(milliseconds: timeoutMs),
              ),
            )
            .timeout(Duration(milliseconds: timeoutMs));

        final status = res.statusCode ?? 0;
        if (status == 402) {
          // سقفِ استفاده‌ی رایگانِ این بخش تمام شده → بدونِ تلاشِ دوباره
          if (reportLimit) FreeLimit.report(feature ?? '');
          throw FreeLimitException(feature ?? '');
        }
        if (status < 200 || status >= 300) {
          var detail = 'HTTP $status';
          final isRateLimited = status == 429;
          final isClientError = status >= 400 && status < 500 && !isRateLimited;
          final errBody = _json(res.data);
          if (errBody is Map && errBody['error'] != null) {
            detail = errBody['error'].toString();
          }
          // سقفِ روزانه‌ی سرور پر شده → بدونِ صبر و تلاشِ دوباره، فوراً پیامِ روشن
          final errCode = errBody is Map ? errBody['code']?.toString() : null;
          if (isRateLimited &&
              (errCode == 'daily_feature_limit' || errCode == 'daily_limit')) {
            kLastAiError = 'HTTP 429 — $errCode';
            throw _AiBackendError(
                'سقف استفاده‌ی امروز تمام شد. فردا دوباره امتحان کن.');
          }
          final maxAttempts = isRateLimited ? (retries > 1 ? retries : 1) : retries;
          if ((!isClientError || isRateLimited) && attempt < maxAttempts) {
            final m = RegExp(r'try again in\s+(\d+(?:\.\d+)?)s',
                    caseSensitive: false)
                .firstMatch(detail);
            final waitMs = isRateLimited
                ? ((m != null ? double.parse(m.group(1)!) : 15) * 1000).ceil() +
                    500
                : 700 * (attempt + 1);
            await Future.delayed(Duration(milliseconds: waitMs));
            continue;
          }
          kLastAiError = 'HTTP $status — ${detail.length > 220 ? detail.substring(0, 220) : detail}';
          throw _AiBackendError(
              (status >= 500 || isRateLimited) ? _aiNetMsg : detail);
        }

        final data = _json(res.data);
        final rawText = (data is Map ? data['text']?.toString() : null) ?? '';
        // خروجیِ گارد/ایمنی جواب نیست → مثل پاسخِ خالی، دوباره امتحان / خطا
        final text = _aiGuardRe.hasMatch(rawText) ? '' : rawText;
        if (text.isEmpty) {
          if (attempt < retries) {
            await Future.delayed(Duration(milliseconds: 700 * (attempt + 1)));
            continue;
          }
          kLastAiError = rawText.isEmpty
              ? 'پاسخ خالی از Worker'
              : 'خروجی گارد/ایمنی از Worker (Worker قدیمی؟)';
          throw _AiBackendError(_aiNetMsg);
        }
        return text;
      } on FreeLimitException {
        rethrow;
      } on _AiBackendError {
        rethrow;
      } catch (e) {
        if (attempt < retries) {
          await Future.delayed(Duration(milliseconds: 700 * (attempt + 1)));
          continue;
        }
        final es = e.toString();
        kLastAiError = es.length > 220 ? es.substring(0, 220) : es;
        throw _AiBackendError(_aiNetMsg);
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ترجمه با AI — معادلِ translateViaAI وب
  // ═══════════════════════════════════════════════════════════════
  Future<String> translateViaAI(
    String text,
    String target,
    String source,
    AiSettings? settings, {
    bool useShared = true,
  }) async {
    if (settings == null) throw Exception('translate-ai-no-settings');
    // 🗄️ اول کشِ مشترکِ سرور (ترجمه‌ی قبلیِ بقیه‌ی کاربرها)؛ اگر نبود/در دسترس نبود همان مسیرِ قبلی.
    if (useShared) {
      final shared = await _viaSharedCache(text, target, source, settings);
      if (shared != null) return shared;
    }
    final targetLabel = englishLangName(target);
    final prompt =
        'Translate the following text into $targetLabel by meaning, the way a native speaker would naturally say it. '
        'Idioms, slang, rhyming or fixed expressions and greeting/farewell formulas must be rendered with their real meaning '
        'or a natural $targetLabel equivalent — never word for word '
        '(e.g. "See you later, alligator!" is just a playful goodbye: drop the animal and the rhyme). '
        'Respond with ONLY the translation itself — no quotes, no explanation, no original text, nothing else.\n\n'
        'Text: $text';

    String clean(String r) => _stripQuotes(stripAIReasoning(r));

    // سقفِ توکن متناسب با طولِ متن (قبلاً همیشه ۲۰۰)
    final tr = (text.length ~/ 2 + 96).clamp(128, 400).toInt();
    var cleaned = clean(await callAI(
        prompt: prompt, maxTokens: tr, retries: 1, settings: settings));

    if (cleaned.isEmpty ||
        looksLikeAIReasoning(cleaned) ||
        looksLikeGuardOutput(cleaned)) {
      final strict =
          'Output ONLY the $targetLabel translation of the text below, as a single line. '
          'Do not think aloud, do not analyze, do not explain, do not use lists or markdown.\n\n'
          'Text: $text\n\n$targetLabel translation:';
      cleaned = clean(await callAI(
          prompt: strict, maxTokens: tr, retries: 0, settings: settings));
    }

    if (cleaned.isEmpty) throw Exception('translate-ai-empty-response');
    if (looksLikeAIReasoning(cleaned)) {
      throw Exception('translate-ai-reasoning-leak');
    }
    if (looksLikeGuardOutput(cleaned)) {
      throw Exception('translate-ai-guard-output');
    }
    return cleaned;
  }

  /// 🕵️ بازبینِ AI برای ترجمه‌ی مشکوک (اصطلاح/محاوره/عبارتِ ثابت که مترجم‌ها کلمه‌به‌کلمه ترجمه می‌کنند،
  /// مثلاً یک اصطلاحِ فارسی که «don't break» می‌شود). ترجمه‌ی ماشینی را می‌گیرد و اگر تحت‌اللفظی/غیرطبیعی
  /// بود، معادلِ طبیعیِ همان معنا را در زبانِ مقصد برمی‌گرداند؛ وگرنه همان ترجمه.
  /// هیچ‌وقت نمی‌اندازد: در هر خطا/خروجیِ نامعتبر همان [translation] برمی‌گردد.
  /// (سقفِ «کل عمر» را مصرف نمی‌کند؛ پرامپتِ یکسان از کشِ سرور هم جواب می‌گیرد.)
  Future<String> reviewTranslation({
    required String source,
    required String translation,
    required String targetLang,
    String sourceLang = 'auto',
    required AiSettings? aiSettings,
  }) async {
    final src = source.trim();
    final tr = translation.trim();
    if (aiSettings == null || src.isEmpty || tr.isEmpty) return translation;
    if (src.length > 300) return translation; // متنِ بلند = داستان/متن، نه لغت/عبارت
    final tgt = englishLangName(targetLang);
    final from = (sourceLang.isEmpty || sourceLang == 'auto')
        ? 'its original language'
        : englishLangName(sourceLang);
    final prompt =
        'You are a strict translation reviewer for a language-learning app. '
        'A learner typed a word or phrase in $from: "$src"\n'
        'A machine translation into $tgt gave: "$tr"\n\n'
        'Decide whether that translation is a literal, word-for-word rendering that is wrong, '
        'unnatural or loses the real meaning of an idiom, slang, colloquial or fixed expression '
        '(for example a figurative phrase translated by its separate words).\n'
        '- If it is correct and natural, output it unchanged.\n'
        '- If not, output the natural $tgt equivalent a native speaker would actually say '
        '(an idiom or common phrase with the same meaning and register; keep it short).\n'
        'Output ONLY the final $tgt text on a single line — no quotes, no explanation, no notes.';
    try {
      final tokens = (tr.length ~/ 2 + 64).clamp(96, 240).toInt();
      var out = _stripQuotes(stripAIReasoning(await callAI(
          prompt: prompt, maxTokens: tokens, retries: 1, settings: aiSettings)));
      out = out.split('\n').first.trim();
      if (out.isEmpty ||
          looksLikeAIReasoning(out) ||
          looksLikeGuardOutput(out) ||
          out.length > tr.length * 3 + 40) {
        return translation;
      }
      return out;
    } catch (_) {
      return translation;
    }
  }

  /// ترجمه‌ی متنِ کوتاه از طریقِ Worker با کشِ مشترکِ همه‌ی کاربرها (/api/translate-text).
  /// null = استفاده نشد یا نشد (متنِ بلند، زبانِ پشتیبانی‌نشده، خطای شبکه/سرور) → مسیرِ قبلیِ AI ادامه می‌یابد.
  Future<String?> _viaSharedCache(
      String text, String target, String source, AiSettings settings) async {
    final t = text.trim();
    if (t.isEmpty || t.length > _kSharedMaxChars) return null;
    if (!_englishNames.containsKey(target)) return null;
    final src = source.isEmpty ? 'auto' : source;
    if (src != 'auto' && !_englishNames.containsKey(src)) return null;
    try {
      final res = await _aiDio
          .post(
            '${settings.baseUrl}/api/translate-text',
            data: {
              'text': t,
              'source_lang_code': src,
              'target_lang_code': target,
            },
            options: Options(
              contentType: 'application/json',
              sendTimeout: const Duration(milliseconds: _kAiTimeoutMs),
              receiveTimeout: const Duration(milliseconds: _kAiTimeoutMs * 2),
            ),
          )
          .timeout(const Duration(milliseconds: _kAiTimeoutMs * 2));
      final status = res.statusCode ?? 0;
      if (status < 200 || status >= 300) return null;
      final data = _json(res.data);
      final out = data is Map ? data['text'] : null;
      if (out is! String) return null;
      final cleaned = _stripQuotes(stripAIReasoning(out));
      if (cleaned.isEmpty ||
          looksLikeAIReasoning(cleaned) ||
          looksLikeGuardOutput(cleaned)) {
        return null;
      }
      return cleaned;
    } catch (_) {
      return null;
    }
  }

  Future<String> _verifyWithAI(
    String source,
    String target,
    String draft,
    AiSettings settings,
  ) async {
    try {
      final targetLabel = englishLangName(target);
      final prompt =
          'Source text: "$source"\n'
          'Draft translation into $targetLabel: "$draft"\n\n'
          'Judge the draft by meaning, not wording. If the source is an idiom, slang, a rhyming or fixed expression, '
          'a greeting/farewell formula or a figure of speech, the draft must be the natural $targetLabel equivalent '
          'a native speaker would actually say — a word-for-word rendering is wrong '
          '(e.g. "See you later, alligator!" is just a playful goodbye: drop the animal and the rhyme).\n'
          'Is the draft accurate, natural and complete? If yes, reply with EXACTLY: OK\n'
          'If no, reply with ONLY the corrected translation — no quotes, no explanation, nothing else.';
      // سقفِ توکن متناسب با طولِ متن (قبلاً ثابتِ ۸۰ بود و اصلاحِ جمله‌های بلند وسط بریده می‌شد)
      final capTokens =
          ((source.length > draft.length ? source.length : draft.length) * 1.3 + 96)
              .round()
              .clamp(96, 1200)
              .toInt();
      final result = await callAI(
          prompt: prompt, maxTokens: capTokens, retries: 0, settings: settings);
      final cleaned = stripAIReasoning(result);
      if (cleaned.isEmpty ||
          RegExp(r'^OK\.?$', caseSensitive: false).hasMatch(cleaned) ||
          looksLikeAIReasoning(cleaned)) {
        return draft;
      }
      if (looksLikeGuardOutput(cleaned)) return draft;
      final fixed = _stripQuotes(cleaned);
      if (fixed.isEmpty) return draft;
      // «اصلاح»ی که چند برابرِ پیش‌نویس است ترجمه نیست
      if (draft.isNotEmpty && fixed.length > draft.length * 3 + 20) return draft;
      return fixed;
    } catch (_) {
      return draft;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ترجمه‌ی «داخل جمله»ی یک کلمه — معادلِ translateWordInContext وب
  // ═══════════════════════════════════════════════════════════════
  static const String _alignL = '⟦';
  static const String _alignR = '⟧';

  Future<String?> translateWordInContext({
    required String sentenceText,
    required String word,
    required String sourceLang,
    required String targetLang,
    AiSettings? aiSettings,
  }) async {
    if (sentenceText.isEmpty || word.isEmpty) return null;
    var idx = findWholeWordIndex(sentenceText, word);
    if (idx == -1) {
      idx = sentenceText.toLowerCase().indexOf(word.toLowerCase());
    }
    if (idx == -1) return null;
    final wrapped = sentenceText.substring(0, idx) +
        _alignL +
        sentenceText.substring(idx, idx + word.length) +
        _alignR +
        sentenceText.substring(idx + word.length);
    try {
      final translated = await translate(
        text: wrapped,
        targetLang: targetLang,
        sourceLang: sourceLang,
        aiSettings: aiSettings,
      );
      final m = RegExp('$_alignL([^$_alignR]*)$_alignR').firstMatch(translated);
      if (m != null && (m.group(1) ?? '').trim().isNotEmpty) {
        return m.group(1)!.trim();
      }
    } catch (_) {}
    return null;
  }
}

/// جستجوی «کلمه‌ی کامل» — معادلِ findWholeWordIndex وب
int findWholeWordIndex(String haystack, String needle) {
  if (haystack.isEmpty || needle.isEmpty) return -1;
  final h = haystack.toLowerCase();
  final n = needle.toLowerCase();
  final wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);
  bool isWordChar(String ch) => ch.isNotEmpty && wordChar.hasMatch(ch);
  var from = 0;
  while (true) {
    final idx = h.indexOf(n, from);
    if (idx == -1) return -1;
    final before = idx > 0 ? h[idx - 1] : '';
    final after = idx + n.length < h.length ? h[idx + n.length] : '';
    if (!isWordChar(before) && !isWordChar(after)) return idx;
    from = idx + 1;
  }
}

class _Provider {
  final String name;
  final Future<String?> Function(String text, String target, String source) call;
  _Provider(this.name, this.call);
}

class _Winner {
  final String result;
  final _Provider provider;
  _Winner(this.result, this.provider);
}
