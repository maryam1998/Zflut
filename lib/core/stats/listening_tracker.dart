// ⏱ ردیابِ «زمانِ گوش‌دادن» — پایه‌ی نمودارِ هفتگیِ تبِ مرور/پیشرفت.
//
// منبع‌ها (در هر لحظه فقط یکی حساب می‌شود تا زمانِ دوبل ثبت نشود):
//   • yt    : ویدیوی یوتیوب (از MediaSessionِ اندروید — NativeBridge.nowPlaying)
//   • audio : فایلِ صوتیِ آپلودیِ داستان (StoryAudioController)
//   • tts   : پلیرِ خودِ برنامه (خواندنِ لغات/مکالمات/داستان)
//
// ذخیره: روزانه (yyyy-MM-dd) → ثانیه‌ی هر منبع؛ ۱۲۰ روزِ اخیر.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../native/native_bridge.dart';
import '../providers/speech_provider.dart';
import '../storage/local_storage.dart';
import '../tts/speech_state.dart';

enum ListenSource { yt, audio, tts }

const String _kListenKey = 'zflut-listen-stats-v1';
const String _kYtPkg = 'com.google.android.youtube';

DateTime _dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

/// آمارِ یک روز (ثانیه به تفکیکِ منبع).
@immutable
class ListenDay {
  final int yt;
  final int audio;
  final int tts;
  const ListenDay({this.yt = 0, this.audio = 0, this.tts = 0});

  int get total => yt + audio + tts;

  ListenDay plus(ListenSource s, int sec) => ListenDay(
        yt: yt + (s == ListenSource.yt ? sec : 0),
        audio: audio + (s == ListenSource.audio ? sec : 0),
        tts: tts + (s == ListenSource.tts ? sec : 0),
      );

  Map<String, dynamic> toJson() => {'y': yt, 'a': audio, 't': tts};

  factory ListenDay.fromJson(Map<dynamic, dynamic> j) => ListenDay(
        yt: (j['y'] as num?)?.toInt() ?? 0,
        audio: (j['a'] as num?)?.toInt() ?? 0,
        tts: (j['t'] as num?)?.toInt() ?? 0,
      );
}

@immutable
class ListenStats {
  final Map<String, ListenDay> days;
  const ListenStats([this.days = const {}]);

  static String keyOf(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  ListenDay day(DateTime d) => days[keyOf(d)] ?? const ListenDay();

  /// [n] روزِ اخیر؛ قدیمی‌ترین اول، آخری = امروز.
  List<DateTime> lastDates(DateTime now, {int n = 7}) {
    final t = _dayStart(now);
    return [
      for (var i = n - 1; i >= 0; i--) DateTime(t.year, t.month, t.day - i),
    ];
  }

  Map<String, dynamic> toJson() =>
      {'days': days.map((k, v) => MapEntry(k, v.toJson()))};

  factory ListenStats.fromJson(Map<String, dynamic> json) {
    final raw = json['days'];
    if (raw is! Map) return const ListenStats();
    final out = <String, ListenDay>{};
    raw.forEach((k, v) {
      if (v is Map) out[k.toString()] = ListenDay.fromJson(v);
    });
    return ListenStats(out);
  }
}

/// ویجت‌ها اینجا اعلام می‌کنند «الان صدا پخش می‌شود / نمی‌شود».
class ListenSignals {
  ListenSignals._();
  static final Map<String, ListenSource> _active = {};

  static void report(String id, ListenSource src, bool playing) {
    if (playing) {
      _active[id] = src;
    } else {
      _active.remove(id);
    }
  }

  static bool has(ListenSource s) => _active.values.contains(s);
}

class ListeningTracker extends StateNotifier<ListenStats>
    with WidgetsBindingObserver {
  ListeningTracker(this._storage)
      : super(ListenStats.fromJson(_storage.readJson(_kListenKey))) {
    _pending = Map<String, ListenDay>.from(state.days);
    WidgetsBinding.instance.addObserver(this);
    _last = DateTime.now();
    _timer = Timer.periodic(_tick, (_) => unawaited(_onTick()));
  }

  static const Duration _tick = Duration(seconds: 3);

  final LocalStorage _storage;
  late Map<String, ListenDay> _pending;
  late DateTime _last;
  Timer? _timer;
  bool _busy = false;
  bool _dirty = false;
  int _carryMs = 0;
  DateTime _lastFlush = DateTime.now();

  Future<ListenSource?> _currentSource() async {
    // yt اول: وقتی یوتیوب پخش می‌شود همان حساب می‌شود
    if (NativeBridge.instance.isSupported) {
      try {
        final r = await NativeBridge.instance.nowPlaying();
        if (r['playing'] == true && r['pkg'] == _kYtPkg) {
          return ListenSource.yt;
        }
      } catch (_) {}
    }
    if (ListenSignals.has(ListenSource.audio)) return ListenSource.audio;
    if (ListenSignals.has(ListenSource.tts)) return ListenSource.tts;
    return null;
  }

  Future<void> _onTick() async {
    if (_busy || !mounted) return;
    _busy = true;
    try {
      final now = DateTime.now();
      // اگر پردازش مدتی معلق بوده، بیش از چند ثانیه اضافه نشود
      var dt = now.difference(_last).inMilliseconds.clamp(0, 6000).toInt();
      _last = now;
      final src = await _currentSource();
      if (src != null && dt > 0) {
        dt += _carryMs;
        final sec = dt ~/ 1000;
        _carryMs = dt % 1000;
        if (sec > 0) {
          final k = ListenStats.keyOf(now);
          _pending[k] = (_pending[k] ?? const ListenDay()).plus(src, sec);
          _dirty = true;
        }
      }
      if (_dirty && now.difference(_lastFlush).inSeconds >= 10) _flush();
    } finally {
      _busy = false;
    }
  }

  void _flush() {
    if (!mounted || !_dirty) return;
    _dirty = false;
    _lastFlush = DateTime.now();
    final cutoff = ListenStats.keyOf(
        _dayStart(DateTime.now()).subtract(const Duration(days: 120)));
    _pending.removeWhere((k, _) => k.compareTo(cutoff) < 0);
    state = ListenStats(Map<String, ListenDay>.from(_pending));
    unawaited(_storage.writeJson(_kListenKey, state.toJson()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused ||
        s == AppLifecycleState.inactive ||
        s == AppLifecycleState.detached) {
      _flush();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _flush();
    super.dispose();
  }
}

/// یک‌بار در LingoLearnApp خوانده می‌شود (ref.read) تا ردیاب از شروعِ برنامه زنده باشد.
final listeningStatsProvider =
    StateNotifierProvider<ListeningTracker, ListenStats>((ref) {
  final t = ListeningTracker(ref.read(localStorageProvider));
  // پلیرِ خودِ برنامه (TTS)
  ref.listen<SpeechStatus>(
    speechControllerProvider.select((s) => s.status),
    (_, st) =>
        ListenSignals.report('tts', ListenSource.tts, st == SpeechStatus.playing),
    fireImmediately: true,
  );
  return t;
});
