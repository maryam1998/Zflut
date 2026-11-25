import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/level_colors.dart';
import '../../../core/providers/primary_school_provider.dart';
import '../../../core/providers/words_filter_provider.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/widgets/category_grid.dart' show categoryAllOpenProvider;

/// ردیفِ چیپ‌های مرحله (مشترک بین تبِ لغات و تبِ مکالمه):
///   [همه] [Preschool·A1] [Primary School·A2] [Lower Secondary·B1]
///   [Upper Secondary·B2] [Undergraduate / Master's·C1] [Postgraduate / Doctorate·C2]
/// [selected] = null → «همه»؛ وگرنه کدِ سطح ('A1'…'C2').
class StageChips extends StatelessWidget {
  final String? selected;
  final ValueChanged<String?> onSelect;
  const StageChips({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  static const List<(String, String)> stages = [
    ('A1', kPreschoolChipLabel),
    ('A2', kPrimaryChipLabel),
    ('B1', 'Lower Secondary'),
    ('B2', 'Upper Secondary'),
    ('C1', "Undergraduate / Master's"),
    ('C2', 'Postgraduate / Doctorate'),
  ];

  static IconData _icon(String lv) {
    switch (lv) {
      case 'A1':
        return Icons.child_care_rounded;
      case 'A2':
        return Icons.school_rounded;
      default:
        return Icons.workspace_premium_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ui = Localizations.localeOf(context).languageCode;
    final allLabel = (ui == 'fa' || ui == 'ar') ? 'همه' : 'All';
    return SizedBox(
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Center(
            child: _StageChip(
              label: allLabel,
              active: selected == null,
              onTap: () => onSelect(null),
            ),
          ),
          for (final st in stages) ...[
            const SizedBox(width: 7),
            Center(
              child: _StageChip(
                label: st.$2,
                sub: st.$1,
                icon: _icon(st.$1),
                active: selected == st.$1,
                color: levelColor(st.$1),
                onTap: () => onSelect(st.$1),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// نسخه‌ی تبِ لغات (با providerها)
class StageChipsBar extends ConsumerWidget {
  const StageChipsBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inPrimary = ref.watch(wordsStageProvider) == kStagePrimary;
    final levels = ref.watch(wordsFilterProvider.select((f) => f.levels));
    final String? selected = inPrimary
        ? ref.watch(primaryLevelProvider)
        : (levels.length == 1 ? levels.first : null);

    void reset() {
      ref.read(primaryTopicProvider.notifier).state = null;
      ref.read(categoryAllOpenProvider('primary').notifier).state = false;
    }

    return StageChips(
      selected: selected,
      onSelect: (lv) {
        reset();
        ref.read(wordsFilterProvider.notifier).setLevels(
            lv == null || lv == 'A1' || lv == 'A2' ? <String>{} : {lv});
        if (lv == 'A1' || lv == 'A2') {
          ref.read(primaryLevelProvider.notifier).state = lv!;
          ref.read(wordsStageProvider.notifier).state = kStagePrimary;
        } else {
          ref.read(wordsStageProvider.notifier).state = null;
        }
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
  final String? sub; // زیرنویسِ سطح (مثلاً A1)
  const _StageChip({
    required this.label,
    required this.active,
    required this.onTap,
    this.icon,
    this.color,
    this.small = false,
    this.sub,
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
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: active ? c.ink : c.inkSoft,
                    fontSize: small ? 12.5 : 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (sub != null)
                  Text(
                    sub!,
                    style: TextStyle(
                      color: active ? tone : c.inkSoft,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
