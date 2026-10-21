import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app.dart' show AppL10nX;
import '../../../core/audio/story_audio_controller.dart';
import '../../../core/player_sync/player_sync_provider.dart';
import '../../../core/player_sync/sync_widgets.dart';
import '../../../core/providers/player_prefs_provider.dart';
import '../../../core/providers/speech_provider.dart';
import '../../../core/providers/story_user_audio_provider.dart';
import '../../../core/scroll/global_scroll.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/tts/sentence_splitter.dart';
import '../../../core/tts/speech_state.dart';
import 'my_voice_recorder.dart';

/// تخمینِ زمانِ نمایشی (میلی‌ثانیه به‌ازای هر کاراکتر) — مثل TTS_MS_PER_CHAR در Hope.
const double _kMsPerChar = 90;

class PlayerBar extends ConsumerWidget {
  const PlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final state = ref.watch(speechControllerProvider);
    final ctrl = ref.read(speechControllerProvider.notifier);
    final opacity = ref.watch(playerOpacityProvider);
    final opacityOpen = ref.watch(playerOpacityPanelOpenProvider);

    final isPlaying = state.status == SpeechStatus.playing;

    // 🎧 صدای اپلودیِ داستانِ بازشده (فقط تبِ داستان‌ساز) — معادلِ storyUserAudio در Hope
    final uaCtrl = ref.watch(storyUserAudioProvider);
    final mode = ref.watch(storyPlaybackModeProvider);

    // شفافیت صفر = پلیر کاملاً ناپدید می‌شود و جایی هم اشغال نمی‌کند
    // (دکمه‌ی بازنشانی را AppShell نشان می‌دهد).
    if (opacity == 0) return const SizedBox.shrink();

    // بدون قابِ سبزِ دورِ پلیر: فقط پنلِ paper با گوشه‌های گردِ بالا.
    Widget buildBar(StoryAudioController? ua) {
      final userMode = ua != null && ua.hasAudio && mode == 'user';
      return Container(
      decoration: BoxDecoration(
        color: c.paper,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(top: BorderSide(color: c.cardBorder, width: 1)),
        boxShadow: [
          BoxShadow(
            color: c.ink.withOpacity(0.10),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ═══ پیام خطا (مثلاً صدای این زبان نصب نیست) ═══
              if (state.error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                  child: Text(
                    state.error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: c.rose,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

              // ═══ سوییچِ «صدای اپ / صدای اپلودی» — فقط وقتی داستانی باز است ═══
              if (ua != null) _StorySourceSwitch(ua: ua, userMode: userMode),

              // ═══ زمان — نوارِ کشیدنی — زمانِ کل ═══
              if (userMode) _UserProgressTrack(ua: ua!) else const _ProgressTrack(),

              // ═══ سرعت (اسلایدر) + مقدارِ پرشِ ثانیه‌ای ═══
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 2),
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Row(
                    children: [
                      if (userMode) ...[
                        Expanded(child: _UserSpeedControl(ua: ua!)),
                        const SizedBox(width: 10),
                        _UserSeekAmountControl(ua: ua!),
                      ] else ...[
                        Expanded(child: _SpeedControl(rate: state.rate)),
                        const SizedBox(width: 10),
                        const _SeekAmountControl(),
                      ],
                    ],
                  ),
                ),
              ),

              // ═══ ردیف دکمه‌ها ═══
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // ضبط صدا (تمرینِ shadowing)
                    const MyVoiceRecorder(),

                    // بی‌صدا
                    _IconBtn(
                      icon: (userMode ? ua!.muted : state.muted)
                          ? Icons.volume_off_outlined
                          : Icons.volume_up_outlined,
                      color: (userMode ? ua!.muted : state.muted)
                          ? c.rose
                          : c.gold,
                      onTap: userMode ? ua!.toggleMuted : ctrl.toggleMuted,
                    ),

                    // 🔁 تکرار  |  صدای اپلودی: ↺ شروع از ابتدای صوت
                    if (userMode)
                      _IconBtn(
                        icon: Icons.restart_alt,
                        color: c.gold,
                        onTap: ua!.restart,
                      )
                    else
                      _IconBtn(
                        icon: Icons.repeat,
                        color: state.globalRepeat != 0 ? c.gold : c.inkSoft,
                        onTap: ctrl.cycleRepeat,
                        badge: state.globalRepeat == -1
                            ? '∞'
                            : (state.globalRepeat == 0
                                ? null
                                : '${state.globalRepeat}'),
                      ),

                    // A-B — همیشه فعال؛ اگر چیزی پخش نمی‌شود اول متنِ صفحه را شروع می‌کند
                    _ABBtn(
                      abState: userMode ? ua!.abState.name : state.abState,
                      color: c.gold,
                      idleColor: c.ink,
                      onTap: () async {
                        if (userMode) {
                          ua!.markAB();
                          return;
                        }
                        if (!_isActive(ref)) {
                          final ok = await _startMain(context, ref);
                          if (!ok) return;
                        }
                        ctrl.markAB();
                      },
                    ),

                    // بعدی — تپ: جمله‌ی بعد | نگه‌داشتن: پرشِ N ثانیه‌ای جلو
                    _HoldSeekBtn(
                      icon: Icons.skip_next,
                      color: c.ink,
                      onTap: () async {
                        if (userMode) {
                          await ua!.nextLine();
                          return;
                        }
                        if (_isActive(ref)) {
                          await ctrl.nextChunk();
                        } else {
                          await _startMain(context, ref);
                        }
                      },
                      onStep: () => userMode
                          ? ua!.skip(ref.read(seekAmountProvider))
                          : _seekStep(ref, 1),
                    ),

                    // پخش/توقف — همیشه فعال
                    _PlayBtn(
                      isPlaying: userMode ? ua!.isPlaying : isPlaying,
                      onTap: () async {
                        if (userMode) {
                          await ua!.toggle();
                          return;
                        }
                        final ok = await syncPlayPause(ref);
                        if (!ok && context.mounted) _toastNoText(context);
                      },
                    ),

                    // قبلی — تپ: جمله‌ی قبل | نگه‌داشتن: پرشِ N ثانیه‌ای عقب
                    _HoldSeekBtn(
                      icon: Icons.skip_previous,
                      color: c.ink,
                      onTap: () async {
                        if (userMode) {
                          await ua!.prevLine();
                          return;
                        }
                        if (_isActive(ref)) {
                          await ctrl.prevChunk();
                        } else {
                          await _startMain(context, ref);
                        }
                      },
                      onStep: () => userMode
                          ? ua!.skip(-ref.read(seekAmountProvider))
                          : _seekStep(ref, -1),
                    ),

                    // شفافیتِ پلیر
                    _IconBtn(
                      icon: Icons.opacity,
                      color: opacityOpen ? c.gold : c.inkSoft,
                      onTap: () => ref
                          .read(playerOpacityPanelOpenProvider.notifier)
                          .state = !opacityOpen,
                    ),

                    // ↻ رفتن به بالای صفحه
                    _IconBtn(
                      icon: Icons.vertical_align_top_rounded,
                      color: c.gold,
                      onTap: () => GlobalScroll.toTop(),
                    ),
                  ],
                ),
              ),

              // ═══ ردیفِ اسلایدرِ شفافیت ═══
              if (opacityOpen) const _OpacityRow(),
            ],
          ),
        ),
      );
    }

    final Widget bar = uaCtrl == null
        ? buildBar(null)
        : ListenableBuilder(
            listenable: uaCtrl,
            builder: (_, __) => buildBar(uaCtrl),
          );

    return Stack(
      children: [
        Opacity(opacity: opacity / 100, child: bar),
        // وقتی پلیر تقریباً نامرئی شد، دکمه‌ی بازنشانی بیرون از اثرِ Opacity
        // می‌ماند تا برگرداندنش سخت نشود.
        if (opacity <= 7)
          Positioned(
            left: 10,
            top: 10,
            child: Material(
              color: c.paper,
              shape: CircleBorder(side: BorderSide(color: c.cardBorder)),
              elevation: 3,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () =>
                    ref.read(playerOpacityProvider.notifier).set(100),
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: Icon(Icons.restart_alt, size: 18, color: c.gold),
                ),
              ),
            ),
          ),
      ],
    );
  }

  bool _isActive(WidgetRef ref) {
    final s = ref.read(speechControllerProvider);
    if (s.status == SpeechStatus.idle || s.key == null) return false;
    // فقط وقتی متنِ در حال پخش مالِ همین صفحه است «جمله‌ی بعد/قبل» کار کند؛
    // اگر متنِ صفحه‌ی قبلی است، متنِ همین صفحه از اول شروع می‌شود.
    final tracks = ref.read(playerSyncProvider).tracks;
    if (!tracks.values.any((t) => t.fullText.isNotEmpty)) return true;
    return tracks.values.any((t) => t.key == s.key);
  }

  Future<bool> _startMain(BuildContext context, WidgetRef ref) async {
    final ok = await syncPlayMainTrack(ref);
    if (!ok && context.mounted) _toastNoText(context);
    return ok;
  }

  void _toastNoText(BuildContext context) {
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(
      const SnackBar(
        content: Text('در این صفحه متنی برای خواندن نیست'),
        duration: Duration(seconds: 1),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final String? badge;

  const _IconBtn({
    required this.icon,
    required this.color,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 22, color: color),
          ),
        ),
        if (badge != null)
          Positioned(
            top: 2,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                badge!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
class _ABBtn extends StatelessWidget {
  final String abState;
  final Color color;
  final Color idleColor;
  final VoidCallback onTap;

  const _ABBtn({
    required this.abState,
    required this.color,
    required this.idleColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = abState == 'waitingB' || abState == 'looping';
    final badge = abState == 'waitingB'
        ? 'A'
        : (abState == 'looping' ? '↻' : null);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'A-B',
              style: TextStyle(
                color: active ? color : idleColor,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
        ),
        if (badge != null)
          Positioned(
            top: 0,
            right: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                badge,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
class _PlayBtn extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onTap;

  const _PlayBtn({
    required this.isPlaying,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;

    return Material(
      color: c.gold,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(
            isPlaying ? Icons.pause : Icons.play_arrow,
            color: c.paper,
            size: 28,
          ),
        ),
      ),
    );
  }
}

/// پرشِ چندثانیه‌ای (تخمینی، بر اساسِ طولِ کاراکتریِ متن — مثل Hope).
void _seekStep(WidgetRef ref, int dir) {
  final st = ref.read(speechControllerProvider);
  if (st.status == SpeechStatus.idle || st.key == null || st.total == 0) {
    return;
  }
  final ctrl = ref.read(speechControllerProvider.notifier);
  final meta = ctrl.chunksMeta;
  final fullLen = ctrl.fullTextLength;
  if (meta.isEmpty || fullLen == 0) return;
  final msPerChar = _kMsPerChar / math.max(st.rate, 0.25);
  final secs = ref.read(seekAmountProvider);
  final deltaChars = (secs * 1000 / msPerChar) * dir;
  final curChar =
      st.chunkIndex < meta.length ? meta[st.chunkIndex].start : 0;
  final target = (curChar + deltaChars).clamp(0, fullLen).toDouble();
  var idx = 0;
  for (var i = 0; i < meta.length; i++) {
    if (target >= meta[i].start) idx = i;
  }
  ctrl.seekToChunk(idx);
}

// ═══════════════════════════════════════════════════════════════════
/// دکمه‌ی کوچکِ گرد (−/+) مثل Hope.
class _MiniBtn extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  const _MiniBtn(
      {required this.label, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: c.cardBorder),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: c.gold,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

SliderThemeData _sliderTheme(BuildContext context) {
  final c = context.appColors;
  return SliderTheme.of(context).copyWith(
    trackHeight: 3,
    activeTrackColor: c.gold,
    inactiveTrackColor: c.goldSoft,
    thumbColor: c.gold,
    overlayColor: c.gold.withOpacity(0.15),
    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
  );
}

// ═══════════════════════════════════════════════════════════════════
/// سرعت پخش — دکمه‌ی −، اسلایدر، دکمه‌ی +، عدد (مثل SpeedControl در Hope).
class _SpeedControl extends ConsumerWidget {
  final double rate;
  const _SpeedControl({required this.rate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final ctrl = ref.read(speechControllerProvider.notifier);
    void step(double d) =>
        ctrl.setRate((((rate + d) * 10).round() / 10).clamp(0.25, 2.0));

    return Row(
      children: [
        Icon(Icons.speed, size: 16, color: c.inkSoft),
        const SizedBox(width: 4),
        _MiniBtn(label: '−', enabled: rate > 0.25, onTap: () => step(-0.1)),
        Expanded(
          child: SliderTheme(
            data: _sliderTheme(context),
            child: Slider(
              value: rate.clamp(0.25, 2.0),
              min: 0.25,
              max: 2.0,
              divisions: 35,
              onChanged: (v) => ctrl.setRate(v),
            ),
          ),
        ),
        _MiniBtn(label: '+', enabled: rate < 2.0, onTap: () => step(0.1)),
        const SizedBox(width: 4),
        SizedBox(
          width: 30,
          child: Text(
            '${rate.toStringAsFixed(1)}×',
            style: TextStyle(color: c.inkSoft, fontSize: 11),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
/// دکمه‌های پرشِ N ثانیه‌ای عقب/جلو (مثل اپ‌های پادکست): فلشِ چرخشی + عدد.
/// تپ = پرش؛ لمسِ طولانی = تغییرِ N (۵ → ۱۰ → ۱۵ → … → ۶۰ → ۵).
class _SeekAmountControl extends ConsumerWidget {
  const _SeekAmountControl();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final amount = ref.watch(seekAmountProvider);
    final n = ref.read(seekAmountProvider.notifier);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SkipBtn(
          icon: Icons.replay,
          amount: amount,
          onTap: () => _seekStep(ref, -1),
          onLongPress: n.cycle,
        ),
        _SkipBtn(
          icon: Icons.refresh,
          amount: amount,
          onTap: () => _seekStep(ref, 1),
          onLongPress: n.cycle,
        ),
      ],
    );
  }
}

class _SkipBtn extends StatelessWidget {
  final IconData icon;
  final int amount;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _SkipBtn({
    required this.icon,
    required this.amount,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: SizedBox(
          width: 30,
          height: 30,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: 30, color: c.gold),
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  '$amount',
                  style: TextStyle(
                    fontSize: 9,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    color: c.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
/// ردیفِ اسلایدرِ شفافیتِ پلیر (کفِ پلیر).
class _OpacityRow extends ConsumerWidget {
  const _OpacityRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final v = ref.watch(playerOpacityProvider);
    final n = ref.read(playerOpacityProvider.notifier);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.cardBorder)),
      ),
      child: Row(
        children: [
          Text('شفافیت', style: TextStyle(fontSize: 11, color: c.inkSoft)),
          Expanded(
            child: SliderTheme(
              data: _sliderTheme(context),
              child: Slider(
                value: v.toDouble(),
                min: 0,
                max: 100,
                onChanged: (x) => n.set(x.round()),
              ),
            ),
          ),
          SizedBox(
            width: 34,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Text('$v%',
                  style: TextStyle(fontSize: 11, color: c.inkSoft)),
            ),
          ),
          GestureDetector(
            onTap: () => n.set(100),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.restart_alt, size: 18, color: c.gold),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
/// دکمه‌ی قبلی/بعدی: تپِ کوتاه = [onTap]؛ نگه‌داشتنِ بیش از ~نیم‌ثانیه =
/// پرشِ چندثانیه‌ای که تا وقتی انگشت هست تکرار می‌شود ([onStep]).
class _HoldSeekBtn extends StatefulWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback onStep;
  const _HoldSeekBtn({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.onStep,
  });

  @override
  State<_HoldSeekBtn> createState() => _HoldSeekBtnState();
}

class _HoldSeekBtnState extends State<_HoldSeekBtn> {
  static const _holdMs = 550;
  static const _repeatMs = 320;
  static const _moveTolerance = 12.0;

  Timer? _hold;
  Timer? _repeat;
  bool _fired = false;
  bool _down = false;
  Offset _start = Offset.zero;

  void _clear() {
    _hold?.cancel();
    _repeat?.cancel();
    _hold = null;
    _repeat = null;
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  void _onDown(PointerDownEvent e) {
    _clear();
    _fired = false;
    _down = true;
    _start = e.position;
    _hold = Timer(const Duration(milliseconds: _holdMs), () {
      _fired = true;
      widget.onStep();
      _repeat = Timer.periodic(
        const Duration(milliseconds: _repeatMs),
        (_) => widget.onStep(),
      );
    });
  }

  void _onMove(PointerMoveEvent e) {
    if (_hold == null) return;
    if ((e.position - _start).distance > _moveTolerance) _clear();
  }

  void _onUp(PointerUpEvent e) {
    if (!_down) return;
    _down = false;
    final fired = _fired;
    _clear();
    if (!fired) widget.onTap();
  }

  void _onCancel(PointerCancelEvent e) {
    _down = false;
    _clear();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: _onCancel,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(widget.icon, size: 22, color: widget.color),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
/// نوارِ پیشرفتِ کشیدنی: زمانِ فعلی — نوار — زمانِ کل (تخمینی، مثل Hope).
class _ProgressTrack extends ConsumerStatefulWidget {
  const _ProgressTrack();

  @override
  ConsumerState<_ProgressTrack> createState() => _ProgressTrackState();
}

class _ProgressTrackState extends ConsumerState<_ProgressTrack> {
  double? _dragPct;

  static String _fmt(double ms) {
    final s = math.max(0, (ms / 1000).round());
    final m = s ~/ 60;
    final r = s % 60;
    return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final state = ref.watch(speechControllerProvider);
    final ctrl = ref.read(speechControllerProvider.notifier);

    final isActive =
        state.status != SpeechStatus.idle && state.key != null && state.total > 0;
    final List<TextChunk> meta = isActive ? ctrl.chunksMeta : const <TextChunk>[];
    final fullLen = isActive ? ctrl.fullTextLength : 0;
    final msPerChar = _kMsPerChar / math.max(state.rate, 0.25);
    final totalMs = fullLen * msPerChar;
    final chunkStart = (isActive && state.chunkIndex < meta.length)
        ? meta[state.chunkIndex].start
        : 0;
    final restPct = fullLen > 0 ? (chunkStart / fullLen) * 100 : 0.0;
    final shown = (_dragPct ?? restPct).clamp(0.0, 100.0);

    int idxFromPct(double pct) {
      if (meta.isEmpty || fullLen == 0) return 0;
      final target = pct / 100 * fullLen;
      var idx = 0;
      for (var i = 0; i < meta.length; i++) {
        if (target >= meta[i].start) idx = i;
      }
      return idx;
    }

    final timeStyle = TextStyle(
      fontSize: 12,
      color: c.inkSoft,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            SizedBox(
              width: 38,
              child: Text(
                isActive ? _fmt(shown / 100 * totalMs) : '00:00',
                textAlign: TextAlign.center,
                style: timeStyle,
              ),
            ),
            Expanded(
              child: LayoutBuilder(builder: (ctx, box) {
                final w = box.maxWidth;
                double pctAt(double dx) =>
                    w <= 0 ? 0 : (dx / w * 100).clamp(0.0, 100.0);
                void commit() {
                  final p = _dragPct;
                  setState(() => _dragPct = null);
                  if (p != null && isActive) ctrl.seekToChunk(idxFromPct(p));
                }

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: isActive
                      ? (d) => setState(() => _dragPct = pctAt(d.localPosition.dx))
                      : null,
                  onTapUp: isActive ? (_) => commit() : null,
                  onTapCancel: () => setState(() => _dragPct = null),
                  onHorizontalDragStart: isActive
                      ? (d) => setState(() => _dragPct = pctAt(d.localPosition.dx))
                      : null,
                  onHorizontalDragUpdate: isActive
                      ? (d) => setState(() => _dragPct = pctAt(d.localPosition.dx))
                      : null,
                  onHorizontalDragEnd: isActive ? (_) => commit() : null,
                  onHorizontalDragCancel: () => setState(() => _dragPct = null),
                  child: Opacity(
                    opacity: isActive ? 1 : 0.45,
                    child: SizedBox(
                      height: 24,
                      child: Stack(
                        alignment: Alignment.centerLeft,
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            height: 4,
                            decoration: BoxDecoration(
                              color: c.goldSoft,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          if (isActive && meta.length > 1 && fullLen > 0)
                            for (var i = 1; i < meta.length; i++)
                              Positioned(
                                left: w * meta[i].start / fullLen,
                                child: Container(
                                  width: 2,
                                  height: 4,
                                  color: c.ink.withOpacity(0.3),
                                ),
                              ),
                          Container(
                            width: w * shown / 100,
                            height: 4,
                            decoration: BoxDecoration(
                              color: c.gold,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          Positioned(
                            left: w * shown / 100 - 7.5,
                            child: Container(
                              width: 15,
                              height: 15,
                              decoration: BoxDecoration(
                                color: c.gold,
                                shape: BoxShape.circle,
                                border: Border.all(color: c.paper, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: c.ink.withOpacity(0.35),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
            SizedBox(
              width: 38,
              child: Text(
                isActive ? _fmt(totalMs) : '00:00',
                textAlign: TextAlign.center,
                style: timeStyle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// ═══════════════════════════════════════════════════════════════════
// 🎧 صدای اپلودیِ داستان روی پلیرِ اصلی (معادلِ PlayerBarStorySwitch و
// UserAudio* در Hope)

String _fmtMs(double ms) {
  final t = math.max(0, (ms / 1000).round());
  final m = t ~/ 60;
  final r = t % 60;
  return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
}

/// سوییچِ دوحالته‌ی «صدای اپ ⇄ صدای اپلودی» بالای نوارِ پیشرفت.
class _StorySourceSwitch extends ConsumerWidget {
  final StoryAudioController ua;
  final bool userMode;
  const _StorySourceSwitch({required this.ua, required this.userMode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final L = context.l10n;

    Widget seg(String label, bool on, bool enabled, VoidCallback onTap) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          decoration: BoxDecoration(
            color: on ? c.teal : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: on ? Colors.white : (enabled ? c.ink : c.cardBorder),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            border: Border.all(color: c.cardBorder),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              seg(L.player_app_voice, !userMode, true, () {
                ref.read(storyPlaybackModeProvider.notifier).state = 'tts';
                ua.pause();
              }),
              const SizedBox(width: 4),
              seg(L.player_my_audio, userMode, ua.hasAudio, () {
                ref.read(storyPlaybackModeProvider.notifier).state = 'user';
                ref.read(speechControllerProvider.notifier).stop();
              }),
            ],
          ),
        ),
      ),
    );
  }
}

/// نوارِ پیشرفتِ صدای اپلودی: زمانِ فعلی — اسلایدر — زمانِ کل.
class _UserProgressTrack extends StatelessWidget {
  final StoryAudioController ua;
  const _UserProgressTrack({required this.ua});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final timeStyle = TextStyle(
      fontSize: 12,
      color: c.inkSoft,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: ValueListenableBuilder<Duration>(
          valueListenable: ua.position,
          builder: (_, pos, __) {
            final total = ua.duration.inMilliseconds.toDouble();
            final cur = pos.inMilliseconds
                .toDouble()
                .clamp(0.0, total > 0 ? total : 1.0)
                .toDouble();
            return Row(
              children: [
                SizedBox(
                  width: 38,
                  child: Text(_fmtMs(cur),
                      textAlign: TextAlign.center, style: timeStyle),
                ),
                Expanded(
                  child: SliderTheme(
                    data: _sliderTheme(context),
                    child: Slider(
                      value: cur,
                      min: 0,
                      max: total > 0 ? total : 1,
                      onChanged: total > 0
                          ? (v) => ua.seek(Duration(milliseconds: v.round()))
                          : null,
                    ),
                  ),
                ),
                SizedBox(
                  width: 38,
                  child: Text(_fmtMs(total),
                      textAlign: TextAlign.center, style: timeStyle),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// سرعتِ صدای اپلودی — هم‌شکلِ _SpeedControl، ولی روی کنترلرِ فایل (۰٫۵× تا ۲×).
class _UserSpeedControl extends StatelessWidget {
  final StoryAudioController ua;
  const _UserSpeedControl({required this.ua});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final rate = ua.rate;
    void step(double d) =>
        ua.setRate((((rate + d) * 10).round() / 10).clamp(0.5, 2.0));
    return Row(
      children: [
        Icon(Icons.speed, size: 16, color: c.inkSoft),
        const SizedBox(width: 4),
        _MiniBtn(label: '−', enabled: rate > 0.5, onTap: () => step(-0.1)),
        Expanded(
          child: SliderTheme(
            data: _sliderTheme(context),
            child: Slider(
              value: rate.clamp(0.5, 2.0),
              min: 0.5,
              max: 2.0,
              divisions: 30,
              onChanged: (v) => ua.setRate(v),
            ),
          ),
        ),
        _MiniBtn(label: '+', enabled: rate < 2.0, onTap: () => step(0.1)),
        const SizedBox(width: 4),
        SizedBox(
          width: 30,
          child: Text(
            '${rate.toStringAsFixed(1)}×',
            style: TextStyle(color: c.inkSoft, fontSize: 11),
          ),
        ),
      ],
    );
  }
}

/// پرشِ N ثانیه‌ای عقب/جلو برای صدای اپلودی (تپ = پرش، لمسِ طولانی = تغییرِ N).
class _UserSeekAmountControl extends ConsumerWidget {
  final StoryAudioController ua;
  const _UserSeekAmountControl({required this.ua});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final amount = ref.watch(seekAmountProvider);
    final n = ref.read(seekAmountProvider.notifier);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SkipBtn(
          icon: Icons.replay,
          amount: amount,
          onTap: () => ua.skip(-amount),
          onLongPress: n.cycle,
        ),
        _SkipBtn(
          icon: Icons.refresh,
          amount: amount,
          onTap: () => ua.skip(amount),
          onLongPress: n.cycle,
        ),
      ],
    );
  }
}
