import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════
// Translation Service — نسخه‌ی Flutter از translateService.js
//
// زنجیره:
//   1. کش محلی (SharedPreferences)
//   2. ۴ سرویس رایگان به‌صورت موازی:
//        Google (unofficial), MyMemory, Lingva, LibreTranslate
//   3. تست looksLikelyMistranslated
//   4. AI از طریق Cloudflare Worker (/api/generate)
//
// الگوها:
//   - Circuit breaker: هر سرویس بعد از ۲ شکست، ۳ دقیقه کنار می‌ره
//   - Concurrency limit: ۱۰ درخواست موازی، بقیه صف
//   - Hard timeout: ۱۵ ثانیه، بعدش متن اصلی برمی‌گرده
// ═══════════════════════════════════════════════════════════════════

const String _kCachePrefix = 'tr2::';
const int _kProviderFailThreshold = 2;
const int _kProviderBlockMs = 3 * 60 * 1000;
const int _kGlobalConcurrency = 10;
const int _kHardTimeoutMs = 15000;

/// نام انگلیسی زبان — برای پرامپت AI
const Map<String, String> _englishNames = {
  'fa': 'Persian', 'en': 'English', 'it': 'Italian', 'hi': 'Hindi',
  'tr': 'Turkish', 'ar': 'Arabic', 'es': 'Spanish', 'de': 'German',
  'fr': 'French', 'zh': 'Chinese', 'ko': 'Korean', 'ru': 'Russian',
  'ja': 'Japanese',
};

String englishLangName(String code) => _englishNames[code] ?? code;

/// بازه‌ی یونیکد برای تشخیص «ترجمه نشده»
final Map<String, RegExp> _scriptRegex = {
  'fa': RegExp(r'[\u0600-\u06FF]'),
  'ar': RegExp(r'[\u0600-\u06FF]'),
  'ru': RegExp(r'[\u0400-\u04FF]'),
  'zh': RegExp(r'[\u4E00-\u9FFF]'),
  'ja': RegExp(r'[\u3040-\u30FF\u4E00-\u9FFF]'),
  'ko': RegExp(r'[\uAC00-\uD7AF]'),
};

/// تشخیص اینکه AI «فکر کردنش» رو برگردونده
final RegExp _aiReasoningRe = RegExp(
  r"(thinking process|here'?s a thinking|analy[sz]e the (request|text|input)|\*\*\s*analy[sz]e|\bconstraint\s*:|the user wants me to|let me (read|think|analy[sz]e|re-?read)|<\/?think(ing)?>|^\s*okay,? (so|let'?s|the user))",
  caseSensitive: false,
  multiLine: true,
);

bool _looksLikeAIReasoning(String text) {
  if (text.isEmpty) return false;
  if (_aiReasoningRe.hasMatch(text)) return true;
  final boldCount = RegExp(r'\*\*').allMatches(text).length;
  return boldCount >= 4 && RegExp(r'(^|\n|\s)\d\.\s').hasMatch(text);
}

String _stripAIReasoning(String text) {
  return text
      .replaceAll(RegExp(r'<think(ing)?>[\s\S]*?<\/think(ing)?>',
          caseSensitive: false), '')
      .replaceAll(RegExp(r'<think(ing)?>[\s\S]*$', caseSensitive: false), '')
      .trim();
}

/// تست «ترجمه‌ی مشکوک» — قبل از کش کردن اجرا می‌شه
bool _looksLikelyMistranslated(
  String source,
  String draft,
  String targetLang, {
  String sourceLang = 'auto',
}) {
  final src = source.trim();
  final out = draft.trim();
  if (out.isEmpty) return true;
  if (_looksLikeAIReasoning(out)) return true;

  // ترجمه‌نشده: متن خروجی عیناً همون ورودیه
  if (sourceLang != 'auto' &&
      sourceLang != targetLang &&
      out.toLowerCase() == src.toLowerCase()) {
    return true;
  }

  // رسم‌الخط زبان مقصد نیست
  final re = _scriptRegex[targetLang];
  if (re != null && src.length > 1 && !re.hasMatch(out)) return true;

  // نسبت طول غیرعادی
  final ratio = out.length / (src.length == 0 ? 1 : src.length);
  if (src.length > 3 && (ratio < 0.25 || ratio > 3.5)) return true;

  return false;
}

// ═══════════════════════════════════════════════════════════════════
// Circuit breaker
// ═══════════════════════════════════════════════════════════════════
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
// Concurrency queue
// ═══════════════════════════════════════════════════════════════════
int _activeJobs = 0;
final List<_Job> _queue = [];

class _Job {
  final Future<dynamic> Function() fn;
  final Completer<dynamic> completer = Completer<dynamic>();
  _Job(this.fn);
}

void _runNextJob() {
  if (_activeJobs >= _kGlobalConcurrency) return;
  if (_queue.isEmpty) return;
  final job = _queue.removeAt(0);
  _activeJobs++;
  job
      .fn()
      .then((v) => job.completer.complete(v))
      .catchError((e) => job.completer.completeError(e))
      .whenComplete(() {
    _activeJobs--;
    _runNextJob();
  });
}

Future<T> _queueJob<T>(Future<T> Function() fn) {
  final job = _Job(fn);
  _queue.add(job);
  _runNextJob();
  return job.completer.future as Future<T>;
}

// ═══════════════════════════════════════════════════════════════════
// Main service
// ═══════════════════════════════════════════════════════════════════
class TranslationService {
  TranslationService(this._prefs)
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 4),
          sendTimeout: const Duration(seconds: 4),
        ));

  final SharedPreferences _prefs;
  final Dio _dio;

  // ─── کش در حافظه ───────────────────────────────────────────────
  final Map<String, String> _mem = {};

  String _cacheKey(String text, String from, String to) =>
      '$from::$to::${text.hashCode}::${text.length}';

  Future<String?> _cacheGet(String text, String from, String to) async {
    final key = _cacheKey(text, from, to);
    final memHit = _mem[key];
    if (memHit != null) return memHit;
    final disk = _prefs.getString('$_kCachePrefix$key');
    if (disk != null && disk.isNotEmpty) {
      _mem[key] = disk;
      return disk;
    }
    return null;
  }

  Future<void> _cacheSet(String text, String from, String to, String value) async {
    final key = _cacheKey(text, from, to);
    _mem[key] = value;
    await _prefs.setString('$_kCachePrefix$key', value);
  }

  // ═══════════════════════════════════════════════════════════════
  // API اصلی: translate
  // ═══════════════════════════════════════════════════════════════
  /// ترجمه‌ی متن از `sourceLang` به `targetLang`.
  /// [aiSettings] برای fallback به Cloudflare Worker.
  Future<String> translate({
    required String text,
    required String targetLang,
    String sourceLang = 'auto',
    AiSettings? aiSettings,
    bool forceVerify = false,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || targetLang.isEmpty) return text;
    if (sourceLang != 'auto' && sourceLang == targetLang) return trimmed;

    // ۱. کش — با چک کیفیت
    final cached = await _cacheGet(trimmed, sourceLang, targetLang);
    if (cached != null &&
        !_looksLikelyMistranslated(trimmed, cached, targetLang,
            sourceLang: sourceLang)) {
      return cached;
    }

    // ۲. صف + hard timeout
    return _queueJob(() async {
      final networkFuture = _translateNetwork(
        text: trimmed,
        targetLang: targetLang,
        sourceLang: sourceLang,
        aiSettings: aiSettings,
        forceVerify: forceVerify,
      );
      final timeoutFuture = Future<String>.delayed(
        const Duration(milliseconds: _kHardTimeoutMs),
        () => trimmed,
      );
      return Future.any([networkFuture, timeoutFuture]);
    });
  }

  /// دوباره ترجمه کردن — بدون کش، اول AI
  Future<String> retranslate({
    required String text,
    required String targetLang,
    String sourceLang = 'auto',
    AiSettings? aiSettings,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return text;

    // اول AI
    if (aiSettings != null && aiSettings.backendUrl.isNotEmpty) {
      try {
        final aiResult = await _translateViaAI(
            trimmed, targetLang, sourceLang, aiSettings);
        if (aiResult.isNotEmpty &&
            !_looksLikelyMistranslated(trimmed, aiResult, targetLang,
                sourceLang: sourceLang)) {
          await _cacheSet(trimmed, sourceLang, targetLang, aiResult);
          return aiResult;
        }
      } catch (_) {
        // می‌رویم سراغ سرویس‌های رایگان
      }
    }
    return _translateNetwork(
      text: trimmed,
      targetLang: targetLang,
      sourceLang: sourceLang,
      aiSettings: aiSettings,
      forceVerify: true,
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // زنجیره‌ی شبکه
  // ═══════════════════════════════════════════════════════════════
  Future<String> _translateNetwork({
    required String text,
    required String targetLang,
    required String sourceLang,
    AiSettings? aiSettings,
    bool forceVerify = false,
  }) async {
    // سرویس‌های فعال
    final providers = <_Provider>[
      _Provider('google', _viaGoogle),
      _Provider('mymemory', _viaMyMemory),
      _Provider('lingva', _viaLingva),
      _Provider('libre', _viaLibre),
    ].where((p) => !_isProviderBlocked(p.name)).toList();

    // موازی
    final winner = await _raceProviders(providers, text, targetLang, sourceLang);

    if (winner != null) {
      var result = winner.result;

      // چک کیفیت — اگر مشکوک بود و AI داشتیم، از AI اصلاح بگیر
      if (aiSettings != null &&
          aiSettings.backendUrl.isNotEmpty &&
          (forceVerify ||
              _looksLikelyMistranslated(text, result, targetLang,
                  sourceLang: sourceLang))) {
        result = await _verifyWithAI(
            text, targetLang, result, aiSettings);
      }

      // اگر بعد از اصلاح هم مشکوک بود، کش نکن
      if (!_looksLikelyMistranslated(text, result, targetLang,
          sourceLang: sourceLang)) {
        _reportProviderOutcome(winner.provider.name, true);
        await _cacheSet(text, sourceLang, targetLang, result);
        return result;
      }
    }

    // fallback نهایی: AI
    if (aiSettings != null && aiSettings.backendUrl.isNotEmpty) {
      try {
        final aiResult = await _translateViaAI(
            text, targetLang, sourceLang, aiSettings);
        if (aiResult.isNotEmpty &&
            !_looksLikelyMistranslated(text, aiResult, targetLang,
                sourceLang: sourceLang)) {
          await _cacheSet(text, sourceLang, targetLang, aiResult);
          return aiResult;
        }
      } catch (_) {}
    }

    return text;
  }

  Future<_Winner?> _raceProviders(
    List<_Provider> providers,
    String text,
    String targetLang,
    String sourceLang,
  ) async {
    if (providers.isEmpty) return null;

    final completer = Completer<_Winner?>();
    int remaining = providers.length;
    bool settled = false;

    for (final p in providers) {
      p
          .call(text, targetLang, sourceLang)
          .then((result) {
        if (result != null && result.trim().isNotEmpty) {
          if (!settled) {
            settled = true;
            completer.complete(_Winner(result, p));
          }
        } else {
          _reportProviderOutcome(p.name, false);
        }
      }).catchError((e) {
        _reportProviderOutcome(p.name, false);
      }).whenComplete(() {
        remaining--;
        if (remaining == 0 && !settled) {
          completer.complete(null);
        }
      });
    }

    return completer.future;
  }

  // ═══════════════════════════════════════════════════════════════
  // Providers
  // ═══════════════════════════════════════════════════════════════
  Future<String?> _viaGoogle(String text, String target, String source) async {
    final url =
        'https://translate.googleapis.com/translate_a/single?client=gtx&sl=$source&tl=$target&dt=t&q=${Uri.encodeComponent(text)}';
    final res = await _dio.get(url);
    if (res.statusCode != 200) throw Exception('google-${res.statusCode}');
    final data = res.data;
    if (data is! List || data.isEmpty) throw Exception('google-empty');
    final chunks = data[0];
    if (chunks is! List) throw Exception('google-shape');
    return chunks
        .whereType<List>()
        .map((c) => c.isNotEmpty ? c[0].toString() : '')
        .join();
  }

  Future<String?> _viaMyMemory(
      String text, String target, String source) async {
    final sl = (source == 'auto' || source.isEmpty) ? 'en' : source;
    final url =
        'https://api.mymemory.translated.net/get?q=${Uri.encodeComponent(text)}&langpair=$sl|$target';
    final res = await _dio.get(url);
    if (res.statusCode != 200) throw Exception('mymemory-${res.statusCode}');
    final data = res.data;
    if (data is! Map) throw Exception('mymemory-shape');
    final translated = data['responseData']?['translatedText']?.toString() ?? '';
    if (translated.isEmpty) throw Exception('mymemory-empty');
    if (RegExp(r'^(PLEASE SELECT|INVALID |NO TRANSLATION|AMOUNT OF WORDS)',
            caseSensitive: false)
        .hasMatch(translated.trim())) {
      throw Exception('mymemory-error: $translated');
    }
    return translated;
  }

  Future<String?> _viaLingva(String text, String target, String source) async {
    final url =
        'https://lingva.ml/api/v1/$source/$target/${Uri.encodeComponent(text)}';
    final res = await _dio.get(url);
    if (res.statusCode != 200) throw Exception('lingva-${res.statusCode}');
    final data = res.data;
    if (data is! Map) throw Exception('lingva-shape');
    final t = data['translation']?.toString() ?? '';
    if (t.isEmpty) throw Exception('lingva-empty');
    return t;
  }

  Future<String?> _viaLibre(String text, String target, String source) async {
    final res = await _dio.post(
      'https://libretranslate.de/translate',
      data: {
        'q': text,
        'source': source.isEmpty ? 'auto' : source,
        'target': target,
        'format': 'text',
      },
      options: Options(contentType: 'application/json'),
    );
    if (res.statusCode != 200) throw Exception('libre-${res.statusCode}');
    final data = res.data;
    if (data is! Map) throw Exception('libre-shape');
    final t = data['translatedText']?.toString() ?? '';
    if (t.isEmpty) throw Exception('libre-empty');
    return t;
  }

  // ═══════════════════════════════════════════════════════════════
  // AI (Cloudflare Worker)
  // ═══════════════════════════════════════════════════════════════
  Future<String> _callAI({
    required String prompt,
    required AiSettings settings,
    int maxTokens = 200,
  }) async {
    final base = settings.backendUrl.replaceAll(RegExp(r'/+$'), '');
    final url = '$base/api/generate';
    final res = await _dio.post(
      url,
      data: {'prompt': prompt, 'maxTokens': maxTokens},
      options: Options(
        contentType: 'application/json',
        sendTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 20),
      ),
    );
    if (res.statusCode != 200) throw Exception('ai-http-${res.statusCode}');
    final data = res.data;
    if (data is! Map) throw Exception('ai-shape');
    final text = data['text']?.toString() ?? '';
    if (text.isEmpty) throw Exception('ai-empty');
    return text;
  }

  Future<String> _translateViaAI(
    String text,
    String target,
    String source,
    AiSettings settings,
  ) async {
    final targetLabel = englishLangName(target);
    final prompt =
        'Translate the following text into $targetLabel. '
        'Respond with ONLY the translation itself — no quotes, no explanation, no original text, nothing else.\n\n'
        'Text: $text';

    String clean(String r) =>
        _stripAIReasoning(r).replaceAll(RegExp(r'^["\'«»]+|["\'«».\s]+$'), '').trim();

    var result = clean(
        await _callAI(prompt: prompt, settings: settings, maxTokens: 200));

    if (result.isEmpty || _looksLikeAIReasoning(result)) {
      final strict =
          'Output ONLY the $targetLabel translation of the text below, as a single line. '
          'Do not think aloud, do not analyze, do not explain, do not use lists or markdown.\n\n'
          'Text: $text\n\n$targetLabel translation:';
      result = clean(
          await _callAI(prompt: strict, settings: settings, maxTokens: 200));
    }

    if (result.isEmpty) throw Exception('ai-translate-empty');
    if (_looksLikeAIReasoning(result)) throw Exception('ai-reasoning-leak');
    return result;
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
          'Is the draft an accurate, complete translation? If yes, reply with EXACTLY: OK\n'
          'If no, reply with ONLY the corrected translation — no quotes, no explanation, nothing else.';
      final result = await _callAI(
          prompt: prompt, settings: settings, maxTokens: 80);
      final cleaned = _stripAIReasoning(result);
      if (cleaned.isEmpty ||
          RegExp(r'^OK\.?$', caseSensitive: false).hasMatch(cleaned) ||
          _looksLikeAIReasoning(cleaned)) {
        return draft;
      }
      return cleaned.replaceAll(RegExp(r'^["\'«»]+|["\'«».\s]+$'), '').trim();
    } catch (_) {
      return draft;
    }
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

/// تنظیمات AI — URL Worker
class AiSettings {
  final String backendUrl;
  const AiSettings({required this.backendUrl});
}
