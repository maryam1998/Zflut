import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/daily_word.dart';
import '../../core/providers/conversation_provider.dart';
import '../../core/providers/words_filter_provider.dart';
import '../../core/theme/app_theme_colors.dart';
import '../shell/widgets/filter_bar.dart';

class DailyWordsList extends ConsumerWidget {
  const DailyWordsList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final words = ref.watch(filteredDailyWordsProvider);
    final all = ref.watch(allDailyWordsProvider);

    // ═══════════════════════════════════════════════════════════════
    // یک CustomScrollView که هم FilterBar هم لیست رو با هم اسکرول می‌کنه.
    // این ساختار با NestedScrollView که در AppShell است درست کار می‌کنه.
    // ═══════════════════════════════════════════════════════════════
    return CustomScrollView(
      // از primary استفاده می‌کنیم تا NestedScrollView هماهنگی داشته باشه
      slivers: [
        // FilterBar — با محتوا اسکرول می‌شه
        const SliverToBoxAdapter(
          child: FilterBar(
            searchHint: 'جستجوی لغت...',
            showLevels: true,
            showSort: true,
          ),
        ),

        if (words.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyState(
              c: c,
              hasData: all.isNotEmpty,
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => _WordCard(word: words[i]),
              childCount: words.length,
            ),
          ),

        // پایین‌ترین فاصله — تا آخرین کارت زیر پلیر پنهان نشه
        const SliverToBoxAdapter(child: SizedBox(height: 90)),
      ],
    );
  }
}

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
                border: Border.all(color: c.gold.withOpacity(0.3), width: 1.5),
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
// کارت لغت — سایز متعادل (نه بزرگ قبلی، نه ریز آخری)
// ═══════════════════════════════════════════════════════════════════
class _WordCard extends StatelessWidget {
  final DailyWord word;
  const _WordCard({required this.word});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final levelColor = _levelColor(word.level);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
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
      child: Row(
        children: [
          // Level badge — متعادل: 40px
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

          // Word + meaning
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  word.en,
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  word.fa,
                  style: TextStyle(
                    color: c.inkSoft,
                    fontSize: 13,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),

          // POS badge — متعادل
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
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
