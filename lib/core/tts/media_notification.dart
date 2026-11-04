import 'dart:async';

import 'package:flutter/foundation.dart';

import '../native/native_bridge.dart';
import 'speech_controller.dart';
import 'speech_state.dart';

/// 🎧 پلیرِ اپ را به نوتیفیکیشنِ مدیای اندروید وصل می‌کند: وقتی از برنامه بیرون می‌روی،
/// روی نوتیفیکیشن/صفحه‌ی قفل «قبلی ⏮ · پخش/توقف ⏯ · بعدی ⏭» (جمله/لغتِ قبلی و بعدی) داری.
class MediaNotificationSync {
  /// [translate]: ترجمه‌ی متنِ جمله (از زبانِ [from]) — اختیاری؛ [peek]: خواندنِ فوریِ ترجمه از کش.
  /// اگر داده شوند، ترجمه‌ی جمله‌ی در حال خوانش زیرِ خودِ جمله در نوتیفیکیشن نشان داده می‌شود.
  MediaNotificationSync(this._ctl, {this.translate, this.peek});

  final SpeechController _ctl;
  final Future<String> Function(String text, String from)? translate;
  final String? Function(String text, String from)? peek;

  // ترجمه‌ی جمله‌های اخیر (متن مبدأ → ترجمه) + جمله‌هایی که الان در حال ترجمه‌اند
  final Map<String, String> _trCache = {};
  final Set<String> _trBusy = {};
  SpeechState? _lastState;
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
    _lastState = s;
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
    final counter = s.total > 1 ? '${s.chunkIndex + 1} / ${s.total}' : '';
    // 🌐 ترجمه‌ی همین جمله (زیرِ جمله، همان خطی که شماره‌ی جمله بود)
    final tr = _translationFor(text, s);
    final sub = tr.isEmpty ? counter : (counter.isEmpty ? tr : '$counter · $tr');
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

  /// زبانِ متنِ در حال خوانش از روی کلیدِ پخش ('en-US::متن' → 'en')
  String _langOf(SpeechState s) {
    final k = s.key ?? '';
    final i = k.indexOf('::');
    if (i <= 0) return 'en';
    return k.substring(0, i).split('-').first.toLowerCase();
  }

  /// ترجمه‌ی آماده (از کش) را برمی‌گرداند؛ اگر نبود در پس‌زمینه می‌گیرد و بعدش نوتیفیکیشن را تازه می‌کند.
  String _translationFor(String text, SpeechState s) {
    if (text.isEmpty || translate == null) return '';
    final from = _langOf(s);
    final hit = _trCache[text];
    if (hit != null) return hit;
    try {
      final quick = peek?.call(text, from);
      if (quick != null && quick.trim().isNotEmpty) {
        return _remember(text, quick);
      }
    } catch (_) {}
    if (_trBusy.add(text)) {
      unawaited(() async {
        String r = '';
        try {
          r = (await translate!(text, from)).trim();
        } catch (_) {}
        _trBusy.remove(text);
        if (_disposed) return;
        // ترجمه‌ی ناموفق (همان متن مبدأ) نشان داده نمی‌شود
        if (r.isEmpty || r.toLowerCase() == text.toLowerCase()) return;
        _remember(text, r);
        // فقط اگر هنوز همین جمله در حال خوانش است نوتیفیکیشن را تازه کن
        final st = _lastState;
        if (st != null && _ctl.currentChunkText.trim() == text) {
          _lastSig = '';
          _push(st);
        }
      }());
    }
    return '';
  }

  String _remember(String text, String tr) {
    var t = tr.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.length > 140) t = '${t.substring(0, 140)}…';
    if (_trCache.length > 80) _trCache.remove(_trCache.keys.first);
    _trCache[text] = t;
    return t;
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
