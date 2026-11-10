import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/dictionary_topics.dart';
import '../../core/models/daily_word.dart';
import '../../core/providers/conversation_provider.dart';
import '../../core/providers/my_dictionary_provider.dart';
import '../../core/theme/app_theme_colors.dart';
import '../words/widgets/word_list_view.dart';
import '_hope_panel.dart' show HopeChoiceChip;

/// تبِ «دیکشنری من»: لغات روزمره + لغات/عبارت‌های شخصی‌ای که کاربر با
/// «ذخیره برای داستان بعدی» نشان کرده (با برچسب «شخصی» و ✕).
/// بالای لیست، موارد (حتی لغاتِ جدیدی که خودت اضافه می‌کنی) بر اساسِ موضوع
/// (غذا، سفر، سلامت، ...) دسته‌بندی می‌شوند؛ لغت، عبارت و اسلنگ هرکدام داخلِ
/// موضوعِ خودشان قرار می‌گیرند (ردیفِ جداگانه‌ای برای نوع نیست).
class WordsTab extends ConsumerWidget {
  const WordsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = ref.watch(wordsTabItemsProvider);
    final base = ref.watch(wordsTabBaseItemsProvider);
    final all = ref.watch(allDailyWordsProvider);
    final personal = ref.watch(myDictionaryWordsProvider);
    final topic = ref.watch(wordsTopicProvider);
    return WordListView(
      // با عوض‌شدنِ دسته، لیست از اول (و اسکرول از بالا) شروع می‌شود
      key: ValueKey('words-${(topic.toList()..sort()).join(',')}'),
      listId: 'words',
      words: words,
      hasAnyData: all.isNotEmpty || personal.isNotEmpty,
      loading: ref.watch(dailyWordsLoaderProvider).isLoading,
      afterHeading: _TopicFilter(all: base),
      freeSource: all, // 💎 ۳۰ لغتِ اولِ لیستِ روزمره رایگان
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
    final topicSel = ref.watch(wordsTopicProvider);
    final topics = ref.watch(wordsTabTopicsProvider);

    // شمارش‌ها از لیستِ پایه (بعد از فیلترِ سطح/جستجو)
    final perTopic = <String, int>{};
    for (final w in all) {
      final t = topics[w.sid] ?? kTopicOther;
      perTopic[t] = (perTopic[t] ?? 0) + 1;
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
          // ردیفِ موضوع‌ها
          row([
            chip('$allLabel (${all.length})', topicSel.isEmpty,
                () => ref.read(wordsTopicProvider.notifier).state = const <String>{}),
            for (final t in kDictTopics)
              if ((perTopic[t.key] ?? 0) > 0)
                chip('${t.label(ui)} (${perTopic[t.key]})',
                    topicSel.contains(t.key), () {
                  final n = Set<String>.of(topicSel);
                  if (!n.remove(t.key)) n.add(t.key);
                  ref.read(wordsTopicProvider.notifier).state = n;
                }),
          ]),
        ],
      ),
    );
  }
}
