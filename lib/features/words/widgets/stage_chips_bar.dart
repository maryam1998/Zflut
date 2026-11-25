import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/level_colors.dart';
import '../../../core/providers/primary_school_provider.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/widgets/category_grid.dart' show categoryAllOpenProvider;

/// ردیفِ چیپ‌های مرحله (مشترک بین تبِ لغات و تبِ مکالمه):
///   [همه]  [Primary School]
/// و وقتی Primary School انتخاب است، زیرش چیپِ سطح: [A1]
class StageChips extends StatelessWidget {
  final bool primary;
  final VoidCallback onAll;
  final VoidCallback onPrimary;
  final VoidCallback onLevel;

  /// سطح‌هایی که زیرِ Primary School نشان داده می‌شوند (تبِ مکالمه فعلاً فقط A1)
  final List<String> levels;
  final String level;
  final ValueChanged<String>? onLevelChanged;
  const StageChips({
    super.key,
    required this.primary,
    required this.onAll,
    required this.onPrimary,
    required this.onLevel,
    this.levels = const ['A1'],
    this.level = 'A1',
    this.onLevelChanged,
  });

  @override
  Widget build(BuildContext context) {
    final ui = Localizations.localeOf(context).languageCode;
    final allLabel = (ui == 'fa' || ui == 'ar') ? 'همه' : 'All';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              Center(
                child: _StageChip(
                  label: allLabel,
                  active: !primary,
                  onTap: onAll,
                ),
              ),
              const SizedBox(width: 7),
              Center(
                child: _StageChip(
                  label: kPrimaryChipLabel,
                  icon: Icons.school_rounded,
                  active: primary,
                  onTap: onPrimary,
                ),
              ),
            ],
          ),
        ),
        if (primary) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final lv in levels) ...[
                  Center(
                    child: _StageChip(
                      label: lv,
                      active: lv == level,
                      color: levelColor(lv),
                      small: true,
                      onTap: () {
                        if (lv == level) {
                          onLevel(); // برگشت به شبکه‌ی موضوع‌ها
                        } else {
                          onLevelChanged?.call(lv);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 7),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// نسخه‌ی تبِ لغات (با providerها)
class StageChipsBar extends ConsumerWidget {
  const StageChipsBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primary = ref.watch(wordsStageProvider) == kStagePrimary;

    void reset() {
      ref.read(primaryTopicProvider.notifier).state = null;
      ref.read(categoryAllOpenProvider('primary').notifier).state = false;
    }

    return StageChips(
      primary: primary,
      onAll: () {
        reset();
        ref.read(wordsStageProvider.notifier).state = null;
      },
      onPrimary: () {
        reset();
        ref.read(wordsStageProvider.notifier).state = kStagePrimary;
      },
      onLevel: reset,
      levels: const ['A1', 'A2'],
      level: ref.watch(primaryLevelProvider),
      onLevelChanged: (lv) {
        reset();
        ref.read(primaryLevelProvider.notifier).state = lv;
      },
    );
  }
}

class _StageChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? color;
  final bool small;
  const _StageChip({
    required this.label,
    required this.active,
    required this.onTap,
    this.icon,
    this.color,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final tone = color ?? c.gold;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: small ? 14 : 16, vertical: small ? 6 : 8),
        decoration: BoxDecoration(
          color: active ? tone.withOpacity(0.16) : c.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? tone : c.cardBorder,
            width: active ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: active ? tone : c.inkSoft),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: active ? c.ink : c.inkSoft,
                fontSize: small ? 12.5 : 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
