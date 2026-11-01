import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/daily_word.dart';
import '../../core/providers/conversation_provider.dart';
import '../../core/providers/my_dictionary_provider.dart';
import '../../core/theme/app_theme_colors.dart';
import '../words/widgets/word_list_view.dart';
import '_hope_panel.dart' show HopeChoiceChip;

/// تبِ «دیکشنری من»: لغات روزمره + لغات/عبارت‌های شخصی‌ای که کاربر با
/// «ذخیره برای داستان بعدی» نشان کرده (با برچسب «شخصی» و ✕).
/// بالای لیست، موارد بر اساسِ نوع (لغت / عبارت و اصطلاح / اسلنگ / جمله / شخصی)
/// و برای لغت‌ها بر اساسِ نقشِ دستوری (اسم / فعل / صفت / ...) دسته‌بندی می‌شوند.
class WordsTab extends ConsumerWidget {
  const WordsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = ref.watch(wordsTabItemsProvider);
    final base = ref.watch(wordsTabBaseItemsProvider);
    final all = ref.watch(allDailyWordsProvider);
    final personal = ref.watch(myDictionaryWordsProvider);
    final kind = ref.watch(wordsKindProvider);
    final pos = ref.watch(wordsPosProvider);
    return WordListView(
      // با عوض‌شدنِ دسته، لیست از اول (و اسکرول از بالا) شروع می‌شود
      key: ValueKey('words-${kind ?? '_'}-${pos ?? '_'}'),
      listId: 'words',
      words: words,
      hasAnyData: all.isNotEmpty || personal.isNotEmpty,
      loading: ref.watch(dailyWordsLoaderProvider).isLoading,
      afterHeading: _KindFilter(all: base),
    );
  }
}

class _KindFilter extends ConsumerWidget {
  final List<DailyWord> all;
  const _KindFilter({required this.all});

  static String _kindLabel(String k, bool fa) {
    switch (k) {
      case kKindWord:
        return fa ? 'لغات' : 'Words';
      case kKindPhrase:
        return fa ? 'عبارات و اصطلاحات' : 'Phrases & idioms';
      case kKindSlang:
        return fa ? 'اسلنگ' : 'Slang';
      case kKindSentence:
        return fa ? 'جملات' : 'Sentences';
      case kKindPersonal:
        return fa ? 'شخصی' : 'Personal';
    }
    return k;
  }

  static String _posLabel(String p, bool fa) {
    switch (p) {
      case 'noun':
        return fa ? 'اسم' : 'Nouns';
      case 'verb':
        return fa ? 'فعل' : 'Verbs';
      case 'adjective':
        return fa ? 'صفت' : 'Adjectives';
      case 'adverb':
        return fa ? 'قید' : 'Adverbs';
      case 'other':
        return fa ? 'سایر' : 'Other';
    }
    return p;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (all.isEmpty) return const SizedBox.shrink();
    final c = context.appColors;
    final ui = Localizations.localeOf(context).languageCode;
    final fa = ui == 'fa' || ui == 'ar';
    final kind = ref.watch(wordsKindProvider);
    final posSel = ref.watch(wordsPosProvider);

    // شمارش‌ها از لیستِ پایه (بعد از فیلترِ سطح/جستجو)
    final perKind = <String, int>{};
    final perPos = <String, int>{};
    for (final w in all) {
      final k = wordKindOf(w);
      perKind[k] = (perKind[k] ?? 0) + 1;
      if (k == kKindWord) {
        final p = wordPosGroupOf(w);
        perPos[p] = (perPos[p] ?? 0) + 1;
      }
      if (w.isPersonal) {
        perKind[kKindPersonal] = (perKind[kKindPersonal] ?? 0) + 1;
      }
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
            chip('$allLabel (${all.length})', kind == null, () {
              ref.read(wordsKindProvider.notifier).state = null;
              ref.read(wordsPosProvider.notifier).state = null;
            }),
            for (final k in kWordKinds)
              if ((perKind[k] ?? 0) > 0)
                chip('${_kindLabel(k, fa)} (${perKind[k]})', kind == k, () {
                  ref.read(wordsKindProvider.notifier).state = k;
                  ref.read(wordsPosProvider.notifier).state = null;
                }),
          ]),
          if (kind == kKindWord && perPos.length > 1) ...[
            const SizedBox(height: 6),
            row([
              chip('$allLabel (${perKind[kKindWord] ?? 0})', posSel == null,
                  () => ref.read(wordsPosProvider.notifier).state = null,
                  fs: 11.5),
              for (final p in kWordPosGroups)
                if ((perPos[p] ?? 0) > 0)
                  chip('${_posLabel(p, fa)} (${perPos[p]})', posSel == p,
                      () => ref.read(wordsPosProvider.notifier).state = p,
                      fs: 11.5),
            ]),
          ],
        ],
      ),
    );
  }
}
