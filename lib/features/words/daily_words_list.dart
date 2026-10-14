import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/cefr_levels.dart';
import '../../core/models/daily_word.dart';
import '../../core/providers/conversation_provider.dart';
import '../../core/providers/language_selection_provider.dart';
import '../../core/providers/translation_provider.dart';
import '../../core/providers/words_filter_provider.dart';
import '../../core/theme/app_theme_colors.dart';

class DailyWordsList extends ConsumerWidget {
  const DailyWordsList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final words = ref.watch(filteredDailyWordsProvider);
    final all = ref.watch(allDailyWordsProvider);
    final sel = ref.watch(languageSelectionProvider);
    final filter = ref.watch(wordsFilterProvider);
    final notifier = ref.read(wordsFilterProvider.notifier);

    // زبان‌های نمایش برای هر لغت
    final langsToShow = <String>[
      if (sel.native != 'en') sel.native,
      ...sel.targets.where((t) => t != 'en'),
    ];

    return Column(
      children: [
        // ═══ نوار فیلتر سطح + جستجو ═══
        Container(
          color: c.paper,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ردیف سطح‌ها
              SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: 1 + kCefrLevels.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 7),
                  itemBuilder: (_, i) {
                    final lvl = i == 0 ? 'all' : kCefrLevels[i - 1];
                    final active = filter.level == lvl;
                    final label = lvl == 'all' ? 'همه سطوح' : lvl;
                    return GestureDetector(
                      onTap: () => notifier.setLevel(lvl),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: EdgeInsets.symmetric(
                          horizontal: lvl == 'all' ? 16 : 14,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: active ? c.headerFrom : Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: active ? c.headerFrom : c.cardBorder,
                            width: 1.1,
                          ),
                          boxShadow: active
                              ? [
                                  BoxShadow(
                                    color: c.headerFrom.withOpacity(0.25),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          label,
                          style: TextStyle(
                            color: active ? c.headerText : c.inkSoft,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),

              // کادر جستجو
              Container(
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.cardBorder, width: 1),
                ),
                child: TextField(
                  onChanged: notifier.setQuery,
                  textAlign: TextAlign.right,
                  style: TextStyle(color: c.ink, fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText: 'جستجوی لغت...',
                    hintStyle: TextStyle(
                      color: c.inkSoft.withOpacity(0.55),
                      fontSize: 13.5,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      color: c.inkSoft,
                      size: 19,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
            ],
          ),
        ),

        // ═══ لیست لغات ═══
        Expanded(
          child: words.isEmpty
              ? _EmptyState(c: c, hasData: all.isNotEmpty)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 90),
                  itemCount: words.length,
                  itemBuilder: (_, i) => _WordCard(
                    word: words[i],
                    langsToShow: langsToShow,
                  ),
                ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
class _EmptyState extends StatelessWidget {
  final dynamic c;
  final bool hasData;
  const _EmptyState({required this.c, required this.hasData});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.gold.withOpacity(0.10),
                border: Border.all(
                  color: c.gold.withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              child: Icon(Icons.search_off, size: 32, color: c.gold),
            ),
            const SizedBox(height: 18),
            Text(
              hasData ? 'چیزی پیدا نشد' : 'داده‌ای بارگذاری نشد',
              style: TextStyle(
                color: c.ink,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              hasData
                  ? 'فیلتر سطح یا جستجو را تغییر بده.'
                  : 'فایل daily_words.json را چک کن.',
              style: TextStyle(color: c.inkSoft, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
class _WordCard extends StatelessWidget {
  final DailyWord word;
  final List<String> langsToShow;

  const _WordCard({
    required this.word,
    required this.langsToShow,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final levelColor = _levelColor(word.level);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: c.cardBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: c.ink.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: levelColor.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  word.level,
                  style: TextStyle(
                    color: levelColor,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  word.en,
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 3.5,
                ),
                decoration: BoxDecoration(
                  color: c.paperDark,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _posFa(word.pos),
                  style: TextStyle(
                    color: c.inkSoft,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (langsToShow.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...langsToShow.map(
              (code) => _TranslationRow(
                en: word.en,
                knownFa: word.fa,
                langCode: code,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static Color _levelColor(String level) {
    switch (level) {
      case 'A1': return const Color(0xFF2E9E7B);
      case 'A2': return const Color(0xFF4C7A8A);
      case 'B1': return const Color(0xFF7A5FA8);
      case 'B2': return const Color(0xFFA34960);
      case 'C1': return const Color(0xFFD9752E);
      case 'C2': return const Color(0xFF9E3B3B);
      default:   return const Color(0xFF4B5551);
    }
  }

  static String _posFa(String pos) {
    const map = {
      'noun': 'اسم',
      'verb': 'فعل',
      'adjective': 'صفت',
      'adverb': 'قید',
      'preposition': 'حرف اضافه',
      'pronoun': 'ضمیر',
      'conjunction': 'حرف ربط',
      'article': 'حرف تعریف',
      'interjection': 'شبه‌جمله',
      'numeral': 'عدد',
      'auxiliary': 'فعل کمکی',
      'other': 'سایر',
      'determiner': 'حرف تعیین‌کننده',
      'exclamation': 'صوت',
      'idiom': 'اصطلاح',
      'slang': 'اسلنگ',
    };
    return map[pos] ?? pos;
  }
}

// ═══════════════════════════════════════════════════════════════════
class _TranslationRow extends ConsumerWidget {
  final String en;
  final String knownFa;
  final String langCode;

  const _TranslationRow({
    required this.en,
    required this.knownFa,
    required this.langCode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;

    if (langCode == 'fa' && knownFa.isNotEmpty) {
      return _row(context, c, knownFa);
    }

    final async = ref.watch(
      translationProvider((text: en, to: langCode, from: 'en', verify: false)),
    );

    return async.when(
      loading: () => _row(context, c, 'در حال ترجمه...', loading: true),
      error: (_, __) => const SizedBox.shrink(),
      data: (text) {
        if (text.isEmpty) return const SizedBox.shrink();
        return _row(context, c, text);
      },
    );
  }

  Widget _row(
    BuildContext context,
    dynamic c,
    String text, {
    bool loading = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
              color: c.paperDark,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: c.cardBorder, width: 0.6),
            ),
            child: Text(
              langCode.toUpperCase(),
              style: TextStyle(
                color: c.gold,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.4,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: loading ? c.inkSoft : const Color(0xFF0F5C34),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
