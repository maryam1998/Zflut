import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/slang_topics.dart';
import '../../core/models/daily_word.dart';
import '../../core/providers/word_sources_provider.dart';
import '../../core/providers/words_filter_provider.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../core/usage/pro_status.dart';
import '../../core/usage/words_index.dart';
import '../../core/widgets/locked_words_card.dart';
import '../words/widgets/word_list_view.dart';
import '_hope_panel.dart' show HopeChoiceChip;

/// تبِ «Slang» (زیرتبِ Words) — مثل Hope.
/// بالای لیست، لغات بر اساسِ موضوع دسته‌بندی می‌شوند (احساسات، غذا، پول، ...).
class SlangTab extends ConsumerWidget {
  const SlangTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = ref.watch(filteredSlangWordsProvider);
    final src = ref.watch(slangWordsProvider);
    final topicKey = ref.watch(slangTopicProvider);
    // 💎 کاربرِ رایگان: کلِ لغاتِ هر دسته + چندتایش قفل است (فقط ده لغتِ هر دسته باز است)
    final isPro = ref.watch(isProProvider);
    final filter = ref.watch(wordsFilterProvider);
    final ui = Localizations.localeOf(context).languageCode;
    final lockedInfo = isPro
        ? null
        : buildLockedInfo(
            index: ref.watch(wordsIndexProvider).valueOrNull,
            list: 'slang',
            groups: topicKey,
            levels: filter.levels,
            query: filter.query,
            groupLabel: (k) => slangTopicByKey(k)?.label(ui),
            scopeLabel: topicKey.length == 1
                ? slangTopicByKey(topicKey.first)?.label(ui)
                : null,
          );
    return WordListView(
      // با عوض‌شدنِ موضوع، لیست از اول (و اسکرول از بالا) شروع می‌شود
      key: ValueKey('slang-${(topicKey.toList()..sort()).join(',')}'),
      listId: 'slang',
      words: words,
      hasAnyData: src.valueOrNull?.isNotEmpty ?? false,
      loading: src.isLoading,
      afterHeading: _SlangTopicFilter(all: src.valueOrNull ?? const <DailyWord>[]),
      freeSource: src.valueOrNull, // 💎 ده لغتِ اولِ هر دسته رایگان
      lockedInfo: lockedInfo,
      levelAvailability: isPro
          ? null
          : ref
              .watch(wordsIndexProvider)
              .valueOrNull
              ?.availability('slang', groups: topicKey),
    );
  }
}

class _SlangTopicFilter extends ConsumerWidget {
  final List<DailyWord> all;
  const _SlangTopicFilter({required this.all});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 💎 کاربرِ رایگان: شمارِ «کلِ» هر دسته از ایندکس می‌آید (نه فقط لغاتِ باز)
    final isPro = ref.watch(isProProvider);
    final index = isPro ? null : ref.watch(wordsIndexProvider).valueOrNull;
    if (all.isEmpty && index == null) return const SizedBox.shrink();
    final c = context.appColors;
    final ui = Localizations.localeOf(context).languageCode;
    final fa = ui == 'fa' || ui == 'ar';
    final sel = ref.watch(slangTopicProvider);

    // شمارش‌ها از کلِ لیست (قبل از فیلترِ سطح/جستجو) تا ثابت بمانند
    final perTopic = <String, int>{};
    for (final w in all) {
      perTopic[w.category] = (perTopic[w.category] ?? 0) + 1;
    }

    int topicCount(String key) => index != null
        ? index.total('slang', groups: {key})
        : (perTopic[key] ?? 0);

    Widget chip(String label, bool active, VoidCallback onTap) {
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: HopeChoiceChip(
          label: label,
          active: active,
          activeBorder: c.gold,
          activeFill: c.goldSoft,
          activeText: c.ink,
          fontSize: 12.5,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          onTap: onTap,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            chip('${fa ? 'همه' : 'All'} (${index != null ? index.total('slang') : all.length})',
                sel.isEmpty,
                () => ref.read(slangTopicProvider.notifier).state = const <String>{}),
            for (final t in kSlangTopics)
              if (topicCount(t.key) > 0)
                chip('${t.label(ui)} (${topicCount(t.key)})', sel.contains(t.key),
                    () {
                  final n = Set<String>.of(sel);
                  if (!n.remove(t.key)) n.add(t.key);
                  ref.read(slangTopicProvider.notifier).state = n;
                }),
          ],
        ),
      ),
    );
  }
}
