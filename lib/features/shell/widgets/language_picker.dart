import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/supported_languages.dart';
import '../../../core/providers/language_selection_provider.dart';
import '../../../core/theme/app_theme_colors.dart';

class LanguagePicker extends ConsumerWidget {
  const LanguagePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final sel = ref.watch(languageSelectionProvider);
    final notifier = ref.read(languageSelectionProvider.notifier);

    return Container(
      color: c.headerFrom,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ══ زبان مادری ══
          const _SectionLabel(text: 'زبان مادری'),
          const SizedBox(height: 6),
          _ChipRow(
            selectedCodes: {sel.native},
            onTap: (code) => notifier.setNative(code),
          ),

          const SizedBox(height: 10),

          // ══ زبان‌های مقصد (چند-انتخابی) ══
          const _SectionLabel(text: 'زبان‌های مقصد'),
          const SizedBox(height: 6),
          _ChipRow(
            selectedCodes: sel.targets.toSet(),
            onTap: (code) => notifier.toggleTarget(code),
          ),

          // ══ ترتیب ترجمه‌ها (drag) ══
          if (sel.targets.length > 1) ...[
            const SizedBox(height: 12),
            const _SectionLabel(
              text: 'ترتیب نمایش ترجمه‌ها (بکش تا جابجا بشه)',
              small: true,
            ),
            const SizedBox(height: 6),
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
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          text,
          style: TextStyle(
            color: c.headerText.withOpacity(small ? 0.6 : 0.75),
            fontSize: small ? 10.5 : 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// ردیف دایره‌های زبان (تک یا چند-انتخابی)
// ═══════════════════════════════════════════════════════════════════
class _ChipRow extends StatelessWidget {
  final Set<String> selectedCodes;
  final ValueChanged<String> onTap;

  const _ChipRow({
    required this.selectedCodes,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: kSupportedLanguages.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final lang = kSupportedLanguages[i];
          final active = selectedCodes.contains(lang.code);
          return _LangCircle(
            code: lang.abbr,
            active: active,
            c: c,
            onTap: () => onTap(lang.code),
          );
        },
      ),
    );
  }
}

class _LangCircle extends StatelessWidget {
  final String code;
  final bool active;
  final dynamic c;
  final VoidCallback onTap;

  const _LangCircle({
    required this.code,
    required this.active,
    required this.c,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? c.gold : c.headerText.withOpacity(0.04),
          border: Border.all(
            color: active ? c.gold : c.headerText.withOpacity(0.35),
            width: active ? 2 : 1,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: c.gold.withOpacity(0.45),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          code,
          style: TextStyle(
            color: active ? c.headerTo : c.headerText,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// چیپ‌های ترتیب ترجمه‌ها (drag + X)
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
    return SizedBox(
      height: 40,
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: targets.length,
        onReorder: onReorder,
        buildDefaultDragHandles: false,
        proxyDecorator: (child, index, animation) {
          return Material(
            color: Colors.transparent,
            child: child,
          );
        },
        itemBuilder: (context, index) {
          final code = targets[index];
          return Padding(
            key: ValueKey('chip-$code'),
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: _OrderChip(
              index: index,
              code: code,
              onRemove: () => onRemove(code),
            ),
          );
        },
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.cardBorder, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // X برای حذف
          GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.rose.withOpacity(0.12),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.close, size: 12, color: c.rose),
            ),
          ),
          const SizedBox(width: 6),
          // نام زبان
          Text(
            langFaName(code),
            style: TextStyle(
              color: c.ink,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          // دسته‌ی drag
          ReorderableDragStartListener(
            index: index,
            child: Icon(
              Icons.drag_indicator,
              size: 16,
              color: c.inkSoft.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }
}
