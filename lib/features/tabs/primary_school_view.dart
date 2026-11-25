import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/daily_word.dart';
import '../../core/providers/primary_school_provider.dart';
import '../../core/providers/words_filter_provider.dart';
import '../../core/widgets/category_grid.dart';
import '../words/widgets/stage_chips_bar.dart';
import '../words/widgets/word_list_view.dart';

/// نمای «Primary School ▸ A1» در تبِ دیکشنری من:
/// شبکه‌ی موضوع‌ها (الفبا، اعداد، رنگ‌ها، حیوان‌ها، ...) و داخلِ هر موضوع لیستِ لغات.
/// این لغات برای همه‌ی کاربران (رایگان و Pro) بازند.
class PrimarySchoolView extends ConsumerWidget {
  const PrimarySchoolView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(primaryTopicsProvider);
    final level = ref.watch(primaryLevelProvider);
    final topics = async.valueOrNull ?? const <PrimaryTopic>[];
    final all = ref.watch(primaryA1AllWordsProvider);
    final topicKey = ref.watch(primaryTopicProvider);
    final filter = ref.watch(wordsFilterProvider);
    final ui = Localizations.localeOf(context).languageCode;
    final allLabel = (ui == 'fa' || ui == 'ar') ? 'همه' : 'All';

    final q = filter.query.trim().toLowerCase();
    final searching = q.isNotEmpty;
    final allOpen = ref.watch(categoryAllOpenProvider('primary'));
    final gridMode = topicKey == null && !allOpen && !searching;

    PrimaryTopic? current;
    for (final t in topics) {
      if (t.key == topicKey) current = t;
    }

    final List<DailyWord> shown;
    if (gridMode) {
      shown = const <DailyWord>[];
    } else if (searching) {
      shown = [
        for (final w in all)
          if (w.en.toLowerCase().contains(q) || w.fa.contains(q)) w,
      ];
    } else if (current != null) {
      shown = current.words;
    } else {
      shown = all;
    }

    return WordListView(
      key: ValueKey('primary-$level-${topicKey ?? (allOpen ? 'all' : 'grid')}'),
      listId: 'words_primary_${level.toLowerCase()}',
      words: shown,
      gridMode: gridMode,
      hasAnyData: all.isNotEmpty,
      loading: async.isLoading,
      topSlot: const StageChipsBar(),
      hideLevelChips: true,
      afterHeading: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (gridMode)
            CategoryGrid(
              list: 'daily',
              items: [
                CategoryItem(key: null, label: allLabel, total: all.length),
                for (final t in topics)
                  CategoryItem(
                    key: t.key,
                    label: t.label(ui),
                    total: t.words.length,
                  ),
              ],
              onTap: (k) {
                if (k == null) {
                  ref.read(categoryAllOpenProvider('primary').notifier).state =
                      true;
                } else {
                  ref.read(primaryTopicProvider.notifier).state = k;
                }
              },
            )
          else if (!searching)
            CategoryBackBar(
              list: 'daily',
              categoryKey: current?.key,
              label: current != null ? current.label(ui) : allLabel,
              onBack: () {
                ref.read(primaryTopicProvider.notifier).state = null;
                ref.read(categoryAllOpenProvider('primary').notifier).state =
                    false;
              },
            ),
        ],
      ),
      // همه‌ی لغاتِ Primary برای همه بازند (قفلی نیست)
      freeSource: all,
      lockedInfo: null,
      levelAvailability: null,
    );
  }
}
