import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/level_colors.dart';
import '../../../core/providers/primary_school_provider.dart';
import '../../../core/providers/words_filter_provider.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/widgets/category_grid.dart' show categoryAllOpenProvider;
import '../../../core/widgets/level_chips.dart' show LevelChip;

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

/// نسخه‌ی تبِ لغات (با providerها): دو ردیفِ جدا
///  ۱) CEFR:  [همه] [A1] [A2] [B1] [B2] [C1] [C2]   ← همه‌ی لغاتِ اصلی، فیلتر بر اساسِ سطح
///  ۲) مقطعِ تحصیلی: [Preschool] [Primary School] [Lower Secondary]
///     [Upper Secondary / Pre-University] [University & Adults]
///     (دو مقطعِ آخر فعلاً خالی‌اند و بعداً با لغاتِ جدید پر می‌شوند)
class StageChipsBar extends ConsumerWidget {
  const StageChipsBar({super.key});

  static const List<(String, String, IconData)> _eduStages = [
    ('A1', kPreschoolChipLabel, Icons.child_care_rounded),
    ('A2', kPrimaryChipLabel, Icons.school_rounded),
    ('B1', kLowerSecondaryChipLabel, Icons.workspace_premium_rounded),
    (kStageUpper, kUpperSecondaryChipLabel, Icons.workspace_premium_rounded),
    (kStageUniversity, kUniversityChipLabel, Icons.workspace_premium_rounded),
  ];

  static Color _eduColor(String key) {
    switch (key) {
      case kStageUpper:
        return levelColor('B2');
      case kStageUniversity:
        return levelColor('C1');
      default:
        return levelColor(key);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final ui = Localizations.localeOf(context).languageCode;
    final fa = ui == 'fa' || ui == 'ar';
    final stage = ref.watch(wordsStageProvider); // null = دسته‌بندیِ CEFR
    final inEdu = stage != null;
    final levels = ref.watch(wordsFilterProvider.select((f) => f.levels));
    final practice = ref.watch(primaryPracticeOpenProvider);
    final primaryLevel = ref.watch(primaryLevelProvider);

    // چیپِ انتخاب‌شده در هر ردیف
    final String? cefrSelected =
        (!inEdu && levels.length == 1) ? levels.first : null;
    final String? eduSelected = stage == kStagePrimary
        ? primaryLevel
        : (stage == kStageUpper || stage == kStageUniversity ? stage : null);

    void reset() {
      ref.read(primaryTopicProvider.notifier).state = null;
      ref.read(categoryAllOpenProvider('primary').notifier).state = false;
      ref.read(primaryPracticeOpenProvider.notifier).state = false;
    }

    Widget heading(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 2),
          child: Text(
            text,
            style: TextStyle(
              color: c.inkSoft,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        );

    // ── گروهِ ۱: CEFR (چیپ‌های رنگیِ هر سطح، همان LevelChip که در بقیه‌ی تب‌ها هست) ──
    final cefrGroup = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading(fa ? 'استاندارد CEFR' : 'CEFR level'),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LevelChip(
              level: 'all',
              active: !inEdu && levels.isEmpty,
              allLabel: fa ? 'همه' : 'All',
              onTap: () {
                reset();
                ref.read(wordsStageProvider.notifier).state = null;
                ref.read(wordsFilterProvider.notifier).setLevels(<String>{});
              },
            ),
            for (final lv in const ['A1', 'A2', 'B1', 'B2', 'C1', 'C2']) ...[
              const SizedBox(width: 7),
              LevelChip(
                level: lv,
                active: cefrSelected == lv,
                onTap: () {
                  reset();
                  ref.read(wordsStageProvider.notifier).state = null;
                  ref.read(wordsFilterProvider.notifier).setLevels({lv});
                },
              ),
            ],
          ],
        ),
      ],
    );

    // ── گروهِ ۲: مقطعِ تحصیلی (رنگِ هر چیپ = رنگِ سطحِ معادلش) ──
    // زیرِ تب‌های Preschool / Primary / Lower Secondary چیپِ Practice همان تب قرار دارد.
    Widget stageColumn((String, String, IconData) st) {
      final hasPractice = st.$1 == 'A1' || st.$1 == 'A2' || st.$1 == 'B1';
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _EduChip(
            label: st.$2,
            icon: st.$3,
            color: _eduColor(st.$1),
            active: eduSelected == st.$1 && !practice,
            onTap: () {
              reset();
              ref.read(wordsFilterProvider.notifier).setLevels(<String>{});
              if (st.$1 == kStageUpper || st.$1 == kStageUniversity) {
                ref.read(wordsStageProvider.notifier).state = st.$1;
              } else {
                ref.read(primaryLevelProvider.notifier).state = st.$1;
                ref.read(wordsStageProvider.notifier).state = kStagePrimary;
              }
            },
          ),
          if (hasPractice) ...[
            const SizedBox(height: 6),
            _EduChip(
              label: fa ? 'تمرین‌ها' : 'Practice',
              icon: Icons.fitness_center_rounded,
              color: levelColor(st.$1),
              active: practice &&
                  stage == kStagePrimary &&
                  primaryLevel == st.$1,
              onTap: () {
                reset();
                ref.read(wordsFilterProvider.notifier).setLevels(<String>{});
                ref.read(primaryLevelProvider.notifier).state = st.$1;
                ref.read(wordsStageProvider.notifier).state = kStagePrimary;
                ref.read(primaryPracticeOpenProvider.notifier).state = true;
              },
            ),
          ],
        ],
      );
    }

    final eduGroup = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading(fa ? 'مقطع تحصیلی' : 'Education stage'),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final st in _eduStages) ...[
              if (st != _eduStages.first) const SizedBox(width: 7),
              stageColumn(st),
            ],
          ],
        ),
      ],
    );

    // دو گروه کنارِ هم (هر کدام عنوان + چیپ‌های زیرش)؛ با هم افقی اسکرول می‌شوند.
    return SizedBox(
      height: 108,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          cefrGroup,
          const SizedBox(width: 22),
          eduGroup,
        ],
      ),
    );
  }
}

/// چیپِ مقطعِ تحصیلی: دقیقاً هم‌سبکِ LevelChip (پس‌زمینه/حاشیه/متنِ رنگیِ سطح؛ فعال = طلایی)، با آیکن.
class _EduChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool active;
  final VoidCallback onTap;
  const _EduChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final fill = active ? c.gold : color.withOpacity(0.14);
    final border = active ? c.gold : color;
    final text = active ? c.headerTo : color;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border, width: 1.1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: text),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: text,
                fontSize: 12.5,
                fontWeight: active ? FontWeight.w800 : FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
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
