import '../config/backend_config.dart';
import '../usage/free_limit.dart';
import '../usage/pro_status.dart' show ProStatus;
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import '../auth/worker_auth.dart';
import '../native/native_bridge.dart';
import '../storage/translation_cache_db.dart';
import 'bundled_translations.dart';
import 'romanization.dart';
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
const String kDefaultBackendUrl = kBackendBaseUrl;

/// 💸 قانونِ طلاییِ هزینه: true = AI فقط برای ترجمه‌ی «مشکوک/اصطلاح» صدا زده می‌شود؛
/// نبودِ پیش‌نویسِ رایگان (ML Kit/مترجمِ آنلاین) ≠ مشکوک، پس AI نمی‌رود و متنِ اصلی برمی‌گردد (کاربر با ↻ می‌تواند AI بخواهد).
/// برای برگشت به رفتارِ قبلی (AI به‌عنوان آخرین چاره) false کن.
const bool kAiOnlyIfSuspiciousDefault = true;

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
  r'|under the weather|an arm and a leg|bite the bullet|once in a blue moon|hit the sack'
  r'|break the ice|call it a day|let the cat out of the bag|pull(?:ing)? (?:my|your|his|her) leg'
  r'|get(?:ting)? cold feet|beat(?:ing)? around the bush|burn(?:ing)? the midnight oil'
  r'|back to square one|blessing in disguise|easier said than done|the ball is in your court'
  r'|out of the blue|a dime a dozen|speak of the devil|let sleeping dogs lie'
  r'|barking up the wrong tree|the last straw|add insult to injury|over the moon|on cloud nine'
  r'|in hot water|throw in the towel|jump on the bandwagon|miss the boat|go the extra mile'
  r'|cost(?:s|ing)? a fortune|cut corners|cross that bridge|devil\x27s advocate|face the music'
  r'|fall head over heels|get out of hand|hang in there'
  r'|hit the nail on the head|in the same boat|keep your fingers crossed'
  r'|learn the ropes|make ends meet|no pain,? no gain|on the fence|once and for all'
  r'|play it by ear|pull yourself together|rule of thumb|see eye to eye'
  r'|sit tight|take it easy|the whole nine yards|through thick and thin|time flies'
  r'|up in the air|walk on eggshells|water under the bridge'
  r'|you can\x27t judge a book by its cover|when pigs fly|your guess is as good as mine'
  r'|long time no see|how come|what\x27s up|no worries|fingers crossed)\b',
  caseSensitive: false,
);

bool _looksIdiomatic(String text) => _idiomRe.hasMatch(text);

/// اصطلاح/عبارتِ ثابت؟ (برای بخش‌های دیگر: اگر true، ترجمه‌ی ماشینی مشکوک است و AI بازبینی می‌کند)
bool looksIdiomatic(String text) => _looksIdiomatic(text);

/// 🔎 «مشکوک» بودنِ یک ترجمه‌ی رایگان (ML Kit / مترجم آنلاین) — تنها منبعِ تصمیم برای رفتن سراغ AI.
/// true اگر: اصطلاح باشد، یا فیلترِ سبک (looksLikelyMistranslated) یا فیلترِ عمیق (looksSuspiciousDeep) رد کند.
/// ترجمه‌ی سالم = false = هیچ هزینه‌ی AI.
bool needsAiReview(String src, String draft, String from, String to) {
  if (_looksIdiomatic(src)) return true;
  if (looksLikelyMistranslated(src, draft, to, sourceLang: from)) return true;
  // فیلترِ عمیق مثلِ بقیه‌ی مسیرها فقط برای Pro فعال است (همان _deepReviewOn)
  return ProStatus.isPro && looksSuspiciousDeep(src, draft, from, to);
}

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
  /// هر بار که کاربر با ↻ ترجمه‌ای را اصلاح (قفل) کند خبر می‌دهد؛
  /// صفحه‌های تمرین/ویدیو کال از آن برای به‌روزرسانیِ فوریِ ترجمه‌هایشان استفاده می‌کنند.
  static final StreamController<void> pinEvents =
      StreamController<void>.broadcast();

  /// پیامِ کوتاه بعد از ↻ (AppShell نشانش می‌دهد): 'confirmed' = ترجمه‌ی جدید با قبلی یکی بود (بدونِ AI تأیید شد)،
  /// 'restored' = سقفِ ↻ پر بود و به ترجمه‌ی اول برگشتیم، 'limit' = سقفِ روزانه‌ی ↻ برای این متن پر شده، 'alt' = ترجمه‌ی جدید به‌عنوان «گزینه‌ی دوم» کنارِ قبلی ماند.
  static final StreamController<String> refreshNotices =
      StreamController<String>.broadcast();

  /// سقفِ ↻ برای هر متن (و هر زبانِ مقصد) در روز، روی همین دستگاه.
  static const int kRefreshPerTextPerDay = 2;

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
    // 📦 ترجمه‌ی آماده‌ی داخلِ اپ (فقط محتوای رایگان)
    unawaited(BundledTranslations.ensureLoaded());
    final bundled = BundledTranslations.get(text, from, to);
    if (bundled != null) return bundled;
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
    pinEvents.add(null);
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
    bool aiOnlyIfSuspicious = kAiOnlyIfSuspiciousDefault,
    // 🎭 لغتِ نوعِ «اصطلاح/عامیانه» (pos از دیتابیس): مثلِ اصطلاح، ترجمه‌ی رایگانش مشکوک حساب می‌شود
    bool treatAsIdiom = false,
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

    // 📦 ترجمه‌ی آماده‌ی داخلِ اپ (فقط محتوای رایگان): بدون کش، شبکه و AI
    await BundledTranslations.ensureLoaded();
    final bundled = BundledTranslations.get(text, sourceLang, targetLang);
    if (bundled != null) return bundled;

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
        aiOnlyIfSuspicious: aiOnlyIfSuspicious,
        treatAsIdiom: treatAsIdiom,
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
  // ═══ ↻ حرفه‌ای: تأییدِ هوشمند + سقفِ روزانه + نگه‌داشتنِ ترجمه‌ی قبلی ═══
  String _refreshCountKey(String text, String to) {
    final d = DateTime.now().toUtc();
    final day = '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
    return '__rf__::$day::$to::${_normPin(text)}';
  }

  String _altKey(String text, String to) => '__alt__::$to::${_normPin(text)}';

  /// ترجمه‌ی «اولِ» هر متن (قبل از اولین ↻). وقتی سقفِ ↻ پر شد و کاربر باز هم زد، به همین برمی‌گردیم:
  /// کاربری که زبانِ مقصد را بلد نیست نمی‌تواند ترجمه‌ی ↻‌شده را بسنجد و نباید تا فردا گیرش بماند.
  String _origKey(String text, String to) => '__orig__::$to::${_normPin(text)}';

  /// «گزینه‌ی دوم» (ترجمه‌ی جدیدِ ↻ که جایگزینِ قبلی نشد). null = نیست.
  String? alternative(String text, String to) {
    final v = _db.peek(_altKey(text, to));
    return (v == null || v.trim().isEmpty) ? null : v;
  }

  /// کاربر گزینه‌ی دوم را برگزید → قفل می‌شود و جای قبلی را می‌گیرد.
  Future<String?> chooseAlternative(String text, String from, String to) async {
    final v = alternative(text, to);
    if (v == null) return null;
    await pinPut(text, from, to, v);
    await _db.put(_altKey(text, to), '');
    return v;
  }

  /// کاربر گزینه‌ی دوم را نخواست → کنار گذاشته می‌شود (ترجمه‌ی قبلی می‌ماند).
  Future<void> dismissAlternative(String text, String to) =>
      _db.put(_altKey(text, to), '');

  /// 🆓 وقتی سقفِ روزانه‌ی ↻ پر شده: ترجمه‌ی «رایگان» (اول ML Kit، بعد مترجم‌های آنلاین) بدونِ AI،
  /// بدونِ شمردنِ سقف و بدونِ نوشتن در کش. فقط اگر با ترجمه‌ی فعلی ([base]) فرق داشته باشد و سالم
  /// باشد برمی‌گردد؛ وگرنه null. کاربر آن را به‌عنوان «گزینه‌ی دوم» همراهِ ترجمه‌ی برگشتی می‌بیند.
  Future<String?> freeAlternative(
      String text, String from, String to, String base) async {
    bool ok(String x) =>
        x.isNotEmpty &&
        x != base.trim() &&
        x.toLowerCase() != text.trim().toLowerCase() &&
        !looksLikelyMistranslated(text, x, to, sourceLang: from);
    try {
      var r = '';
      try {
        r = (await _viaMlKit(text, to, from))?.trim() ?? '';
      } catch (_) {}
      if (!ok(r)) {
        r = '';
        try {
          final w = await _raceProviders(_freeProviders(), text, to, from);
          r = (w?.result ?? '').trim();
        } catch (_) {}
      }
      return ok(r) ? r : null;
    } catch (_) {
      return null;
    }
  }

  /// 🚦 یک «سهمِ ↻» برای این متن (و زبانِ مقصد) برمی‌دارد. false = سقفِ روزانه پر است (پیامِ 'limit' هم می‌آید)
  /// و نباید هیچ تماسِ شبکه/AI زده شود. برای مسیرهایی که خودشان قبل از AI سقف را چک می‌کنند
  /// (مثل reviewedTranslate) و بعد retranslate را با skipQuota صدا می‌زنند تا دوبار نشمرد.
  Future<bool> takeRefreshSlot(String text, String to) async {
    final ck = _refreshCountKey(text, to);
    final n = int.tryParse(await _db.get(ck) ?? '') ?? 0;
    if (n >= kRefreshPerTextPerDay) {
      refreshNotices.add('limit');
      return false;
    }
    await _db.put(ck, '${n + 1}');
    return true;
  }

  // 🛟 آخرین _retranslate0 با «چاره‌ی آخر» (ML Kit/کش) جواب داد؛ چنین ترجمه‌ای برای همیشه قفل (pin) نمی‌شود
  bool _retranslateWeak = false;

  Future<String> retranslate({
    required String text,
    required String targetLang,
    String sourceLang = 'en',
    AiSettings? aiSettings,
    String? previous,
    // true = سقفِ روزانه را خودِ صدازننده قبلاً شمرده (takeRefreshSlot)؛ اینجا دوباره نشمار.
    bool skipQuota = false,
    // true = ترجمه‌ی جدید جایگزینِ قبلی نمی‌شود؛ به‌عنوان «گزینه‌ی دوم» ذخیره می‌شود (alternative) و قبلی برمی‌گردد.
    bool keepPrevious = false,
  }) async {
    final hard = _hardcodedFarewell(text, sourceLang, targetLang);
    if (hard != null) return hard;

    // ترجمه‌ی فعلی (برای مقایسه/سقف): آنچه UI نشان می‌دهد، وگرنه قفل‌شده/کش
    var base = previous?.trim() ?? '';
    if (base.isEmpty) {
      base = pinned(text, targetLang)?.trim() ??
          _db.peek(_cacheKey(text, sourceLang, targetLang))?.trim() ??
          '';
    }
    final hasBase = base.isNotEmpty && base.toLowerCase() != text.trim().toLowerCase();

    // 🚦 سقفِ روزانه برای هر متن: بعد از N بار، بدونِ هیچ تماسِ شبکه/AI همان ترجمه‌ی فعلی
    if (hasBase && !skipQuota) {
      final ck = _refreshCountKey(text, targetLang);
      final n = int.tryParse(await _db.get(ck) ?? '') ?? 0;
      final ok = _origKey(text, targetLang);
      final orig = (await _db.get(ok))?.trim() ?? '';
      if (orig.isEmpty) await _db.put(ok, base); // اولین ↻ِ این متن: ترجمه‌ی اول را نگه دار
      if (n >= kRefreshPerTextPerDay) {
        // 🆓 سقف پر است ولی کاربر نباید تا فردا گیر کند: ترجمه‌ی رایگانِ ML Kit/آنلاین به‌عنوان
        // «گزینه‌ی دوم» (همراهِ ترجمه‌ی برگشتی) نشان داده می‌شود؛ انتخاب با خودش.
        if (keepPrevious) {
          if (alternative(text, targetLang) != null) {
            refreshNotices.add('altfree');
            return base;
          }
          final fa = await freeAlternative(text, sourceLang, targetLang, base)
              .timeout(const Duration(seconds: 15), onTimeout: () => null);
          if (fa != null) {
            await _db.put(_altKey(text, targetLang), fa);
            refreshNotices.add('altfree');
            return base;
          }
        }
        // 🔙 بار سوم: اگر ترجمه‌ی فعلی با اولی فرق دارد، به ترجمه‌ی اول برگرد
        if (orig.isNotEmpty && orig != base) {
          await pinPut(text, sourceLang, targetLang, orig);
          await _db.put(_altKey(text, targetLang), '');
          refreshNotices.add('restored');
          return orig;
        }
        refreshNotices.add('limit');
        return base;
      }
      await _db.put(ck, '${n + 1}');
    }

    var sameHit = false;
    final r0 = await _retranslate0(
      text: text,
      targetLang: targetLang,
      sourceLang: sourceLang,
      aiSettings: aiSettings,
      previous: hasBase ? base : previous,
      onSame: () => sameHit = true,
    );
    // ✅ تأییدِ هوشمند: ترجمه‌ی جدید با قبلی یکی بود → AI صدا زده نشد
    if (sameHit && hasBase) {
      refreshNotices.add('confirmed');
      return base;
    }
    final weak = _retranslateWeak;
    final out0 = _fixFarewell(text, sourceLang, targetLang, r0.text);

    // 🗂️ نگه‌داشتنِ قبلی: جدید فقط «گزینه‌ی دوم» می‌شود
    if (keepPrevious && hasBase) {
      final o = out0.trim();
      // _retranslate0 در کشِ عادی نوشته بود؛ قبلی را برگردان (قفل‌شده‌ها که دست‌نخورده‌اند)
      await _db.put(_cacheKey(text, sourceLang, targetLang), base);
      if (o.isNotEmpty &&
          o != base &&
          o.toLowerCase() != text.trim().toLowerCase() &&
          !looksLikelyMistranslated(text, o, targetLang, sourceLang: sourceLang)) {
        await _db.put(_altKey(text, targetLang), o);
        refreshNotices.add('alt');
      }
      return base;
    }
    final out = out0;
    // 📌 نتیجه‌ی ↻ برای همیشه روی دستگاه قفل می‌شود (حتی بعد از بستن/آپدیتِ برنامه)
    final o = out.trim();
    if (!weak &&
        o.isNotEmpty &&
        o.toLowerCase() != text.trim().toLowerCase() &&
        !looksLikelyMistranslated(text, o, targetLang,
            sourceLang: sourceLang)) {
      await pinPut(text, sourceLang, targetLang, o);
      // 🔒 ↻ فقط برای خودِ کاربر قفل می‌شود. فقط اگر AI تأییدش کرده باشد به‌عنوان «پیشنهاد» به
      // سرور می‌رود؛ سرور هرگز با آن ترجمه‌ی موجودِ کشِ مشترک را جایگزین نمی‌کند.
      if (r0.aiApproved && o == r0.text.trim()) {
        SharedTranslations.share(aiSettings?.baseUrl ?? kDefaultBackendUrl,
            text, sourceLang, targetLang, o,
            aiVerified: true);
      }
    }
    return out;
  }

  /// aiApproved = نتیجه را خودِ AI ساخته یا اصلاح/تأیید کرده (فقط همین‌ها لایقِ پیشنهاد به سرورند).
  Future<({String text, bool aiApproved})> _retranslate0({
    required String text,
    required String targetLang,
    String sourceLang = 'en',
    AiSettings? aiSettings,
    String? previous,
    void Function()? onSame,
  }) async {
    _retranslateWeak = false;
    if (text.trim().isEmpty) return (text: text, aiApproved: false);
    final ai = aiSettings;
    final prev = previous?.trim();

    bool bad(String r) =>
        r.trim().isEmpty ||
        looksLikelyMistranslated(text, r, targetLang, sourceLang: sourceLang);
    bool same(String r) =>
        prev != null && prev.isNotEmpty && r.trim() == prev;

    // 🛟 چاره‌ی آخر وقتی مترجم‌های رایگان/AI هیچ‌کدام جواب ندادند (مثلاً اینترنتِ محدود یا AI در دسترس نیست):
    // ۱) ترجمه‌ی ML Kit روی گوشی  ۲) ترجمه‌ی موجود در کش. فقط وقتی ترجمه‌ی قبلی‌ای در کار نیست
    // (ردیفِ «ترجمه نشد»)؛ وگرنه ↻ نباید ترجمه‌ی ضعیف‌تر را به‌عنوان گزینه‌ی دوم بیاورد.
    String? mlSaved;
    String? lastResort() {
      if (prev != null && prev.isNotEmpty) return null;
      final m = mlSaved?.trim() ?? '';
      if (m.isNotEmpty && !bad(m)) return m;
      final c =
          _db.peek(_cacheKey(text, sourceLang, targetLang))?.trim() ?? '';
      if (c.isNotEmpty && !bad(c)) return c;
      return null;
    }

    Future<({String text, bool aiApproved})> run() async {
      // ۰. ML Kit (برای تشخیصِ لغتِ هم‌شکل مثل hospital؛ و نگه‌داشتن به‌عنوانِ چاره‌ی آخر)
      try {
        final ml = await _viaMlKit(text, targetLang, sourceLang);
        if (ml != null) {
          mlSaved = ml;
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

      // ✅ تأییدِ هوشمند: مترجم‌ها همان ترجمه‌ی قبلیِ سالم را دادند → AI لازم نیست
      if (onSame != null && result.trim().isNotEmpty && !bad(result) && same(result)) {
        onSame();
        return (text: result, aiApproved: false);
      }

      // ۲. ناظر AI: فقط اگر مشکوک بود یا همان ترجمه‌ی قبلی تکرار شد
      var approved = false;
      if (ai != null && result.trim().isNotEmpty &&
          (bad(result) || same(result))) {
        final v = await _verifyWithAIQ(text, targetLang, result, ai,
            sourceLang: sourceLang, viaWorker: false);
        result = v.text;
        approved = v.approved;
      }
      if (result.trim().isNotEmpty && !bad(result) && !same(result)) {
        await cachePut(text, sourceLang, targetLang, result);
        return (text: result, aiApproved: approved);
      }

      // ۳. آخرین چاره: ترجمه‌ی مستقیم با AI
      if (ai != null) {
        try {
          final r = await translateViaAI(text, targetLang, sourceLang, ai,
              useShared: false);
          if (!bad(r)) {
            await cachePut(text, sourceLang, targetLang, r);
            return (text: r, aiApproved: true);
          }
        } catch (_) {}
      }
      // اگر ترجمه‌ی سالمی هست (حتی تکراری) همان را بده؛ وگرنه ML Kit/کش؛ وگرنه متن اصلی
      if (result.trim().isNotEmpty && !bad(result)) {
        return (text: result, aiApproved: false);
      }
      final lr = lastResort();
      if (lr != null) _retranslateWeak = true;
      return (text: lr ?? text, aiApproved: false);
    }

    try {
      return await run().timeout(const Duration(seconds: 25));
    } catch (_) {
      final lr = lastResort();
      if (lr != null) _retranslateWeak = true;
      return (text: lr ?? text, aiApproved: false);
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
    bool aiOnlyIfSuspicious = kAiOnlyIfSuspiciousDefault,
    bool treatAsIdiom = false,
  }) async {
    final hard = _hardcodedFarewell(text, sourceLang, targetLang);
    if (hard != null) return hard;
    final r = await _translateNetwork0(
      text: text,
      targetLang: targetLang,
      sourceLang: sourceLang,
      aiSettings: aiSettings,
      forceVerify: forceVerify,
      aiOnlyIfSuspicious: aiOnlyIfSuspicious,
      treatAsIdiom: treatAsIdiom,
    );
    return _fixFarewell(text, sourceLang, targetLang, r);
  }

  Future<String> _translateNetwork0({
    required String text,
    required String targetLang,
    required String sourceLang,
    AiSettings? aiSettings,
    bool forceVerify = false,
    bool aiOnlyIfSuspicious = kAiOnlyIfSuspiciousDefault,
    bool treatAsIdiom = false,
  }) async {
    final isIdiom = treatAsIdiom || _looksIdiomatic(text);
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
          !looksLikelyMistranslated(text, ml, targetLang,
              sourceLang: sourceLang)) {
        // اصطلاح یا مشکوکِ عمیق: پیش‌نویسِ ML Kit نگه داشته می‌شود (برای بازبینیِ AI و به‌عنوان پشتیبان)،
        // نه دور ریخته؛ وگرنه اگر مترجمِ آنلاین هم جواب نمی‌داد، AI هیچ‌وقت صدا زده نمی‌شد.
        if ((aiSettings != null && isIdiom) ||
            (_deepReviewOn(aiSettings) &&
                looksSuspiciousDeep(text, ml, sourceLang, targetLang))) {
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
              isIdiom ||
              looksLikelyMistranslated(text, result, targetLang,
                  sourceLang: sourceLang) ||
              (_deepReviewOn(aiSettings) &&
                  looksSuspiciousDeep(
                      text, result, sourceLang, targetLang)))) {
        final before = result;
        result = await _verifyWithAI(text, targetLang, result, aiSettings,
            sourceLang: sourceLang);
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
              aiSettings.baseUrl, text, sourceLang, targetLang, result,
              aiVerified: true);
        }
        return result;
      }
    }

    // آخرین چاره: بک‌اند AI — این نتیجه هم از فیلتر کیفیت رد می‌شود
    // 💸 حالتِ کم‌هزینه (تب Talk): اگر هیچ پیش‌نویسِ رایگانی نبود (نه ML Kit و نه مترجمِ آنلاین؛
    // مثلاً مدل هنوز دانلود نشده یا سقفِ MyMemory پر شده) این «مشکوک» حساب نمی‌شود، فقط «در دسترس
    // نبود»؛ پس AI صدا زده نمی‌شود و متنِ اصلی برمی‌گردد تا دفعه‌ی بعد با ML Kit/کش ترجمه شود.
    // AI فقط وقتی می‌رود که پیش‌نویس هست و مشکوک است (winner مشکوک، یا mlDraft مشکوکِ عمیق).
    final noDraftAtAll = winner == null && (mlDraft == null || mlDraft.isEmpty);
    final skipAiNoDraft = aiOnlyIfSuspicious && !forceVerify && noDraftAtAll;

    final aiKey = RetryFlag.keyFor('ai', text, '$sourceLang>$targetLang');
    if (aiSettings != null && !skipAiNoDraft && !RetryFlag.blocked(aiKey)) {
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
      final shared = await _aiBatched(text, target, source, settings);
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
      String text, String target, String source, AiSettings settings,
      {String? draft}) async {
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
              ...Romanization.nativeField, // 🔤 زبانِ مادری: رومی‌سازیِ زبانِ خودش برنمی‌گردد
              // 🕵️ پیش‌نویسِ مشکوکِ رایگان: Worker (DeepSeek) آن را بازبینی/اصلاح می‌کند و در D1 برای همه می‌ماند
              if (draft != null && draft.trim().isNotEmpty) 'draft': draft.trim(),
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
      Romanization.ingestSingle(target, data); // 🔤 فیلدِ roman
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

  // ═══════════════════════════════════════════════════════════════
  // 📦 دسته‌ایِ AI برای ترجمه‌های مشکوک
  // جمله‌ها/لغت‌های مشکوکِ یک صفحه (تا ۴۰۰ms جمع می‌شوند، حداکثر ۲۰ تا) در «یک» درخواستِ
  // /api/translate-batch (با drafts) به Worker (DeepSeek) می‌روند؛ یک مورد تنها = همان /api/translate-text.
  // null = نشد (Workerِ قدیمی، سقف/مکث، خروجیِ نامعتبر) و تصمیمش با صدازننده است.
  // ═══════════════════════════════════════════════════════════════
  static const int _kRvWindowMs = 400;
  static const int _kRvMax = 20;
  final Map<String, _RvGroup> _rvGroups = <String, _RvGroup>{};
  bool _rvBatchOff = false; // Workerِ قدیمی (۴۰۴/۴۰۵): همه تک‌به‌تک
  int _rvPausedUntil = 0; // سقف/سهمیه پر شد: چند دقیقه AI صدا نزن

  Future<String?> _aiBatched(
      String text, String target, String source, AiSettings settings,
      {String draft = ''}) {
    final t = text.trim();
    if (t.isEmpty || t.length > _kSharedMaxChars) {
      return Future<String?>.value(null);
    }
    if (!_englishNames.containsKey(target)) return Future<String?>.value(null);
    final src = source.isEmpty ? 'auto' : source;
    if (src != 'auto' && !_englishNames.containsKey(src)) {
      return Future<String?>.value(null);
    }
    if (_rvBatchOff) {
      return _viaSharedCache(t, target, src, settings, draft: draft);
    }
    if (DateTime.now().millisecondsSinceEpoch < _rvPausedUntil) {
      return Future<String?>.value(null);
    }
    final key = '${settings.baseUrl}|$src|$target';
    final g = _rvGroups.putIfAbsent(
        key, () => _RvGroup(settings.baseUrl, src, target, settings));
    final c = Completer<String?>();
    final it = g.items.putIfAbsent(t, () => _RvItem(t, draft.trim()));
    it.waiters.add(c);
    if (g.items.length >= _kRvMax) {
      g.timer?.cancel();
      g.timer = null;
      unawaited(_flushRv(key));
    } else {
      g.timer ??= Timer(
          const Duration(milliseconds: _kRvWindowMs), () => unawaited(_flushRv(key)));
    }
    return c.future;
  }

  Future<void> _flushRv(String key) async {
    final g = _rvGroups.remove(key);
    if (g == null) return;
    g.timer?.cancel();
    final items = g.items.values.toList();
    void done(_RvItem it, String? v) {
      for (final c in it.waiters) {
        if (!c.isCompleted) c.complete(v);
      }
    }

    void single(_RvItem it) {
      unawaited(_viaSharedCache(it.text, g.target, g.src, g.settings,
              draft: it.draft)
          .then((v) => done(it, v), onError: (_) => done(it, null)));
    }

    try {
      if (items.length == 1) {
        single(items.first);
        return;
      }
      final res = await _postRvBatch(g, items);
      if (res == null) {
        if (_rvBatchOff) {
          items.forEach(single);
        } else {
          for (final it in items) {
            done(it, null);
          }
        }
        return;
      }
      for (var i = 0; i < items.length; i++) {
        done(items[i], i < res.length ? res[i] : null);
      }
    } catch (_) {
      for (final it in items) {
        done(it, null);
      }
    }
  }

  Future<List<String?>?> _postRvBatch(_RvGroup g, List<_RvItem> items) async {
    try {
      final hasDraft = items.any((it) => it.draft.isNotEmpty);
      final res = await _aiDio
          .post(
            '${g.base}/api/translate-batch',
            data: {
              'items': [for (final it in items) it.text],
              if (hasDraft) 'drafts': [for (final it in items) it.draft],
              'source_lang_code': g.src,
              'target_lang_code': g.target,
              ...Romanization.nativeField,
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
        final data = _json(res.data);
        final arr = data is Map ? data['results'] : null;
        if (arr is! List || arr.length != items.length) return null;
        Romanization.ingestBatch(g.target, data); // 🔤 آرایه‌ی romans
        return <String?>[
          for (final v in arr)
            () {
              if (v is! String) return null;
              final c = _stripQuotes(stripAIReasoning(v));
              if (c.isEmpty || looksLikeAIReasoning(c) || looksLikeGuardOutput(c)) {
                return null;
              }
              return c;
            }(),
        ];
      }
      if (st == 404 || st == 405) {
        _rvBatchOff = true;
      } else if (st == 429 || st == 402) {
        _rvPausedUntil = DateTime.now().millisecondsSinceEpoch + 5 * 60 * 1000;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<({String text, bool approved})> _verifyWithAIQ(
    String source,
    String target,
    String draft,
    AiSettings settings, {
    String sourceLang = 'auto',
    bool viaWorker = true,
  }) async {
    // 🧠 اول مسیرِ بازبینیِ Worker (/api/translate-text با draft): زنجیره‌ی DeepSeek + ذخیره در D1 برای همه.
    // اگر Workerِ قدیمی بود/نشد، همان مسیرِ قبلیِ /api/generate ادامه می‌یابد.
    if (viaWorker) {
      final w = await _aiBatched(source, target, sourceLang, settings,
          draft: draft);
      if (w != null &&
          w.trim().isNotEmpty &&
          !(draft.isNotEmpty && w.length > draft.length * 3 + 20)) {
        return (text: w, approved: true);
      }
    }
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
      if (cleaned.isEmpty || looksLikeAIReasoning(cleaned)) {
        return (text: draft, approved: false);
      }
      // AI صراحتاً «OK» گفت = پیش‌نویس را تأیید کرد
      if (RegExp(r'^OK\.?$', caseSensitive: false).hasMatch(cleaned)) {
        return (text: draft, approved: true);
      }
      if (looksLikeGuardOutput(cleaned)) return (text: draft, approved: false);
      final fixed = _stripQuotes(cleaned);
      if (fixed.isEmpty) return (text: draft, approved: false);
      // «اصلاح»ی که چند برابرِ پیش‌نویس است ترجمه نیست
      if (draft.isNotEmpty && fixed.length > draft.length * 3 + 20) {
        return (text: draft, approved: false);
      }
      return (text: fixed, approved: true);
    } catch (_) {
      return (text: draft, approved: false);
    }
  }

  Future<String> _verifyWithAI(
    String source,
    String target,
    String draft,
    AiSettings settings, {
    String sourceLang = 'auto',
  }) async =>
      (await _verifyWithAIQ(source, target, draft, settings,
              sourceLang: sourceLang))
          .text;

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

class _RvItem {
  _RvItem(this.text, this.draft);
  final String text;
  final String draft;
  final List<Completer<String?>> waiters = <Completer<String?>>[];
}

class _RvGroup {
  _RvGroup(this.base, this.src, this.target, this.settings);
  final String base;
  final String src;
  final String target;
  final AiSettings settings;
  final Map<String, _RvItem> items = <String, _RvItem>{};
  Timer? timer;
}
