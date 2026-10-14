import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';

import 'native_tts_bridge.dart';
import 'sentence_splitter.dart';
import 'speech_state.dart';
import 'tts_config.dart';

class SpeechController extends StateNotifier<SpeechState> {
  SpeechController() : super(const SpeechState()) {
    _initLocalTts();
  }

  final FlutterTts _localTts = FlutterTts();
  final AudioPlayer _onlinePlayer = AudioPlayer();

  String _fullText = '';
  List<TextChunk> _chunks = [];
  int _chunkIndex = 0;
  String? _currentKey;
  String? _currentCode;
  int _generation = 0;
  bool _disposed = false;
  Completer<bool>? _nativeDoneCompleter;

  // A-B
  String _abState = 'idle';
  int? _abChunkA;
  int? _abChunkB;

  // شمارنده‌ی تکرار برای هر چانک
  final Map<int, int> _chunkRepeatsDone = {};

  Future<void> _initLocalTts() async {
    try {
      await _localTts.setSharedInstance(true);
      await _localTts.awaitSpeakCompletion(true); // ✅ مهم برای تکرار
    } catch (e) {
      debugPrint('initLocalTts error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // API عمومی
  // ═══════════════════════════════════════════════════════════════

  Future<String> toggle(
    String text,
    String code, {
    int? startCharOffset,
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
    _generation++;
    await _stopAll();

    _fullText = text;
    _chunks = SentenceSplitter.split(text);
    _chunkRepeatsDone.clear();
    _currentKey = newKey;
    _currentCode = code;

    final startIdx = startCharOffset != null && startCharOffset > 0
        ? _chunkIndexForOffset(startCharOffset)
        : 0;

    _chunkIndex = startIdx;
    _abState = 'idle';
    _abChunkA = null;
    _abChunkB = null;

    state = state.copyWith(
      key: newKey,
      total: _chunks.length,
      chunkIndex: startIdx,
      clearError: true,
    );

    unawaited(_playFrom(startIdx));
    return 'ok';
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
    state = const SpeechState();
  }

  Future<void> seekToChunk(int idx) async {
    if (_chunks.isEmpty) return;
    final clamped = idx.clamp(0, _chunks.length - 1);
    _generation++;
    await _stopAll();
    _chunkRepeatsDone.remove(clamped);
    _chunkIndex = clamped;
    state = state.copyWith(chunkIndex: clamped, status: SpeechStatus.playing);
    unawaited(_playFrom(clamped));
  }

  Future<void> nextChunk() async {
    if (_chunkIndex + 1 >= _chunks.length) return;
    await seekToChunk(_chunkIndex + 1);
  }

  Future<void> prevChunk() async {
    if (_chunkIndex <= 0) return;
    await seekToChunk(_chunkIndex - 1);
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
    state = state.copyWith();
  }

  int getChunkCount() => _chunks.length;
  String getChunkText(int idx) =>
      (idx >= 0 && idx < _chunks.length) ? _chunks[idx].text : '';
  String get fullText => _fullText;
  int get currentChunk => _chunkIndex;

  // ═══════════════════════════════════════════════════════════════
  // داخلی
  // ═══════════════════════════════════════════════════════════════

  Future<void> _pause() async {
    _generation++;
    try {
      await _localTts.stop();
      await NativeTtsBridge.stop();
      await _onlinePlayer.pause();
    } catch (_) {}
    state = state.copyWith(status: SpeechStatus.paused);
  }

  Future<void> _stopAll() async {
    try {
      await _localTts.stop();
      await NativeTtsBridge.stop();
      await _onlinePlayer.stop();
    } catch (_) {}
  }

  Future<void> _playFrom(int idx) async {
    if (_disposed) return;
    if (idx >= _chunks.length) {
      if (state.globalRepeat == -1) {
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
    );

    final chunk = _chunks[idx];
    final cleanText = SentenceSplitter.sanitize(chunk.text);
    if (cleanText.isEmpty) {
      unawaited(_playFrom(idx + 1));
      return;
    }

    final code = _currentCode ?? 'en';

    // ۱. Piper نیتیو
    if (NativeTtsBridge.isAvailable) {
      final ready = await NativeTtsBridge.isModelReady(code);
      if (ready) {
        final ok = await _playNative(idx, cleanText, code, myGen);
        if (ok && myGen == _generation) return;
      }
    }

    // ۲. TTS خود گوشی
    if (NativeTtsBridge.isAvailable) {
      final ok = await _playSystemTts(idx, cleanText, code, myGen);
      if (ok && myGen == _generation) return;
    }

    // ۳. Web Speech / Edge
    await _playOnline(idx, cleanText, code, myGen);
  }

  Future<bool> _playNative(
    int idx,
    String text,
    String code,
    int myGen,
  ) async {
    try {
      _nativeDoneCompleter = Completer<bool>();
      NativeTtsBridge.onDone(() {
        if (_nativeDoneCompleter?.isCompleted == false) {
          _nativeDoneCompleter!.complete(true);
        }
      });
      final ok = await NativeTtsBridge.speak(text, code, state.rate);
      if (!ok || myGen != _generation) return false;
      await _nativeDoneCompleter!.future.timeout(
        Duration(seconds: 30 + text.length ~/ 10),
        onTimeout: () => true,
      );
      if (myGen != _generation) return false;
      await _gapThenNext(idx, text, myGen);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _playSystemTts(
    int idx,
    String text,
    String code,
    int myGen,
  ) async {
    try {
      _nativeDoneCompleter = Completer<bool>();
      NativeTtsBridge.onDone(() {
        if (_nativeDoneCompleter?.isCompleted == false) {
          _nativeDoneCompleter!.complete(true);
        }
      });
      final ok = await NativeTtsBridge.speakSystem(text, code, state.rate);
      if (!ok || myGen != _generation) return false;
      await _nativeDoneCompleter!.future.timeout(
        Duration(seconds: 30 + text.length ~/ 10),
        onTimeout: () => true,
      );
      if (myGen != _generation) return false;
      await _gapThenNext(idx, text, myGen);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _playWebSpeech(
    int idx,
    String text,
    String code,
    int myGen,
  ) async {
    try {
      final locale = TtsConfig.locale[code] ?? 'en-US';
      await _localTts.setLanguage(locale);
      await _localTts.setSpeechRate(state.rate);
      await _localTts.setVolume(state.muted ? 0.0 : 1.0);
      await _localTts.setPitch(1.0);

      if (myGen != _generation) return false;

      // ✅ با awaitSpeakCompletion که در _initLocalTts فعاله،
      // این فراخوانی تا پایان پخش صبر می‌کنه
      await _localTts.speak(text);

      if (myGen != _generation) return false;

      await _gapThenNext(idx, text, myGen);
      return true;
    } catch (e) {
      debugPrint('WebSpeech error: $e');
      return false;
    }
  }

  Future<void> _playOnline(
    int idx,
    String text,
    String code,
    int myGen,
  ) async {
    // روی وب: flutter_tts اول
    if (!NativeTtsBridge.isAvailable) {
      final localOk = await _playWebSpeech(idx, text, code, myGen);
      if (localOk && myGen == _generation) return;
    }

    // Edge TTS از Worker
    final voice = TtsConfig.edgeVoice[code] ?? 'en-US-AriaNeural';
    final url = '${TtsConfig.backendUrl}/api/tts'
        '?voice=${Uri.encodeComponent(voice)}'
        '&text=${Uri.encodeComponent(text)}';

    try {
      await _onlinePlayer.stop();
      await _onlinePlayer.setUrl(url);
      await _onlinePlayer.setSpeed(state.rate);
      await _onlinePlayer.setVolume(state.muted ? 0.0 : 1.0);

      if (myGen != _generation) return;

      final completer = Completer<void>();
      StreamSubscription<PlayerState>? sub;
      sub = _onlinePlayer.playerStateStream.listen((ps) {
        if (ps.processingState == ProcessingState.completed) {
          sub?.cancel();
          if (!completer.isCompleted) completer.complete();
        }
      });

      await _onlinePlayer.play();
      await completer.future;
      if (myGen != _generation) return;

      await _gapThenNext(idx, text, myGen);
    } catch (e) {
      debugPrint('Online TTS error: $e');
      if (myGen != _generation) return;
      state = state.copyWith(
        status: SpeechStatus.idle,
        error: 'خطا در پخش صدا',
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // مکث + منطق تکرار
  // ═══════════════════════════════════════════════════════════════
  Future<void> _gapThenNext(int idx, String text, int myGen) async {
    final gap = _gapMs(chunk: text, rate: state.rate);
    await Future.delayed(Duration(milliseconds: gap));
    if (myGen != _generation) return;

    // A-B looping
    if (_abState == 'looping' && _abChunkB != null && idx == _abChunkB) {
      final targetA = _abChunkA ?? 0;
      _chunkRepeatsDone.remove(idx);
      unawaited(_playFrom(targetA));
      return;
    }

    // ═══ تکرار ═══
    final target = state.globalRepeat; // 0 | 2 | 3 | -1
    if (target != 0) {
      final done = _chunkRepeatsDone[idx] ?? 1;
      final needRepeat = target == -1 ? true : done < target;
      debugPrint('🔁 repeat check: idx=$idx, done=$done, target=$target, needRepeat=$needRepeat');
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
    _localTts.stop();
    _onlinePlayer.dispose();
    super.dispose();
  }
}
