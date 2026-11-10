import 'package:flutter/material.dart';

import '../constants/level_colors.dart';
import '../theme/app_theme_colors.dart';
import '../usage/free_limit.dart';
import '../usage/pro_i18n.dart';
import '../usage/words_index.dart';

/// یک چیپِ شمارش داخلِ کارتِ قفل (سطح یا موضوع)
class LockedChipData {
  final String label;
  final int count;
  final Color? color;
  const LockedChipData(this.label, this.count, {this.color});
}

/// اطلاعاتِ کارتِ «لغاتِ قفل‌شده» برای کاربرِ رایگان
class LockedWordsInfo {
  /// لغاتِ قفل‌شده در محدوده‌ی فعلی
  final int locked;

  /// کلِ لغاتِ محدوده‌ی فعلی (رایگان + قفل)
  final int total;

  /// نامِ دسته‌ی انتخاب‌شده (null = همه / چند دسته)
  final String? scopeLabel;

  /// سطح‌های انتخاب‌شده، مثلاً «B1 · B2» (null = همه‌ی سطح‌ها)
  final String? levelsLabel;

  /// تفکیک: سطح‌ها (وقتی یک دسته انتخاب شده) یا موضوع‌ها (وقتی همه)
  final List<LockedChipData> chips;
  final bool chipsAreLevels;

  /// جستجو فعال است (جستجو فقط روی لغاتِ رایگان کار می‌کند)
  final bool searchActive;

  /// متنِ جستجو
  final String query;

  const LockedWordsInfo({
    required this.locked,
    required this.total,
    this.scopeLabel,
    this.levelsLabel,
    this.chips = const <LockedChipData>[],
    this.chipsAreLevels = false,
    this.searchActive = false,
    this.query = '',
  });

  int get free => total - locked;
}

/// ساختِ [LockedWordsInfo] از ایندکسِ شمارش؛ اگر چیزی قفل نیست (یا ایندکس نیست) null.
/// [groupLabel] نامِ نمایشیِ کلیدِ گروه را می‌دهد (null = آن گروه در چیپ‌ها نیاید).
LockedWordsInfo? buildLockedInfo({
  required WordsIndex? index,
  required String list,
  required Set<String> groups,
  String? category,
  required Set<String> levels,
  required String query,
  required String? Function(String key) groupLabel,
  String? scopeLabel,
}) {
  if (index == null) return null;
  final locked =
      index.locked(list, groups: groups, category: category, levels: levels);
  if (locked <= 0) return null;
  final total =
      index.total(list, groups: groups, category: category, levels: levels);

  final byLevel = category != null || groups.length == 1;
  final chips = <LockedChipData>[];
  if (byLevel) {
    final m = index.lockedByLevel(list,
        groups: groups, category: category, levels: levels);
    for (final e in m.entries) {
      chips.add(LockedChipData(e.key, e.value, color: levelColor(e.key)));
    }
  } else {
    final m = index.lockedByGroup(list, groups: groups, levels: levels);
    final sorted = m.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in sorted) {
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

String _n(int v) {
  final s = v.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

/// 🔒 کارتِ «لغاتِ بیشتر با Pro»: کلِ لغاتِ دسته، چندتایش رایگان است، چندتا قفل است
/// و قفل‌شده‌ها به چه سطح/موضوعی مربوط‌اند — تا کاربر ارزشِ Pro را ببیند.
class LockedWordsCard extends StatelessWidget {
  final LockedWordsInfo info;

  /// نتیجه‌ی رایگانی برای نمایش نیست (لیستِ باز خالی است) — برای متنِ جستجو
  final bool emptyResults;

  const LockedWordsCard({
    super.key,
    required this.info,
    this.emptyResults = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    String t(String k, [Map<String, Object> a = const <String, Object>{}]) =>
        ProI18n.t(context, k, a);

    // زیرعنوان: «در «دسته»» + سطح‌های انتخاب‌شده
    final subParts = <String>[
      if (info.scopeLabel != null) t('in_scope', {'scope': info.scopeLabel!}),
      if (info.levelsLabel != null) info.levelsLabel!,
    ];
    final subtitle = subParts.isEmpty ? null : subParts.join(' · ');

    final title = t('words_locked_title', {'n': _n(info.locked)});
    final progressText =
        t('words_progress', {'free': _n(info.free), 'total': _n(info.total)});
    final chipsTitle =
        t(info.chipsAreLevels ? 'locked_by_level' : 'locked_by_topic');
    final cta = t('words_cta');
    final searchNote = t('search_note', {'total': _n(info.total)});

    final value = info.total <= 0 ? 0.0 : info.free / info.total;

    Widget skeletonRow(double w1, double w2) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: c.surface.withOpacity(0.7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.cardBorder.withOpacity(0.7)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FractionallySizedBox(
                      widthFactor: w1,
                      child: Container(
                        height: 11,
                        decoration: BoxDecoration(
                          color: c.inkSoft.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FractionallySizedBox(
                      widthFactor: w2,
                      child: Container(
                        height: 9,
                        decoration: BoxDecoration(
                          color: c.inkSoft.withOpacity(0.11),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(Icons.lock_outline, size: 18, color: c.gold.withOpacity(0.85)),
            ],
          ),
        );

    Widget perk(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Icon(Icons.check_circle, size: 16, color: c.gold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text,
                    style: TextStyle(
                        color: c.ink,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );

    return InkWell(
      onTap: FreeLimit.reportLocked,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [c.goldSoft.withOpacity(0.55), c.goldSoft.withOpacity(0.18)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.gold, width: 1.2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (info.searchActive) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock, color: c.gold, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (emptyResults && info.query.isNotEmpty) ...[
                          Text(
                            t('search_empty_title', {'q': info.query}),
                            style: TextStyle(
                                color: c.ink,
                                fontSize: 14,
                                height: 1.4,
                                fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                        ],
                        Text(
                          searchNote,
                          style: TextStyle(
                              color: emptyResults ? c.inkSoft : c.ink,
                              fontSize: 13,
                              height: 1.5,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: c.gold.withOpacity(0.18),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.lock, color: c.gold, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: TextStyle(
                                color: c.ink,
                                fontSize: 15,
                                fontWeight: FontWeight.w800)),
                        if (subtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(subtitle,
                                style: TextStyle(
                                    color: c.inkSoft,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: c.gold,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text('PRO',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: value.clamp(0.0, 1.0),
                  minHeight: 7,
                  backgroundColor: c.gold.withOpacity(0.2),
                  valueColor: AlwaysStoppedAnimation<Color>(c.gold),
                ),
              ),
              const SizedBox(height: 6),
              Text(progressText,
                  style: TextStyle(
                      color: c.inkSoft,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              if (info.chips.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(chipsTitle,
                    style: TextStyle(
                        color: c.inkSoft,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final ch in info.chips)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: (ch.color ?? c.gold).withOpacity(0.14),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: (ch.color ?? c.gold).withOpacity(0.55)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lock,
                                size: 11, color: ch.color ?? c.gold),
                            const SizedBox(width: 5),
                            Text('${ch.label} · ${_n(ch.count)}',
                                style: TextStyle(
                                    color: c.ink,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              skeletonRow(0.55, 0.8),
              skeletonRow(0.4, 0.65),
              skeletonRow(0.62, 0.5),
              const SizedBox(height: 4),
              perk(t('perk_words', {'total': _n(info.total)})),
              perk(t('perk_levels')),
              perk(t('perk_search')),
            ],
            const SizedBox(height: 6),
            FilledButton.icon(
              onPressed: FreeLimit.reportLocked,
              icon: const Icon(Icons.workspace_premium, size: 18),
              label: Text(cta),
              style: FilledButton.styleFrom(
                backgroundColor: c.gold,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                textStyle:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
