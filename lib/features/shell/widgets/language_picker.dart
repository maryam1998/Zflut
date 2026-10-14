import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/supported_languages.dart';
import '../../../core/providers/language_selection_provider.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/theme/screen_scale.dart';

/// اندازه‌ها بر حسب «پیکسلِ اسکرین‌شات» (context.px) هستند.
class LanguagePicker extends ConsumerWidget {
  const LanguagePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final sel = ref.watch(languageSelectionProvider);
    final notifier = ref.read(languageSelectionProvider.notifier);

    // زبان مادری — ترتیب دلخواه
    final nativeOrder = ref.watch(nativeOrderProvider);
    final nativeDefaults = kSupportedLanguages.map((l) => l.code).toList();
    final nativeOrderList = nativeOrder.isEmpty
        ? nativeDefaults
        : [
            ...nativeOrder.where(nativeDefaults.contains),
            ...nativeDefaults.where((c) => !nativeOrder.contains(c)),
          ];
    final nativeLanguages = nativeOrderList
        .map((code) => kSupportedLanguages.firstWhere((l) => l.code == code))
        .toList();

    // زبان‌های مقصد — انتخاب‌شده‌ها اول
    final targetDisplayOrder = ref.watch(targetDisplayOrderProvider);
    final selected = sel.targets.toList();
    final selectedLangs = selected
        .map((code) => kSupportedLanguages.firstWhere(
              (l) => l.code == code,
              orElse: () => kSupportedLanguages.first,
            ))
        .toList();
    final unselectedCodes = targetDisplayOrder.isEmpty
        ? kSupportedLanguages
            .where((l) => !selected.contains(l.code))
            .map((l) => l.code)
            .toList()
        : [
            ...targetDisplayOrder.where((c) =>
                !selected.contains(c) &&
                kSupportedLanguages.any((l) => l.code == c)),
            ...kSupportedLanguages
                .map((l) => l.code)
                .where((c) =>
                    !selected.contains(c) && !targetDisplayOrder.contains(c)),
          ];
    final unselectedLangs = unselectedCodes
        .map((code) => kSupportedLanguages.firstWhere((l) => l.code == code))
        .toList();

    return Padding(
      padding: EdgeInsets.only(top: context.px(38), bottom: context.px(40)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // زبان مادری
          const _SectionLabel(text: 'زبان مادری'),
          SizedBox(height: context.px(20)),
          _DragRow(
            key: const ValueKey('native-row'),
            languages: nativeLanguages,
            selectedCodes: {sel.native},
            onTap: (code) => notifier.setNative(code),
            onReorder: (oldIdx, newIdx) {
              ref
                  .read(nativeOrderProvider.notifier)
                  .reorder(nativeOrderList, oldIdx, newIdx);
            },
          ),

          // خط جداکننده
          SizedBox(height: context.px(34)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: context.px(34)),
            child: Container(
              height: context.px(2),
              color: c.headerText.withOpacity(0.16),
            ),
          ),
          SizedBox(height: context.px(30)),

          // زبان‌های مقصد
          const _SectionLabel(text: 'زبان‌های مقصد'),
          SizedBox(height: context.px(20)),
          _DragRow(
            key: const ValueKey('target-row'),
            languages: [...selectedLangs, ...unselectedLangs],
            selectedCodes: selected.toSet(),
            onTap: (code) => notifier.toggleTarget(code),
            onReorder: (oldIdx, newIdx) {
              if (oldIdx < selected.length && newIdx <= selected.length) {
                notifier.reorderTargets(oldIdx, newIdx);
              } else {
                final allLangs = [...selectedLangs, ...unselectedLangs]
                    .map((l) => l.code)
                    .toList();
                ref
                    .read(targetDisplayOrderProvider.notifier)
                    .reorder(allLangs, oldIdx, newIdx);
              }
            },
          ),

          // ترتیب ترجمه‌ها
          if (sel.targets.length > 1) ...[
            SizedBox(height: context.px(14)),
            const _SectionLabel(
              text: 'ترتیب نمایش ترجمه‌ها (بکش تا جابجا بشه)',
              small: true,
            ),
            SizedBox(height: context.px(14)),
            _ReorderableChips(
              targets: sel.targets,
              onReorder: notifier.reorderTargets,
              onRemove: notifier.removeTarget,
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
class _SectionLabel extends StatelessWidget {
  final String text;
  final bool small;
  const _SectionLabel({required this.text, this.small = false});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.px(34)),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          text,
          style: TextStyle(
            color: c.headerText.withOpacity(small ? 0.80 : 0.88),
            fontSize: context.px(small ? 27 : 29),
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
class _DragRow extends StatelessWidget {
  final List<SupportedLanguage> languages;
  final Set<String> selectedCodes;
  final ValueChanged<String> onTap;
  final void Function(int oldIndex, int newIndex) onReorder;

  const _DragRow({
    super.key,
    required this.languages,
    required this.selectedCodes,
    required this.onTap,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final d = context.px(108); // قطر دایره
    final gap = context.px(17);

    // padding بیرونی (نه padding خودِ لیست) تا آیتم‌ها دقیقاً در لبه‌ی
    // ۳۴px بریده شوند، مثل اسکرین‌شات.
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.px(34)),
      child: SizedBox(
        height: d + context.px(24), // جا برای سایه‌ی درخشان
        child: ReorderableListView.builder(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          itemCount: languages.length,
          onReorder: onReorder,
          buildDefaultDragHandles: false,
          proxyDecorator: (child, index, animation) {
            return AnimatedBuilder(
              animation: animation,
              builder: (context, _) {
                return Transform.scale(
                  scale: 1.0 + (animation.value * 0.12),
                  child: Material(
                    color: Colors.transparent,
                    elevation: 8,
                    shape: const CircleBorder(),
                    child: child,
                  ),
                );
              },
            );
          },
          itemBuilder: (context, i) {
            final lang = languages[i];
            final active = selectedCodes.contains(lang.code);
            return Padding(
              key: ValueKey('circle-${lang.code}'),
              padding: EdgeInsetsDirectional.only(end: gap),
              child: Center(
                child: _CircleItem(
                  index: i,
                  abbr: lang.abbr,
                  active: active,
                  size: d,
                  c: c,
                  onTap: () => onTap(lang.code),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CircleItem extends StatelessWidget {
  final int index;
  final String abbr;
  final bool active;
  final double size;
  final dynamic c;
  final VoidCallback onTap;

  const _CircleItem({
    required this.index,
    required this.abbr,
    required this.active,
    required this.size,
    required this.c,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color gold = c.gold as Color;
    return ReorderableDragStartListener(
      index: index,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: active
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.lerp(gold, Colors.white, 0.22)!,
                      gold,
                    ],
                  )
                : null,
            boxShadow: active
                ? [
                    BoxShadow(
                      color: gold.withOpacity(0.50),
                      blurRadius: context.px(22),
                      offset: Offset(0, context.px(6)),
                    ),
                  ]
                : null,
          ),
          child: CustomPaint(
            painter: active
                ? null
                : _DashedCirclePainter(
                    color: (c.headerText as Color).withOpacity(0.40),
                    stroke: context.px(3),
                    dash: context.px(13),
                    gap: context.px(8),
                  ),
            child: Center(
              child: Text(
                abbr,
                style: TextStyle(
                  color: active ? c.headerTo : c.headerText,
                  fontSize: context.px(31),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// دایره‌ی خط‌چین (برای زبان‌های انتخاب‌نشده).
class _DashedCirclePainter extends CustomPainter {
  final Color color;
  final double stroke;
  final double dash;
  final double gap;

  const _DashedCirclePainter({
    required this.color,
    required this.stroke,
    required this.dash,
    required this.gap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final r = (math.min(size.width, size.height) - stroke) / 2;
    final path = Path()
      ..addOval(Rect.fromCircle(center: size.center(Offset.zero), radius: r));
    for (final m in path.computeMetrics()) {
      double d = 0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + dash, m.length)), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCirclePainter old) =>
      old.color != color ||
      old.stroke != stroke ||
      old.dash != dash ||
      old.gap != gap;
}

// ═══════════════════════════════════════════════════════════════════
// چیپ‌های ترتیب ترجمه
// ═══════════════════════════════════════════════════════════════════
class _ReorderableChips extends StatelessWidget {
  final List<String> targets;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(String code) onRemove;

  const _ReorderableChips({
    required this.targets,
    required this.onReorder,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.px(34)),
      child: SizedBox(
        height: context.px(68) + context.px(12),
        child: ReorderableListView.builder(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          itemCount: targets.length,
          onReorder: onReorder,
          buildDefaultDragHandles: false,
          proxyDecorator: (child, index, animation) {
            return Material(
              color: Colors.transparent,
              elevation: 4,
              borderRadius: BorderRadius.circular(999),
              child: child,
            );
          },
          itemBuilder: (context, index) {
            final code = targets[index];
            return Padding(
              key: ValueKey('chip-$code'),
              padding: EdgeInsetsDirectional.only(end: context.px(18)),
              child: Center(
                child: _OrderChip(
                  index: index,
                  code: code,
                  onRemove: () => onRemove(code),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _OrderChip extends StatelessWidget {
  final int index;
  final String code;
  final VoidCallback onRemove;

  const _OrderChip({
    required this.index,
    required this.code,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return ReorderableDragStartListener(
      index: index,
      child: Container(
        height: context.px(68),
        padding: EdgeInsets.symmetric(horizontal: context.px(16)),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.10),
              blurRadius: context.px(8),
              offset: Offset(0, context.px(2)),
            ),
          ],
        ),
        // RTL: اولین فرزند = راست → [دستگیره][متن][×]
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.drag_indicator,
              size: context.px(30),
              color: c.gold,
            ),
            SizedBox(width: context.px(8)),
            Text(
              langFaName(code),
              style: TextStyle(
                color: c.ink,
                fontSize: context.px(30),
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(width: context.px(14)),
            GestureDetector(
              onTap: onRemove,
              child: Container(
                width: context.px(38),
                height: context.px(38),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.paperDark.withOpacity(0.9),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.close,
                  size: context.px(22),
                  color: c.inkSoft,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
