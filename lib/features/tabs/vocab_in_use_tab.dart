import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/vocab_topics.dart';
import '../../core/models/daily_word.dart';
import '../../core/providers/word_sources_provider.dart';
import '../../core/providers/words_filter_provider.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../core/usage/free_limit.dart';
import '../../core/usage/pro_i18n.dart';
import '../../core/usage/pro_status.dart';
import '../../core/usage/words_index.dart';
import '../../core/widgets/locked_words_card.dart';
import '../words/widgets/word_list_view.dart';

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
    // 💎 کاربرِ رایگان: کلِ لغاتِ هر موضوع + چندتایش قفل است (فقط ده لغتِ هر موضوع باز است)
    final isPro = ref.watch(isProProvider);
    final filter = ref.watch(wordsFilterProvider);
    final proIndex = isPro ? null : ref.watch(wordsIndexProvider).valueOrNull;
    final ui = Localizations.localeOf(context).languageCode;
    String? catSel;
    if (topicKey.length == 1 && cat != null) {
      final t = vocabTopicByKey(topicKey.first);
      if (t != null && t.categories.contains(cat)) catSel = cat;
    }
    final lockedInfo = isPro
        ? null
        : buildLockedInfo(
            index: ref.watch(wordsIndexProvider).valueOrNull,
            list: 'vocab',
            groups: topicKey,
            category: catSel,
            levels: filter.levels,
            query: filter.query,
            groupLabel: (k) => vocabTopicByKey(k)?.label(ui),
            scopeLabel: catSel != null
                ? vocabCategoryLabel(catSel, ui)
                : (topicKey.length == 1
                    ? vocabTopicByKey(topicKey.first)?.label(ui)
                    : null),
          );
    return WordListView(
      // با عوض‌شدنِ موضوع/دسته، لیست از اول (و اسکرول از بالا) شروع می‌شود
      key: ValueKey('vocab-${(topicKey.toList()..sort()).join(',')}-${cat ?? '_'}'),
      listId: 'vocab-in-use',
      words: words,
      hasAnyData: src.valueOrNull?.isNotEmpty ?? false,
      loading: src.isLoading,
      afterHeading: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!isPro && proIndex != null && proIndex.total('vocab') > 0)
            _ProBanner(
              free: proIndex.total('vocab') - proIndex.locked('vocab'),
              total: proIndex.total('vocab'),
            ),
          _TopicFilter(all: src.valueOrNull ?? const <DailyWord>[]),
        ],
      ),
      freeSource: src.valueOrNull, // 💎 ده لغتِ اولِ هر موضوع رایگان
      lockedInfo: lockedInfo,
      levelAvailability: isPro
          ? null
          : ref
              .watch(wordsIndexProvider)
              .valueOrNull
              ?.availability('vocab', groups: topicKey, category: catSel),
    );
  }
}

class _TopicFilter extends ConsumerWidget {
  final List<DailyWord> all;
  const _TopicFilter({required this.all});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 💎 کاربرِ رایگان: شمارِ «کلِ» هر موضوع/دسته از ایندکس می‌آید (نه فقط لغاتِ باز)
    final isPro = ref.watch(isProProvider);
    final index = isPro ? null : ref.watch(wordsIndexProvider).valueOrNull;
    if (all.isEmpty && index == null) return const SizedBox.shrink();
    final c = context.appColors;
    final ui = Localizations.localeOf(context).languageCode;
    final fa = ui == 'fa' || ui == 'ar';
    final topicSel = ref.watch(vocabTopicProvider);
    final catSel = ref.watch(vocabCategoryProvider);
    // ردیفِ دسته‌های ریز فقط وقتی دقیقاً یک موضوع انتخاب شده
    final topic = topicSel.length == 1 ? vocabTopicByKey(topicSel.first) : null;

    // شمارش‌ها از کلِ لیست (قبل از فیلترِ سطح/جستجو) تا ثابت بمانند
    final perCat = <String, int>{};
    for (final w in all) {
      perCat[w.category] = (perCat[w.category] ?? 0) + 1;
    }
    int catCount(String x) =>
        index != null ? index.total('vocab', category: x) : (perCat[x] ?? 0);
    int topicCount(VocabTopic t) {
      if (index != null) return index.total('vocab', groups: {t.key});
      var n = 0;
      for (final x in t.categories) {
        n += perCat[x] ?? 0;
      }
      return n;
    }

    Widget chip(String label, bool active, VoidCallback onTap,
        {double fs = 12.5, bool locked = false}) {
      return _TopicChip(
        label: label,
        active: active,
        locked: locked,
        fontSize: fs,
        onTap: onTap,
      );
    }

    // 🔒 موضوع/دسته‌ای که بخشی از لغاتش قفل است
    bool topicLocked(String key) =>
        index != null && index.locked('vocab', groups: {key}) > 0;
    bool catLocked(String key) =>
        index != null && index.locked('vocab', category: key) > 0;
    final anyLocked = index != null && index.locked('vocab') > 0;

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
            chip('$allLabel (${index != null ? index.total('vocab') : all.length})',
                topicSel.isEmpty, () {
              ref.read(vocabTopicProvider.notifier).state = const <String>{};
              ref.read(vocabCategoryProvider.notifier).state = null;
            }, locked: anyLocked),
            for (final t in kVocabTopics)
              if (topicCount(t) > 0)
                chip('${t.label(ui)} (${topicCount(t)})',
                    topicSel.contains(t.key), () {
                  final n = Set<String>.of(topicSel);
                  if (!n.remove(t.key)) n.add(t.key);
                  ref.read(vocabTopicProvider.notifier).state = n;
                  ref.read(vocabCategoryProvider.notifier).state = null;
                }, locked: topicLocked(t.key)),
          ]),
          if (topic != null && topic.categories.length > 1) ...[
            const SizedBox(height: 6),
            row([
              chip('$allLabel (${topicCount(topic)})', catSel == null,
                  () => ref.read(vocabCategoryProvider.notifier).state = null,
                  fs: 11.5, locked: topicLocked(topic.key)),
              for (final x in topic.categories)
                if (catCount(x) > 0)
                  chip('${vocabCategoryLabel(x, ui)} (${catCount(x)})', catSel == x,
                      () => ref.read(vocabCategoryProvider.notifier).state = x,
                      fs: 11.5, locked: catLocked(x)),
            ]),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 💎 بنرِ Pro (بالای تب، فقط نسخه‌ی رایگان) — هم‌شکلِ «دیکشنری من»
// ═══════════════════════════════════════════════════════════════════

class _ProBanner extends StatelessWidget {
  final int free;
  final int total;
  const _ProBanner({required this.free, required this.total});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    String t(String k, Map<String, Object> a) => ProI18n.t(context, k, a);
    final locked = total - free < 0 ? 0 : total - free;
    final value = total <= 0 ? 0.0 : (free / total).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: FreeLimit.reportLocked,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  c.goldSoft.withOpacity(0.75),
                  c.goldSoft.withOpacity(0.25),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.gold, width: 1.2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: c.gold,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: c.gold.withOpacity(0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.workspace_premium,
                          color: Colors.white, size: 21),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t('dict_banner_title',
                                {'free': free, 'total': total}),
                            style: TextStyle(
                                color: c.ink,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            t('dict_banner_sub', {'locked': locked}),
                            style: TextStyle(
                                color: c.inkSoft,
                                fontSize: 12,
                                height: 1.45,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: value,
                          minHeight: 6,
                          backgroundColor: c.gold.withOpacity(0.2),
                          valueColor: AlwaysStoppedAnimation<Color>(c.gold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: c.gold,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.lock_open_rounded,
                              color: Colors.white, size: 14),
                          const SizedBox(width: 5),
                          Text(
                            t('dict_banner_cta', const <String, Object>{}),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// چیپِ موضوع/دسته — هم‌شکلِ «دیکشنری من»؛ اگر بخشی از آن قفل باشد 🔒 کنارش می‌نشیند.
class _TopicChip extends StatelessWidget {
  final String label;
  final bool active;
  final bool locked;
  final double fontSize;
  final VoidCallback onTap;
  const _TopicChip({
    required this.label,
    required this.active,
    required this.locked,
    required this.onTap,
    this.fontSize = 12.5,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: active ? c.gold : c.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: active ? c.gold : c.cardBorder, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: active ? c.headerTo : c.ink,
                  fontSize: fontSize,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w400,
                ),
              ),
              if (locked) ...[
                const SizedBox(width: 5),
                Icon(Icons.lock_rounded,
                    size: 12, color: active ? c.headerTo : c.gold),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
