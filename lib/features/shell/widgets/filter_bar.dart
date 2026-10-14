import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/cefr_levels.dart';
import '../../../core/models/filter_state.dart';
import '../../../core/providers/words_filter_provider.dart';
import '../../../core/theme/app_theme_colors.dart';

class FilterBar extends ConsumerStatefulWidget {
  /// برچسبِ جستجو (مثلاً 'جستجوی لغت...' یا 'جستجوی مکالمه...')
  final String searchHint;

  /// آیا ردیف سطح نشون داده بشه؟
  final bool showLevels;

  /// آیا ردیف مرتب‌سازی نشون داده بشه؟
  final bool showSort;

  const FilterBar({
    super.key,
    this.searchHint = 'جستجو...',
    this.showLevels = true,
    this.showSort = true,
  });

  @override
  ConsumerState<FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends ConsumerState<FilterBar> {
  late final TextEditingController _searchCtrl;

  @override
  void initState() {
    super.initState();
    final q = ref.read(wordsFilterProvider).query;
    _searchCtrl = TextEditingController(text: q);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final filter = ref.watch(wordsFilterProvider);
    final notifier = ref.read(wordsFilterProvider.notifier);

    return Container(
      color: c.paper,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── ردیف سطح ──
          if (widget.showLevels) ...[
            _LevelRow(
              selected: filter.level,
              c: c,
              onSelect: notifier.setLevel,
            ),
            const SizedBox(height: 12),
          ],

          // ── ردیف مرتب‌سازی ──
          if (widget.showSort) ...[
            _SortRow(
              current: filter.sort,
              c: c,
              onSelect: notifier.setSort,
            ),
            const SizedBox(height: 12),
          ],

          // ── جستجو ──
          _SearchField(
            controller: _searchCtrl,
            hint: widget.searchHint,
            c: c,
            onChanged: notifier.setQuery,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Level chips
// ═══════════════════════════════════════════════════════════════════
class _LevelRow extends StatelessWidget {
  final String selected;
  final dynamic c;
  final ValueChanged<String> onSelect;

  const _LevelRow({
    required this.selected,
    required this.c,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final levels = ['all', ...kCefrLevels];
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: levels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final lvl = levels[i];
          final active = lvl == selected;
          final label = lvl == 'all' ? 'همه سطوح' : lvl;
          return GestureDetector(
            onTap: () => onSelect(lvl),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: EdgeInsets.symmetric(
                horizontal: lvl == 'all' ? 16 : 14,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: active
                    ? c.headerFrom
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: active
                      ? c.headerFrom
                      : c.cardBorder,
                  width: 1.2,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                label,
                style: TextStyle(
                  color: active ? c.headerText : c.inkSoft,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Sort dropdown
// ═══════════════════════════════════════════════════════════════════
class _SortRow extends StatelessWidget {
  final SortMode current;
  final dynamic c;
  final ValueChanged<SortMode> onSelect;

  const _SortRow({
    required this.current,
    required this.c,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: PopupMenuButton<SortMode>(
        initialValue: current,
        onSelected: onSelect,
        color: c.paper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        itemBuilder: (_) => SortMode.values.map((mode) {
          return PopupMenuItem<SortMode>(
            value: mode,
            child: Row(
              children: [
                if (mode == current)
                  Icon(Icons.check, size: 16, color: c.gold)
                else
                  const SizedBox(width: 16),
                const SizedBox(width: 8),
                Text(mode.faLabel, style: TextStyle(color: c.ink)),
              ],
            ),
          );
        }).toList(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: c.paperDark.withOpacity(0.5),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: c.cardBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sort, size: 16, color: c.inkSoft),
              const SizedBox(width: 6),
              Text(
                'مرتب‌سازی: ${current.faLabel}',
                style: TextStyle(
                  color: c.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.keyboard_arrow_down, size: 16, color: c.inkSoft),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Search field
// ═══════════════════════════════════════════════════════════════════
class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final dynamic c;
  final ValueChanged<String> onChanged;

  const _SearchField({
    required this.controller,
    required this.hint,
    required this.c,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.cardBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: c.ink.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textAlign: TextAlign.right,
        style: TextStyle(color: c.ink, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: c.inkSoft.withOpacity(0.6)),
          prefixIcon: Icon(Icons.search, color: c.inkSoft, size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
        ),
      ),
    );
  }
}
