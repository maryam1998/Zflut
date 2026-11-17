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
import '../player_sync/playback_origin.dart';
import '../player_sync/player_sync_provider.dart';
import '../providers/speech_provider.dart';
import '../storage/local_storage.dart';
import '../tts/speech_controller.dart' show SpeechController;
import '../tts/speech_state.dart';

enum ListenSource { yt, audio, tts }

const String _kListenKey = 'zflut-listen-stats-v1';
const String _kYtPkg = 'com.google.android.youtube';

DateTime _dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

/// 📍 «آخرین جای» گوش‌داده‌شده در یک تب: شناسه‌ی آیتم/جمله + حالتِ درونیِ تب
/// (مثلاً موضوع/سناریوی مکالمه یا شناسه‌ی داستان) برای برگشتنِ دقیق.
@immutable
class ListenPoint {
  final String? id;
  final Map<String, Object> extra;
  const ListenPoint(this.id, [this.extra = const {}]);

  Map<String, dynamic> toJson() => {
        if (id != null) 'i': id,
        if (extra.isNotEmpty) 'x': extra,
      };

  factory ListenPoint.fromJson(Map<dynamic, dynamic> j) {
    final x = <String, Object>{};
    final raw = j['x'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v is String || v is num || v is bool) x[k.toString()] = v as Object;
      });
    }
    return ListenPoint(j['i']?.toString(), x);
  }
}

/// 📖 «چه چیزی خوانده شد» در یک تب: حالتِ درونیِ تب (موضوع/سناریو/شناسه‌ی داستان)
/// + شناسه‌ی آیتم‌ها/جمله‌هایی که آن روز با پلیر خوانده شدند (به ترتیبِ خوانش).
@immutable
class ReadCtx {
  static const int maxIds = 200;
  final Map<String, Object> extra;
  final List<String> ids;
  const ReadCtx(this.extra, this.ids);

  static bool sameExtra(Map<String, Object> a, Map<String, Object> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  Map<String, dynamic> toJson() => {
        if (extra.isNotEmpty) 'x': extra,
        'i': ids,
      };

  factory ReadCtx.fromJson(Map<dynamic, dynamic> j) {
    final x = <String, Object>{};
    final raw = j['x'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v is String || v is num || v is bool) x[k.toString()] = v as Object;
      });
    }
    final ids = <String>[];
    final i = j['i'];
    if (i is List) {
      for (final e in i) {
        if (e != null) ids.add(e.toString());
      }
    }
    return ReadCtx(x, ids);
  }
}

/// آمارِ یک روز (ثانیه به تفکیکِ منبع). برای پلیرِ برنامه، زمان به تفکیکِ تب
/// (مسیر: '/words'، '/slang'، '/conversations' …) هم نگه داشته می‌شود.
@immutable
class ListenDay {
  final int yt;
  final int audio;
  final int tts;

  /// مسیرِ تب → ثانیه (زیرمجموعه‌ی [tts]؛ دیتای قدیمی خالی است)
  final Map<String, int> tabs;

  /// مسیرِ تب → آخرین جمله‌ای که آن روز در آن تب خوانده شد
  final Map<String, ListenPoint> last;

  /// مسیرِ تب → چیزهایی که آن روز در آن تب خوانده شد (به تفکیکِ موضوع/سناریو/داستان)
  final Map<String, List<ReadCtx>> reads;

  const ListenDay({
    this.yt = 0,
    this.audio = 0,
    this.tts = 0,
    this.tabs = const {},
    this.last = const {},
    this.reads = const {},
  });

  int get total => yt + audio + tts;

  ListenDay plus(ListenSource s, int sec) => ListenDay(
        yt: yt + (s == ListenSource.yt ? sec : 0),
        audio: audio + (s == ListenSource.audio ? sec : 0),
        tts: tts + (s == ListenSource.tts ? sec : 0),
        tabs: tabs,
        last: last,
        reads: reads,
      );

  /// ثبتِ یک آیتمِ خوانده‌شده در تبِ [route] (در همان موضوع/سناریو/داستان).
  ListenDay withRead(String route, Map<String, Object> extra, String id) {
    final list = List<ReadCtx>.of(reads[route] ?? const <ReadCtx>[]);
    final i = list.indexWhere((c) => ReadCtx.sameExtra(c.extra, extra));
    if (i < 0) {
      list.add(ReadCtx(extra, [id]));
      if (list.length > 12) list.removeAt(0);
    } else {
      final c = list[i];
      if (c.ids.contains(id)) return this;
      final ids = [...c.ids, id];
      if (ids.length > ReadCtx.maxIds) ids.removeAt(0);
      list.removeAt(i);
      list.add(ReadCtx(c.extra, ids));
    }
    return ListenDay(
      yt: yt,
      audio: audio,
      tts: tts,
      tabs: tabs,
      last: last,
      reads: {...reads, route: list},
    );
  }

  /// زمانِ پلیرِ برنامه که مالِ یک تبِ مشخص است.
  ListenDay plusTab(String route, int sec, ListenPoint? point) => ListenDay(
        yt: yt,
        audio: audio,
        tts: tts + sec,
        tabs: {...tabs, route: (tabs[route] ?? 0) + sec},
        last: point == null ? last : {...last, route: point},
        reads: reads,
      );

  Map<String, dynamic> toJson() => {
        'y': yt,
        'a': audio,
        't': tts,
        if (tabs.isNotEmpty) 'b': tabs,
        if (last.isNotEmpty) 'l': last.map((k, v) => MapEntry(k, v.toJson())),
        if (reads.isNotEmpty)
          'r': reads.map((k, v) => MapEntry(k, [for (final c in v) c.toJson()])),
      };

  factory ListenDay.fromJson(Map<dynamic, dynamic> j) {
    final tabs = <String, int>{};
    final b = j['b'];
    if (b is Map) {
      b.forEach((k, v) {
        if (v is num) tabs[k.toString()] = v.toInt();
      });
    }
    final last = <String, ListenPoint>{};
    final l = j['l'];
    if (l is Map) {
      l.forEach((k, v) {
        if (v is Map) last[k.toString()] = ListenPoint.fromJson(v);
      });
    }
    final reads = <String, List<ReadCtx>>{};
    final r = j['r'];
    if (r is Map) {
      r.forEach((k, v) {
        if (v is List) {
          reads[k.toString()] = [
            for (final e in v)
              if (e is Map) ReadCtx.fromJson(e),
          ];
        }
      });
    }
    return ListenDay(
      yt: (j['y'] as num?)?.toInt() ?? 0,
      audio: (j['a'] as num?)?.toInt() ?? 0,
      tts: (j['t'] as num?)?.toInt() ?? 0,
      tabs: tabs,
      last: last,
      reads: reads,
    );
  }
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
  ListeningTracker(this._storage, {this.ttsContext})
      : super(ListenStats.fromJson(_storage.readJson(_kListenKey))) {
    _pending = Map<String, ListenDay>.from(state.days);
    WidgetsBinding.instance.addObserver(this);
    _last = DateTime.now();
    _timer = Timer.periodic(_tick, (_) => unawaited(_onTick()));
  }

  static const Duration _tick = Duration(seconds: 3);

  final LocalStorage _storage;

  /// پلیرِ برنامه الان مالِ کدام تب/جمله است؟ (null = نامشخص)
  final ({String route, ListenPoint? point})? Function()? ttsContext;
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
          final cur = _pending[k] ?? const ListenDay();
          ({String route, ListenPoint? point})? ctx;
          if (src == ListenSource.tts) {
            try {
              ctx = ttsContext?.call();
            } catch (_) {}
          }
          _pending[k] = ctx == null
              ? cur.plus(src, sec)
              : cur.plusTab(ctx.route, sec, ctx.point);
          _dirty = true;
        }
      }
      if (_dirty && now.difference(_lastFlush).inSeconds >= 10) _flush();
    } finally {
      _busy = false;
    }
  }

  /// 📖 یک آیتم (جمله/لغت) در تبِ [route] با پلیر خوانده شد.
  void noteRead(String route, Map<String, Object> extra, String id) {
    if (!mounted) return;
    final k = ListenStats.keyOf(DateTime.now());
    final cur = _pending[k] ?? const ListenDay();
    final next = cur.withRead(route, extra, id);
    if (identical(next, cur)) return;
    _pending[k] = next;
    _dirty = true;
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
  // کلیدهای متنی که برای مبدأِ فعلی دیده شده‌اند (متنِ اصلی، ترجمه‌ها…). اگر کاربر وسطِ پخش
  // تب را عوض کند، اسکوپِ تب‌ِ قبلی دیگر «فعال» نیست؛ ولی همین کلیدها هنوز مالِ همان تب‌اند.
  final originKeys = <String>{};
  String? originKeysFor;

  ({String route, ListenPoint? point})? ctxNow({bool withId = true}) {
    final sp = ref.read(speechControllerProvider);
    final o = ref.read(playbackOriginProvider);
    if (o == null || sp.key == null) return null;
    if (originKeysFor != o.key) {
      originKeys.clear();
      originKeysFor = o.key;
    }
    final inScope = o.key == sp.key ||
        ref.read(playerSyncProvider).tracks.values.any((tr) => tr.key == sp.key);
    if (!inScope) {
      // هنوز همان پخش است (تب عوض شده) → ثانیه‌ها به تبِ مبدأ حساب شود، بدونِ آیتم
      if (originKeys.contains(sp.key)) return (route: o.route, point: null);
      // 🌐 خوانشِ ترجمه (زبانِ مبدأ/مقصد) ادامه‌ی همان پخش است → مالِ همان تب
      // (قبلاً چون این کلید جزو تراک‌ها نبود، به‌اشتباه در «پلیر برنامه (سایر)» می‌رفت)
      if (sp.key == SpeechController.translationReadKey) {
        originKeys.add(sp.key!);
        return (route: o.route, point: null);
      }
      return null;
    }
    originKeys.add(sp.key!);
    final id = withId ? ref.read(activeSyncProvider)?.id : null;
    final extra = <String, Object>{};
    o.extra.forEach((k, v) {
      if (v is String || v is num || v is bool) extra[k] = v as Object;
    });
    return (route: o.route, point: id == null ? null : ListenPoint(id, extra));
  }

  final t = ListeningTracker(
    ref.read(localStorageProvider),
    ttsContext: ctxNow,
  );
  // پلیرِ خودِ برنامه (TTS)
  ref.listen<SpeechStatus>(
    speechControllerProvider.select((s) => s.status),
    (_, st) =>
        ListenSignals.report('tts', ListenSource.tts, st == SpeechStatus.playing),
    fireImmediately: true,
  );
  // 📖 هر جمله/لغتی که پلیر به آن می‌رسد ثبت می‌شود (نه فقط هر ۳ ثانیه)
  ref.listen<ActiveSync?>(activeSyncProvider, (_, a) {
    try {
      if (a == null) return;
      if (ref.read(speechControllerProvider).status != SpeechStatus.playing) {
        return;
      }
      final c = ctxNow();
      final pt = c?.point;
      if (c == null || pt == null || pt.id == null) return;
      t.noteRead(c.route, pt.extra, pt.id!);
    } catch (_) {}
  });
  return t;
});
