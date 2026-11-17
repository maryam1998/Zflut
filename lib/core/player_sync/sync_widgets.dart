import 'dart:async' show Completer, Timer, unawaited;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/app_prefs_provider.dart';
import '../providers/language_selection_provider.dart';
import '../storage/local_storage.dart' show sharedPrefsProvider;
import '../providers/speech_provider.dart';
import '../theme/app_theme_colors.dart';
import '../providers/ai_settings_provider.dart';
import '../providers/translation_provider.dart';
import '../translate/known_translations.dart';
import '../ai/word_examples.dart' show wordExamplesStoreProvider;
import '../tts/native_tts_bridge.dart';
import '../tts/sentence_splitter.dart';
import '../tts/speech_controller.dart' show SpeechController;
import '../tts/speech_state.dart';
import 'examples_registry.dart';
import 'playback_origin.dart';
import 'player_sync_provider.dart';
import 'player_track.dart';
import '../../features/shell/widgets/spotlight_tour.dart' show SpotlightTour;

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

/// آخرین لحظه‌ای که برنامه واقعاً فریم کشیده است. وقتی روی صفحه هستی (نوارِ پیشرفتِ پلیر
/// و هایلایت مدام فریم می‌سازند) فریم‌ها می‌آیند؛ در پس‌زمینه/قفل‌صفحه فریمی نیست. این
/// معیار از «حالتِ چرخه‌ی عمرِ» اندروید که روی بعضی گوشی‌ها اشتباه گزارش می‌شود مستقل است.
class _FrameWatch {
  static DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  static bool _on = false;

  static void ensure() {
    if (_on) return;
    _on = true;
    SchedulerBinding.instance.addPersistentFrameCallback((_) {
      _last = DateTime.now();
    });
  }

  static bool get recent =>
      DateTime.now().difference(_last) < const Duration(seconds: 12);
}

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

  /// 🎭 اختیاری: صدای خواندنِ «ترجمه»‌ی هر آیتم به یک زبان (مثلاً مکالمه: گوینده‌ی A و B در هر زبان صدای جدا).
  final String? Function(String itemId, String lang)? voiceForTrans;

  const SyncPlayScope({
    super.key,
    required this.revision,
    required this.itemsBuilder,
    required this.mode,
    required this.child,
    this.mainCode = 'en',
    this.originExtra = const {},
    this.voiceForItem,
    this.voiceForTrans,
  });

  @override
  ConsumerState<SyncPlayScope> createState() => _SyncPlayScopeState();
}

class _SyncPlayScopeState extends ConsumerState<SyncPlayScope> {
  late final String _scopeId = 'scope_${identityHashCode(this)}';
  static final Set<_SyncPlayScopeState> _live = <_SyncPlayScopeState>{};
  late final PlayerSyncNotifier _notifier;
  Object? _registeredRevision;
  TrackMode? _registeredMode;
  String? _registeredMain;
  Map<String, int> _indexById = const {};
  int _count = 0;
  ActiveSync? _lastActive;
  int _scrollToken = 0;

  late final SpeechController _ctrl;
  // کانتینرِ ریورپاد: بعد از dispose هم می‌شود ازش خواند (برای خوانشِ مستقل از تب)
  late final ProviderContainer _pc;
  // بعد از تمام شدنِ مثال‌ها، پخشِ لیست از این آیتم ادامه می‌یابد
  String? _resumeSpanId;
  bool _resumeFromHook = false;

  @override
  void initState() {
    super.initState();
    _FrameWatch.ensure();
    _live.add(this);
    _notifier = ref.read(playerSyncProvider.notifier);
    _ctrl = ref.read(speechControllerProvider.notifier);
    _pc = ProviderScope.containerOf(context, listen: false);
    _ctrl.addChunkAdvanceHook(_chunkHook);
    _ctrl.addChunkVoiceResolver(_voiceResolver);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _register();
      // برگشت به تب وسطِ پخش (remount) → همان لحظه به خطِ در حال پخش برو
      _onActive(ref.read(activeSyncProvider));
      // پرش به جمله‌ای که از نمودارِ زمانِ گوش‌دادن درخواست شده
      _tryRevealRequested();
    });
  }

  Timer? _revealTimer;

  /// 📍 پرش به آیتمِ درخواست‌شده (revealItemProvider). تب تازه باز شده و آیتم‌ها
  /// ممکن است چند فریم بعد ثبت شوند؛ پس چند بار تلاش می‌کند. اگر آیتم مالِ این
  /// اسکوپ نبود درخواست را پاک نمی‌کند.
  void _tryRevealRequested([int attempt = 0]) {
    _revealTimer?.cancel();
    if (!mounted) return;
    final id = ref.read(revealItemProvider);
    if (id == null) return;
    if (_indexById.containsKey(id)) {
      ref.read(revealItemProvider.notifier).state = null;
      final a = ActiveSync(widget.mainCode, id);
      _lastActive = a;
      _scrollToken++;
      _scrollTo(a, _scrollToken, 0);
      return;
    }
    if (attempt >= 14) return;
    _revealTimer = Timer(const Duration(milliseconds: 150),
        () => _tryRevealRequested(attempt + 1));
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

  /// 🔁 تب وسطِ «لغت ← ترجمه‌ها/مثال‌ها ← لغتِ بعد» ترک شد: این صف به خودِ تب بسته است و با
  /// بسته‌شدنش می‌مُرد؛ بعد از تمام شدنِ همان ترجمه/مثال هیچ‌چیز ادامه نمی‌یافت و خوانش قطع می‌شد.
  /// اینجا ادامه‌ی خوانشِ همان لیست (از آیتمِ بعد) به کنترلرِ صدا سپرده می‌شود.
  void _handOffReadingIfNeeded() {
    try {
      final id = _resumeSpanId;
      if (id == null || !(_bgActive || _resumeFromHook)) return;
      final track = _notifier.trackFor(_resumeCode);
      final span = track?.byId[id];
      if (track == null || span == null) return;
      // کلیدِ همه‌ی متن‌های همین اسکوپ: اگر موقعِ ترک، پلیر هنوز روی یکی از آن‌هاست ولی
      // صفِ ترجمه/مثال (که مالِ همین تب بود) دیگر زنده نیست، خوانش باید همان لحظه ادامه پیدا کند.
      final ownKeys = <String>{track.key};
      final mainTrack = _notifier.trackFor(null);
      if (mainTrack != null) ownKeys.add(mainTrack.key);
      _resumeAfterLeaving(_ctrl, track, span.start,
          ownKeys: ownKeys, eager: _bgActive);
    } catch (_) {}
  }

  /// 🔁 تب وسطِ خوانش ترک شد (مثلاً مکالمات ← لغات): صفِ «لغت ← ترجمه‌ها» به خودِ تب بسته بود و با
  /// بسته‌شدنش می‌مُرد؛ فقط متنِ اصلی ادامه می‌یافت و ترجمه‌ها دیگر خوانده نمی‌شدند تا کاربر به
  /// همان تب برگردد. اینجا یک «خوانشگرِ مستقل از تب» ساخته می‌شود که همان کار را ادامه می‌دهد
  /// (ترجمه‌ی هر آیتم به‌ترتیبِ زبان‌های هدر، با همان صدای گوینده/زبان). true = خوانشگر ساخته شد.
  bool _detachReading() {
    try {
      if (!(_readTransFg() || _readTransBg())) return false;
      final sync = ref.read(playerSyncProvider);
      if (sync.scopeId != _scopeId) return false;
      final main = sync.tracks[sync.mainCode];
      if (main == null || main.spans.isEmpty) return false;
      final sp = ref.read(speechControllerProvider);
      if (sp.key == null) return false;
      final inQueue = _bgActive;
      if (!inQueue && sp.status == SpeechStatus.idle) return false;
      final onMain = sp.key == main.key;
      if (!onMain && !inQueue) return false; // متنِ دیگری (مثلاً ردیفِ ترجمه) پخش می‌شود
      // صفِ «ترجمه‌ی ترک»(▶ روی ردیفِ ترجمه) مالِ همین تب است؛ همان رفتارِ قبلی
      if (inQueue && _resumeCode != null && _resumeCode != main.code) return false;

      final texts = <String, String>{};
      final foreign = <String>{};
      for (final s in main.spans) {
        final t = _notifier.itemText(s.id);
        if (t != null) texts[s.id] = t;
        if (_notifier.isForeignItem(s.id)) foreign.add(s.id);
      }
      final sel = ref.read(languageSelectionProvider);
      final allLangs = <String>{
        for (final c in [sel.native, ...sel.targets])
          if (c.trim().isNotEmpty && c.trim().toLowerCase() != main.code)
            c.trim().toLowerCase(),
      };
      final ready = <String, Map<String, String>>{};
      for (final s in main.spans) {
        for (final l in allLangs) {
          final tr = _notifier.translationFor(s.id, l);
          if (tr != null) (ready[s.id] ??= <String, String>{})[l] = tr;
        }
      }

      final reader = _DetachedReader(
        container: _pc,
        ctrl: _ctrl,
        main: main,
        scopeId: _scopeId,
        texts: texts,
        foreign: foreign,
        ready: ready,
        voiceForItem: widget.voiceForItem,
        voiceForTrans: widget.voiceForTrans,
      )..attach();

      if (inQueue) {
        // آیتمِ در حال خواندن = آیتمِ قبل از «آیتمِ بعد» (resume)؛ اگر بعدی نیست = آخرین آیتم
        final spans = main.spans;
        final rid = _resumeSpanId;
        var ci = spans.length - 1;
        if (rid != null) {
          final ri = spans.indexWhere((x) => x.id == rid);
          if (ri >= 0) ci = (ri - 1 + spans.length) % spans.length;
        }
        final stepIsTrans = _bgKey != null && _bgKey == _trVoiceKey;
        final stepIsOther = _bgKey != null && _bgKey != _trVoiceKey; // مثال: بقیه‌ی مرحله‌ها رد می‌شوند
        unawaited(reader.runItem(
          spans[ci].id,
          rid,
          pendingKey: _bgKey,
          afterLang: stepIsTrans ? _trVoiceLang : null,
          skipLangs: stepIsOther,
        ));
      }
      return true;
    } catch (e) {
      debugPrint('detachReading error: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _live.remove(this);
    _revealTimer?.cancel();
    // 🔁 اگر «خواندن ترجمه‌ها» روشن است، خوانش بعد از ترکِ تب هم با ترجمه‌ها و همان صداها ادامه پیدا می‌کند
    final detached = _detachReading();
    if (!detached) _handOffReadingIfNeeded();
    _bgCancel();
    _ctrl.removeChunkAdvanceHook(_chunkHook);
    _ctrl.removeChunkVoiceResolver(_voiceResolver);
    if (detached) {
      _clearDetachedVoices(); // صدای ترجمه‌ها/گوینده‌ها را خودِ خوانشگرِ مستقل نگه می‌دارد
    } else {
      _keepVoicesAfterLeaving();
    }
    final n = _notifier;
    final id = _scopeId;
    Future.microtask(() {
      if (n.mounted) n.clearScope(id);
    });
    super.dispose();
  }

  // 🎭 صدای گوینده‌ها (مثلاً A مرد / B زن در مکالمه) بعد از ترکِ تب هم باید بماند.
  // resolverِ اصلی به خودِ تب بسته است و با dispose برداشته می‌شود؛ پخش ولی ادامه دارد و با صدای
  // پیش‌فرض می‌خواند. اینجا از جای هر جمله (در لحظه‌ی ترک) یک عکس برمی‌داریم و یک resolverِ مستقل
  // ثبت می‌کنیم؛ با پخشِ متنِ دیگر خودکار برداشته می‌شود.
  static String? Function(String?, int)? _detachedResolver;
  static void Function()? _detachedUnlisten;

  void _clearDetachedVoices() {
    final r = _detachedResolver;
    if (r != null) {
      try {
        _ctrl.removeChunkVoiceResolver(r);
      } catch (_) {}
    }
    _detachedResolver = null;
    try {
      _detachedUnlisten?.call();
    } catch (_) {}
    _detachedUnlisten = null;
  }

  void _keepVoicesAfterLeaving() {
    try {
      // ⚠️ اینجا دیگر resolverِ تبِ قبلی بی‌قیدوشرط پاک نمی‌شود: عبور از یک تبِ بی‌صدا (مثلاً لغات)
      // صدای گوینده‌های مکالمه‌ای را که هنوز در حال خواندن است عوض می‌کرد.
      final vf = widget.voiceForItem;
      final vt = widget.voiceForTrans;
      if (vf == null && vt == null) return;
      final playing = ref.read(speechControllerProvider);
      if (playing.key == null) return; // چیزی پخش نمی‌شود
      final st = ref.read(playerSyncProvider);
      if (st.scopeId != _scopeId) return;
      final mainCode = st.mainCode;
      final snap = <String, ({String code, List<TrackSpan> spans})>{};
      void add(PlayerTrack t) {
        snap[t.key] = (code: t.code, spans: List<TrackSpan>.of(t.spans));
      }

      st.tracks.values.forEach(add);
      st.legacy.forEach(add);
      final trKey = _trVoiceKey, trItem = _trVoiceItem, trLang = _trVoiceLang;
      if (trKey != null) snap.putIfAbsent(trKey, () => (code: '', spans: const <TrackSpan>[]));
      if (snap.isEmpty || !snap.containsKey(playing.key)) return;

      String? resolver(String? key, int start) {
        try {
          if (key == null) return null;
          if (vt != null &&
              key == trKey &&
              trItem != null &&
              trLang != null) {
            return vt(trItem, trLang);
          }
          final e = snap[key];
          if (e == null || e.spans.isEmpty) return null;
          TrackSpan? sp;
          for (var i = e.spans.length - 1; i >= 0; i--) {
            if (start >= e.spans[i].start) {
              sp = e.spans[i];
              break;
            }
          }
          sp ??= e.spans.first;
          if (e.code == mainCode) return vf?.call(sp.id);
          return vt?.call(sp.id, e.code);
        } catch (_) {
          return null;
        }
      }

      _clearDetachedVoices(); // فقط وقتی resolverِ تازه جایگزین می‌شود
      _detachedResolver = resolver;
      _ctrl.addChunkVoiceResolver(resolver);
      _detachedUnlisten = _ctrl.addListener((SpeechState s) {
        // متنِ دیگری (نه مالِ این اسکوپ) شروع شد → دیگر لازم نیست
        if (s.key != null && !snap.containsKey(s.key)) _clearDetachedVoices();
      });
    } catch (_) {}
  }

  /// 🎭 صدای جمله‌ی در حال خواندن (فقط وقتی متنِ پخش‌شده مالِ همین اسکوپ است).
  // 🎭 ترجمه‌ای که الان خوانده می‌شود: (کلیدِ متن، شناسه‌ی آیتم، زبان) — تا صدای ترجمه هم مثلِ متنِ اصلی عوض شود
  String? _trVoiceKey, _trVoiceItem, _trVoiceLang;

  String? _voiceResolver(String? key, int start) {
    final vf = widget.voiceForItem;
    final vt = widget.voiceForTrans;
    if ((vf == null && vt == null) || !mounted) return null;
    final sync = ref.read(playerSyncProvider);
    if (sync.scopeId != _scopeId) return null;
    if (vt != null &&
        key != null &&
        key == _trVoiceKey &&
        _trVoiceItem != null &&
        _trVoiceLang != null) {
      return vt(_trVoiceItem!, _trVoiceLang!);
    }
    if (vf == null) return null;
    final track = _notifier.mainTrackForKey(key);
    if (track == null) return null;
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

  // ───────────── 🔊 روی ترجمه (مثلاً اسپانیایی) ← ترجمه‌ی زبان مبدأ ← آیتمِ بعدیِ همان ترجمه ─────────────
  String? _resumeCode;

  /// پایانِ خواندنِ یک آیتم در «تراکِ ترجمه» (کاربر 🔊 ردیفِ ترجمه را زده): بعدش
  /// ترجمه‌ی همان آیتم به زبان مبدأ (مادری) خوانده می‌شود، چه داخل برنامه چه پس‌زمینه.
  bool _transChunkHook(String? key, int thisStart, int nextStart, bool loops) {
    if (key == null) return false;
    // فقط اگر تیکِ تنظیماتِ همان حالت روشن باشد: داخل برنامه ← «داخل برنامه»، پس‌زمینه ← «پس‌زمینه»
    if (_inBackground() ? !_readTransBg() : !_readTransFg()) return false;
    final sync = ref.read(playerSyncProvider);
    PlayerTrack? track;
    for (final t in sync.tracks.values) {
      if (t.key == key && t.code != sync.mainCode) track = t;
    }
    if (track == null || track.spans.isEmpty) return false;
    // 🌐 همه‌ی زبان‌های هدر (مبدأ + مقصدها) به‌ترتیب؛ نه فقط زبانِ مبدأ، و نه فقط زبانی که کاربر ▶ زده
    final langs = _transTrackLangs(track.code);
    if (langs.isEmpty) return false;

    int skipWs(int i) {
      final t = track!.fullText;
      while (i >= 0 && i < t.length && t.codeUnitAt(i) <= 32) {
        i++;
      }
      return i;
    }

    final cur = _spanAt(track, skipWs(thisStart));
    if (cur == null) return false;
    final nxt = nextStart >= 0 ? _spanAt(track, skipWs(nextStart)) : null;
    if (nxt != null && nxt.id == cur.id) return false; // هنوز همین آیتم

    _startTransTrackQueue(track, cur.id, langs,
        nxt != null ? nxt.id : (loops ? track.spans.first.id : null));
    return true;
  }

  /// زبان‌هایی که بعد از خواندنِ یک آیتمِ «تراکِ ترجمه» خوانده می‌شوند: مبدأ + همه‌ی مقصدهای هدر
  /// (به‌ترتیبِ هدر، بدون تکرار، بدون زبانِ خودِ همین ترک که همین الان خوانده شد).
  List<String> _transTrackLangs(String trackCode) {
    final sel = ref.read(languageSelectionProvider);
    final off = _bgOffLangs();
    final out = <String>[];
    for (final c in [
      if (!sel.targets.contains(sel.native)) sel.native,
      ...sel.targets,
    ]) {
      final t = c.trim().toLowerCase();
      if (t.isNotEmpty && t != trackCode && !out.contains(t) && !off.contains(t)) {
        out.add(t);
      }
    }
    return out;
  }

  void _startTransTrackQueue(PlayerTrack track, String id,
      List<String> langs, String? resumeId) {
    _bgCancel();
    _resumeFromHook = true;
    _resumeCode = track.code;
    _resumeSpanId = resumeId;
    final sync = ref.read(playerSyncProvider);
    final foreign = _notifier.isForeignItem(id);
    final steps = <_BgStep>[
      for (final l in langs)
        _BgStep(
          l,
          true,
          null,
          (!foreign && l == sync.mainCode)
              ? Future<String?>.value(_notifier.itemText(id)?.trim()) // متنِ اصلی
              : _translationText(
                  id, foreign ? track.code : sync.mainCode, l),
          (t) => id,
          retry: () => _translationText(
              id, foreign ? track.code : sync.mainCode, l,
              timeout: const Duration(seconds: 30)),
        ),
    ];
    _bgItemId = id;
    _bgTrackCode = track.code;
    _bgActive = true;
    ExamplesRegistry.bgDriving = true;
    final token = ++_bgToken;
    unawaited(_runBgQueue(steps, token, track.key));
  }

  void _playExample(String code, String text) {
    ref.read(adhocSyncProvider.notifier).state = (
      key: PlayerTrack.keyFor(code, text),
      active: ActiveSync(code, 'ai-ex-$code-${text.hashCode}')
    );
    unawaited(_ctrl.toggle(text, code));
  }

  /// مثال‌های یک لغت برای خوانش: اول مثال‌های بازِ روی صفحه، وگرنه مثال‌های ذخیره‌شده
  /// (هم داخل برنامه و هم پس‌زمینه، حتی اگر پنلِ مثال‌ها بسته باشد).
  List<String> _examplesOf(String word, String code) {
    final open = ExamplesRegistry.textsFor(code, word);
    if (open != null && open.isNotEmpty) return open;
    try {
      return [
        for (final e in ref.read(wordExamplesStoreProvider).load(word, code))
          if (e.text.trim().isNotEmpty) e.text,
      ];
    } catch (_) {
      return const <String>[];
    }
  }

  /// پایانِ طبیعیِ خواندنِ یک لغت در پلیرِ لیست: اگر مثال‌های بازِ این لغت
  /// هست، به‌جای رفتن به لغتِ بعد اول مثال‌ها خوانده می‌شود.
  bool _chunkHook(String? key, int thisStart, int nextStart, bool loops) {
    if (!mounted) return false;
    final sync = ref.read(playerSyncProvider);
    if (sync.scopeId != _scopeId) return false;
    final track = _notifier.mainTrackForKey(key);
    if (track == null) return _transChunkHook(key, thisStart, nextStart, loops);
    _resumeCode = null;
    if (track.spans.isEmpty) return false;
    // ⚠️ شروعِ تکه‌ها گاهی روی فاصله/خطِ جدیدِ «قبل از متن» می‌افتد و آیتمِ قبلی را نشان می‌دهد
    // (آن‌وقت جمله «هنوز همین آیتم» حساب می‌شد و ترجمه رد می‌شد) → فاصله‌ها را کنار بگذار.
    int skipWs(int i) {
      final t = track.fullText;
      while (i >= 0 && i < t.length && t.codeUnitAt(i) <= 32) {
        i++;
      }
      return i;
    }

    final cur = _spanAt(track, skipWs(thisStart));
    if (cur == null) return false;
    final nxt = nextStart >= 0 ? _spanAt(track, skipWs(nextStart)) : null;
    if (nxt != null && nxt.id == cur.id) return false; // هنوز همین آیتم
    final word = _notifier.itemText(cur.id);
    if (word == null) return false;
    if (_notifier.isForeignItem(cur.id)) return false; // ترجمه‌ی انگلیسیِ لغتِ زبانِ دیگر
    // مثال‌های باز؛ اگر پنلِ مثال بسته بود، مثال‌های ذخیره‌شده‌ی همین لغت
    final texts = ExamplesRegistry.textsFor(track.code, word); // فقط بازها
    final allTexts = _examplesOf(word, track.code);
    // 🌐 داخل برنامه (اگر در تنظیمات روشن باشد): ترجمه‌ی همه‌ی زبان‌های انتخاب‌شده
    final fgOn = _readTransFg() && !_inBackground();
    if (fgOn) {
      if (_startFgQueue(track, cur, nxt, loops, word, allTexts)) return true;
    }
    if (allTexts.isNotEmpty &&
        _startBgQueue(track, cur, nxt, loops, word, allTexts)) {
      return true;
    }
    if (texts == null || texts.isEmpty) {
      // 🌐 پس‌زمینه: ترجمه‌ی (آماده‌شده‌ی) این آیتم را هم بخوان — اگر در تنظیمات روشن باشد
      return _readTranslation(track, cur, nxt, loops);
    }
    _resumeFromHook = true;
    _resumeSpanId =
        nxt != null ? nxt.id : (loops ? track.spans.first.id : null);
    _playExample(track.code, texts.first);
    return true;
  }

  bool _readTransBg() {
    try {
      return ref.read(sharedPrefsProvider).getBool('zflut-read-trans-bg') ?? true;
    } catch (_) {
      return false;
    }
  }

  bool _readTransFg() {
    try {
      return ref.read(sharedPrefsProvider).getBool('zflut-read-trans-fg') ??
          true;
    } catch (_) {
      return false;
    }
  }

  /// زبان‌هایی که ترجمه‌شان خوانده می‌شود: مبدأ + همه‌ی مقصدها (بدون زبانِ خودِ متن، بدون تکرار)
  List<String> _fgLangs(String mainCode) {
    final sel = ref.read(languageSelectionProvider);
    final off = _bgOffLangs();
    final out = <String>[];
    for (final c in [if (!sel.targets.contains(sel.native)) sel.native, ...sel.targets]) {
      final t = c.trim().toLowerCase();
      if (t.isNotEmpty && t != mainCode && !out.contains(t) && !off.contains(t)) {
        out.add(t);
      }
    }
    return out;
  }

  /// 🌐 چیپ‌های زبانِ تنظیمات («خواندن ترجمه‌ها در پس‌زمینه»): زبان‌های خاموش — فقط وقتی اپ در پس‌زمینه است اعمال می‌شود.
  Set<String> _bgOffLangs() {
    if (!_inBackground()) return const <String>{};
    try {
      return (ref.read(sharedPrefsProvider).getString('zflut-read-trans-bg-off') ?? '')
          .split(',')
          .map((e) => e.trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toSet();
    } catch (_) {
      return const <String>{};
    }
  }

  bool _inBackground() {
    if (_FrameWatch.recent) return false; // فریم می‌آید = داخل برنامه‌ای
    final st = WidgetsBinding.instance.lifecycleState;
    if (st == null) return false;
    // «inactive» یعنی اپ هنوز روی صفحه است ولی فوکوس ندارد (مثلاً کادر شناور/
    // اعلان/دیالوگِ سیستم) — این پس‌زمینه نیست. فقط paused/hidden/detached.
    // «hidden» را پس‌زمینه حساب نمی‌کنیم: روی بعضی گوشی‌ها (کادر شناور/پنجره‌ی کوچک)
    // وقتی داخل برنامه‌ای هم می‌آید و باعث می‌شد فقط ترجمه‌ی زبان مبدأ خوانده شود.
    return st == AppLifecycleState.paused || st == AppLifecycleState.detached;
  }

  String _nativeCode() =>
      ref.read(languageSelectionProvider).native.trim().toLowerCase();

  /// درخواست‌های ترجمه‌ی در حال انجام — پیش‌گرم‌کردن و صفِ خوانش برای یک متن/زبان
  /// یک درخواستِ مشترک دارند (قبلاً دومی ته صف می‌رفت و بعد از ۸ ثانیه رد می‌شد).
  final Map<String, Future<String?>> _trInflight = {};

  /// ترجمه‌ی آیتم: اول آنچه روی صفحه آماده شده، بعد کشِ ترجمه/داده‌های اپ، و اگر نبود همان لحظه ترجمه می‌کند.
  Future<String?> _translationText(String id, String from, String to,
      {Duration timeout = const Duration(seconds: 25)}) async {
    final local = _notifier.translationFor(id, to);
    if (local != null) return local;
    final src = _notifier.itemText(id)?.trim();
    if (src == null || src.isEmpty) return null;
    try {
      final svc = ref.read(translationServiceProvider);
      final hit =
          svc.peekCached(src, from, to) ?? KnownTranslations.get(src, from, to);
      if (hit != null && hit.trim().isNotEmpty) return hit.trim();
      final k = '$from>$to|$src';
      final fut = _trInflight.putIfAbsent(k, () {
        final f = () async {
          final r = (await svc.translate(
                  text: src,
                  targetLang: to,
                  sourceLang: from,
                  aiSettings: ref.read(aiSettingsProvider)))
              .trim();
          if (r.isEmpty) return null;
          // همان متن: برای زبان‌های لاتین (مثلاً hotel ← es/de) ترجمه‌ی درست است و باید خوانده شود؛
          // برای فارسی/عربی یعنی ترجمه شکست خورده.
          if (r.toLowerCase() == src.toLowerCase() &&
              (to == 'fa' || to == 'ar')) {
            return null;
          }
          return r;
        }();
        return f.whenComplete(() => _trInflight.remove(k));
      });
      return await fut.timeout(timeout, onTimeout: () => null);
    } catch (_) {
      return null;
    }
  }

  /// وقتی اپ در پس‌زمینه است و گزینه‌ی تنظیمات روشن: بعد از هر آیتم، ترجمه‌اش خوانده می‌شود
  /// (اگر هنوز ترجمه نشده باشد همان لحظه ترجمه می‌شود؛ فقط اگر نشد رد می‌شود).
  bool _readTranslation(
      PlayerTrack track, TrackSpan cur, TrackSpan? nxt, bool loops) {
    if (!_readTransBg() || !_inBackground()) return false;
    // 🌐 همه‌ی زبان‌های انتخاب‌شده در هدر (مبدأ + مقصدها) به‌ترتیب؛ نه فقط اولی
    if (_fgLangs(track.code).isEmpty) return false;
    return _startFgQueue(track, cur, nxt, loops, '', const <String>[]);
  }

  Future<void> _playTranslationThenResume(
      PlayerTrack track, String id, String to) async {
    final text = await _translationText(id, track.code, to);
    if (!mounted) return;
    final sp = ref.read(speechControllerProvider);
    if (sp.key != track.key || sp.status != SpeechStatus.playing) {
      // کاربر در این فاصله توقف کرد یا متن را عوض کرد
      _resumeSpanId = null;
      _resumeFromHook = false;
      return;
    }
    if (text == null) {
      _resumeMain(); // ترجمه‌ای نبود → همان آیتمِ بعد
      return;
    }
    final key = PlayerTrack.keyFor(to, text);
    SpeechController.translationReadKey = key;
    _trVoiceKey = key; _trVoiceItem = id; _trVoiceLang = to;
    ref.read(adhocSyncProvider.notifier).state =
        (key: key, active: ActiveSync(to, id));
    unawaited(_ctrl.toggle(text, to));
    SpotlightTour.startTranslationReading(); // 🎓 بارِ اول: راهنمای خوانشِ ترجمه
    // اگر خوانشِ ترجمه به هر دلیل (خطا/شروع‌نشدن) تمام نشد، پلیر گیر نکند و ادامه بدهد
    Timer(Duration(seconds: 12 + text.length ~/ 6), () {
      if (!mounted || _resumeSpanId == null) return;
      if (SpeechController.translationReadKey != key) return;
      final cur = ref.read(speechControllerProvider);
      if (cur.key == key && cur.status == SpeechStatus.paused) return; // کاربر مکث کرده
      _resumeMain();
    });
  }

  String? _prewarmId;

  /// پس‌زمینه: ترجمه‌ی آیتمِ در حال خوانش و بعدی از قبل آماده و صدایشان پیش‌ساخته می‌شود (بدون مکث بینِ جمله‌ها).
  void _prewarmTranslations(SpeechState s) {
    if (!_readTransBg() || !_inBackground()) return;
    final sync = ref.read(playerSyncProvider);
    final track = sync.tracks[sync.mainCode];
    if (track == null || track.key != s.key) return;
    final cur = track.spanAt(s.charOffset);
    if (cur == null || cur.id == _prewarmId) return;
    _prewarmId = cur.id;
    final langs = _fgLangs(track.code); // همه‌ی زبان‌های هدر (مبدأ + مقصدها)
    if (langs.isEmpty) return;
    final i = track.spans.indexWhere((x) => x.id == cur.id);
    for (final k in [i, i + 1]) {
      if (k < 0 || k >= track.spans.length) continue;
      final id = track.spans[k].id;
      for (final to in langs) {
        unawaited(() async {
          final t = await _translationText(id, track.code, to);
          if (t == null || !mounted) return;
          final clean = SentenceSplitter.sanitize(t);
          if (clean.isEmpty) return;
          unawaited(NativeTtsBridge.prefetch(
              clean, to, ref.read(speechControllerProvider).rate,
              voice: widget.voiceForTrans?.call(id, to)));
        }());
      }
      // مثال‌های بازِ این لغت و ترجمه‌هایشان هم از قبل آماده شوند
      final w = _notifier.itemText(id);
      final exs = w == null ? null : _examplesOf(w, track.code);
      if (w != null && exs != null) {
        for (final e in exs) {
          final rate = ref.read(speechControllerProvider).rate;
          final ce = SentenceSplitter.sanitize(e);
          if (ce.isNotEmpty) {
            unawaited(NativeTtsBridge.prefetch(ce, track.code, rate));
          }
          for (final to in langs) {
            unawaited(() async {
              final t = await _exampleTranslation(w, track.code, e, to);
              if (t == null || !mounted) return;
              final ct = SentenceSplitter.sanitize(t);
              if (ct.isNotEmpty) {
                unawaited(NativeTtsBridge.prefetch(ct, to, rate));
              }
            }());
          }
        }
      }
    }
    // ⚡ ترجمه‌ی چند لغتِ بعدی هم از همین الان گرفته می‌شود تا موقعِ نوبتشان مکثی نباشد
    for (var k = i + 2; i >= 0 && k <= i + 6 && k < track.spans.length; k++) {
      for (final to in langs) {
        unawaited(_translationText(track.spans[k].id, track.code, to,
            timeout: const Duration(seconds: 20)));
      }
    }
  }

  // ═══════════════ صفِ خوانشِ پس‌زمینه (لغت + مثال‌ها + ترجمه‌ها) ═══════════════
  bool _bgActive = false;
  String? _bgItemId; // آیتمی که ترجمه‌هایش در صف خوانده می‌شود (برای «قبلی/بعدی»)
  String? _bgTrackCode;
  int _bgToken = 0;
  Completer<bool>? _bgWait;
  String? _bgKey;
  bool _bgSeen = false;

  /// ترجمه‌ی یک مثال: اول از حافظه‌ی مثال‌ها (همان که روی صفحه است)، بعد کش/مترجم.
  Future<String?> _exampleTranslation(
      String word, String from, String text, String to,
      {Duration timeout = const Duration(seconds: 20)}) async {
    try {
      final list = ref.read(wordExamplesStoreProvider).load(word, from);
      for (final e in list) {
        if (e.text == text) {
          final t = e.translations[to]?.trim();
          if (t != null && t.isNotEmpty) return t;
          break;
        }
      }
    } catch (_) {}
    final src = text.trim();
    if (src.isEmpty) return null;
    try {
      final svc = ref.read(translationServiceProvider);
      final hit =
          svc.peekCached(src, from, to) ?? KnownTranslations.get(src, from, to);
      if (hit != null && hit.trim().isNotEmpty) return hit.trim();
      final r = (await svc
              .translate(
                  text: src,
                  targetLang: to,
                  sourceLang: from,
                  aiSettings: ref.read(aiSettingsProvider))
              .timeout(timeout))
          .trim();
      if (r.isEmpty) return null;
      if (r.toLowerCase() == src.toLowerCase() && (to == 'fa' || to == 'ar')) {
        return null;
      }
      return r;
    } catch (_) {
      return null;
    }
  }

  bool _startBgQueue(PlayerTrack track, TrackSpan cur, TrackSpan? nxt,
      bool loops, String word, List<String> texts) {
    if (!_readTransBg() || !_inBackground()) return false;
    // 🌐 پس‌زمینه هم مثل داخل برنامه: ترجمه‌ی همه‌ی زبان‌های انتخاب‌شده در هدر (مبدأ + مقصدها)
    // به‌ترتیبِ هدر خوانده می‌شود؛ هر تغییری در هدر بلافاصله اعمال می‌شود.
    return _startFgQueue(track, cur, nxt, loops, word, texts);
  }

  /// داخل برنامه: لغت ← ترجمه‌ی هر زبان ← (مثال ← ترجمه‌ی هر زبان) ← لغتِ بعد
  bool _startFgQueue(PlayerTrack track, TrackSpan cur, TrackSpan? nxt,
      bool loops, String word, List<String> texts) {
    final langs = _fgLangs(track.code);
    if (langs.isEmpty) return false;
    debugPrint('🌐 صفِ ترجمه: زبان‌ها=$langs (متن=${track.code})');
    _bgCancel();
    _resumeFromHook = true;
    _resumeSpanId =
        nxt != null ? nxt.id : (loops ? track.spans.first.id : null);

    final steps = <_BgStep>[
      for (final l in langs)
        _BgStep(l, true, null, _translationText(cur.id, track.code, l),
            (t) => cur.id,
            retry: () => _translationText(cur.id, track.code, l,
                timeout: const Duration(seconds: 30))),
    ];
    for (final ex in List<String>.of(texts)) {
      steps.add(_BgStep(track.code, false, ex, null,
          (t) => 'ai-ex-${track.code}-${ex.hashCode}'));
      for (final l in langs) {
        steps.add(_BgStep(l, true, null,
            _exampleTranslation(word, track.code, ex, l),
            (t) => 'ai-ex-tr-$l-${t.hashCode}',
            retry: () => _exampleTranslation(word, track.code, ex, l,
                timeout: const Duration(seconds: 25))));
      }
    }

    _bgItemId = cur.id;
    _bgTrackCode = track.code;
    _bgActive = true;
    ExamplesRegistry.bgDriving = true;
    final token = ++_bgToken;
    unawaited(_runBgQueue(steps, token, track.key));
    return true;
  }

  String? _prewarmFgId;

  /// داخل برنامه: ترجمه‌ی چند آیتمِ بعدی برای همه‌ی زبان‌ها از قبل گرفته و صدایشان پیش‌ساخته می‌شود.
  void _prewarmFg(SpeechState s) {
    if (!_readTransFg() || _inBackground()) return;
    final track = _notifier.mainTrackForKey(s.key);
    if (track == null) return;
    final cur = track.spanAt(s.charOffset);
    if (cur == null || cur.id == _prewarmFgId) return;
    _prewarmFgId = cur.id;
    final langs = _fgLangs(track.code);
    final i = track.spans.indexWhere((x) => x.id == cur.id);
    if (i < 0) return;
    for (var k = i; k <= i + 4 && k < track.spans.length; k++) {
      final id = track.spans[k].id;
      for (final l in langs) {
        unawaited(() async {
          final t = await _translationText(id, track.code, l,
              timeout: const Duration(seconds: 20));
          if (t == null || !mounted || k > i + 3) return;
          final clean = SentenceSplitter.sanitize(t);
          if (clean.isNotEmpty) {
            unawaited(NativeTtsBridge.prefetch(
                clean, l, ref.read(speechControllerProvider).rate,
                voice: widget.voiceForTrans?.call(id, l)));
          }
        }());
      }
    }
  }

  Future<void> _runBgQueue(
      List<_BgStep> steps, int token, String firstKey) async {
    var expectKey = firstKey;
    var first = true;
    var completed = false;
    try {
      for (final st in steps) {
        // ⏱ منتظرِ ترجمه‌ی طولانی نمی‌مانیم: اگر آماده نشد، رد می‌شویم و خوانش به آیتمِ بعد می‌رود
        // (ترجمه در پس‌زمینه ادامه پیدا می‌کند و برای دفعه‌ی بعد کش می‌شود).
        var timedOut = false;
        var text = (await st.text().timeout(const Duration(seconds: 5),
                onTimeout: () {
          timedOut = true;
          return null;
        }))
            ?.trim();
        if (!mounted || token != _bgToken) return;
        if ((text == null || text.isEmpty) && !timedOut && st.retry != null) {
          text = (await st.retry!().timeout(const Duration(seconds: 5),
                  onTimeout: () => null))
              ?.trim();
          if (!mounted || token != _bgToken) return;
        }
        if (text == null || text.isEmpty) {
          debugPrint('⏭ خوانش ترجمه رد شد (متن آماده نشد): ${st.code}');
          continue; // ترجمه‌ای نبود → رد شو
        }
        debugPrint('🌐 خوانش ${st.code} (${steps.indexOf(st) + 1}/${steps.length})');
        // مکثِ کاربر بین مرحله‌ها فقط تأخیر می‌اندازد؛ توقفِ کامل صف را تمام می‌کند
        if (!await _bgWaitFree(token, first ? expectKey : null)) return;
        final key = PlayerTrack.keyFor(st.code, text);
        _bgKey = key;
        _bgSeen = false;
        _bgWait = null; // ✅ پایانِ مرحله دیگر با «رویداد» نیست؛ وضعیتِ واقعیِ پخش را می‌خوانیم
        SpeechController.translationReadKey = st.isTrans ? key : null;
        _trVoiceKey = st.isTrans ? key : null;
        _trVoiceItem = st.isTrans ? st.idFor(text) : null;
        _trVoiceLang = st.code;
        ref.read(adhocSyncProvider.notifier).state =
            (key: key, active: ActiveSync(st.code, st.idFor(text)));
        unawaited(_ctrl.toggle(text, st.code));
        if (st.isTrans) SpotlightTour.startTranslationReading(); // 🎓 بارِ اول: راهنمای خوانشِ ترجمه
        first = false;
        expectKey = key;
        if (!await _awaitFinish(key, text, token)) return;
        if (!mounted || token != _bgToken) return;
      }
      completed = true;
    } finally {
      if (token == _bgToken) {
        _bgActive = false;
        _bgWait = null;
        ExamplesRegistry.bgDriving = false;
      }
    }
    if (completed && mounted && token == _bgToken) _resumeMain();
  }

  /// ⏱ پایانِ یک مرحله‌ی صف را از «وضعیتِ واقعیِ پخش» می‌فهمد (هر ۶۰ms)، نه از رویدادِ
  /// گذرِ playing→idle که اگر از دست می‌رفت زبانِ بعد هیچ‌وقت خوانده نمی‌شد.
  ///   true  = این مرحله تمام شد/رد شد → مرحله‌ی بعد
  ///   false = کاربر توقفِ کامل کرد یا صف لغو شد → پایانِ صف
  Future<bool> _awaitFinish(String key, String text, int token) async {
    final started = DateTime.now();
    var deadline = started.add(Duration(seconds: 25 + text.length ~/ 4));
    var seenActive = false;
    DateTime? idleSince;
    while (true) {
      if (!mounted || token != _bgToken) return false;
      final sp = ref.read(speechControllerProvider);
      final now = DateTime.now();
      if (sp.key == key) {
        if (sp.status == SpeechStatus.paused) {
          deadline = deadline.add(const Duration(milliseconds: 60)); // مکثِ کاربر
          idleSince = null;
          seenActive = true;
        } else if (sp.status == SpeechStatus.playing) {
          seenActive = true;
          idleSince = null;
        } else {
          // idle
          if (seenActive || sp.error != null) {
            if (sp.error != null) debugPrint('🌐 مرحله رد شد (خطا: ${sp.error})');
            return true; // تمام شد (یا خطا) → زبانِ بعد
          }
          idleSince ??= now;
          if (now.difference(idleSince) > const Duration(seconds: 3)) {
            debugPrint('🌐 مرحله هیچ‌وقت شروع نشد؛ رد می‌شود');
            return true;
          }
        }
      } else if (sp.key == null) {
        if (now.difference(started) > const Duration(milliseconds: 1500)) {
          return false; // توقفِ کاملِ کاربر
        }
      } else if (now.difference(started) > const Duration(seconds: 4)) {
        // چیزِ دیگری جایش را گرفت
        return seenActive;
      }
      if (now.isAfter(deadline)) return true;
      await Future.delayed(const Duration(milliseconds: 60));
    }
  }

  Future<bool> _bgWaitDone(Completer<bool> w, String key, String text) async {
    final cap = Duration(seconds: 25 + text.length ~/ 4);
    final Future<bool?> f = w.future;
    while (true) {
      final r = await f.timeout(cap, onTimeout: () => null);
      if (r != null) return r;
      final cur = ref.read(speechControllerProvider);
      if (cur.key == key && cur.status == SpeechStatus.paused) continue;
      return cur.key != null; // گیر کرده بود (یا چیزِ دیگری پخش شد) → مرحله‌ی بعد
    }
  }

  /// صبر تا موتورِ صدا آزاد شود: بیکار است، یا (فقط برای مرحله‌ی اول) متنِ اصلیِ منتظرِ ماست.
  /// مکثِ کاربر یا پخشِ دیگر فقط تأخیر می‌اندازد و چیزی کنسل نمی‌شود.
  /// فقط «توقفِ کامل» (پلیر بسته شد) یا ترک‌کردنِ اسکوپ صف را تمام می‌کند.
  Future<bool> _bgWaitFree(int token, String? firstKey) async {
    while (true) {
      if (!mounted || token != _bgToken) return false;
      if (ref.read(playerSyncProvider).scopeId != _scopeId) return false;
      final sp = ref.read(speechControllerProvider);
      if (sp.key == null) return false;
      if (sp.status == SpeechStatus.idle) return true;
      if (firstKey != null &&
          sp.key == firstKey &&
          sp.status == SpeechStatus.playing) {
        return true;
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  void _bgOnSpeech(SpeechState? prev, SpeechState next) {
    final w = _bgWait;
    final key = _bgKey;
    if (w == null || w.isCompleted || key == null) return;
    if (next.key == key) {
      _bgSeen = true;
      // ⛔ خطای همین مرحله (مثلاً صدای آن زبان روی گوشی نصب نیست / بسته‌ی صوتی نیست):
      // بلافاصله برو سراغ زبانِ بعد؛ قبلاً تا ۲۵+ ثانیه گیر می‌کرد و کاربر فکر می‌کرد
      // فقط زبانِ اول خوانده می‌شود.
      if (next.status == SpeechStatus.idle && next.error != null) {
        debugPrint('🌐 مرحله‌ی خوانش رد شد (خطا: ${next.error})');
        w.complete(true);
        return;
      }
      if (prev != null &&
          prev.key == key &&
          prev.status != SpeechStatus.idle &&
          next.status == SpeechStatus.idle) {
        w.complete(true); // پایانِ همین مرحله (هر نوع پایان، نه فقط از حالتِ playing)
      }
      return;
    }
    // پخشِ دیگری جایش را گرفت → مرحله‌ی بعد (بعد از آزاد شدنِ صدا)؛ فقط توقفِ کامل پایان می‌دهد
    if (next.key == null) {
      w.complete(false);
      return;
    }
    if (_bgSeen) w.complete(true);
  }

  /// ⏭/⏮ نوتیفیکیشن وسطِ خوانشِ ترجمه‌ها: به لغتِ بعدی/قبلیِ همین فهرست می‌رود (نه زبانِ بعدیِ همین لغت).
  bool _skipWord(int dir) {
    if (!_bgActive) return false;
    final id = _bgItemId;
    if (id == null) return false;
    final sync = ref.read(playerSyncProvider);
    final track = sync.tracks[_bgTrackCode ?? sync.mainCode];
    if (track == null || track.spans.isEmpty) return false;
    final i = track.spans.indexWhere((x) => x.id == id);
    if (i < 0) return false;
    final n = track.spans.length;
    final span = track.spans[((i + dir) % n + n) % n];
    _bgCancel();
    SpeechController.translationReadKey = null;
    _resumeSpanId = span.id;
    _resumeCode = track.code;
    _resumeFromHook = true;
    _resumeMain();
    return true;
  }

  void _bgCancel() {
    _bgToken++;
    final w = _bgWait;
    if (w != null && !w.isCompleted) w.complete(false);
    _bgWait = null;
    _bgKey = null;
    if (_bgActive) {
      _bgActive = false;
      ExamplesRegistry.bgDriving = false;
    }
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
    if (_bgActive && sync.scopeId != _scopeId) _bgCancel();
    if (sync.scopeId != _scopeId) return;
    if (_bgActive) {
      _bgOnSpeech(prev, next);
      return;
    }
    if (next.key == null) {
      _resumeSpanId = null;
      _resumeFromHook = false;
      _resumeCode = null;
      return;
    }
    if (next.status == SpeechStatus.playing) {
      _prewarmTranslations(next);
      _prewarmFg(next);
    }
    final ad = ref.read(adhocSyncProvider);
    final isExample = ad != null && ad.key == next.key;

    if (prev?.key != next.key) {
      if (!isExample) {
        _resumeSpanId = null;
        _resumeFromHook = false;
        _resumeCode = null;
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
        (next.error == null || next.key == SpeechController.translationReadKey)) {
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
    final rc = _resumeCode;
    _resumeCode = null;
    final track = sync.tracks[rc ?? sync.mainCode];
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
    ref.listen<String?>(revealItemProvider, (prev, next) {
      if (next != null) _tryRevealRequested();
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
    // 🖍 محدوده‌ی خوانده‌شده از نمودارِ گوش‌دادن: 0 = نه، 1 = پررنگ، 2 = در حالِ محو شدن
    final rh = ref.watch(readHighlightProvider.select((h) =>
        h == null || !h.ids.contains(id) ? 0 : (h.fading ? 2 : 1)));

    final Color target = (hl != null && (active || rh == 1))
        ? hl
        : (hl ?? kReadMarkerColor).withOpacity(0);

    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: target),
      duration: rh == 2 ? const Duration(milliseconds: 3000) : duration,
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
  if (track == null ||
      track.fullText.isEmpty ||
      !ref.read(playerSyncProvider.notifier).hasMainItems) {
    // تراکِ اصلی خالی است (مثلاً فهرست فقط لغاتِ غیرانگلیسی دارد) → اولین
    // تراکِ دارای متن
    track = null;
    final ownMain = ref.read(playerSyncProvider.notifier).hasMainItems;
    for (final t in sync.tracks.values) {
      // فهرست فقط لغاتِ زبانِ دیگر دارد: تراکِ اصلی فقط ترجمه‌هاست، نه لغت‌ها
      if (!ownMain && t.code == sync.mainCode) continue;
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

  if (st.key != null && st.status != SpeechStatus.idle) {
    // چیزی در حال پخش/مکث است (از هر تب/زیرتبی که شروع شده باشد) → فقط پخش/توقفِ همان.
    // بعد از جابه‌جایی بین تب‌ها پلیر نباید متنِ تبِ تازه را جایش بخواند؛
    // برای شروعِ لیستِ این تب، 🔊 کنارِ هر آیتم را بزن.
    await ctrl.togglePlayPause();
    return true;
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

/// یک مرحله از صفِ خوانشِ پس‌زمینه: متنِ آماده یا ترجمه‌ای که هنوز در راه است.
class _BgStep {
  final String code;
  final bool isTrans;
  final String? _fixed;
  final Future<String?>? _fut;
  final String Function(String text) idFor;

  /// اگر ترجمه‌ی اول نرسید، یک بار دیگر با مهلتِ بیشتر امتحان می‌شود (رد نشود).
  final Future<String?> Function()? retry;
  _BgStep(this.code, this.isTrans, this._fixed, this._fut, this.idFor,
      {this.retry});

  Future<String?> text() => _fixed != null ? Future.value(_fixed) : (_fut ?? Future.value(null));
}


/// ⏭/⏮ پلیرِ پس‌زمینه: اگر الان صفِ ترجمه‌ها در حال خواندن است، به لغتِ بعدی/قبلی می‌پرد و true برمی‌گرداند.
bool syncSkipWord(int dir) {
  for (final st in List<_SyncPlayScopeState>.of(_SyncPlayScopeState._live)) {
    if (st.mounted && st._skipWord(dir)) return true;
  }
  return _DetachedReader._active?.skipWord(dir) ?? false;
}

/// آیا برنامه الان در پس‌زمینه است؟ (همان منطقِ `_inBackground` ویجتِ اسکوپ، برای خوانشگرِ مستقل از تب)
bool _appInBackgroundNow() {
  if (_FrameWatch.recent) return false;
  final st = WidgetsBinding.instance.lifecycleState;
  if (st == null) return false;
  return st == AppLifecycleState.paused || st == AppLifecycleState.detached;
}

/// 🔁 خوانشگرِ مستقل از تب.
///
/// صفِ «لغت ← ترجمه‌ی هر زبان ← آیتمِ بعد» به ویجتِ اسکوپِ همان تب بسته است و با عوض‌شدنِ تب
/// (هر تب یک route جداست) از بین می‌رفت؛ بعدش فقط متنِ اصلی خوانده می‌شد و ترجمه‌ها نه. این کلاس
/// موقعِ ترکِ تب یک عکس از متن/ترجمه‌های آماده می‌گیرد و همان کار را ادامه می‌دهد:
///   • بعد از هر آیتمِ متنِ اصلی، ترجمه‌ی همه‌ی زبان‌های هدر (به‌ترتیب) خوانده می‌شود؛
///   • صدای گوینده‌ها (A/B) و صدای هر ترجمه همان می‌ماند (voiceForItem / voiceForTrans)؛
///   • اگر چیزِ دیگری پخش شد، یا کاربر به همان تب برگشت (اسکوپِ تازه)، خودش را کنار می‌کشد.
class _DetachedReader {
  static _DetachedReader? _active;

  final ProviderContainer _c;
  final SpeechController _ctrl;
  final PlayerTrack _main;
  final String _oldScopeId;
  final Map<String, String> _texts;
  final Set<String> _foreign;
  final Map<String, Map<String, String>> _ready;
  final String? Function(String itemId)? _vf;
  final String? Function(String itemId, String lang)? _vt;

  bool _dead = false;
  bool _busy = false;
  int _token = 0;
  String? _trKey, _trItem, _trLang;
  String? _curItem; // آیتمی که ترجمه‌هایش در حال خواندن است
  final Set<String> _own = <String>{};
  void Function()? _unlisten;
  Timer? _guard;

  _DetachedReader({
    required ProviderContainer container,
    required SpeechController ctrl,
    required PlayerTrack main,
    required String scopeId,
    required Map<String, String> texts,
    required Set<String> foreign,
    required Map<String, Map<String, String>> ready,
    String? Function(String itemId)? voiceForItem,
    String? Function(String itemId, String lang)? voiceForTrans,
  })  : _c = container,
        _ctrl = ctrl,
        _main = main,
        _oldScopeId = scopeId,
        _texts = texts,
        _foreign = foreign,
        _ready = ready,
        _vf = voiceForItem,
        _vt = voiceForTrans;

  void attach() {
    _active?._stop(); // فقط یک خوانشگر؛ تازه‌ترین
    _active = this;
    _own.add(_main.key);
    _ctrl.addChunkAdvanceHook(_onAdvance);
    if (_vf != null || _vt != null) _ctrl.addChunkVoiceResolver(_resolveVoice);
    _unlisten = _ctrl.addListener((SpeechState s) {
      if (_dead) return;
      // متنِ دیگری (نه مالِ این خوانشگر) شروع شد → کاربر چیزِ دیگری پخش کرده؛ کنار می‌کشیم
      if (s.key != null && s.status != SpeechStatus.idle && !_own.contains(s.key)) {
        _stop();
      }
    }, fireImmediately: false);
    _guard = Timer(const Duration(minutes: 90), _stop);
  }

  void _stop() {
    if (_dead) return;
    _dead = true;
    _token++;
    _guard?.cancel();
    try {
      _ctrl.removeChunkAdvanceHook(_onAdvance);
    } catch (_) {}
    try {
      _ctrl.removeChunkVoiceResolver(_resolveVoice);
    } catch (_) {}
    try {
      _unlisten?.call();
    } catch (_) {}
    if (identical(_active, this)) _active = null;
  }

  // 🎭 صدای جمله: ترجمه‌ی در حال خواندن ← صدای همان گوینده/زبان؛ متنِ اصلی ← صدای گوینده‌ی آن آیتم
  String? _resolveVoice(String? key, int start) {
    if (_dead || key == null) return null;
    try {
      if (key == _trKey && _trItem != null && _trLang != null) {
        return _vt?.call(_trItem!, _trLang!);
      }
      if (key == _main.key) {
        final sp = _main.spanAt(start);
        return sp == null ? null : _vf?.call(sp.id);
      }
    } catch (_) {}
    return null;
  }

  bool _liveScopeOwnsMain() {
    final sync = _c.read(playerSyncProvider);
    if (sync.scopeId == null || sync.scopeId == _oldScopeId) return false;
    return sync.tracks.values.any((t) => t.key == _main.key);
  }

  bool _enabled() {
    try {
      final p = _c.read(sharedPrefsProvider);
      return _appInBackgroundNow()
          ? (p.getBool('zflut-read-trans-bg') ?? true)
          : (p.getBool('zflut-read-trans-fg') ?? true);
    } catch (_) {
      return false;
    }
  }

  /// زبان‌هایی که ترجمه‌شان خوانده می‌شود: مبدأ + همه‌ی مقصدهای هدر (مثل `_fgLangs`)
  List<String> _langs() {
    final sel = _c.read(languageSelectionProvider);
    var off = <String>{};
    if (_appInBackgroundNow()) {
      try {
        off = (_c.read(sharedPrefsProvider).getString('zflut-read-trans-bg-off') ?? '')
            .split(',')
            .map((e) => e.trim().toLowerCase())
            .where((e) => e.isNotEmpty)
            .toSet();
      } catch (_) {}
    }
    final out = <String>[];
    for (final c in [
      if (!sel.targets.contains(sel.native)) sel.native,
      ...sel.targets,
    ]) {
      final t = c.trim().toLowerCase();
      if (t.isNotEmpty && t != _main.code && !out.contains(t) && !off.contains(t)) {
        out.add(t);
      }
    }
    return out;
  }

  /// پایانِ طبیعیِ خواندنِ یک آیتمِ متنِ اصلی (مثل `_chunkHook` ویجتِ اسکوپ)
  bool _onAdvance(String? key, int thisStart, int nextStart, bool loops) {
    if (_dead || key == null || key != _main.key) return false;
    if (_busy) return false;
    if (_liveScopeOwnsMain()) {
      // کاربر به همان تب برگشته؛ ویجتِ زنده خودش ادامه می‌دهد
      _stop();
      return false;
    }
    if (!_enabled()) return false;
    final langs = _langs();
    if (langs.isEmpty) return false;
    int skipWs(int i) {
      final t = _main.fullText;
      while (i >= 0 && i < t.length && t.codeUnitAt(i) <= 32) {
        i++;
      }
      return i;
    }

    final cur = _main.spanAt(skipWs(thisStart));
    if (cur == null) return false;
    final nxt = nextStart >= 0 ? _main.spanAt(skipWs(nextStart)) : null;
    if (nxt != null && nxt.id == cur.id) return false; // هنوز همین آیتم
    if (_foreign.contains(cur.id)) return false;
    final resumeId =
        nxt != null ? nxt.id : (loops ? _main.spans.first.id : null);
    unawaited(runItem(cur.id, resumeId));
    return true;
  }

  Future<String?> _text(String id, String lang,
      {Duration timeout = const Duration(seconds: 25)}) async {
    final r0 = _ready[id]?[lang];
    if (r0 != null && r0.trim().isNotEmpty) return r0.trim();
    final src = _texts[id]?.trim();
    if (src == null || src.isEmpty) return null;
    try {
      final svc = _c.read(translationServiceProvider);
      final hit = svc.peekCached(src, _main.code, lang) ??
          KnownTranslations.get(src, _main.code, lang);
      if (hit != null && hit.trim().isNotEmpty) return hit.trim();
      final r = (await svc
              .translate(
                  text: src,
                  targetLang: lang,
                  sourceLang: _main.code,
                  aiSettings: _c.read(aiSettingsProvider))
              .timeout(timeout))
          .trim();
      if (r.isEmpty) return null;
      if (r.toLowerCase() == src.toLowerCase() && (lang == 'fa' || lang == 'ar')) {
        return null;
      }
      return r;
    } catch (_) {
      return null;
    }
  }

  /// یک آیتم: ترجمه‌ی هر زبان به‌ترتیب ← ادامه‌ی متنِ اصلی از [resumeId].
  /// [pendingKey]: مرحله‌ای که هنگامِ ترکِ تب در حال پخش بود (اول تمام می‌شود).
  /// [afterLang]: فقط زبان‌های بعد از این زبان؛ [skipLangs]: هیچ زبانی نماند (فقط ادامه‌ی متن).
  Future<void> runItem(String itemId, String? resumeId,
      {String? pendingKey, String? afterLang, bool skipLangs = false}) async {
    final token = ++_token;
    _busy = true;
    _curItem = itemId;
    try {
      if (pendingKey != null) {
        _own.add(pendingKey);
        if (!await _awaitFinish(pendingKey, 120, token)) return;
      }
      var langs = skipLangs ? <String>[] : _langs();
      if (afterLang != null) {
        final i = langs.indexOf(afterLang);
        if (i >= 0) langs = langs.sublist(i + 1);
      }
      var first = pendingKey == null;
      for (final l in langs) {
        // ⏱ ترجمه‌ی دیرآماده نمی‌ماند: رد می‌شویم (در پس‌زمینه کش می‌شود)
        var timedOut = false;
        var text = (await _text(itemId, l).timeout(const Duration(seconds: 5),
                onTimeout: () {
          timedOut = true;
          return null;
        }))
            ?.trim();
        if (_dead || token != _token) return;
        if ((text == null || text.isEmpty) && !timedOut) {
          text = (await _text(itemId, l, timeout: const Duration(seconds: 30))
                  .timeout(const Duration(seconds: 5), onTimeout: () => null))
              ?.trim();
          if (_dead || token != _token) return;
        }
        if (text == null || text.isEmpty) continue;
        if (!await _waitFree(token, first ? _main.key : null)) return;
        final key = PlayerTrack.keyFor(l, text);
        _own.add(key);
        _trKey = key;
        _trItem = itemId;
        _trLang = l;
        SpeechController.translationReadKey = key;
        _c.read(adhocSyncProvider.notifier).state =
            (key: key, active: ActiveSync(l, itemId));
        unawaited(_ctrl.toggle(text, l));
        first = false;
        if (!await _awaitFinish(key, text.length, token)) return;
      }
      if (_dead || token != _token) return;
      _trKey = null;
      _resumeMain(resumeId);
    } catch (e) {
      debugPrint('detached reader error: $e');
    } finally {
      if (token == _token) _busy = false;
    }
  }

  /// ⏭/⏮ نوتیفیکیشن وسطِ خوانشِ ترجمه‌ها: لغتِ بعدی/قبلی (نه زبانِ بعدیِ همین لغت)
  bool skipWord(int dir) {
    final id = _curItem;
    if (_dead || !_busy || id == null) return false;
    final i = _main.spans.indexWhere((x) => x.id == id);
    if (i < 0) return false;
    final n = _main.spans.length;
    final span = _main.spans[((i + dir) % n + n) % n];
    _token++;
    _busy = false;
    _trKey = null;
    SpeechController.translationReadKey = null;
    _resumeMain(span.id);
    return true;
  }

  void _resumeMain(String? id) {
    final cur = _c.read(speechControllerProvider);
    final span = id == null ? null : _main.byId[id];
    if (span == null) {
      // لیست تمام شد (بدون تکرار): پلیرِ «بی‌صدا ولی در حال پخش» نماند
      if (cur.key == _main.key && cur.status != SpeechStatus.idle) {
        unawaited(_ctrl.stop());
      }
      return;
    }
    // همین متن هنوز «در حال پخش» ثبت است (کنترلر بینِ دو جمله منتظر مانده) → toggle آن را مکث می‌کرد
    if (cur.key == _main.key && cur.status != SpeechStatus.idle) {
      unawaited(_ctrl.seekToChunk(_ctrl.chunkIndexForOffset(span.start)));
      return;
    }
    unawaited(_ctrl.toggle(
      _main.fullText,
      _main.code,
      startCharOffset: span.start,
      loop: true,
      sentenceBoundaries: _main.boundaries,
    ));
  }

  /// صبر تا موتورِ صدا آزاد شود (یا، فقط برای مرحله‌ی اول، متنِ اصلیِ منتظرِ ما باشد).
  /// فقط «توقفِ کامل» صف را تمام می‌کند.
  Future<bool> _waitFree(int token, String? firstKey) async {
    while (true) {
      if (_dead || token != _token) return false;
      final sp = _c.read(speechControllerProvider);
      if (sp.key == null) return false;
      if (sp.status == SpeechStatus.idle) return true;
      if (firstKey != null &&
          sp.key == firstKey &&
          sp.status == SpeechStatus.playing) {
        return true;
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  /// پایانِ یک مرحله را از «وضعیتِ واقعیِ پخش» می‌فهمد (مثل `_awaitFinish` ویجتِ اسکوپ).
  ///   true = تمام شد/رد شد؛ false = توقفِ کامل یا لغو.
  Future<bool> _awaitFinish(String key, int textLen, int token) async {
    final started = DateTime.now();
    var deadline = started.add(Duration(seconds: 25 + textLen ~/ 4));
    var seenActive = false;
    DateTime? idleSince;
    while (true) {
      if (_dead || token != _token) return false;
      final sp = _c.read(speechControllerProvider);
      final now = DateTime.now();
      if (sp.key == key) {
        if (sp.status == SpeechStatus.paused) {
          deadline = deadline.add(const Duration(milliseconds: 60)); // مکثِ کاربر
          idleSince = null;
          seenActive = true;
        } else if (sp.status == SpeechStatus.playing) {
          seenActive = true;
          idleSince = null;
        } else {
          if (seenActive || sp.error != null) return true;
          idleSince ??= now;
          if (now.difference(idleSince) > const Duration(seconds: 3)) return true;
        }
      } else if (sp.key == null) {
        if (now.difference(started) > const Duration(milliseconds: 1500)) {
          return false; // توقفِ کاملِ کاربر
        }
      } else if (now.difference(started) > const Duration(seconds: 4)) {
        return seenActive; // چیزِ دیگری جایش را گرفت
      }
      if (now.isAfter(deadline)) return true;
      await Future.delayed(const Duration(milliseconds: 60));
    }
  }
}

/// بعد از ترکِ تب: وقتی آیتمِ در حال خواندن (ترجمه/مثال) تمام شد، خوانشِ لیست از آیتمِ بعد
/// ادامه پیدا می‌کند. اگر کاربر در این فاصله توقفِ کامل کرد یا چیزِ دیگری پخش کرد، کاری نمی‌کند.
void _resumeAfterLeaving(SpeechController ctrl, PlayerTrack track, int start,
    {Set<String> ownKeys = const <String>{}, bool eager = false}) {
  void Function()? remove;
  Timer? guard;
  var done = false;
  var first = true;
  String? watchKey;

  void resume(SpeechState cur) {
    // اگر همین متن الان «در حال پخش» ثبت شده (کنترلر منتظرِ صفِ تبِ بسته‌شده مانده بود)،
    // toggle آن را مکث می‌کرد؛ پس مستقیم به جمله‌ی بعد می‌رویم.
    if (cur.key == track.key && cur.status != SpeechStatus.idle) {
      unawaited(ctrl.seekToChunk(ctrl.chunkIndexForOffset(start)));
      return;
    }
    unawaited(ctrl.toggle(
      track.fullText,
      track.code,
      startCharOffset: start,
      loop: true,
      sentenceBoundaries: track.boundaries,
    ));
  }

  void finish() {
    if (done) return;
    done = true;
    guard?.cancel();
    try {
      remove?.call();
    } catch (_) {}
  }

  remove = ctrl.addListener((SpeechState s) {
    if (done) return;
    if (first) {
      first = false;
      if (s.key == null) {
        finish(); // چیزی پخش نمی‌شد / کاربر کامل متوقف کرده بود
        return;
      }
      if (s.status == SpeechStatus.idle) {
        finish(); // بینِ دو مرحله‌ی صف بود → همین حالا از آیتمِ بعد ادامه بده
        if (s.error == null) resume(s);
        return;
      }
      // ⛓ صفِ ترجمه/مثال هنوز اولین مرحله‌اش را شروع نکرده بود (کنترلر «در حال پخش» نشان
      // می‌دهد ولی بی‌صداست و منتظرِ صفی است که با بسته‌شدنِ تب مرده) → همین حالا ادامه بده
      if (eager && s.status == SpeechStatus.playing && ownKeys.contains(s.key)) {
        finish();
        if (s.error == null) resume(s);
        return;
      }
      watchKey = s.key;
      return;
    }
    if (s.key != watchKey) {
      finish(); // چیزِ دیگری پخش شد یا توقفِ کامل
      return;
    }
    if (s.status == SpeechStatus.idle) {
      finish();
      if (s.error == null) resume(s);
    }
  }, fireImmediately: true);
  if (done) {
    try {
      remove?.call();
    } catch (_) {}
  }
  guard = Timer(const Duration(minutes: 5), finish);
}
