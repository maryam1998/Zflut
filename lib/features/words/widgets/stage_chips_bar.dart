import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/level_colors.dart';
import '../../../core/providers/primary_school_provider.dart';
import '../../../core/providers/words_filter_provider.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/widgets/category_grid.dart' show categoryAllOpenProvider;

/// آیا چیپِ «تمرین‌ها» (کنارِ A1 یا A2) باز است؟ (تمرین‌های درک شنیداری، ساخت سؤال، نوشتن)
final primaryPracticeOpenProvider = StateProvider<bool>((ref) => false);

/// ردیفِ چیپ‌های مرحله (مشترک بین تبِ لغات و تبِ مکالمه):
///   [همه] [Preschool·A1] [Primary School·A2] [Lower Secondary·B1]
///   [Upper Secondary·B2] [Undergraduate / Master's·C1] [Postgraduate / Doctorate·C2]
/// [selected] = null → «همه»؛ وگرنه کدِ سطح ('A1'…'C2').
class StageChips extends StatelessWidget {
  final String? selected;
  final ValueChanged<String?> onSelect;

  /// اگر داده شود، کنارِ چیپِ A2 چیپِ «تمرین‌ها» نشان داده می‌شود (فقط تبِ لغات)
  final ValueChanged<String>? onPractice; // با سطح: 'A1' یا 'A2'
  final bool practiceActive;

  /// سطحی که تمرینش باز است ('A1' یا 'A2')؛ فقط وقتی [practiceActive] است معنی دارد
  final String practiceLevel;

  /// true (فقط تبِ مکالمه): [همه] + چیپ‌های جدیدِ مقاطعِ تحصیلی؛
  /// چیپ‌های جدیدِ مرحله‌ها (Preschool … Postgraduate) با کدِ 'P-A1' … 'P-C2'. (تبِ «همه» و سطح‌هایش دست‌نخورده می‌مانند)
  final bool levelsPlusPrimary;
  const StageChips({
    super.key,
    required this.selected,
    required this.onSelect,
    this.onPractice,
    this.practiceActive = false,
    this.practiceLevel = 'A2',
    this.levelsPlusPrimary = false,
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
    if (levelsPlusPrimary) {
      // تبِ مکالمه: [همه] + مقاطعِ تحصیلیِ جدید (کدِ 'P-A1' … 'P-C1' = پیشوندِ شناسه‌ی مکالمه‌ها p-a1-…)
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
            for (final st in const <(String, String, IconData)>[
              ('A1', kPreschoolChipLabel, Icons.child_care_rounded),
              ('A2', kPrimaryChipLabel, Icons.school_rounded),
              ('B1', 'Secondary School', Icons.workspace_premium_rounded),
              ('B2', 'Sixth Form / College', Icons.workspace_premium_rounded),
              ('C1', 'University', Icons.workspace_premium_rounded),
            ]) ...[
              const SizedBox(width: 7),
              Center(
                child: _StageChip(
                  label: st.$2,
                  icon: st.$3,
                  active: selected == 'P-${st.$1}',
                  color: levelColor(st.$1),
                  onTap: () => onSelect('P-${st.$1}'),
                ),
              ),
            ],
          ],
        ),
      );
    }
    return SizedBox(
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Center(
            child: _StageChip(
              label: allLabel,
              active: selected == null && !practiceActive,
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
                active: selected == st.$1 && !practiceActive,
                color: levelColor(st.$1),
                onTap: () => onSelect(st.$1),
              ),
            ),
            if ((st.$1 == 'A1' || st.$1 == 'A2') && onPractice != null) ...[
              const SizedBox(width: 7),
              Center(
                child: _StageChip(
                  label: (ui == 'fa' || ui == 'ar') ? 'تمرین‌ها' : 'Practice',
                  icon: Icons.fitness_center_rounded,
                  active: practiceActive && practiceLevel == st.$1,
                  color: levelColor(st.$1),
                  onTap: () => onPractice!(st.$1),
                ),
              ),
            ],
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

    final practice = ref.watch(primaryPracticeOpenProvider);

    void reset() {
      ref.read(primaryTopicProvider.notifier).state = null;
      ref.read(categoryAllOpenProvider('primary').notifier).state = false;
      ref.read(primaryPracticeOpenProvider.notifier).state = false;
    }

    return StageChips(
      selected: selected,
      practiceActive: practice,
      practiceLevel: ref.watch(primaryLevelProvider),
      onPractice: (pl) {
        reset();
        ref.read(wordsFilterProvider.notifier).setLevels(<String>{});
        ref.read(primaryLevelProvider.notifier).state = pl;
        ref.read(wordsStageProvider.notifier).state = kStagePrimary;
        ref.read(primaryPracticeOpenProvider.notifier).state = true;
      },
      onSelect: (lv) {
        reset();
        ref.read(wordsFilterProvider.notifier).setLevels(
            lv == null || lv == 'A1' || lv == 'A2' || lv == 'B1'
                ? <String>{}
                : {lv});
        if (lv == 'A1' || lv == 'A2' || lv == 'B1') {
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
