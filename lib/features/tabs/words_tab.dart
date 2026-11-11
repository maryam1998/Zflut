import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/dictionary_topics.dart';
import '../../core/constants/level_colors.dart';
import '../../core/models/daily_word.dart';
import '../../core/providers/conversation_provider.dart';
import '../../core/providers/my_dictionary_provider.dart';
import '../../core/providers/words_filter_provider.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../core/usage/free_limit.dart';
import '../../core/usage/pro_i18n.dart';
import '../../core/usage/pro_status.dart';
import '../../core/usage/words_index.dart';
import '../../core/widgets/category_grid.dart';
import '../../core/widgets/locked_words_card.dart';
import '../words/widgets/word_list_view.dart';

/// تبِ «دیکشنری من»: لغات روزمره + لغات/عبارت‌های شخصی‌ای که کاربر با
/// «ذخیره برای داستان بعدی» نشان کرده (با برچسب «شخصی» و ✕).
/// بالای لیست، موارد (حتی لغاتِ جدیدی که خودت اضافه می‌کنی) بر اساسِ موضوع
/// (غذا، سفر، سلامت، ...) دسته‌بندی می‌شوند؛ لغت، عبارت و اسلنگ هرکدام داخلِ
/// موضوعِ خودشان قرار می‌گیرند (ردیفِ جداگانه‌ای برای نوع نیست).
///
/// 💎 نسخه‌ی رایگان: در کلِ تب فقط [kFreeDictionaryWords] لغت باز است (از بینِ موضوع‌ها
/// پخش شده)؛ بقیه قفل‌اند ولی شمارِ کل/قفلِ هر موضوع و سطح به کاربر نشان داده می‌شود.
class WordsTab extends ConsumerWidget {
  const WordsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = ref.watch(wordsTabItemsProvider);
    final base = ref.watch(wordsTabBaseItemsProvider);
    final all = ref.watch(allDailyWordsProvider);
    final personal = ref.watch(myDictionaryWordsProvider);
    final topic = ref.watch(wordsTopicProvider);
    // 💎 کاربرِ رایگان: فقط ۲۰ لغتِ باز؛ کلِ لغاتِ هر موضوع/سطح از ایندکس شمرده می‌شود
    final isPro = ref.watch(isProProvider);
    final free = isPro ? const <DailyWord>[] : ref.watch(_freeDictionaryProvider);
    final index = isPro ? null : ref.watch(wordsIndexProvider).valueOrNull;
    final filter = ref.watch(wordsFilterProvider);
    final ui = Localizations.localeOf(context).languageCode;

    // 🗂️ شبکه‌ی دسته‌ها: بدونِ دسته/«همه»/جستجو ← شبکه؛ وگرنه لیستِ لغات
    final searching = filter.query.trim().isNotEmpty;
    final allOpen = ref.watch(categoryAllOpenProvider('words'));
    final gridMode = topic.isEmpty && !allOpen && !searching;
    // جستجو همیشه روی همه‌ی دسته‌ها کار می‌کند
    final scope = searching ? const <String>{} : topic;
    final shown = gridMode ? const <DailyWord>[] : (searching ? base : words);

    // 💎 فقط لغاتِ باز (و شخصی) — برای شمارشِ چیپ‌ها وقتی جستجو فعال است
    List<DailyWord> gated(List<DailyWord> src) {
      if (isPro) return src;
      final ids = {for (final w in free) w.sid};
      return [
        for (final w in src)
          if (w.isPersonal || ids.contains(w.sid)) w,
      ];
    }

    final lockedInfo = isPro
        ? null
        : _scopedLockedInfo(
            index: index,
            free: free,
            groups: scope,
            levels: filter.levels,
            query: filter.query,
            groupLabel: (k) => dictTopicByKey(k)?.label(ui),
            scopeLabel: scope.length == 1
                ? dictTopicByKey(scope.first)?.label(ui)
                : null,
          );
    return WordListView(
      // با عوض‌شدنِ دسته، لیست از اول (و اسکرول از بالا) شروع می‌شود
      key: ValueKey('words-${(topic.toList()..sort()).join(',')}'),
      listId: 'words',
      words: shown,
      gridMode: gridMode,
      hasAnyData: all.isNotEmpty || personal.isNotEmpty,
      loading: ref.watch(dailyWordsLoaderProvider).isLoading,
      afterHeading: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!isPro && index != null && free.isNotEmpty)
            _ProBanner(
              free: free.length,
              total: index.total('daily'),
            ),
          if (gridMode)
            CategoryGrid(
              list: 'daily',
              items: _dictItems(
                context: context,
                base: base,
                topics: ref.watch(wordsTabTopicsProvider),
                index: index,
                free: free,
                levels: filter.levels,
              ),
              onTap: (k) {
                if (k == null) {
                  ref.read(categoryAllOpenProvider('words').notifier).state =
                      true;
                } else {
                  ref.read(wordsTopicProvider.notifier).state = {k};
                }
              },
            )
          else if (!searching)
            CategoryBackBar(
              list: 'daily',
              categoryKey: topic.length == 1 ? topic.first : null,
              label: topic.length == 1
                  ? (dictTopicByKey(topic.first)?.label(ui) ?? topic.first)
                  : (ui == 'fa' || ui == 'ar' ? 'همه' : 'All'),
              onBack: () {
                ref.read(wordsTopicProvider.notifier).state = const <String>{};
                ref.read(categoryAllOpenProvider('words').notifier).state =
                    false;
              },
            ),
        ],
      ),
      freeSource: isPro ? all : free, // 💎 فقط ۲۰ لغتِ رایگان
      lockedInfo: lockedInfo,
      levelAvailability:
          isPro ? null : _levelAvailability(index, free, scope),
    );
  }
}

/// 🗂️ کارت‌های شبکه‌ی دسته‌ها (با احترام به فیلترِ سطح). کاربرِ رایگان: «باز از کل».
List<CategoryItem> _dictItems({
  required BuildContext context,
  required List<DailyWord> base,
  required Map<String, String> topics,
  required WordsIndex? index,
  required List<DailyWord> free,
  required Set<String> levels,
}) {
  final ui = Localizations.localeOf(context).languageCode;
  final isFree = index != null; // فقط برای کاربرِ رایگان ایندکس داریم
  final perTopic = <String, int>{};
  final personalPer = <String, int>{};
  var personalAll = 0;
  for (final w in base) {
    final t = topics[w.sid] ?? kTopicOther;
    perTopic[t] = (perTopic[t] ?? 0) + 1;
    if (w.isPersonal) {
      personalPer[t] = (personalPer[t] ?? 0) + 1;
      personalAll++;
    }
  }
  int totalOf(String k) => index != null
      ? index.total('daily', groups: {k}, levels: levels) +
          (personalPer[k] ?? 0)
      : (perTopic[k] ?? 0);
  int? freeOf(String k) =>
      isFree ? _freeCount(free, {k}, levels) + (personalPer[k] ?? 0) : null;

  final allTotal = index != null
      ? index.total('daily', levels: levels) + personalAll
      : base.length;
  return [
    CategoryItem(
      key: null,
      label: ui == 'fa' || ui == 'ar' ? 'همه' : 'All',
      total: allTotal,
      free: isFree ? _freeCount(free, <String>{}, levels) + personalAll : null,
    ),
    for (final t in kDictTopics)
      if (totalOf(t.key) > 0)
        CategoryItem(
          key: t.key,
          label: t.label(ui),
          total: totalOf(t.key),
          free: freeOf(t.key),
        ),
  ];
}

// ═══════════════════════════════════════════════════════════════════
// 💎 انتخابِ ۲۰ لغتِ رایگان
// از هر موضوع به‌نوبت یکی (ساده‌ترین‌ها ــ A1 ــ اول)، تا همه‌ی موضوع‌ها یک نمونه داشته
// باشند. فقط به لغاتِ «بدونِ فیلتر» وابسته است، پس با عوض‌کردنِ سطح/جستجو/موضوع
// لغاتِ رایگان عوض نمی‌شوند (راهِ دورزدنِ سقف نیست).
// ═══════════════════════════════════════════════════════════════════

const Map<String, int> _kLevelOrder = {
  'A1': 1,
  'A2': 2,
  'B1': 3,
  'B2': 4,
  'C1': 5,
  'C2': 6,
};

String _topicOfFree(DailyWord w) =>
    w.category.isEmpty ? kTopicOther : w.category;

final _freeDictionaryProvider = Provider<List<DailyWord>>((ref) {
  final all = ref.watch(allDailyWordsProvider);
  if (all.isEmpty) return const <DailyWord>[];

  final pos = <String, int>{};
  final groups = <String, List<DailyWord>>{};
  for (var i = 0; i < all.length; i++) {
    final w = all[i];
    if (w.isPersonal) continue;
    pos[w.sid] = i;
    groups.putIfAbsent(_topicOfFree(w), () => <DailyWord>[]).add(w);
  }
  for (final g in groups.values) {
    g.sort((a, b) {
      final r = (_kLevelOrder[a.level] ?? 99)
          .compareTo(_kLevelOrder[b.level] ?? 99);
      return r != 0 ? r : (pos[a.sid] ?? 0).compareTo(pos[b.sid] ?? 0);
    });
  }
  final known = <String>[for (final t in kDictTopics) t.key];
  final extra = [
    for (final k in groups.keys)
      if (!known.contains(k)) k,
  ]..sort();
  final order = <String>[...known, ...extra];

  final picked = <String>{};
  var round = 0;
  while (picked.length < kFreeDictionaryWords) {
    var added = false;
    for (final k in order) {
      final g = groups[k];
      if (g == null || round >= g.length) continue;
      picked.add(g[round].sid);
      added = true;
      if (picked.length >= kFreeDictionaryWords) break;
    }
    if (!added) break;
    round++;
  }
  // ترتیبِ اصلیِ لیست حفظ می‌شود
  return [
    for (final w in all)
      if (picked.contains(w.sid)) w,
  ];
});

int _freeCount(List<DailyWord> free, Set<String> groups, Set<String> levels) {
  var n = 0;
  for (final w in free) {
    if (groups.isNotEmpty && !groups.contains(_topicOfFree(w))) continue;
    if (levels.isNotEmpty && !levels.contains(w.level)) continue;
    n++;
  }
  return n;
}

/// کارتِ «لغاتِ قفل‌شده»: کل (از ایندکس) − لغاتِ بازِ همین محدوده
LockedWordsInfo? _scopedLockedInfo({
  required WordsIndex? index,
  required List<DailyWord> free,
  required Set<String> groups,
  required Set<String> levels,
  required String query,
  required String? Function(String key) groupLabel,
  String? scopeLabel,
}) {
  if (index == null) return null;
  final total = index.total('daily', groups: groups, levels: levels);
  final locked = total - _freeCount(free, groups, levels);
  if (locked <= 0) return null;

  final byLevel = groups.length == 1;
  final chips = <LockedChipData>[];
  if (byLevel) {
    for (final lv in kIndexLevels) {
      if (levels.isNotEmpty && !levels.contains(lv)) continue;
      final n = index.total('daily', groups: groups, levels: {lv}) -
          _freeCount(free, groups, {lv});
      if (n > 0) chips.add(LockedChipData(lv, n, color: levelColor(lv)));
    }
  } else {
    final rows = <MapEntry<String, int>>[];
    for (final t in kDictTopics) {
      if (groups.isNotEmpty && !groups.contains(t.key)) continue;
      final n = index.total('daily', groups: {t.key}, levels: levels) -
          _freeCount(free, {t.key}, levels);
      if (n > 0) rows.add(MapEntry(t.key, n));
    }
    rows.sort((a, b) => b.value.compareTo(a.value));
    for (final e in rows) {
      final label = groupLabel(e.key);
      if (label == null) continue;
      chips.add(LockedChipData(label, e.value));
      if (chips.length >= 8) break;
    }
  }
  final lv = [for (final l in kIndexLevels) if (levels.contains(l)) l];
  return LockedWordsInfo(
    locked: locked,
    total: total,
    scopeLabel: scopeLabel,
    levelsLabel: lv.isEmpty ? null : lv.join(' · '),
    chips: chips,
    chipsAreLevels: byLevel,
    searchActive: query.trim().isNotEmpty,
    query: query.trim(),
  );
}

/// چیپ‌های سطح: «قفل» = لغت دارد ولی هیچ‌کدام باز نیست · «خالی» = لغتی ندارد
LevelAvailability? _levelAvailability(
    WordsIndex? index, List<DailyWord> free, Set<String> groups) {
  if (index == null) return null;
  final locked = <String>{};
  final empty = <String>{};
  for (final lv in kIndexLevels) {
    final t = index.total('daily', groups: groups, levels: {lv});
    if (t == 0) {
      empty.add(lv);
    } else if (_freeCount(free, groups, {lv}) == 0) {
      locked.add(lv);
    }
  }
  return LevelAvailability(locked, empty);
}

// ═══════════════════════════════════════════════════════════════════
// بنرِ Pro (بالای تب، فقط نسخه‌ی رایگان)
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
                            t('dict_banner_title', {
                              'free': free,
                              'total': total,
                            }),
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

/// چیپِ موضوع؛ اگر بخشی از آن قفل باشد یک 🔒 کوچک کنارش می‌نشیند.
class _TopicChip extends StatelessWidget {
  final String label;
  final bool active;
  final bool locked;
  final VoidCallback onTap;
  const _TopicChip({
    required this.label,
    required this.active,
    required this.locked,
    required this.onTap,
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
            border: Border.all(
                color: active ? c.gold : c.cardBorder, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: active ? c.headerTo : c.ink,
                  fontSize: 12.5,
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

class _TopicFilter extends ConsumerWidget {
  final List<DailyWord> all;

  /// 💎 ۲۰ لغتِ بازِ کاربرِ رایگان (برای Pro خالی)
  final List<DailyWord> free;
  const _TopicFilter({required this.all, required this.free});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 💎 کاربرِ رایگان: شمارِ «کلِ» هر موضوع از ایندکس می‌آید (نه فقط لغاتِ باز)
    final isPro = ref.watch(isProProvider);
    final filter = ref.watch(wordsFilterProvider);
    final idx = isPro ? null : ref.watch(wordsIndexProvider).valueOrNull;
    // با جستجوی فعال، شمارش‌ها از لغاتِ باز می‌آید (جستجو فقط روی لغاتِ رایگان است)
    final index = filter.query.trim().isEmpty ? idx : null;
    if (all.isEmpty && index == null) return const SizedBox.shrink();
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
    var allCount = all.length;
    if (index != null) {
      // لغاتِ شخصیِ کاربر (همیشه باز) + کلِ لغاتِ روزمره‌ی هر موضوع
      final personal = <String, int>{};
      var personalAll = 0;
      for (final w in all) {
        if (!w.isPersonal) continue;
        final t = topics[w.sid] ?? kTopicOther;
        personal[t] = (personal[t] ?? 0) + 1;
        personalAll++;
      }
      perTopic.clear();
      for (final t in kDictTopics) {
        perTopic[t.key] = index.total('daily',
                groups: {t.key}, levels: filter.levels) +
            (personal[t.key] ?? 0);
      }
      allCount = index.total('daily', levels: filter.levels) + personalAll;
    }

    // 🔒 موضوعی که بخشی از لغاتش قفل است (مستقل از سطح/جستجو)
    final freeByTopic = <String, int>{};
    for (final w in free) {
      final t = _topicOfFree(w);
      freeByTopic[t] = (freeByTopic[t] ?? 0) + 1;
    }
    bool topicLocked(String key) =>
        idx != null &&
        idx.total('daily', groups: {key}) > (freeByTopic[key] ?? 0);
    final anyLocked = idx != null && idx.total('daily') > free.length;

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
            _TopicChip(
              label: '$allLabel ($allCount)',
              active: topicSel.isEmpty,
              locked: anyLocked,
              onTap: () => ref.read(wordsTopicProvider.notifier).state =
                  const <String>{},
            ),
            for (final t in kDictTopics)
              if ((perTopic[t.key] ?? 0) > 0)
                _TopicChip(
                  label: '${t.label(ui)} (${perTopic[t.key]})',
                  active: topicSel.contains(t.key),
                  locked: topicLocked(t.key),
                  onTap: () {
                    final n = Set<String>.of(topicSel);
                    if (!n.remove(t.key)) n.add(t.key);
                    ref.read(wordsTopicProvider.notifier).state = n;
                  },
                ),
          ]),
        ],
      ),
    );
  }
}
