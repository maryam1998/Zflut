import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/app_prefs_provider.dart';
import '../providers/speech_provider.dart';
import '../theme/app_theme_colors.dart';
import '../tts/speech_controller.dart' show SpeechController;
import '../tts/speech_state.dart';
import 'examples_registry.dart';
import 'playback_origin.dart';
import 'player_sync_provider.dart';
import 'player_track.dart';

// ═══════════════════════════════════════════════════════════════════
// رنگ هایلایت — معادل highlightBg در theme.js
// ═══════════════════════════════════════════════════════════════════
const Color kReadMarkerColor = Color(0xFFFFD54F);

/// null = هایلایت خاموش ('none')
Color? syncHighlightColor(String pref) {
  if (pref == 'none') return null;
  final m = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(pref.trim());
  if (m == null) return kReadMarkerColor;
  return Color(int.parse('FF${m.group(1)}', radix: 16));
}

// ═══════════════════════════════════════════════════════════════════
// اسکوپ: همه‌ی تب‌ها (لغات، علاقه‌مندی، اسلنگ، Vocab in Use، مکالمات،
// داستان، ...) فقط همین یک ویجت را دور محتوایشان می‌گذارند.
// ═══════════════════════════════════════════════════════════════════
class _ScopeToken extends InheritedWidget {
  final String scopeId;
  const _ScopeToken({required this.scopeId, required super.child});

  static String? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ScopeToken>()?.scopeId;

  @override
  bool updateShouldNotify(_ScopeToken old) => old.scopeId != scopeId;
}

/// شناسه‌ی اسکوپِ بالاتر (برای گزارشِ ترجمه‌ها) — null اگر اسکوپی نیست.
String? syncScopeOf(BuildContext context) => _ScopeToken.maybeOf(context);

class SyncPlayScope extends ConsumerStatefulWidget {
  /// تا وقتی همین شیء (identical / ==) بماند، آیتم‌ها دوباره ساخته نمی‌شوند.
  final Object revision;
  final List<SyncItem> Function() itemsBuilder;
  final TrackMode mode;

  /// زبانِ متنِ اصلی (پیش‌فرض 'en'؛ داستان زبانِ خودش را می‌دهد)
  final String mainCode;

  final Widget child;

  /// حالتِ درونیِ تب که برای برگشتن به همین متن لازم است (مثلاً موضوع/سناریو
  /// یا شناسه‌ی داستان). با لمسِ طولانیِ دکمه‌ی پخش به تب برمی‌گردد.
  final Map<String, Object?> originExtra;

  /// 🎭 اختیاری: شناسه‌ی صدای خواندنِ هر آیتم (مثلاً مکالمه: گوینده‌ی A و B صدای جدا).
  /// null برگرداند = صدای معمولیِ تنظیمات.
  final String? Function(String itemId)? voiceForItem;

  const SyncPlayScope({
    super.key,
    required this.revision,
    required this.itemsBuilder,
    required this.mode,
    required this.child,
    this.mainCode = 'en',
    this.originExtra = const {},
    this.voiceForItem,
  });

  @override
  ConsumerState<SyncPlayScope> createState() => _SyncPlayScopeState();
}

class _SyncPlayScopeState extends ConsumerState<SyncPlayScope> {
  late final String _scopeId = 'scope_${identityHashCode(this)}';
  late final PlayerSyncNotifier _notifier;
  Object? _registeredRevision;
  TrackMode? _registeredMode;
  String? _registeredMain;
  Map<String, int> _indexById = const {};
  int _count = 0;
  ActiveSync? _lastActive;
  int _scrollToken = 0;

  late final SpeechController _ctrl;
  // بعد از تمام شدنِ مثال‌ها، پخشِ لیست از این آیتم ادامه می‌یابد
  String? _resumeSpanId;
  bool _resumeFromHook = false;

  @override
  void initState() {
    super.initState();
    _notifier = ref.read(playerSyncProvider.notifier);
    _ctrl = ref.read(speechControllerProvider.notifier);
    _ctrl.addChunkAdvanceHook(_chunkHook);
    _ctrl.addChunkVoiceResolver(_voiceResolver);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _register();
      // برگشت به تب وسطِ پخش (remount) → همان لحظه به خطِ در حال پخش برو
      _onActive(ref.read(activeSyncProvider));
    });
  }

  @override
  void didUpdateWidget(covariant SyncPlayScope old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _register();
    });
  }

  void _register() {
    if (_registeredRevision != null &&
        identical(_registeredRevision, widget.revision) &&
        _registeredMode == widget.mode &&
        _registeredMain == widget.mainCode) {
      return;
    }
    final items = widget.itemsBuilder();
    _registeredRevision = widget.revision;
    _registeredMode = widget.mode;
    _registeredMain = widget.mainCode;
    _count = items.length;
    _indexById = {for (var i = 0; i < items.length; i++) items[i].id: i};
    _notifier.setScope(_scopeId, items, widget.mode,
        mainCode: widget.mainCode);
  }

  @override
  void dispose() {
    _ctrl.removeChunkAdvanceHook(_chunkHook);
    _ctrl.removeChunkVoiceResolver(_voiceResolver);
    final n = _notifier;
    final id = _scopeId;
    Future.microtask(() {
      if (n.mounted) n.clearScope(id);
    });
    super.dispose();
  }

  /// 🎭 صدای جمله‌ی در حال خواندن (فقط وقتی متنِ پخش‌شده مالِ همین اسکوپ است).
  String? _voiceResolver(String? key, int start) {
    final vf = widget.voiceForItem;
    if (vf == null || !mounted) return null;
    final sync = ref.read(playerSyncProvider);
    if (sync.scopeId != _scopeId) return null;
    final track = sync.tracks[sync.mainCode];
    if (track == null || track.key != key) return null;
    final sp = track.spanAt(start);
    return sp == null ? null : vf(sp.id);
  }

  /// ثبتِ «پخش از کجاست»: وقتی متنِ پخش‌شده مالِ همین اسکوپ است.
  void _recordOrigin() {
    if (!mounted) return;
    final sp = ref.read(speechControllerProvider);
    final key = sp.key;
    if (key == null || sp.status == SpeechStatus.idle) return;
    final sync = ref.read(playerSyncProvider);
    if (sync.scopeId != _scopeId) return;
    if (!sync.tracks.values.any((t) => t.key == key)) return;
    String route;
    try {
      route = GoRouter.of(context).routeInformationProvider.value.uri.path;
    } catch (_) {
      return;
    }
    ref.read(playbackOriginProvider.notifier).state =
        PlaybackOrigin(route, key, widget.originExtra);
  }

  // ───────────── لغت ← مثال‌هایش ← لغتِ بعد ─────────────
  TrackSpan? _spanAt(PlayerTrack t, int offset) {
    for (var i = t.spans.length - 1; i >= 0; i--) {
      if (offset >= t.spans[i].start) return t.spans[i];
    }
    return null;
  }

  void _playExample(String code, String text) {
    ref.read(adhocSyncProvider.notifier).state = (
      key: PlayerTrack.keyFor(code, text),
      active: ActiveSync(code, 'ai-ex-$code-${text.hashCode}')
    );
    unawaited(_ctrl.toggle(text, code));
  }

  /// پایانِ طبیعیِ خواندنِ یک لغت در پلیرِ لیست: اگر مثال‌های بازِ این لغت
  /// هست، به‌جای رفتن به لغتِ بعد اول مثال‌ها خوانده می‌شود.
  bool _chunkHook(String? key, int thisStart, int nextStart, bool loops) {
    if (!mounted) return false;
    final sync = ref.read(playerSyncProvider);
    if (sync.scopeId != _scopeId) return false;
    final track = sync.tracks[sync.mainCode];
    if (track == null || track.key != key || track.spans.isEmpty) return false;
    final cur = _spanAt(track, thisStart);
    if (cur == null) return false;
    final nxt = nextStart >= 0 ? _spanAt(track, nextStart) : null;
    if (nxt != null && nxt.id == cur.id) return false; // هنوز همین آیتم
    final word = _notifier.itemText(cur.id);
    if (word == null) return false;
    final texts = ExamplesRegistry.textsFor(track.code, word);
    if (texts == null || texts.isEmpty) return false;
    _resumeFromHook = true;
    _resumeSpanId =
        nxt != null ? nxt.id : (loops ? track.spans.first.id : null);
    _playExample(track.code, texts.first);
    return true;
  }

  String? _nextSpanAfterWord(PlayerTrack track, String word) {
    final w = word.trim().toLowerCase();
    for (var i = 0; i < track.spans.length; i++) {
      final t = _notifier.itemText(track.spans[i].id);
      if (t != null && t.trim().toLowerCase() == w) {
        return track.spans[(i + 1) % track.spans.length].id;
      }
    }
    return null;
  }

  void _onSpeech(SpeechState? prev, SpeechState next) {
    final sync = ref.read(playerSyncProvider);
    if (sync.scopeId != _scopeId) return;
    if (next.key == null) {
      _resumeSpanId = null;
      _resumeFromHook = false;
      return;
    }
    final ad = ref.read(adhocSyncProvider);
    final isExample = ad != null && ad.key == next.key;

    if (prev?.key != next.key) {
      if (!isExample) {
        _resumeSpanId = null;
        _resumeFromHook = false;
      } else if (!_resumeFromHook) {
        // مثالی که کاربر خودش زد: بعد از مثال‌های همان لغت، لغتِ بعدی
        final o = ExamplesRegistry.ownerOfKey(next.key!);
        final track = sync.tracks[sync.mainCode];
        _resumeSpanId = (o == null || track == null)
            ? null
            : _nextSpanAfterWord(track, o.word);
      }
    }

    // پایانِ طبیعیِ آخرین مثال → ادامه‌ی لیست از لغتِ بعد
    if (isExample &&
        _resumeSpanId != null &&
        prev != null &&
        prev.status == SpeechStatus.playing &&
        next.status == SpeechStatus.idle &&
        prev.key == next.key &&
        next.error == null) {
      final o = ExamplesRegistry.ownerOfKey(next.key!);
      if (o != null && o.index + 1 < o.count) return; // پنل مثالِ بعدی را می‌خواند
      _resumeMain();
    }
  }

  void _resumeMain() {
    final id = _resumeSpanId;
    _resumeSpanId = null;
    _resumeFromHook = false;
    if (id == null) return;
    final sync = ref.read(playerSyncProvider);
    final track = sync.tracks[sync.mainCode];
    final span = track?.byId[id];
    if (track == null || span == null) return;
    unawaited(_ctrl.toggle(
      track.fullText,
      track.code,
      startCharOffset: span.start,
      loop: true,
      sentenceBoundaries: track.boundaries,
    ));
  }

  // ───────────────────────── اسکرول خودکار ─────────────────────────
  void _onActive(ActiveSync? a) {
    _lastActive = a;
    if (a == null) return;
    _scrollToken++;
    _scrollTo(a, _scrollToken, 0);
  }

  void _scrollTo(ActiveSync a, int token, int attempt) {
    if (!mounted || token != _scrollToken || _lastActive != a) return;

    final anchor = SyncAnchorRegistry.find(a.code, a.id);
    if (anchor != null) {
      _reveal(anchor);
      return;
    }

    // آیتم هنوز ساخته نشده (ListView.builder) → نزدیکش می‌پریم، بعد دقیق.
    // به‌جای کنترلرِ جدا (که NestedScrollViewِ هدر را خراب می‌کرد)، موقعیتِ
    // اسکرول را از یکی از آیتم‌های همین لحظه ساخته‌شده می‌گیریم.
    final idx = _indexById[a.id];
    if (idx == null || attempt >= 8) return;

    var refCode = a.code;
    var ids = SyncAnchorRegistry.mountedIds(refCode).toList();
    if (ids.isEmpty) {
      refCode = widget.mainCode;
      ids = SyncAnchorRegistry.mountedIds(refCode).toList();
    }
    if (ids.isEmpty) return;
    final refCtx = SyncAnchorRegistry.find(refCode, ids.first);
    final scrollable = refCtx == null ? null : Scrollable.maybeOf(refCtx);
    if (scrollable == null) return;
    final pos = scrollable.position;

    double target;
    if (attempt == 0) {
      final avg =
          (pos.maxScrollExtent + pos.viewportDimension) / math.max(1, _count);
      target = idx * avg;
    } else {
      final builtIdx =
          ids.map((id) => _indexById[id]).whereType<int>().toList();
      if (builtIdx.isEmpty) {
        target = pos.pixels;
      } else {
        final lo = builtIdx.reduce(math.min);
        final hi = builtIdx.reduce(math.max);
        final step = pos.viewportDimension * 0.8;
        if (idx < lo) {
          target = pos.pixels - step;
        } else if (idx > hi) {
          target = pos.pixels + step;
        } else {
          target = pos.pixels;
        }
      }
    }
    pos.jumpTo(target.clamp(pos.minScrollExtent, pos.maxScrollExtent));
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollTo(a, token, attempt + 1));
  }

  /// scrollIntoView({behavior:"smooth", block:"center"})
  void _reveal(BuildContext ctx) {
    final ro = ctx.findRenderObject();
    if (ro == null || !ro.attached) return;
    final scrollable = Scrollable.maybeOf(ctx);
    final viewport = RenderAbstractViewport.maybeOf(ro);
    if (scrollable == null || viewport == null) return;
    final pos = scrollable.position;
    final off = viewport
        .getOffsetToReveal(ro, 0.5)
        .offset
        .clamp(pos.minScrollExtent, pos.maxScrollExtent);
    if ((off - pos.pixels).abs() < 1) return;
    pos.animateTo(
      off,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ActiveSync?>(activeSyncProvider, (prev, next) {
      if (prev != next) _onActive(next);
    });
    // پخش از این اسکوپ شروع شد/متنش عوض شد → مبدأ را ثبت کن
    ref.listen<({String? key, bool active})>(
        speechControllerProvider.select(
            (s) => (key: s.key, active: s.status != SpeechStatus.idle)),
        (prev, next) {
      if (next.active && next.key != null) _recordOrigin();
    });
    ref.listen<SpeechState>(speechControllerProvider, _onSpeech);
    // لمسِ طولانیِ دکمه‌ی پخش: دوباره به خطِ در حال پخش اسکرول کن
    ref.listen<int>(revealActiveTickProvider, (prev, next) {
      if (prev != next) _onActive(ref.read(activeSyncProvider));
    });
    return _ScopeToken(scopeId: _scopeId, child: widget.child);
  }
}

// ═══════════════════════════════════════════════════════════════════
// لنگر (anchor): ردیف/کارتی که اسکرول خودکار باید به آن برسد
// ═══════════════════════════════════════════════════════════════════
class SyncAnchorRegistry {
  static final Map<String, Map<String, _SyncAnchorState>> _byCode = {};

  static BuildContext? find(String code, String id) {
    final s = _byCode[code]?[id];
    return (s != null && s.mounted) ? s.context : null;
  }

  static Iterable<String> mountedIds(String code) =>
      _byCode[code]?.keys ?? const [];

  static void _add(String code, String id, _SyncAnchorState s) =>
      (_byCode[code] ??= {})[id] = s;

  static void _remove(String code, String id, _SyncAnchorState s) {
    final m = _byCode[code];
    if (m != null && identical(m[id], s)) m.remove(id);
  }
}

class SyncAnchor extends StatefulWidget {
  final String code;
  final String id;
  final Widget child;
  const SyncAnchor(
      {super.key, required this.code, required this.id, required this.child});

  @override
  State<SyncAnchor> createState() => _SyncAnchorState();
}

class _SyncAnchorState extends State<SyncAnchor> {
  @override
  void initState() {
    super.initState();
    SyncAnchorRegistry._add(widget.code, widget.id, this);
  }

  @override
  void didUpdateWidget(covariant SyncAnchor old) {
    super.didUpdateWidget(old);
    if (old.code != widget.code || old.id != widget.id) {
      SyncAnchorRegistry._remove(old.code, old.id, this);
      SyncAnchorRegistry._add(widget.code, widget.id, this);
    }
  }

  @override
  void dispose() {
    SyncAnchorRegistry._remove(widget.code, widget.id, this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ═══════════════════════════════════════════════════════════════════
// متنِ هایلایت‌شونده — مارکرِ تنگِ دورِ خودِ متن (نه کلِ ردیف)،
// با چند خطی شدن هم درست می‌ماند (box-decoration-break: clone)
// ═══════════════════════════════════════════════════════════════════
class SyncText extends ConsumerWidget {
  final String code;
  final String id;
  final String text;
  final TextStyle style;
  final TextDirection? textDirection;
  final TextAlign? textAlign;
  final Duration duration;

  const SyncText({
    super.key,
    required this.code,
    required this.id,
    required this.text,
    required this.style,
    this.textDirection,
    this.textAlign,
    this.duration = const Duration(milliseconds: 350),
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeSyncProvider
        .select((a) => a != null && a.code == code && a.id == id));
    final pref = ref.watch(appPrefsProvider.select((p) => p.highlightColor));
    final hl = syncHighlightColor(pref);

    final Color target = (hl != null && active)
        ? hl
        : (hl ?? kReadMarkerColor).withOpacity(0);

    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: target),
      duration: duration,
      builder: (_, bg, __) => Text(
        text,
        textDirection: textDirection,
        textAlign: textAlign,
        style: style.copyWith(backgroundColor: bg),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// دکمه‌ی 🔊 مشترک — معادل SpeakButton.jsx با fullText + startOffset:
// کلیک روی هر آیتم، وسطِ پخشِ «کلِ متن» همان‌جا می‌پرد.
// ═══════════════════════════════════════════════════════════════════
class SyncSpeakButton extends ConsumerWidget {
  final String code;
  final String id;

  /// متنِ همین آیتم — فقط وقتی اسکوپ/متنِ کاملی ثبت نشده، تکی خوانده می‌شود
  final String text;
  final Color? color;
  final double size;
  final EdgeInsets padding;

  const SyncSpeakButton({
    super.key,
    required this.code,
    required this.id,
    required this.text,
    this.color,
    this.size = 20,
    this.padding = const EdgeInsets.all(4),
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final track = ref.watch(playerSyncProvider.select((s) => s.tracks[code]));

    // مثل Hope: isActive = «همین متنِ کامل» پخش/مکث است؛ isPlaying = در حال پخش
    final mode = ref.watch(speechControllerProvider.select((s) {
      if (track == null || s.key != track.key) return 0;
      if (s.status == SpeechStatus.playing) return 2;
      if (s.status == SpeechStatus.paused) return 1;
      return 0;
    }));
    final isPlaying = mode == 2;

    return InkWell(
      onTap: () => syncSpeak(ref, code, id, text),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: padding,
        child: Icon(
          isPlaying ? Icons.pause : Icons.volume_up_outlined,
          size: size,
          color: color ?? c.gold,
        ),
      ),
    );
  }
}

/// منطقِ کلیکِ دکمه‌ی 🔊 (handleToggle با fullText در Hope)
Future<void> syncSpeak(WidgetRef ref, String code, String id, String text) async {
  final ctrl = ref.read(speechControllerProvider.notifier);
  final st = ref.read(speechControllerProvider);
  final track = ref.read(playerSyncProvider).tracks[code];
  final span = track?.byId[id];

  if (track == null || span == null) {
    await ctrl.toggle(text, code);
    return;
  }

  if (st.key == track.key && st.status != SpeechStatus.idle) {
    final idx = ctrl.chunkIndexForOffset(span.start);
    if (idx == st.chunkIndex) {
      await ctrl.toggle(track.fullText, code); // همان جمله → پاز/ادامه
    } else {
      await ctrl.seekToChunk(idx); // جمله‌ی دیگر → پرش
    }
    return;
  }

  // «کلِ متن را از همین‌جا بخوان» — همیشه loop، مثلِ پلیرِ مرکزی
  await ctrl.toggle(
    track.fullText,
    code,
    startCharOffset: span.start,
    loop: true,
    sentenceBoundaries: track.boundaries,
  );
}

/// 🔊 برای متن‌هایی که جزو لیستِ اسکوپ نیستند (مثال‌های AI و ترجمه‌هایشان):
/// پخشِ تکی، ولی با همان هایلایت و اسکرولِ خودکارِ پلیر.
Future<void> syncSpeakAdhoc(
    WidgetRef ref, String code, String id, String text) async {
  ref.read(adhocSyncProvider.notifier).state =
      (key: PlayerTrack.keyFor(code, text), active: ActiveSync(code, id));
  await ref.read(speechControllerProvider.notifier).toggle(text, code);
}

/// دکمه‌ی مرکزیِ پلیرِ پایین وقتی چیزی پخش نمی‌شود: کلِ متنِ تبِ فعلی
/// را از اول می‌خواند (onFullTextChange → دکمه‌ی پخش در Hope).
Future<bool> syncPlayMainTrack(WidgetRef ref) async {
  final sync = ref.read(playerSyncProvider);
  var track = sync.tracks[sync.mainCode];
  if (track == null || track.fullText.isEmpty) {
    // تراکِ اصلی خالی است (مثلاً فهرست فقط لغاتِ غیرانگلیسی دارد) → اولین
    // تراکِ دارای متن
    track = null;
    for (final t in sync.tracks.values) {
      if (t.fullText.isNotEmpty) {
        track = t;
        break;
      }
    }
    if (track == null) return false;
  }
  await ref.read(speechControllerProvider.notifier).toggle(
        track.fullText,
        track.code,
        loop: true,
        sentenceBoundaries: track.boundaries,
      );
  return true;
}

/// دکمه‌ی پخش/توقفِ مرکزیِ پلیر — همیشه کاری می‌کند:
///  • چیزی پخش/مکث است → پخش/توقف
///  • بیکار است و آخرین متنِ خوانده‌شده هنوز مالِ همین صفحه است → دوباره از اول
///  • وگرنه → کلِ متنِ صفحه‌ی فعلی از اول
/// false = در این صفحه متنی برای خواندن نیست.
Future<bool> syncPlayPause(WidgetRef ref) async {
  final st = ref.read(speechControllerProvider);
  final ctrl = ref.read(speechControllerProvider.notifier);
  final tracks = ref.read(playerSyncProvider).tracks;
  final hasPageText = tracks.values.any((t) => t.fullText.isNotEmpty);

  final ad = ref.read(adhocSyncProvider);
  final adhocHere = ad != null && ad.key == st.key;
  if (st.key != null && st.status != SpeechStatus.idle) {
    // متنِ در حال پخش/مکث مالِ همین صفحه است (یا این صفحه متنی ندارد) → پخش/توقف
    if (!hasPageText || adhocHere || tracks.values.any((t) => t.key == st.key)) {
      await ctrl.togglePlayPause();
      return true;
    }
    // متنِ صفحه‌ی قبلی هنوز در پلیر است → متنِ همین صفحه از اول خوانده شود
    return syncPlayMainTrack(ref);
  }

  final key = st.key;
  if (key != null) {
    final stillHere = tracks.values.any((t) => t.key == key);
    if (stillHere) {
      await ctrl.togglePlayPause();
      return true;
    }
  }
  return syncPlayMainTrack(ref);
}

/// ردیف‌های ترجمه این را صدا می‌زنند تا متنِ کاملِ ترجمه ساخته شود.
void syncReportTranslation(
    BuildContext context, WidgetRef ref, String code, String id, String text) {
  final scopeId = syncScopeOf(context);
  if (scopeId == null || text.trim().isEmpty) return;
  final notifier = ref.read(playerSyncProvider.notifier);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (notifier.mounted) notifier.reportTranslation(scopeId, code, id, text);
  });
}
