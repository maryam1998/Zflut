import 'dart:async';

import 'package:flutter/foundation.dart';

import '../native/native_bridge.dart';
import 'speech_controller.dart';
import 'speech_state.dart';

/// 🎧 پلیرِ اپ را به نوتیفیکیشنِ مدیای اندروید وصل می‌کند: وقتی از برنامه بیرون می‌روی،
/// روی نوتیفیکیشن/صفحه‌ی قفل «قبلی ⏮ · پخش/توقف ⏯ · بعدی ⏭» (جمله/لغتِ قبلی و بعدی) داری.
class MediaNotificationSync {
  MediaNotificationSync(this._ctl);

  final SpeechController _ctl;
  void Function()? _removeListener;
  StreamSubscription<Map<String, dynamic>>? _cmdSub;
  Timer? _debounce;
  String _lastSig = '';
  bool _disposed = false;

  void attach() {
    final nb = NativeBridge.instance;
    if (!nb.isSupported) return;
    _removeListener = _ctl.addListener(_onState, fireImmediately: false);
    _cmdSub = nb.on('mediaCmd').listen((d) {
      switch (d['cmd']?.toString()) {
        case 'toggle':
          unawaited(_ctl.togglePlayPause());
          break;
        case 'next':
          unawaited(_ctl.nextChunk());
          break;
        case 'prev':
          unawaited(_ctl.prevChunk());
          break;
        case 'stop':
          unawaited(_ctl.stop());
          break;
      }
    }, onError: (Object e) => debugPrint('mediaCmd stream error: $e'));
  }

  void _onState(SpeechState s) {
    if (_disposed) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () => _push(s));
  }

  void _push(SpeechState s) {
    if (_disposed) return;
    final nb = NativeBridge.instance;
    if (s.status == SpeechStatus.idle || s.key == null) {
      if (_lastSig != 'hidden') {
        _lastSig = 'hidden';
        unawaited(nb.mediaNotifHide().catchError((_) => <String, dynamic>{}));
      }
      return;
    }
    final text = _ctl.currentChunkText.trim();
    final title = text.length > 90 ? '${text.substring(0, 90)}…' : text;
    final playing = s.status == SpeechStatus.playing;
    final sub = s.total > 1 ? '${s.chunkIndex + 1} / ${s.total}' : '';
    final sig = '$title|$sub|$playing|${s.hasPrev}|${s.hasNext}';
    if (sig == _lastSig) return;
    _lastSig = sig;
    unawaited(nb
        .mediaNotifUpdate(
          title: title,
          sub: sub,
          playing: playing,
          // «قبلی/بعدی» همیشه کار می‌کنند (در لبه‌ی متن، همان جمله را از اول می‌خوانند)
          prev: true,
          next: true,
        )
        .catchError((_) => <String, dynamic>{}));
  }

  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _removeListener?.call();
    _cmdSub?.cancel();
    if (NativeBridge.instance.isSupported) {
      unawaited(NativeBridge.instance
          .mediaNotifHide()
          .catchError((_) => <String, dynamic>{}));
    }
  }
}
