import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/level_chips.dart';
import '../../../core/models/daily_word.dart';
import '../../../core/player_sync/player_track.dart';
import '../../../core/player_sync/sync_widgets.dart';
import '../../../core/providers/language_selection_provider.dart';
import '../../../core/providers/words_filter_provider.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../shell/widgets/shell_header.dart';
import 'word_card.dart';

class WordListView extends ConsumerWidget {
  /// لیست لغات (خالیه = حالت خالی)
  final List<DailyWord> words;

  /// آیا داده بارگذاری شده؟
  final bool hasAnyData;

  /// پیام حالت خالی
  final String emptyMessage;

  /// هنوز در حال بارگذاری است؟ (به‌جای «بارگذاری نشد» چرخنده نشان بده)
  final bool loading;

  const WordListView({
    super.key,
    required this.words,
    required this.hasAnyData,
    this.emptyMessage = 'چیزی پیدا نشد',
    this.loading = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final sel = ref.watch(languageSelectionProvider);
    final filter = ref.watch(wordsFilterProvider);
    final notifier = ref.read(wordsFilterProvider.notifier);

    final langsToShow = <String>[
      if (sel.native != 'en') sel.native,
      ...sel.targets.where((t) => t != 'en'),
    ];

    // مثل Hope: سطح‌ها، مرتب‌سازی و جستجو بخشی از خودِ محتوا هستند و
    // همراه لیست اسکرول می‌شوند (ثابت روی صفحه نمی‌مانند). برای اینکه فیلدِ
    // جستجو هنگام خالی‌شدنِ نتایج از بین نرود، یک CustomScrollView ثابت
    // داریم و فقط اسلیورِ زیرِ فیلترها عوض می‌شود.
    final filterHeader =
    Container(
              color: c.paper,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LevelChips(
                    selected: filter.level,
                    onSelect: notifier.setLevel,
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: c.paperDark.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: c.cardBorder),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.sort, size: 14, color: c.inkSoft),
                          const SizedBox(width: 6),
                          Text('مرتب‌سازی: پیش‌فرض',
                              style: TextStyle(
                                  color: c.ink,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(width: 3),
                          Icon(Icons.keyboard_arrow_down,
                              size: 14, color: c.inkSoft),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.cardBorder, width: 1),
                    ),
                    child: TextField(
                      onChanged: notifier.setQuery,
                      textAlign: TextAlign.right,
                      style: TextStyle(color: c.ink, fontSize: 13.5),
                      decoration: InputDecoration(
                        hintText: 'جستجوی لغت...',
                        hintStyle: TextStyle(
                            color: c.inkSoft.withOpacity(0.55), fontSize: 13.5),
                        prefixIcon:
                            Icon(Icons.search, color: c.inkSoft, size: 19),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 13),
                      ),
                    ),
                  ),
                ],
              ),
            );

    return SyncPlayScope(
      revision: words,
      mode: TrackMode.words,
      itemsBuilder: () => [
        for (final w in words) SyncItem(w.id.toString(), w.en),
      ],
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: ShellHeader()),
          SliverToBoxAdapter(child: filterHeader),
          if (words.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(
                c: c,
                hasData: hasAnyData,
                loading: loading && !hasAnyData,
                message: emptyMessage,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) {
                    final w = words[i];
                    return WordCard(
                      key: ValueKey('word-${w.id}'),
                      id: w.id.toString(),
                      en: w.en,
                      fa: w.fa,
                      level: w.level,
                      pos: w.pos,
                      langsToShow: langsToShow,
                    );
                  },
                  childCount: words.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// حالت خالی / در حال بارگذاری لیست
class _EmptyState extends StatelessWidget {
  final AppThemeColorsExt c;
  final bool hasData;
  final bool loading;
  final String message;

  const _EmptyState({
    required this.c,
    required this.hasData,
    required this.message,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.4, color: c.gold),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasData ? Icons.search_off : Icons.hourglass_empty,
              size: 38,
              color: c.inkSoft.withOpacity(0.5),
            ),
            const SizedBox(height: 12),
            Text(
              hasData ? message : 'داده‌ای بارگذاری نشد',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.inkSoft,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
