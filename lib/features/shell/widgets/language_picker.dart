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

    // ═══ زبان مادری — ترتیب دلخواه ═══
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

    // ═══ زبان‌های مقصد — انتخاب‌شده‌ها اول، بعد بقیه ═══
    final targetDisplayOrder = ref.watch(targetDisplayOrderProvider);
    final selected = sel.targets.toList();
    // دایره‌های انتخاب‌شده به ترتیب targets
    final selectedLangs = selected
        .map((code) => kSupportedLanguages.firstWhere(
              (l) => l.code == code,
              orElse: () => kSupportedLanguages.first,
            ))
        .toList();
    // بقیه به ترتیب دلخواه یا پیش‌فرض
    final unselectedCodes = targetDisplayOrder.isEmpty
        ? kSupportedLanguages
            .where((l) => !selected.contains(l.code))
            .map((l) => l.code)
            .toList()
        : [
            ...targetDisplayOrder.where(
              (c) => !selected.contains(c) && kSupportedLanguages.any((l) => l.code == c),
            ),
            ...kSupportedLanguages
                .map((l) => l.code)
                .where((c) => !selected.contains(c) && !targetDisplayOrder.contains(c)),
          ];
    final unselectedLangs = unselectedCodes
        .map((code) => kSupportedLanguages.firstWhere((l) => l.code == code))
        .toList();

    return Container(
      color: c.headerFrom,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ═══ زبان مادری ═══
          const _SectionLabel(text: 'زبان مادری'),
          const SizedBox(height: 6),
          _DraggableCircleRow(
            key: const ValueKey('native-row'),
            languages: nativeLanguages,
            selectedCodes: {sel.native},
            onTap: (code) => notifier.setNative(code),
            onReorder: (oldIdx, newIdx) {
              ref.read(nativeOrderProvider.notifier)
                  .reorder(nativeOrderList, oldIdx, newIdx);
            },
          ),

          const SizedBox(height: 10),

          // ═══ زبان‌های مقصد ═══
          const _SectionLabel(text: 'زبان‌های مقصد'),
          const SizedBox(height: 6),
          _DraggableCircleRow(
            key: const ValueKey('target-row'),
            languages: [...selectedLangs, ...unselectedLangs],
            selectedCodes: selected.toSet(),
            onTap: (code) => notifier.toggleTarget(code),
            onReorder: (oldIdx, newIdx) {
              // فقط اگر هر دو آیتم در محدوده‌ی «انتخاب‌شده‌ها» باشند،
              // ترتیب targets را عوض می‌کنیم.
              if (oldIdx < selected.length && newIdx <= selected.length) {
                notifier.reorderTargets(oldIdx, newIdx);
              } else {
                // در غیر این صورت فقط ترتیب نمایش دایره‌ها را عوض کن.
                final allLangs = [...selectedLangs, ...unselectedLangs]
                    .map((l) => l.code)
                    .toList();
                ref.read(targetDisplayOrderProvider.notifier)
                    .reorder(allLangs, oldIdx, newIdx);
              }
            },
          ),

          // ═══ ترتیب ترجمه‌ها (drag chips) ═══
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
// ردیف دایره‌های قابل‌کشیدن
// ═══════════════════════════════════════════════════════════════════
class _DraggableCircleRow extends StatelessWidget {
  final List<SupportedLanguage> languages;
  final Set<String> selectedCodes;
  final ValueChanged<String> onTap;
  final void Function(int oldIndex, int newIndex) onReorder;

  const _DraggableCircleRow({
    super.key,
    required this.languages,
    required this.selectedCodes,
    required this.onTap,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;

    return SizedBox(
      height: 60,
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: languages.length,
        onReorder: onReorder,
        buildDefaultDragHandles: false,
        proxyDecorator: (child, index, animation) {
          return Material(
            color: Colors.transparent,
            elevation: 8,
            shape: const CircleBorder(),
            child: child,
          );
        },
        itemBuilder: (context, i) {
          final lang = languages[i];
          final active = selectedCodes.contains(lang.code);

          return Padding(
            key: ValueKey('circle-${lang.code}'),
            padding: const EdgeInsetsDirectional.only(end: 10),
            child: _DraggableCircle(
              index: i,
              code: lang.abbr,
              active: active,
              c: c,
              onTap: () => onTap(lang.code),
            ),
          );
        },
      ),
    );
  }
}

class _DraggableCircle extends StatelessWidget {
  final int index;
  final String code;
  final bool active;
  final dynamic c;
  final VoidCallback onTap;

  const _DraggableCircle({
    required this.index,
    required this.code,
    required this.active,
    required this.c,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final circle = GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
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

    // لمس طولانی → شروع drag، تپ سریع → toggle
    return ReorderableDelayedDragStartListener(
      index: index,
      child: circle,
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
      height: 42,
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
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
          Text(
            langFaName(code),
            style: TextStyle(
              color: c.ink,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
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
