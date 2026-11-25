import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/level_colors.dart';
import '../../../core/providers/primary_school_provider.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/widgets/category_grid.dart' show categoryAllOpenProvider;

/// ردیفِ بالای تبِ «دیکشنری من»:
///   [همه]  [Primary School]
/// و وقتی Primary School انتخاب است، زیرش چیپِ سطح: [A1]
class StageChipsBar extends ConsumerWidget {
  const StageChipsBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stage = ref.watch(wordsStageProvider);
    final ui = Localizations.localeOf(context).languageCode;
    final allLabel = (ui == 'fa' || ui == 'ar') ? 'همه' : 'All';
    final primary = stage == kStagePrimary;

    void reset() {
      ref.read(primaryTopicProvider.notifier).state = null;
      ref.read(categoryAllOpenProvider('primary').notifier).state = false;
    }

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
                  onTap: () {
                    reset();
                    ref.read(wordsStageProvider.notifier).state = null;
                  },
                ),
              ),
              const SizedBox(width: 7),
              Center(
                child: _StageChip(
                  label: kPrimaryChipLabel,
                  icon: Icons.school_rounded,
                  active: primary,
                  onTap: () {
                    reset();
                    ref.read(wordsStageProvider.notifier).state =
                        kStagePrimary;
                  },
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
                Center(
                  child: _StageChip(
                    label: 'A1',
                    active: true,
                    color: levelColor('A1'),
                    small: true,
                    onTap: reset, // برگشت به شبکه‌ی موضوع‌ها
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
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
