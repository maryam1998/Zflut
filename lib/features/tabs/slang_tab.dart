import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/slang_topics.dart';
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
    final proIndex = isPro ? null : ref.watch(wordsIndexProvider).valueOrNull;
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
      afterHeading: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!isPro && proIndex != null && proIndex.total('slang') > 0)
            _ProBanner(
              free: proIndex.total('slang') - proIndex.locked('slang'),
              total: proIndex.total('slang'),
            ),
          _SlangTopicFilter(all: src.valueOrNull ?? const <DailyWord>[]),
        ],
      ),
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

    Widget chip(String label, bool active, VoidCallback onTap,
        {bool locked = false}) {
      return _TopicChip(
        label: label,
        active: active,
        locked: locked,
        onTap: onTap,
      );
    }

    // 🔒 دسته‌ای که بخشی از لغاتش قفل است
    bool topicLocked(String key) =>
        index != null && index.locked('slang', groups: {key}) > 0;
    final anyLocked = index != null && index.locked('slang') > 0;

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            chip('${fa ? 'همه' : 'All'} (${index != null ? index.total('slang') : all.length})',
                sel.isEmpty,
                () => ref.read(slangTopicProvider.notifier).state = const <String>{},
                locked: anyLocked),
            for (final t in kSlangTopics)
              if (topicCount(t.key) > 0)
                chip('${t.label(ui)} (${topicCount(t.key)})', sel.contains(t.key),
                    () {
                  final n = Set<String>.of(sel);
                  if (!n.remove(t.key)) n.add(t.key);
                  ref.read(slangTopicProvider.notifier).state = n;
                }, locked: topicLocked(t.key)),
          ],
        ),
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
