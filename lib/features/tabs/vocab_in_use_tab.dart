import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/vocab_topics.dart';
import '../../core/models/daily_word.dart';
import '../../core/providers/word_sources_provider.dart';
import '../../core/theme/app_theme_colors.dart';
import '../words/widgets/word_list_view.dart';
import '_hope_panel.dart' show HopeChoiceChip;

/// تبِ «Vocab in use» (زیرتبِ Words) — مثل Hope.
/// بالای لیست، لغات بر اساسِ موضوع دسته‌بندی می‌شوند (مثلاً «سلامت و بیماری»)
/// و با انتخابِ هر موضوع، دسته‌های ریزِ آن (مثلاً «سلامت و پزشکی») هم می‌آید.
class VocabInUseTab extends ConsumerWidget {
  const VocabInUseTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = ref.watch(filteredVocabInUseWordsProvider);
    final src = ref.watch(vocabInUseWordsProvider);
    final topicKey = ref.watch(vocabTopicProvider);
    final cat = ref.watch(vocabCategoryProvider);
    return WordListView(
      // با عوض‌شدنِ موضوع/دسته، لیست از اول (و اسکرول از بالا) شروع می‌شود
      key: ValueKey('vocab-${topicKey ?? '_'}-${cat ?? '_'}'),
      listId: 'vocab-in-use',
      words: words,
      hasAnyData: src.valueOrNull?.isNotEmpty ?? false,
      loading: src.isLoading,
      afterHeading: _TopicFilter(all: src.valueOrNull ?? const <DailyWord>[]),
    );
  }
}

class _TopicFilter extends ConsumerWidget {
  final List<DailyWord> all;
  const _TopicFilter({required this.all});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (all.isEmpty) return const SizedBox.shrink();
    final c = context.appColors;
    final ui = Localizations.localeOf(context).languageCode;
    final fa = ui == 'fa' || ui == 'ar';
    final topicKey = ref.watch(vocabTopicProvider);
    final catSel = ref.watch(vocabCategoryProvider);
    final topic = vocabTopicByKey(topicKey);

    // شمارش‌ها از کلِ لیست (قبل از فیلترِ سطح/جستجو) تا ثابت بمانند
    final perCat = <String, int>{};
    for (final w in all) {
      perCat[w.category] = (perCat[w.category] ?? 0) + 1;
    }
    int topicCount(VocabTopic t) {
      var n = 0;
      for (final x in t.categories) {
        n += perCat[x] ?? 0;
      }
      return n;
    }

    Widget chip(String label, bool active, VoidCallback onTap,
        {double fs = 12.5}) {
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: HopeChoiceChip(
          label: label,
          active: active,
          activeBorder: c.gold,
          activeFill: c.goldSoft,
          activeText: c.ink,
          fontSize: fs,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          onTap: onTap,
        ),
      );
    }

    Widget row(List<Widget> kids) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: kids),
        );

    final allLabel = fa ? 'همه' : 'All';
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row([
            chip('$allLabel (${all.length})', topic == null, () {
              ref.read(vocabTopicProvider.notifier).state = null;
              ref.read(vocabCategoryProvider.notifier).state = null;
            }),
            for (final t in kVocabTopics)
              if (topicCount(t) > 0)
                chip('${t.label(ui)} (${topicCount(t)})', topic?.key == t.key,
                    () {
                  ref.read(vocabTopicProvider.notifier).state = t.key;
                  ref.read(vocabCategoryProvider.notifier).state = null;
                }),
          ]),
          if (topic != null && topic.categories.length > 1) ...[
            const SizedBox(height: 6),
            row([
              chip('$allLabel (${topicCount(topic)})', catSel == null,
                  () => ref.read(vocabCategoryProvider.notifier).state = null,
                  fs: 11.5),
              for (final x in topic.categories)
                if ((perCat[x] ?? 0) > 0)
                  chip('$x (${perCat[x]})', catSel == x,
                      () => ref.read(vocabCategoryProvider.notifier).state = x,
                      fs: 11.5),
            ]),
          ],
        ],
      ),
    );
  }
}
