import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/daily_word.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../core/providers/primary_school_provider.dart';
import '../../core/providers/words_filter_provider.dart';
import '../../core/widgets/category_grid.dart';
import '../words/widgets/stage_chips_bar.dart';
import '../words/widgets/word_list_view.dart';
import 'listening_practice_page.dart';
import 'question_practice_page.dart';
import 'writing_practice_page.dart';

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
          if (gridMode && level == 'A2') ...[
            _PracticeCard(
              icon: Icons.headphones_rounded,
              title: (ui == 'fa' || ui == 'ar')
                  ? 'تمرین درک شنیداری'
                  : 'Listening Practice',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => const ListeningPracticePage()),
              ),
            ),
            _PracticeCard(
              icon: Icons.quiz_rounded,
              title: (ui == 'fa' || ui == 'ar')
                  ? 'تمرین ساخت سؤال'
                  : 'Build the Question',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => const QuestionPracticePage()),
              ),
            ),
            _PracticeCard(
              icon: Icons.edit_note_rounded,
              title: (ui == 'fa' || ui == 'ar')
                  ? 'تمرین نوشتن پیام و ایمیل'
                  : 'Writing Practice',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => const WritingPracticePage()),
              ),
            ),
          ],
          if (gridMode)
            ..._gridSections(
              topics: topics,
              allTotal: all.length,
              allLabel: allLabel,
              ui: ui,
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

/// کارتِ ورود به یک تمرین (بالای شبکه‌ی موضوع‌های A2)
class _PracticeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  const _PracticeCard(
      {required this.icon, required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.gold),
          ),
          child: Row(
            children: [
              Icon(icon, color: c.gold),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                      color: c.ink, fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.inkSoft),
            ],
          ),
        ),
      ),
    );
  }
}


/// شبکه‌ی موضوع‌ها؛ اگر موضوع‌ها `group` داشته باشند (A2) در بخش‌های «مدرسه» و
/// «زندگی روزمره» نشان داده می‌شوند، وگرنه همان شبکه‌ی ساده (A1).
List<Widget> _gridSections({
  required List<PrimaryTopic> topics,
  required int allTotal,
  required String allLabel,
  required String ui,
  required ValueChanged<String?> onTap,
}) {
  CategoryItem item(PrimaryTopic t) => CategoryItem(
        key: t.key,
        label: t.label(ui),
        total: t.words.length,
      );
  final allItem = CategoryItem(key: null, label: allLabel, total: allTotal);

  if (!topics.any((t) => t.group.isNotEmpty)) {
    return [
      CategoryGrid(
        list: 'daily',
        items: [allItem, for (final t in topics) item(t)],
        onTap: onTap,
      ),
    ];
  }

  // گروه‌ها به ترتیبِ اولین دیدن
  final groups = <String>[];
  for (final t in topics) {
    if (!groups.contains(t.group)) groups.add(t.group);
  }
  final isFa = ui == 'fa';
  String title(String g) {
    switch (g) {
      case 'school':
        return isFa ? 'مدرسه' : 'School';
      case 'life':
        return isFa ? 'زندگی روزمره' : 'Everyday Life';
      default:
        return g;
    }
  }

  final out = <Widget>[
    CategoryGrid(
      list: 'daily',
      items: [allItem],
      onTap: onTap,
      bottomPadding: 0,
    ),
  ];
  for (var i = 0; i < groups.length; i++) {
    final g = groups[i];
    out.add(_SectionHeader(text: title(g)));
    out.add(CategoryGrid(
      list: 'daily',
      items: [
        for (final t in topics)
          if (t.group == g) item(t),
      ],
      onTap: onTap,
      bottomPadding: i == groups.length - 1 ? 90 : 4,
    ));
  }
  return out;
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader({required this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 2),
      child: Text(
        text,
        style: TextStyle(
          color: c.ink,
          fontWeight: FontWeight.w800,
          fontSize: 15,
        ),
      ),
    );
  }
}
