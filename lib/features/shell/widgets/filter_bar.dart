import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/cefr_levels.dart';
import '../../../core/models/filter_state.dart';
import '../../../core/providers/words_filter_provider.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/theme/screen_scale.dart';

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
      padding: EdgeInsets.fromLTRB(
        context.px(34),
        context.px(26),
        context.px(34),
        context.px(30),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showLevels) ...[
            _LevelRow(
              selected: filter.level,
              c: c,
              onSelect: notifier.setLevel,
            ),
            SizedBox(height: context.px(34)),
          ],
          if (widget.showSort) ...[
            _SortRow(
              current: filter.sort,
              c: c,
              onSelect: notifier.setSort,
            ),
            SizedBox(height: context.px(27)),
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
      height: context.px(81),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: levels.length,
        separatorBuilder: (_, __) => SizedBox(width: context.px(20)),
        itemBuilder: (_, i) {
          final lvl = levels[i];
          final active = lvl == selected;
          final label = lvl == 'all' ? 'همه سطوح' : lvl;
          return GestureDetector(
            onTap: () => onSelect(lvl),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: EdgeInsets.symmetric(
                horizontal: context.px(lvl == 'all' ? 36 : 28),
              ),
              decoration: BoxDecoration(
                color: active ? c.headerTo as Color : Colors.white,
                borderRadius: BorderRadius.circular(999),
              ),
              alignment: Alignment.center,
              child: Text(
                label,
                style: TextStyle(
                  color: active ? c.headerText as Color : c.ink as Color,
                  fontSize: context.px(30),
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
      alignment: AlignmentDirectional.centerStart,
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
          height: context.px(56),
          padding: EdgeInsets.symmetric(horizontal: context.px(28)),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: c.cardBorder, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.swap_vert, size: context.px(30), color: c.ink),
              SizedBox(width: context.px(10)),
              Text(
                'مرتب‌سازی: ${current.faLabel}',
                style: TextStyle(
                  color: c.ink,
                  fontSize: context.px(27),
                  fontWeight: FontWeight.w600,
                ),
              ),
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
      height: context.px(97),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(context.px(48)),
        border: Border.all(color: c.cardBorder.withOpacity(0.7), width: 1),
      ),
      alignment: Alignment.center,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textAlign: TextAlign.start,
        style: TextStyle(color: c.ink, fontSize: context.px(30)),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: c.inkSoft.withOpacity(0.6),
            fontSize: context.px(30),
          ),
          prefixIcon: Icon(Icons.search, color: c.ink, size: context.px(42)),
          prefixIconConstraints: BoxConstraints(
            minWidth: context.px(100),
            minHeight: context.px(60),
          ),
          border: InputBorder.none,
          isCollapsed: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }
}
