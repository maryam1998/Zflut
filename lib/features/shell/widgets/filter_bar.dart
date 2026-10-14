import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/cefr_levels.dart';
import '../../../core/models/filter_state.dart';
import '../../../core/providers/words_filter_provider.dart';
import '../../../core/theme/app_theme_colors.dart';

class FilterBar extends ConsumerStatefulWidget {
  final String searchHint;
  final bool showLevels;
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
    _searchCtrl = TextEditingController(
      text: ref.read(wordsFilterProvider).query,
    );
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
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showLevels) ...[
            _LevelRow(
              selected: filter.level,
              c: c,
              onSelect: notifier.setLevel,
            ),
            const SizedBox(height: 8),
          ],
          if (widget.showSort) ...[
            _SortRow(
              current: filter.sort,
              c: c,
              onSelect: notifier.setSort,
            ),
            const SizedBox(height: 8),
          ],
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
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: levels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final lvl = levels[i];
          final active = lvl == selected;
          final label = lvl == 'all' ? 'همه سطوح' : lvl;
          return GestureDetector(
            onTap: () => onSelect(lvl),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: EdgeInsets.symmetric(
                horizontal: lvl == 'all' ? 14 : 12,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: active ? c.headerFrom : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: active ? c.headerFrom : c.cardBorder,
                  width: 1,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                label,
                style: TextStyle(
                  color: active ? c.headerText : c.inkSoft,
                  fontSize: 12,
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
            height: 38,
            child: Row(
              children: [
                if (mode == current)
                  Icon(Icons.check, size: 15, color: c.gold)
                else
                  const SizedBox(width: 15),
                const SizedBox(width: 8),
                Text(mode.faLabel,
                    style: TextStyle(color: c.ink, fontSize: 13)),
              ],
            ),
          );
        }).toList(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: c.paperDark.withOpacity(0.5),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: c.cardBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sort, size: 14, color: c.inkSoft),
              const SizedBox(width: 5),
              Text(
                'مرتب‌سازی: ${current.faLabel}',
                style: TextStyle(
                  color: c.ink,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 3),
              Icon(Icons.keyboard_arrow_down, size: 14, color: c.inkSoft),
            ],
          ),
        ),
      ),
    );
  }
}

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
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.cardBorder, width: 1),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textAlign: TextAlign.right,
        style: TextStyle(color: c.ink, fontSize: 13.5),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: c.inkSoft.withOpacity(0.6), fontSize: 13.5),
          prefixIcon: Icon(Icons.search, color: c.inkSoft, size: 19),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}
