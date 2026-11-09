import 'dart:async';

import 'package:flutter/foundation.dart';

import '../native/native_bridge.dart';
import 'speech_controller.dart';
import 'speech_state.dart';

/// 🎧 پلیرِ اپ را به نوتیفیکیشنِ مدیای اندروید وصل می‌کند: وقتی از برنامه بیرون می‌روی،
/// روی نوتیفیکیشن/صفحه‌ی قفل «قبلی ⏮ · پخش/توقف ⏯ · بعدی ⏭» (جمله/لغتِ قبلی و بعدی) داری.
class MediaNotificationSync {
  /// [translate]: ترجمه‌ی متنِ جمله از زبانِ [from] به زبانِ [to] — اختیاری؛ [peek]: خواندنِ فوریِ ترجمه از کش.
  /// [targets]: زبان‌های مقصدِ انتخابی برای زبانِ مبدأِ [from] (خودِ مبدأ در آن نیست).
  /// اگر داده شوند، ترجمه‌ی همه‌ی زبان‌های مقصد زیرِ جمله‌ی در حال خوانش در نوتیفیکیشن نشان داده می‌شود.
  MediaNotificationSync(this._ctl, {this.translate, this.peek, this.targets});

  final SpeechController _ctl;
  final Future<String> Function(String text, String from, String to)? translate;
  final String? Function(String text, String from, String to)? peek;
  final List<String> Function(String from)? targets;

  // ترجمه‌ی جمله‌های اخیر (متن مبدأ → ترجمه) + جمله‌هایی که الان در حال ترجمه‌اند
  final Map<String, String> _trCache = {};
  final Set<String> _trBusy = {};
  SpeechState? _lastState;
  void Function()? _removeListener;
  StreamSubscription<Map<String, dynamic>>? _cmdSub;
  Timer? _debounce;
  Timer? _rotTimer;
  int _rot = 0; // نوبتِ نمایشِ زبان‌های مقصد (نوتیفیکیشن فقط یک خط جا دارد)
  bool _multi = false;
  String _lastSig = '';
  bool _disposed = false;
  String? _heldTitle; // آخرین عنوان/زیرعنوانِ «جمله‌ی اصلی» (برای زمانی که ترجمه خوانده می‌شود)
  String? _heldSub;

  void attach() {
    final nb = NativeBridge.instance;
    if (!nb.isSupported) return;
    _removeListener = _ctl.addListener(_onState, fireImmediately: false);
    // وقتی چند زبان مقصد هست، هر ۳ ثانیه نوبتِ زبانِ بعدی می‌شود تا همه دیده شوند
    _rotTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      final st = _lastState;
      if (_disposed || !_multi || st == null) return;
      if (st.status == SpeechStatus.idle || st.key == null) return;
      _rot++;
      _lastSig = '';
      _push(st);
    });
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
    final playing = s.status == SpeechStatus.playing;
    String title;
    String sub;
    if (s.key != null && s.key == SpeechController.translationReadKey &&
        _heldTitle != null) {
      // 🌐 پلیر دارد ترجمه را می‌خواند: نوتیفیکیشن همان جمله‌ی اصلی (با ترجمه‌اش زیرش) را نگه می‌دارد
      title = _heldTitle!;
      sub = _heldSub ?? '';
    } else {
      final text = _ctl.currentChunkText.trim();
      title = text.length > 90 ? '${text.substring(0, 90)}…' : text;
      final counter = s.total > 1 ? '${s.chunkIndex + 1} / ${s.total}' : '';
      // 🌐 ترجمه‌ی همین جمله (زیرِ جمله، همان خطی که شماره‌ی جمله بود)
      final tr = _translationFor(text, s);
      sub = tr.isEmpty ? counter : (counter.isEmpty ? tr : '$counter · $tr');
      _heldTitle = title;
      _heldSub = sub;
      // ⚡ ترجمه‌ی چند جمله‌ی بعدی از قبل آماده می‌شود تا در بارِ اول هم همراهِ جمله نشان داده شود
      _prefetchAhead(s);
    }
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

  /// ترجمه‌ی آماده‌ی همه‌ی زبان‌های مقصد (از کش) را برمی‌گرداند؛ هر کدام که نبود در پس‌زمینه
  /// می‌گیرد و به‌محضِ آماده شدن نوتیفیکیشن را تازه می‌کند.
  String _translationFor(String text, SpeechState s) {
    if (text.isEmpty || translate == null) return '';
    final from = _langOf(s);
    List<String> tos;
    try {
      tos = targets?.call(from) ?? const <String>[];
    } catch (_) {
      tos = const <String>[];
    }
    if (tos.isEmpty) return '';
    final parts = <String>[];
    for (final to in tos) {
      if (to == from) continue;
      final ck = '$from>$to|$text';
      // اول کشِ اصلیِ برنامه (ترجمه‌ی رفرش‌شده‌ی کاربر همان‌جا ذخیره می‌شود)؛ بعد حافظه‌ی همین کلاس
      String? hit;
      try {
        final quick = peek?.call(text, from, to);
        if (quick != null && quick.trim().isNotEmpty) {
          hit = _remember(ck, quick);
        }
      } catch (_) {}
      hit ??= _trCache[ck];
      if (hit == null) {
        _fetch(text, from, to, ck);
        continue;
      }
      parts.add(tos.length > 1 ? '${to.toUpperCase()}: $hit' : hit);
    }
    _multi = parts.length > 1;
    if (parts.isEmpty) return '';
    return parts[_rot % parts.length];
  }

  /// ترجمه‌ی ۳ جمله‌ی بعدیِ متنِ در حال خوانش را از قبل در کش می‌گذارد.
  void _prefetchAhead(SpeechState s) {
    if (translate == null) return;
    final from = _langOf(s);
    List<String> tos;
    try {
      tos = targets?.call(from) ?? const <String>[];
    } catch (_) {
      tos = const <String>[];
    }
    if (tos.isEmpty) return;
    final n = _ctl.getChunkCount();
    for (var i = s.chunkIndex + 1; i <= s.chunkIndex + 3 && i < n; i++) {
      final t = _ctl.getChunkText(i).trim();
      if (t.isEmpty) continue;
      for (final to in tos) {
        if (to == from) continue;
        final ck = '$from>$to|$t';
        try {
          final quick = peek?.call(t, from, to);
          if (quick != null && quick.trim().isNotEmpty) {
            _remember(ck, quick);
            continue;
          }
        } catch (_) {}
        if (_trCache.containsKey(ck)) continue;
        _fetch(t, from, to, ck);
      }
    }
  }

  void _fetch(String text, String from, String to, String ck, [int tries = 0]) {
    if (!_trBusy.add(ck)) return;
    unawaited(() async {
      String r = '';
      try {
        r = (await translate!(text, from, to)).trim();
      } catch (_) {}
      _trBusy.remove(ck);
      if (_disposed) return;
      // ترجمه‌ی ناموفق (همان متن مبدأ) نشان داده نمی‌شود؛ یک بار دیگر هم تلاش می‌کنیم
      if (r.isEmpty || r.toLowerCase() == text.toLowerCase()) {
        if (tries < 1) {
          Timer(const Duration(milliseconds: 1500), () {
            if (_disposed) return;
            _fetch(text, from, to, ck, tries + 1);
          });
        }
        return;
      }
      _remember(ck, r);
      // فقط اگر هنوز همین جمله در حال خوانش است نوتیفیکیشن را تازه کن
      final st = _lastState;
      if (st != null && _ctl.currentChunkText.trim() == text) {
        _lastSig = '';
        _push(st);
      }
    }());
  }

  String _remember(String key, String tr) {
    var t = tr.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.length > 140) t = '${t.substring(0, 140)}…';
    if (_trCache.length > 200) _trCache.remove(_trCache.keys.first);
    _trCache[key] = t;
    return t;
  }

  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _rotTimer?.cancel();
    _removeListener?.call();
    _cmdSub?.cancel();
    if (NativeBridge.instance.isSupported) {
      unawaited(NativeBridge.instance
          .mediaNotifHide()
          .catchError((_) => <String, dynamic>{}));
    }
  }
}
