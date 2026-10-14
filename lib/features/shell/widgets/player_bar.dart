import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/speech_provider.dart';
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

    return Container(
      decoration: BoxDecoration(
        color: c.paper,
        border: Border(top: BorderSide(color: c.cardBorder, width: 1)),
        boxShadow: [
          BoxShadow(
            color: c.ink.withOpacity(0.06),
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
            // ═══ نوار پیشرفت ═══
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
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
                        value: isActive && state.total > 0
                            ? (state.chunkIndex + 1) / state.total
                            : 0,
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
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // ضبط صدا
                  _IconBtn(
                    icon: Icons.mic_none_outlined,
                    color: c.rose,
                    onTap: () {},
                    size: 22,
                  ),
                  // بی‌صدا
                  _IconBtn(
                    icon: state.muted
                        ? Icons.volume_off_outlined
                        : Icons.volume_up_outlined,
                    color: state.muted ? c.rose : c.gold,
                    onTap: ctrl.toggleMuted,
                    size: 20,
                  ),
                  // تکرار
                  _IconBtn(
                    icon: Icons.repeat,
                    color: state.globalRepeat != 0 ? c.gold : c.inkSoft,
                    onTap: ctrl.cycleRepeat,
                    size: 20,
                    badge: state.globalRepeat == -1
                        ? '∞'
                        : state.globalRepeat == 0
                            ? null
                            : '${state.globalRepeat}',
                  ),
                  // A-B
                  _TextBtn(
                    label: 'A-B',
                    color: c.inkSoft,
                    onTap: isActive ? ctrl.markAB : null,
                  ),
                  // قبلی
                  _IconBtn(
                    icon: Icons.skip_previous,
                    color: isActive ? c.ink : c.cardBorder,
                    onTap: isActive ? ctrl.prevChunk : null,
                    size: 24,
                  ),
                  // پخش/توقف
                  _PlayButton(
                    isPlaying: isPlaying,
                    isActive: isActive,
                    onTap: () {
                      if (isActive && state.key != null) {
                        final parts = state.key!.split('::');
                        if (parts.length == 2) {
                          ctrl.toggle(parts[1], _codeFromLocale(parts[0]));
                        }
                      }
                    },
                  ),
                  // بعدی
                  _IconBtn(
                    icon: Icons.skip_next,
                    color: isActive ? c.ink : c.cardBorder,
                    onTap: isActive ? ctrl.nextChunk : null,
                    size: 24,
                  ),
                  // سرعت
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: c.paperDark,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: c.cardBorder),
                    ),
                    child: Text(
                      '${state.rate.toStringAsFixed(1)}×',
                      style: TextStyle(
                        color: c.gold,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  // شفافیت
                  _IconBtn(
                    icon: Icons.opacity,
                    color: c.inkSoft,
                    onTap: () {},
                    size: 18,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _codeFromLocale(String locale) {
    final map = {
      'fa-IR': 'fa', 'en-US': 'en', 'de-DE': 'de', 'es-ES': 'es',
      'fr-FR': 'fr', 'ar-SA': 'ar', 'tr-TR': 'tr', 'zh-CN': 'zh',
      'ru-RU': 'ru', 'it-IT': 'it', 'ko-KR': 'ko', 'ja-JP': 'ja',
      'hi-IN': 'hi',
    };
    return map[locale] ?? 'en';
  }
}

// ═══════════════════════════════════════════════════════════════════
class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final double size;
  final String? badge;

  const _IconBtn({
    required this.icon,
    required this.color,
    required this.onTap,
    this.size = 20,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: size, color: color),
          ),
        ),
        if (badge != null)
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(5),
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

class _TextBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _TextBtn({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  final bool isPlaying;
  final bool isActive;
  final VoidCallback onTap;

  const _PlayButton({
    required this.isPlaying,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;

    return Material(
      color: isActive ? c.gold : c.cardBorder,
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
