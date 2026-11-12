import 'dart:async';

import 'package:flutter/foundation.dart';

import '../native/native_bridge.dart';

/// پل به TTS نیتیو اندروید (Piper/Sherpa + TTS خودِ گوشی).
///
/// ⚠️ باگِ قبلی: این کلاس روی کانالِ `lingolearn/tts` صدا می‌زد، ولی سمتِ
/// اندروید هیچ‌وقت چنین کانالی ثبت نشده بود (فقط `com.linglearn.app/bubble`
/// وجود دارد). نتیجه: همه‌ی صدا زدن‌ها بی‌صدا شکست می‌خوردند و TTS گوشی
/// هیچ صدایی نداشت. حالا همه‌چیز از همان [NativeBridge] می‌گذرد:
///   • speak / speakSystem / stopSpeaking  ← متدهای BubblePlugin
///   • پایانِ خوانش ← رویداد `ttsSpeakDone` با { id, ok }
///
/// مثل Hope (nativeTtsFast.js) هر خوانش یک `id` یکتا دارد تا رویدادِ «تمام شد»
/// یک خوانشِ قدیمی (بعد از stop/pause) خوانشِ جدید را تمام‌شده حساب نکند.
class NativeTtsBridge {
  NativeTtsBridge._();

  static final NativeBridge _b = NativeBridge.instance;

  static bool get isAvailable => !kIsWeb && _b.isSupported;

  static void Function(String? id, bool ok)? _doneHandler;
  static StreamSubscription<Map<String, dynamic>>? _sub;

  static final Map<String, String> _restById = <String, String>{};

  /// باقیمانده‌ی نخوانده‌ی خوانشِ [id] (بعد از شکستِ جزئیِ Piper) — یک‌بار مصرف؛ وگرنه null.
  static String? takeRest(String id) => _restById.remove(id);

  static void _ensureListening() {
    _sub ??= _b.on('ttsSpeakDone').listen((d) {
      final h = _doneHandler;
      if (h == null) return;
      final rawId = d['id']?.toString();
      // اگر بخشی از جمله با مدلِ اپ خوانده شده و بقیه شکست خورده، نیتیو فقط «باقیمانده» را می‌فرستد
      final rest = d['rest']?.toString();
      if (rawId != null && rawId.isNotEmpty && rest != null && rest.isNotEmpty) {
        if (_restById.length > 50) _restById.clear();
        _restById[rawId] = rest;
      }
      h((rawId == null || rawId.isEmpty) ? null : rawId, d['ok'] != false);
    }, onError: (Object e) => debugPrint('ttsSpeakDone stream error: $e'));
  }

  /// آیا بسته‌ی آفلاینِ (Piper) این زبان نصب شده؟
  static final Map<String, DateTime> _readyAt = {};
  static final Map<String, DateTime> _notReadyAt = {};

  static Future<bool> isModelReady(String lang) async {
    if (!isAvailable) return false;
    // ⚡ بدون رفت‌وبرگشتِ اضافه به نیتیو برای هر جمله: جوابِ «آماده» ۳۰ ثانیه کش می‌شود
    final t = _readyAt[lang];
    if (t != null && DateTime.now().difference(t) < const Duration(seconds: 30)) {
      return true;
    }
    // ⚡ جوابِ «آماده نیست» هم چند ثانیه کش می‌شود (قبلاً برای هر جمله یک رفت‌وبرگشتِ اضافه بود)
    final nt = _notReadyAt[lang];
    if (nt != null && DateTime.now().difference(nt) < const Duration(seconds: 8)) {
      return false;
    }
    try {
      final r = await _b.checkTtsStatus(lang: lang);
      final ok = r['downloaded'] == true;
      if (ok) {
        _readyAt[lang] = DateTime.now();
        _notReadyAt.remove(lang);
      } else {
        _readyAt.remove(lang);
        _notReadyAt[lang] = DateTime.now();
      }
      return ok;
    } catch (e) {
      debugPrint('checkTtsStatus error: $e');
      return false;
    }
  }

  /// موتورِ Piper را از قبل (پس‌زمینه) لود و گرم می‌کند تا اولین خوانش تأخیر نداشته باشد.
  static Future<void> preload({String? lang}) async {
    if (!isAvailable) return;
    try {
      await _b.preloadTts(lang: lang);
    } catch (_) {}
  }

  /// صدای جمله‌ی بعدی را پیش‌پیش می‌سازد (موقعِ نوبتش بدون تأخیر پخش می‌شود).
  static Future<void> prefetch(String text, String lang, double rate,
      {String? voice}) async {
    if (!isAvailable) return;
    _markPrefetched(text, lang, rate);
    try {
      await _b.prefetchTts(text: text, lang: lang, speed: rate, voice: voice);
    } catch (_) {}
  }

  // ⚡ جمله‌هایی که برایشان prefetch فرستاده شده (صدای Piper‌شان ساخته شده یا در حال ساخته‌شدن است)
  static final Map<String, DateTime> _prefetched = <String, DateTime>{};

  static String _pfKey(String text, String lang, double rate) =>
      '$lang|$rate|$text';

  static void _markPrefetched(String text, String lang, double rate) {
    if (_prefetched.length > 400) _prefetched.clear();
    _prefetched.putIfAbsent(_pfKey(text, lang, rate), () => DateTime.now());
  }

  /// ⚡ صدای Piperِ این جمله «احتمالاً ساخته شده» است؟ (prefetch فرستاده شده و به‌اندازه‌ی کافی
  /// گذشته). نیتیو prefetch را فوری resolve می‌کند و خبرِ پایانِ ساخت نمی‌دهد؛ پس اگر تازه فرستاده
  /// شده، سرد حساب می‌شود و همان لحظه با صدای گوشی خوانده می‌شود (بدون انتظار برای Piper).
  static bool isPrefetchWarm(String text, String lang, double rate) {
    final t = _prefetched[_pfKey(text, lang, rate)];
    if (t == null) return false;
    final need = (300 + text.length * 12).clamp(300, 1500);
    return DateTime.now().difference(t).inMilliseconds >= need;
  }

  /// آیا برای این جمله قبلاً prefetch فرستاده شده؟ (false = «سرد»؛ ساختنِ صدای Piper تأخیر دارد)
  static bool wasPrefetched(String text, String lang, double rate) =>
      _prefetched.containsKey(_pfKey(text, lang, rate));

  static final Map<String, ({bool ok, DateTime at})> _sysAvail = {};

  /// آیا TTS خودِ گوشی برای این زبان صدا دارد؟ (۶۰ ثانیه کش می‌شود)
  static Future<bool> systemAvailable(String lang) async {
    if (!isAvailable) return false;
    final c = _sysAvail[lang];
    if (c != null &&
        DateTime.now().difference(c.at) < const Duration(seconds: 60)) {
      return c.ok;
    }
    try {
      final r = await _b.checkSystemTts(lang: lang);
      final ok = r['available'] == true;
      _sysAvail[lang] = (ok: ok, at: DateTime.now());
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// زبان‌هایی که در همین اجرا درخواستِ دانلودِ خودکارشان فرستاده شده (تکراری نشود).
  static final Set<String> _autoDlRequested = {};

  /// اگر بسته‌ی «صدای اپ» این زبان نصب نیست و در حال دانلود هم نیست، دانلودش را
  /// شروع می‌کند (فقط یک‌بار برای هر زبان در هر اجرا). تا آماده شدن، خوانش با
  /// صدای گوشی ادامه پیدا می‌کند. پیشرفت در تنظیمات → «صدای برنامه» دیده می‌شود.
  static Future<void> ensureModelDownload(String lang) async {
    if (!isAvailable || lang.isEmpty || _autoDlRequested.contains(lang)) return;
    _autoDlRequested.add(lang);
    try {
      final r = await _b.checkTtsStatus(lang: lang);
      if (r['downloaded'] == true || r['downloading'] == true) return;
      await _b.downloadTtsModel(lang: lang);
    } catch (e) {
      debugPrint('auto tts download error: $e');
    }
  }

  /// TTS نیتیو (Piper) — true یعنی خوانش شروع شد (پایانش با [onDone] می‌رسد).
  static Future<bool> speak(
    String text,
    String lang,
    double rate, {
    String? id,
    String? voice,
  }) async {
    if (!isAvailable) return false;
    _ensureListening();
    try {
      await _b.speak(text: text, lang: lang, speed: rate, id: id, voice: voice);
      return true;
    } catch (e) {
      debugPrint('native speak error: $e');
      return false;
    }
  }

  /// TTS خودِ گوشی (android.speech.tts).
  static Future<bool> speakSystem(
    String text,
    String lang,
    double rate, {
    String? id,
  }) async {
    if (!isAvailable) return false;
    _ensureListening();
    try {
      await _b.speakSystem(text: text, lang: lang, speed: rate, id: id);
      return true;
    } catch (e) {
      debugPrint('speakSystem error: $e');
      return false;
    }
  }

  /// توقف
  static Future<void> stop() async {
    if (!isAvailable) return;
    try {
      await _b.stopSpeaking();
    } catch (_) {}
  }

  /// منتظر پایانِ خوانش. handler پارامترهای (id, ok) می‌گیرد؛
  /// اگر سمتِ نیتیو id نفرستد، id == null می‌آید.
  static void onDone(void Function(String? id, bool ok) handler) {
    if (!isAvailable) return;
    _doneHandler = handler;
    _ensureListening();
  }
}
