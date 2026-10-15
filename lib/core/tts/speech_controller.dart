import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';

import 'native_tts_bridge.dart';
import 'sentence_splitter.dart';
import 'speech_state.dart';
import 'tts_config.dart';

enum _WebResult { done, cancelled, noVoice, failed }

class SpeechController extends StateNotifier<SpeechState> {
  /// [voicePref]: صدای ذخیره‌شده‌ی کاربر برای یک زبان (نام صدا) — اختیاری
  SpeechController({String? Function(String lang)? voicePref})
      : _voicePref = voicePref,
        super(const SpeechState()) {
    _initLocalTts();
  }

  final String? Function(String lang)? _voicePref;
  List<Map<String, String>> _voices = [];

  final FlutterTts _localTts = FlutterTts();
  final AudioPlayer _onlinePlayer = AudioPlayer();

  String _fullText = '';
  List<TextChunk> _chunks = [];
  int _chunkIndex = 0;
  String? _currentKey;
  String? _currentCode;
  int _generation = 0;
  bool _disposed = false;

  // منتظرهای «پایان خوانش» — هر کدوم مخصوص یک خوانش‌اند و با stop/pause
  // کنسل می‌شن تا هیچ زنجیره‌ی قدیمی‌ای بعداً ناخواسته چیزی پخش نکنه.
  Completer<bool>? _nativeWaiter;
  Completer<bool>? _webWaiter;
  Completer<bool>? _onlineWaiter;
  int _utteranceSeq = 0;

  /// ttsDone ای که id نداره و زودتر از این مدت بعد از شروع برسه، مال
  /// خوانشِ قبلی (متوقف‌شده) حساب می‌شه، نه خوانش فعلی.
  static const _staleDoneGuard = Duration(milliseconds: 150);

  // صف: لیست متن‌های هم‌زبان (مثلاً خطوط یک مکالمه) تا «قبلی/بعدی» در لبه‌ی
  // جمله‌ها به آیتم قبلی/بعدی برود.
  List<String> _queue = [];
  int _queueIndex = -1;

  // A-B
  String _abState = 'idle';
  int? _abChunkA;
  int? _abChunkB;

  // شمارنده‌ی «چندبار این جمله تا الان خونده شده» (شامل خوانش اول)
  final Map<int, int> _chunkRepeatsDone = {};

  Future<void> _initLocalTts() async {
    // ⚠️ هر فراخوانی جداگانه try/catch دارد: قبلاً اگر setSharedInstance
    // (فقط iOS) روی وب خطا می‌داد، بقیه‌ی تنظیمات هم نادیده می‌ماند.
    if (!kIsWeb) {
      try {
        await _localTts.setSharedInstance(true);
      } catch (e) {
        debugPrint('setSharedInstance error: $e');
      }
    }
    try {
      // پایان خوانش را با completion handler می‌فهمیم، نه با awaitSpeakCompletion.
      await _localTts.awaitSpeakCompletion(false);
    } catch (e) {
      debugPrint('awaitSpeakCompletion error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // API عمومی
  // ═══════════════════════════════════════════════════════════════

  Future<String> toggle(
    String text,
    String code, {
    int? startCharOffset,
    List<String>? queue,
    int? queueIndex,
  }) async {
    if (text.isEmpty) return 'unsupported';

    final newKey = '${TtsConfig.locale[code] ?? 'en-US'}::$text';

    // همان متن، در حال پخش → pause
    if (_currentKey == newKey && state.status == SpeechStatus.playing) {
      await _pause();
      return 'ok';
    }

    // همان متن، paused → resume
    if (_currentKey == newKey && state.status == SpeechStatus.paused) {
      _generation++;
      state = state.copyWith(status: SpeechStatus.playing);
      unawaited(_playFrom(_chunkIndex));
      return 'ok';
    }

    // متن جدید
    await _startText(
      text,
      code,
      startCharOffset: startCharOffset,
      queue: queue,
      queueIndex: queueIndex,
    );
    return 'ok';
  }

  Future<void> _startText(
    String text,
    String code, {
    int? startCharOffset,
    List<String>? queue,
    int? queueIndex,
    bool startAtEnd = false,
  }) async {
    final newKey = '${TtsConfig.locale[code] ?? 'en-US'}::$text';
    _generation++;
    await _stopAll();

    _fullText = text;
    _chunks = SentenceSplitter.split(text);
    _chunkRepeatsDone.clear();
    _currentKey = newKey;
    _currentCode = code;
    _queue = queue ?? const [];
    _queueIndex = queue == null ? -1 : (queueIndex ?? -1);

    var startIdx = startCharOffset != null && startCharOffset > 0
        ? _chunkIndexForOffset(startCharOffset)
        : 0;
    if (startAtEnd && _chunks.isNotEmpty) startIdx = _chunks.length - 1;

    _chunkIndex = startIdx;
    _abState = 'idle';
    _abChunkA = null;
    _abChunkB = null;

    state = state.copyWith(
      key: newKey,
      total: _chunks.length,
      chunkIndex: startIdx,
      abState: 'idle',
      clearAB: true,
      clearError: true,
      hasPrev: _hasPrev(startIdx),
      hasNext: _hasNext(startIdx),
    );

    unawaited(_playFrom(startIdx));
  }

  bool _hasPrev(int chunkIdx) => chunkIdx > 0 || _queueIndex > 0;

  bool _hasNext(int chunkIdx) =>
      chunkIdx + 1 < _chunks.length ||
      (_queueIndex >= 0 && _queueIndex + 1 < _queue.length);

  /// دکمه‌ی پلی/توقف خودِ پلیر — بدون parse کردن key (که با '::' داخل متن خراب می‌شد)
  Future<void> togglePlayPause() async {
    final key = _currentKey;
    if (key == null || _fullText.isEmpty) return;
    await toggle(
      _fullText,
      _currentCode ?? 'en',
      queue: _queue.isEmpty ? null : _queue,
      queueIndex: _queue.isEmpty ? null : _queueIndex,
    );
  }

  Future<void> stop() async {
    _generation++;
    await _stopAll();
    _fullText = '';
    _chunks = [];
    _chunkIndex = 0;
    _chunkRepeatsDone.clear();
    _currentKey = null;
    _currentCode = null;
    _abState = 'idle';
    _abChunkA = null;
    _abChunkB = null;
    _queue = [];
    _queueIndex = -1;
    state = state.copyWith(
      status: SpeechStatus.idle,
      hasPrev: false,
      hasNext: false,
      clearKey: true,
      chunkIndex: 0,
      total: 0,
      abState: 'idle',
      clearAB: true,
      clearError: true,
    );
  }

  Future<void> seekToChunk(int idx) async {
    if (_chunks.isEmpty) return;
    final clamped = idx.clamp(0, _chunks.length - 1);
    _generation++;
    await _stopAll();
    // با جابجایی دستی، شمارنده‌ی تکرار از صفر شروع شود
    _chunkRepeatsDone.clear();
    _chunkIndex = clamped;
    state = state.copyWith(
      chunkIndex: clamped,
      status: SpeechStatus.playing,
      hasPrev: _hasPrev(clamped),
      hasNext: _hasNext(clamped),
    );
    unawaited(_playFrom(clamped));
  }

  /// جمله‌ی بعد؛ اگر آخرین جمله بود و صف داریم → آیتم بعدیِ صف
  Future<void> nextChunk() async {
    if (_chunks.isEmpty) return;
    if (_chunkIndex + 1 < _chunks.length) {
      await seekToChunk(_chunkIndex + 1);
      return;
    }
    final code = _currentCode;
    if (code != null && _queueIndex >= 0 && _queueIndex + 1 < _queue.length) {
      final i = _queueIndex + 1;
      await _startText(_queue[i], code, queue: _queue, queueIndex: i);
    }
  }

  /// جمله‌ی قبل؛ اگر اولین جمله بود و صف داریم → آخرین جمله‌ی آیتم قبلی
  Future<void> prevChunk() async {
    if (_chunks.isEmpty) return;
    if (_chunkIndex > 0) {
      await seekToChunk(_chunkIndex - 1);
      return;
    }
    final code = _currentCode;
    if (code != null && _queueIndex > 0) {
      final i = _queueIndex - 1;
      await _startText(_queue[i], code,
          queue: _queue, queueIndex: i, startAtEnd: true);
    }
  }

  Future<void> setRate(double r) async {
    final clamped = r.clamp(0.25, 2.0);
    state = state.copyWith(rate: clamped);
    try {
      await _localTts.setSpeechRate(clamped);
      await _onlinePlayer.setSpeed(clamped);
    } catch (_) {}
  }

  Future<void> toggleMuted() async {
    final muted = !state.muted;
    state = state.copyWith(muted: muted);
    try {
      await _localTts.setVolume(muted ? 0.0 : 1.0);
      await _onlinePlayer.setVolume(muted ? 0.0 : 1.0);
    } catch (_) {}
  }

  /// چرخه تکرار: 0 → 2 → 3 → ∞ → 0
  /// (مثل Hope: «N بار کلاً» روی هر جمله؛ ∞ = همین جمله تا وقتی خودت
  /// «بعدی» را بزنی یا خاموشش کنی)
  void cycleRepeat() {
    final order = [0, 2, 3, -1];
    final i = order.indexOf(state.globalRepeat);
    final next = order[(i + 1) % order.length];
    debugPrint('🔁 cycleRepeat: ${state.globalRepeat} → $next');
    state = state.copyWith(globalRepeat: next);
  }

  void markAB() {
    if (_chunks.isEmpty) return;
    if (_abState == 'idle') {
      _abChunkA = _chunkIndex;
      _abState = 'waitingB';
    } else if (_abState == 'waitingB') {
      if (_chunkIndex < (_abChunkA ?? 0)) {
        _abChunkB = _abChunkA;
        _abChunkA = _chunkIndex;
      } else {
        _abChunkB = _chunkIndex;
      }
      _abState = 'looping';
    } else {
      _abState = 'idle';
      _abChunkA = null;
      _abChunkB = null;
    }
    // ✅ قبلاً state.copyWith() خالی بود و دکمه‌ی A-B هیچ‌وقت تغییر نمی‌کرد
    if (_abState == 'idle') {
      state = state.copyWith(abState: 'idle', clearAB: true);
    } else {
      state = state.copyWith(
        abState: _abState,
        abChunkA: _abChunkA,
        abChunkB: _abChunkB,
      );
    }
  }

  int getChunkCount() => _chunks.length;
  String getChunkText(int idx) =>
      (idx >= 0 && idx < _chunks.length) ? _chunks[idx].text : '';
  String get fullText => _fullText;
  int get currentChunk => _chunkIndex;

  // ═══════════════════════════════════════════════════════════════
  // داخلی
  // ═══════════════════════════════════════════════════════════════

  /// همه‌ی منتظرهای پایان خوانش را با false آزاد می‌کند.
  void _cancelWaiters() {
    for (final c in [_nativeWaiter, _webWaiter, _onlineWaiter]) {
      if (c != null && !c.isCompleted) c.complete(false);
    }
    _nativeWaiter = null;
    _webWaiter = null;
    _onlineWaiter = null;
  }

  Future<void> _pause() async {
    _generation++;
    _cancelWaiters();
    try {
      await _localTts.stop();
      await NativeTtsBridge.stop();
      await _onlinePlayer.pause();
    } catch (_) {}
    state = state.copyWith(status: SpeechStatus.paused);
  }

  Future<void> _stopAll() async {
    _cancelWaiters();
    try {
      await _localTts.stop();
      await NativeTtsBridge.stop();
      await _onlinePlayer.stop();
    } catch (_) {}
  }

  Future<void> _playFrom(int idx) async {
    if (_disposed) return;
    if (idx >= _chunks.length) {
      if (state.globalRepeat == -1 && _chunks.isNotEmpty) {
        unawaited(_playFrom(0));
        return;
      }
      _chunkIndex = 0;
      state = state.copyWith(status: SpeechStatus.idle, chunkIndex: 0);
      return;
    }

    final myGen = _generation;
    _chunkIndex = idx;
    state = state.copyWith(
      chunkIndex: idx,
      status: SpeechStatus.playing,
      total: _chunks.length,
      hasPrev: _hasPrev(idx),
      hasNext: _hasNext(idx),
    );

    final chunk = _chunks[idx];
    final cleanText = SentenceSplitter.sanitize(chunk.text);
    if (cleanText.isEmpty) {
      unawaited(_playFrom(idx + 1));
      return;
    }

    final code = _currentCode ?? 'en';

    if (NativeTtsBridge.isAvailable) {
      // ۱. Piper نیتیو
      final ready = await NativeTtsBridge.isModelReady(code);
      if (myGen != _generation) return;
      if (ready) {
        final ok = await _playNative(idx, cleanText, code, myGen);
        // ✅ اگر وسط کار pause/stop/seek شد، هرگز سراغ موتور بعدی نرو
        // (قبلاً بعد از pause، موتور بعدی خوانش قدیمی را ناخواسته پخش می‌کرد)
        if (myGen != _generation) return;
        if (ok) return;
      }

      // ۲. TTS خود گوشی
      final okSys = await _playSystemTts(idx, cleanText, code, myGen);
      if (myGen != _generation) return;
      if (okSys) return;
    }

    // ۳. Web Speech / Edge
    if (myGen != _generation) return;
    await _playOnline(idx, cleanText, code, myGen);
  }

  /// خوانش با موتور نیتیو و انتظار برای رویداد پایان.
  /// true = خوانده و به مرحله‌ی «مکث + تکرار» رفت؛ false = شکست یا لغو.
  Future<bool> _speakNativeAndWait({
    required Future<bool> Function(String id) speakFn,
    required int idx,
    required String text,
    required int myGen,
  }) async {
    try {
      final id = 'f${++_utteranceSeq}';
      final waiter = Completer<bool>();
      _nativeWaiter = waiter;
      final startedAt = DateTime.now();

      NativeTtsBridge.onDone((doneId, ok) {
        if (waiter.isCompleted || !identical(_nativeWaiter, waiter)) return;
        if (doneId != null && doneId != id) return; // مال خوانش قبلی
        if (doneId == null &&
            DateTime.now().difference(startedAt) < _staleDoneGuard) {
          return; // احتمالاً مال خوانش قبلیِ متوقف‌شده
        }
        waiter.complete(ok);
      });

      final started = await speakFn(id);
      if (myGen != _generation) return false;
      if (!started) return false;

      final finished = await waiter.future.timeout(
        Duration(seconds: 30 + text.length ~/ 10),
        onTimeout: () => true,
      );
      if (identical(_nativeWaiter, waiter)) _nativeWaiter = null;
      if (myGen != _generation) return false;
      if (!finished) return false;

      await _gapThenNext(idx, text, myGen);
      return true;
    } catch (e) {
      debugPrint('native speak error: $e');
      return false;
    }
  }

  Future<bool> _playNative(int idx, String text, String code, int myGen) {
    return _speakNativeAndWait(
      speakFn: (id) => NativeTtsBridge.speak(text, code, state.rate, id: id),
      idx: idx,
      text: text,
      myGen: myGen,
    );
  }

  Future<bool> _playSystemTts(int idx, String text, String code, int myGen) {
    return _speakNativeAndWait(
      speakFn: (id) =>
          NativeTtsBridge.speakSystem(text, code, state.rate, id: id),
      idx: idx,
      text: text,
      myGen: myGen,
    );
  }

  /// فهرست صداهای دستگاه/مرورگر (مثل getCachedVoices در Hope). روی وب،
  /// getVoices() بار اول ممکنه خالی باشه، پس چند بار تلاش می‌کنیم.
  Future<List<Map<String, String>>> _loadVoices() async {
    if (_voices.isNotEmpty) return _voices;
    for (var i = 0; i < 6; i++) {
      try {
        final raw = await _localTts.getVoices;
        if (raw is List && raw.isNotEmpty) {
          _voices = raw
              .whereType<Map>()
              .map((m) => {
                    'name': '${m['name'] ?? ''}',
                    'locale': '${m['locale'] ?? m['lang'] ?? ''}',
                  })
              .where((m) => m['name']!.isNotEmpty && m['locale']!.isNotEmpty)
              .toList();
          if (_voices.isNotEmpty) return _voices;
        }
      } catch (e) {
        debugPrint('getVoices error: $e');
      }
      await Future.delayed(const Duration(milliseconds: 250));
    }
    return _voices;
  }

  String _normLocale(String l) => l.toLowerCase().replaceAll('_', '-');

  /// انتخاب بهترین صدا برای زبان — همون ترتیبِ getBestVoice در Hope:
  /// صدای ذخیره‌شده‌ی کاربر > کیفیت (neural/wavenet/...) > Google > اولین صدای منطبق.
  /// null = فهرست صداها خالیه (نامعلوم)؛ [_noVoiceMarker] = مطمئنیم صدایی برای این زبان نیست.
  static const Map<String, String> _noVoiceMarker = {'none': 'true'};

  Future<Map<String, String>?> _pickVoice(String locale, String code) async {
    final voices = await _loadVoices();
    if (voices.isEmpty) return null;

    final prefix = _normLocale(locale).split('-').first;
    final wanted = _normLocale(locale);
    final matching = voices.where((v) {
      final l = _normLocale(v['locale']!);
      return l == prefix || l.startsWith('$prefix-');
    }).toList();
    if (matching.isEmpty) return _noVoiceMarker;

    // صدای دقیقاً هم‌locale (مثلاً de-DE) جلوتر قرار بگیره
    matching.sort((a, b) {
      final ea = _normLocale(a['locale']!) == wanted ? 0 : 1;
      final eb = _normLocale(b['locale']!) == wanted ? 0 : 1;
      return ea.compareTo(eb);
    });

    final saved = _voicePref?.call(code);
    if (saved != null && saved.isNotEmpty) {
      for (final v in matching) {
        if (v['name'] == saved) return v;
      }
    }

    const quality = [
      'neural', 'wavenet', 'chirp', 'studio', 'natural', 'premium',
      'enhanced', 'polyglot',
    ];
    final genderRe = RegExp('female|male', caseSensitive: false);
    for (final kw in quality) {
      for (final v in matching) {
        final n = v['name']!.toLowerCase();
        if (n.contains(kw) && genderRe.hasMatch(v['name']!)) return v;
      }
    }
    for (final kw in quality) {
      for (final v in matching) {
        if (v['name']!.toLowerCase().contains(kw)) return v;
      }
    }
    for (final v in matching) {
      if (v['name']!.toLowerCase().contains('google')) return v;
    }
    return matching.first;
  }

  Future<_WebResult> _playWebSpeech(
    int idx,
    String text,
    String code,
    int myGen,
  ) async {
    try {
      final locale = TtsConfig.locale[code] ?? 'en-US';

      // ✅ مثل Hope: صدای مخصوصِ همین زبان را از بین صداهای نصب‌شده‌ی
      // دستگاه/مرورگر انتخاب می‌کنیم — قبلاً فقط setLanguage زده می‌شد و
      // روی وب همه‌چیز با صدای انگلیسیِ پیش‌فرض خوانده می‌شد.
      final voice = await _pickVoice(locale, code);
      if (myGen != _generation) return _WebResult.cancelled;
      if (identical(voice, _noVoiceMarker)) return _WebResult.noVoice;

      final waiter = Completer<bool>();
      _webWaiter = waiter;

      // پایان خوانش را با handler می‌فهمیم (نه awaitSpeakCompletion که روی
      // وب فعال نمی‌شد و تکرار، خوانش‌ها را پشت سر هم داخل صف مرورگر می‌ریخت).
      _localTts.setCompletionHandler(() {
        if (waiter.isCompleted || !identical(_webWaiter, waiter)) return;
        waiter.complete(true);
      });
      _localTts.setCancelHandler(() {
        // cancel یعنی خودمان stop زدیم؛ _cancelWaiters کارش را کرده.
      });
      _localTts.setErrorHandler((msg) {
        if (waiter.isCompleted || !identical(_webWaiter, waiter)) return;
        final m = '$msg'.toLowerCase();
        if (m.contains('interrupted') || m.contains('cancel')) {
          return; // قطع‌شدن عمدیِ خودمان، خطا نیست
        }
        debugPrint('WebSpeech error event: $msg');
        waiter.complete(false);
      });

      await _localTts.setLanguage(voice?['locale'] ?? locale);
      if (voice != null) {
        await _localTts.setVoice({
          'name': voice['name']!,
          'locale': voice['locale']!,
        });
      }
      await _localTts.setSpeechRate(state.rate);
      await _localTts.setVolume(state.muted ? 0.0 : 1.0);
      await _localTts.setPitch(1.0);

      if (myGen != _generation) return _WebResult.cancelled;

      await _localTts.speak(text);

      if (myGen != _generation) return _WebResult.cancelled;

      final finished = await waiter.future.timeout(
        Duration(seconds: 20 + text.length ~/ 5),
        onTimeout: () => true,
      );
      if (identical(_webWaiter, waiter)) _webWaiter = null;
      if (myGen != _generation) return _WebResult.cancelled;
      if (!finished) return _WebResult.failed;

      await _gapThenNext(idx, text, myGen);
      return _WebResult.done;
    } catch (e) {
      debugPrint('WebSpeech error: $e');
      return _WebResult.failed;
    }
  }

  Future<void> _playOnline(
    int idx,
    String text,
    String code,
    int myGen,
  ) async {
    // روی وب (مثل Hope): فارسی/عربی همیشه آنلاین (Edge)؛ بقیه‌ی زبان‌ها فقط
    // با صدای نصب‌شده‌ی همان زبان روی دستگاه/مرورگر، بدون رفتن سراغ آنلاین.
    if (!NativeTtsBridge.isAvailable && !TtsConfig.onlineOnly.contains(code)) {
      final r = await _playWebSpeech(idx, text, code, myGen);
      if (myGen != _generation) return;
      switch (r) {
        case _WebResult.done:
        case _WebResult.cancelled:
          return;
        case _WebResult.noVoice:
          state = state.copyWith(
            status: SpeechStatus.idle,
            error: 'برای این زبان صدایی روی دستگاه نصب نیست؛ '
                'صدای آن را از تنظیمات دستگاه/مرورگر نصب کنید.',
          );
          return;
        case _WebResult.failed:
          state = state.copyWith(
            status: SpeechStatus.idle,
            error: 'خطا در پخش صدا',
          );
          return;
      }
    }

    // Edge TTS از Worker
    final voice = TtsConfig.edgeVoice[code] ?? 'en-US-AriaNeural';
    final url = '${TtsConfig.backendUrl}/api/tts'
        '?voice=${Uri.encodeComponent(voice)}'
        '&text=${Uri.encodeComponent(text)}';

    StreamSubscription<PlayerState>? sub;
    try {
      await _onlinePlayer.stop();
      await _onlinePlayer.setUrl(url);
      await _onlinePlayer.setSpeed(state.rate);
      await _onlinePlayer.setVolume(state.muted ? 0.0 : 1.0);

      if (myGen != _generation) return;

      final waiter = Completer<bool>();
      _onlineWaiter = waiter;
      sub = _onlinePlayer.playerStateStream.listen((ps) {
        if (ps.processingState == ProcessingState.completed &&
            !waiter.isCompleted) {
          waiter.complete(true);
        }
      });

      unawaited(_onlinePlayer.play());
      final finished = await waiter.future;
      if (identical(_onlineWaiter, waiter)) _onlineWaiter = null;
      if (myGen != _generation) return;
      if (!finished) return;

      await _gapThenNext(idx, text, myGen);
    } catch (e) {
      debugPrint('Online TTS error: $e');
      if (myGen != _generation) return;
      state = state.copyWith(
        status: SpeechStatus.idle,
        error: 'خطا در پخش صدا',
      );
    } finally {
      await sub?.cancel();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // مکث + منطق تکرار (هم‌مفهوم با speechController.js در Hope)
  //   • تکرار روی «هر جمله» اعمال می‌شود، نه کل متن.
  //   • تنظیم N یعنی «کلاً N بار» (خوانش اول هم حساب است).
  //   • ∞ یعنی همین جمله دوباره و دوباره، تا کاربر «بعدی» بزند.
  // ═══════════════════════════════════════════════════════════════
  Future<void> _gapThenNext(int idx, String text, int myGen) async {
    final gap = _gapMs(chunk: text, rate: state.rate);
    await Future.delayed(Duration(milliseconds: gap));
    if (myGen != _generation || _disposed) return;

    // A-B looping
    if (_abState == 'looping' && _abChunkB != null && idx == _abChunkB) {
      final targetA = _abChunkA ?? 0;
      _chunkRepeatsDone.clear();
      unawaited(_playFrom(targetA));
      return;
    }

    // ═══ تکرار ═══
    final target = state.globalRepeat; // 0 | 2 | 3 | -1
    if (target != 0) {
      final done = _chunkRepeatsDone[idx] ?? 1; // تعداد دفعاتی که تا الان خونده شده
      final needRepeat = target == -1 || done < target;
      debugPrint(
          '🔁 repeat check: idx=$idx, done=$done, target=$target, needRepeat=$needRepeat');
      if (needRepeat) {
        _chunkRepeatsDone[idx] = done + 1;
        unawaited(_playFrom(idx));
        return;
      }
    }

    _chunkRepeatsDone.remove(idx);
    unawaited(_playFrom(idx + 1));
  }

  int _chunkIndexForOffset(int offset) {
    for (int i = _chunks.length - 1; i >= 0; i--) {
      if (offset >= _chunks[i].start) return i;
    }
    return 0;
  }

  int _gapMs({required String chunk, required double rate}) {
    final trimmed = chunk.trimRight();
    final last = trimmed.isEmpty ? '' : trimmed[trimmed.length - 1];
    final base = switch (last) {
      '!' || '！' => 420,
      '?' || '؟' || '？' => 400,
      '…' => 480,
      _ => 360,
    };
    return (base / rate.clamp(0.2, 2.0)).round();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelWaiters();
    _localTts.stop();
    _onlinePlayer.dispose();
    super.dispose();
  }
}
