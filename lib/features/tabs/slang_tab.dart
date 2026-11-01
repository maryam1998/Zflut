import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/slang_topics.dart';
import '../../core/models/daily_word.dart';
import '../../core/providers/word_sources_provider.dart';
import '../../core/theme/app_theme_colors.dart';
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
    return WordListView(
      // با عوض‌شدنِ موضوع، لیست از اول (و اسکرول از بالا) شروع می‌شود
      key: ValueKey('slang-${topicKey ?? '_'}'),
      listId: 'slang',
      words: words,
      hasAnyData: src.valueOrNull?.isNotEmpty ?? false,
      loading: src.isLoading,
      afterHeading: _SlangTopicFilter(all: src.valueOrNull ?? const <DailyWord>[]),
    );
  }
}

class _SlangTopicFilter extends ConsumerWidget {
  final List<DailyWord> all;
  const _SlangTopicFilter({required this.all});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (all.isEmpty) return const SizedBox.shrink();
    final c = context.appColors;
    final ui = Localizations.localeOf(context).languageCode;
    final fa = ui == 'fa' || ui == 'ar';
    final sel = ref.watch(slangTopicProvider);

    // شمارش‌ها از کلِ لیست (قبل از فیلترِ سطح/جستجو) تا ثابت بمانند
    final perTopic = <String, int>{};
    for (final w in all) {
      perTopic[w.category] = (perTopic[w.category] ?? 0) + 1;
    }

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
            chip('${fa ? 'همه' : 'All'} (${all.length})', sel == null,
                () => ref.read(slangTopicProvider.notifier).state = null),
            for (final t in kSlangTopics)
              if ((perTopic[t.key] ?? 0) > 0)
                chip('${t.label(ui)} (${perTopic[t.key]})', sel == t.key,
                    () => ref.read(slangTopicProvider.notifier).state = t.key),
          ],
        ),
      ),
    );
  }
}
