import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/paid_content.dart';
import '../../core/models/daily_word.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../core/usage/free_limit.dart';
import '../../core/usage/pro_status.dart';
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
/// 💎 Education stage پولی است: Pro کلِ لغات را (از سرور/کشِ گوشی) می‌بیند؛ کاربرِ رایگان
/// شبکه‌ی موضوع‌ها را با کارت‌های قفل‌شده می‌بیند و با لمس، پنجره‌ی «مخصوص Pro» باز می‌شود.
class PrimarySchoolView extends ConsumerWidget {
  const PrimarySchoolView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPro = ref.watch(isProProvider);
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
    final practice = ref.watch(primaryPracticeOpenProvider);
    // 🔒 کاربرِ رایگان همیشه فقط شبکه‌ی قفل‌شده را می‌بیند (لیستِ لغات/جستجو ندارد)
    final loadFailed = isPro && async.hasError && topics.isEmpty;
    final gridMode = !isPro ||
        loadFailed ||
        practice ||
        (topicKey == null && !allOpen && !searching);

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
      key: ValueKey(
          'primary-$level-${practice ? 'practice' : (topicKey ?? (allOpen ? 'all' : 'grid'))}'),
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
          if (practice) ...[
            _PracticeCard(
              icon: Icons.headphones_rounded,
              title: (ui == 'fa' || ui == 'ar')
                  ? 'تمرین درک شنیداری'
                  : 'Listening Practice',
              locked: !isPro,
              onTap: () {
                if (FreeLimit.blockUnlessPro()) return;
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => ListeningPracticePage(level: level)),
                );
              },
            ),
            _PracticeCard(
              icon: Icons.quiz_rounded,
              title: (ui == 'fa' || ui == 'ar')
                  ? 'تمرین ساخت سؤال'
                  : 'Build the Question',
              locked: !isPro,
              onTap: () {
                if (FreeLimit.blockUnlessPro()) return;
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => QuestionPracticePage(level: level)),
                );
              },
            ),
            _PracticeCard(
              icon: Icons.edit_note_rounded,
              title: (ui == 'fa' || ui == 'ar')
                  ? 'تمرین نوشتن پیام و ایمیل'
                  : 'Writing Practice',
              locked: !isPro,
              onTap: () {
                if (FreeLimit.blockUnlessPro()) return;
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => WritingPracticePage(level: level)),
                );
              },
            ),
          ],
          if (practice)
            const SizedBox(height: 90)
          else if (loadFailed)
            _RetryCard(
              ui: ui,
              onRetry: () {
                ref.invalidate(primaryA1TopicsProvider);
                ref.invalidate(primaryA2TopicsProvider);
                ref.invalidate(primaryB1TopicsProvider);
                PaidContent.prefetchEducation();
              },
            )
          else if (gridMode)
            ..._gridSections(
              topics: topics,
              allTotal: isPro
                  ? all.length
                  : topics.fold<int>(0, (a, t) => a + t.count),
              allLabel: allLabel,
              ui: ui,
              locked: !isPro,
              onTap: (k) {
                if (!isPro) {
                  FreeLimit.reportLocked();
                  return;
                }
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
      // لغاتِ Education stage فقط برای Pro‌اند (برای رایگان اصلاً لیستی نیست)
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
  final bool locked;
  const _PracticeCard(
      {required this.icon,
      required this.title,
      required this.onTap,
      this.locked = false});

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
              Icon(locked ? Icons.lock : Icons.chevron_right_rounded,
                  color: locked ? c.gold : c.inkSoft),
            ],
          ),
        ),
      ),
    );
  }
}


/// شبکه‌ی موضوع‌ها: کارتِ «همه» و بعد همه‌ی موضوع‌ها کنارِ هم، در یک شبکه
/// (بدونِ عنوانِ بخش مثل «مدرسه» / «زندگی روزمره» و بدونِ فاصله‌ی خالی).
List<Widget> _gridSections({
  required List<PrimaryTopic> topics,
  required int allTotal,
  required String allLabel,
  required String ui,
  required bool locked,
  required ValueChanged<String?> onTap,
}) {
  // free = 0 → کارتِ قفل‌شده‌ی طلایی با تعدادِ لغات؛ null = کارتِ عادی (Pro)
  CategoryItem item(PrimaryTopic t) => CategoryItem(
        key: t.key,
        label: t.label(ui),
        total: t.count,
        free: locked ? 0 : null,
      );
  final allItem = CategoryItem(
      key: null, label: allLabel, total: allTotal, free: locked ? 0 : null);
  return [
    CategoryGrid(
      list: 'daily',
      items: [allItem, for (final t in topics) item(t)],
      onTap: onTap,
    ),
  ];
}

/// وقتی لغاتِ Pro نه در کشِ گوشی هست و نه دانلود شد: به‌جای چرخشِ بی‌پایان، دکمه‌ی تلاشِ دوباره.
class _RetryCard extends StatelessWidget {
  final String ui;
  final VoidCallback onRetry;
  const _RetryCard({required this.ui, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final fa = ui == 'fa' || ui == 'ar';
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 90),
      child: Column(
        children: [
          Icon(Icons.cloud_off_rounded, size: 40, color: c.inkSoft),
          const SizedBox(height: 12),
          Text(
            fa
                ? 'دریافتِ لغات انجام نشد. اینترنت را بررسی کن و دوباره تلاش کن. (بعد از اولین دانلود، لغات روی گوشی می‌مانند و آفلاین هم باز می‌شوند.)'
                : "Couldn't load the words. Check your connection and try again. (After the first download they stay on your phone and work offline.)",
            textAlign: TextAlign.center,
            style: TextStyle(color: c.inkSoft, fontSize: 13.5, height: 1.5),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(fa ? 'تلاش دوباره' : 'Try again'),
          ),
        ],
      ),
    );
  }
}
