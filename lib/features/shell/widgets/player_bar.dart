import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/player_sync/sync_widgets.dart';
import '../../../core/providers/speech_provider.dart';
import '../../../core/scroll/global_scroll.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/tts/speech_state.dart';

class PlayerBar extends ConsumerWidget {
  const PlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final state = ref.watch(speechControllerProvider);
    final ctrl = ref.read(speechControllerProvider.notifier);

    final isActive = state.status != SpeechStatus.idle && state.key != null;
    final isPlaying = state.status == SpeechStatus.playing;
    final progress =
        (isActive && state.total > 0) ? (state.chunkIndex + 1) / state.total : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: c.paper,
        border: Border(top: BorderSide(color: c.cardBorder, width: 1)),
        boxShadow: [
          BoxShadow(
            color: c.ink.withOpacity(0.08),
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
            // ═══ نوار پیشرفت ═══
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
              child: Row(
                children: [
                  Text(
                    isActive ? '${state.chunkIndex + 1}' : '0',
                    style: TextStyle(
                      fontSize: 11,
                      color: c.inkSoft,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        backgroundColor: c.cardBorder,
                        valueColor: AlwaysStoppedAnimation(c.gold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isActive ? '${state.total}' : '0',
                    style: TextStyle(
                      fontSize: 11,
                      color: c.inkSoft,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),

            // ═══ ردیف دکمه‌ها ═══
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // ضبط صدا
                  _IconBtn(
                    icon: Icons.mic_none_outlined,
                    color: c.rose,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('ضبط صدا به‌زودی'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                  ),

                  // بی‌صدا
                  _IconBtn(
                    icon: state.muted
                        ? Icons.volume_off_outlined
                        : Icons.volume_up_outlined,
                    color: state.muted ? c.rose : c.gold,
                    onTap: ctrl.toggleMuted,
                  ),

                  // 🔁 تکرار
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
                    abState: state.abState,
                    color: c.gold,
                    idleColor: c.ink,
                    onTap: () async {
                      if (!_isActive(ref)) {
                        final ok = await _startMain(context, ref);
                        if (!ok) return;
                      }
                      ctrl.markAB();
                    },
                  ),

                  // قبلی — همیشه فعال
                  _IconBtn(
                    icon: Icons.skip_previous,
                    color: c.ink,
                    onTap: () async {
                      if (_isActive(ref)) {
                        await ctrl.prevChunk();
                      } else {
                        await _startMain(context, ref);
                      }
                    },
                  ),

                  // پخش/توقف — همیشه فعال
                  _PlayBtn(
                    isPlaying: isPlaying,
                    onTap: () async {
                      final ok = await syncPlayPause(ref);
                      if (!ok && context.mounted) _toastNoText(context);
                    },
                  ),

                  // بعدی — همیشه فعال
                  _IconBtn(
                    icon: Icons.skip_next,
                    color: c.ink,
                    onTap: () async {
                      if (_isActive(ref)) {
                        await ctrl.nextChunk();
                      } else {
                        await _startMain(context, ref);
                      }
                    },
                  ),

                  // سرعت
                  _SpeedBtn(
                    rate: state.rate,
                    color: c.gold,
                    onTap: () => _showSpeedSheet(context, ref),
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
          ],
        ),
      ),
    );
  }

  bool _isActive(WidgetRef ref) {
    final s = ref.read(speechControllerProvider);
    return s.status != SpeechStatus.idle && s.key != null;
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

  void _showSpeedSheet(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(speechControllerProvider.notifier);
    final state = ref.read(speechControllerProvider);
    final c = context.appColors;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: c.paper,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.speed, color: c.gold),
                const SizedBox(width: 10),
                Text(
                  'سرعت پخش',
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    '${state.rate.toStringAsFixed(1)}×',
                    style: TextStyle(
                      color: c.gold,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Slider(
              value: state.rate,
              min: 0.25,
              max: 2.0,
              divisions: 35,
              activeColor: c.gold,
              inactiveColor: c.cardBorder,
              onChanged: (v) => ctrl.setRate(v),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((r) {
                final selected = (state.rate - r).abs() < 0.01;
                return GestureDetector(
                  onTap: () => ctrl.setRate(r),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected ? c.gold : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected ? c.gold : c.cardBorder,
                        width: 1,
                      ),
                    ),
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        '$r×',
                        style: TextStyle(
                          color: selected ? c.paper : c.ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
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

// ═══════════════════════════════════════════════════════════════════
class _SpeedBtn extends StatelessWidget {
  final double rate;
  final Color color;
  final VoidCallback onTap;

  const _SpeedBtn({
    required this.rate,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Text(
            '${rate.toStringAsFixed(1)}×',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
