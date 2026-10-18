import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/level_chips.dart';
import '../../../core/models/daily_word.dart';
import '../../../core/player_sync/player_track.dart';
import '../../../core/player_sync/sync_widgets.dart';
import '../../../core/providers/language_selection_provider.dart';
import '../../../core/providers/my_dictionary_provider.dart';
import '../../../core/providers/read_ids_provider.dart';
import '../../../core/providers/words_filter_provider.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/widgets/range_card.dart';
import '../../shell/widgets/shell_header.dart';
import 'word_card.dart';

/// تعدادِ لغتی که در هر «بخش» رندر می‌شود (مثل WORDS_PAGE_SIZE در Hope).
/// با رسیدنِ اسکرول به ته، بخشِ بعدی خودکار اضافه می‌شود.
const int kWordsPageSize = 60;

class WordListView extends ConsumerStatefulWidget {
  /// شناسه‌ی لیست برای ذخیره‌ی «خوانده‌شده‌ها» ('words' / 'slang' / …)
  final String listId;

  /// لیست لغات (خالیه = حالت خالی)
  final List<DailyWord> words;

  /// آیا داده بارگذاری شده؟
  final bool hasAnyData;

  /// پیام حالت خالی
  final String emptyMessage;

  /// هنوز در حال بارگذاری است؟ (به‌جای «بارگذاری نشد» چرخنده نشان بده)
  final bool loading;

  /// عنوانِ بالای لیست (مثل «لغات» در تبِ علاقه‌مندی‌های Hope)
  final String? heading;

  const WordListView({
    super.key,
    required this.listId,
    required this.words,
    required this.hasAnyData,
    this.emptyMessage = 'چیزی پیدا نشد',
    this.loading = false,
    this.heading,
  });

  @override
  ConsumerState<WordListView> createState() => _WordListViewState();
}

class _WordListViewState extends ConsumerState<WordListView> {
  // بازه‌ی دستیِ کاربر (null = خودکار)
  int? _from;
  int? _to;

  // مرزِ بالاییِ «خودکار» — با اسکرول به ته، kWordsPageSize تا زیاد می‌شود.
  int _autoTo = kWordsPageSize;

  String _sigLevel = 'all';
  String _sigQuery = '';

  // برای ثابت‌ماندنِ revision پلیر (identical) تا هر build دوباره ثبت نشود
  List<DailyWord> _visible = const <DailyWord>[];
  List<DailyWord>? _visibleSrc;
  int _visibleFrom = -1;
  int _visibleTo = -1;

  void _resetRange() {
    _from = null;
    _to = null;
    _autoTo = kWordsPageSize;
  }

  @override
  Widget build(BuildContext context) {
    final words = widget.words;
    final c = context.appColors;
    final sel = ref.watch(languageSelectionProvider);
    final filter = ref.watch(wordsFilterProvider);
    final notifier = ref.read(wordsFilterProvider.notifier);
    final readIds = ref.watch(readIdsProvider(widget.listId));
    final readNotifier = ref.read(readIdsProvider(widget.listId).notifier);

    // با عوض‌شدنِ سطح/جستجو، بازه به ابتدای لیست برمی‌گردد (مثل Hope)
    if (filter.level != _sigLevel || filter.query != _sigQuery) {
      _sigLevel = filter.level;
      _sigQuery = filter.query;
      _resetRange();
    }

    final total = words.length;
    final defaultTo = total == 0 ? 0 : math.min(total, _autoTo);
    final from = total == 0
        ? 1
        : (_from ?? 1).clamp(1, total).toInt();
    final to = total == 0
        ? 0
        : (_to ?? defaultTo).clamp(from, total).toInt();

    if (!identical(_visibleSrc, words) ||
        _visibleFrom != from ||
        _visibleTo != to) {
      _visible = total == 0
          ? const <DailyWord>[]
          : words.sublist(from - 1, to);
      _visibleSrc = words;
      _visibleFrom = from;
      _visibleTo = to;
    }
    final visible = _visible;
    final readInRange =
        visible.where((w) => readIds.contains(w.sid)).length;
    final readTotal = words.where((w) => readIds.contains(w.sid)).length;
    final hasMore = _to == null && to < total;

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
                    alignment: Alignment.centerRight, // همیشه سمتِ راست (فیزیکی)
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
      // فقط بازه‌ی نمایش‌داده‌شده خوانده/ردیابی می‌شود (مثل Hope)
      revision: visible,
      mode: TrackMode.words,
      itemsBuilder: () => [
        for (final w in visible) SyncItem(w.sid, w.en),
      ],
      child: CustomScrollView(
        cacheExtent: 600,
        slivers: [
          const SliverToBoxAdapter(child: ShellHeader()),
          SliverToBoxAdapter(child: filterHeader),
          if (widget.heading != null && words.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    widget.heading!,
                    style: TextStyle(
                      color: c.gold,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          if (words.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: RangeCard(
                  label: widget.listId == 'favorites' ? 'لغات' : 'دیکشنری',
                  max: total,
                  from: from,
                  to: to,
                  readInRange: readInRange,
                  totalInRange: visible.length,
                  readTotal: readTotal,
                  onFromChanged: (v) => setState(() => _from = v),
                  onToChanged: (v) => setState(() => _to = v),
                  onMarkRead: () => readNotifier.setMany(
                      visible.map((w) => w.sid), true),
                  onClear: () => readNotifier.setMany(
                      visible.map((w) => w.sid), false),
                ),
              ),
            ),
          if (words.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(
                c: c,
                hasData: widget.hasAnyData,
                loading: widget.loading && !widget.hasAnyData,
                message: widget.emptyMessage,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) {
                    if (i >= visible.length) {
                      // سنتینلِ اسکرولِ بی‌نهایت: با ورود به دید، بخشِ بعدی
                      return _LoadMoreSentinel(
                        key: ValueKey('more-$to'),
                        onVisible: () {
                          if (!mounted) return;
                          setState(() {
                            _autoTo = math.min(
                                math.max(_autoTo, to) + kWordsPageSize,
                                total);
                          });
                        },
                      );
                    }
                    final w = visible[i];
                    return WordCard(
                      key: ValueKey('word-${w.sid}'),
                      id: w.sid,
                      en: w.en,
                      fa: w.fa,
                      level: w.level,
                      pos: w.pos,
                      langsToShow: langsToShow,
                      isPersonal: w.isPersonal,
                      knownTranslations: w.translations,
                      isRead: readIds.contains(w.sid),
                      onToggleRead: () => readNotifier.toggle(w.sid),
                      onRemove: w.isPersonal
                          ? () => ref
                              .read(wordsTabHiddenProvider.notifier)
                              .hide(w.en)
                          : null,
                    );
                  },
                  childCount: visible.length + (hasMore ? 1 : 0),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// نشانگرِ انتهای لیست: وقتی ساخته شد (یعنی کاربر به ته رسید) یک‌بار
/// onVisible را صدا می‌زند تا بخشِ بعدیِ لغات اضافه شود.
class _LoadMoreSentinel extends StatefulWidget {
  final VoidCallback onVisible;
  const _LoadMoreSentinel({super.key, required this.onVisible});

  @override
  State<_LoadMoreSentinel> createState() => _LoadMoreSentinelState();
}

class _LoadMoreSentinelState extends State<_LoadMoreSentinel> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onVisible();
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 48,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
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
