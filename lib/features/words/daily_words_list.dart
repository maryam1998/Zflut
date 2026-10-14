import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/daily_word.dart';
import '../../core/providers/conversation_provider.dart';
import '../../core/providers/words_filter_provider.dart';
import '../../core/theme/app_theme_colors.dart';

/// Sliver (نه ویجت اسکرول‌دار) تا داخل CustomScrollViewِ تب قرار بگیرد.
class DailyWordsList extends ConsumerWidget {
  const DailyWordsList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final words = ref.watch(filteredDailyWordsProvider);
    final all = ref.watch(allDailyWordsProvider);

    if (words.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.gold.withOpacity(0.10),
                  border: Border.all(color: c.gold.withOpacity(0.3), width: 1.5),
                ),
                child: Icon(Icons.search_off, size: 30, color: c.gold),
              ),
              const SizedBox(height: 16),
              Text(
                all.isEmpty ? 'داده‌ای بارگذاری نشد' : 'چیزی پیدا نشد',
                style: TextStyle(
                  color: c.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                all.isEmpty
                    ? 'فایل daily_words.json را چک کن.'
                    : 'فیلتر سطح یا جستجو را تغییر بده.',
                style: TextStyle(color: c.inkSoft, fontSize: 12),
              ),
            ],
          ),
        ),
      ));
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 12),
      sliver: SliverFixedExtentList(
        itemExtent: 66, // ارتفاع ثابت = سرعت بالاتر
        delegate: SliverChildBuilderDelegate(
          (_, i) => _WordCard(word: words[i]),
          childCount: words.length,
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: true,
        ),
      ),
    );
  }
}

class _WordCard extends StatelessWidget {
  final DailyWord word;
  const _WordCard({required this.word});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final levelColor = _levelColor(word.level);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.cardBorder, width: 0.8),
      ),
      child: Row(
        children: [
          // سطح — کوچیک‌تر
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: levelColor.withOpacity(0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            alignment: Alignment.center,
            child: Text(
              word.level,
              style: TextStyle(
                color: levelColor,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),

          // کلمه + معنی
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  word.en,
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  word.fa,
                  style: TextStyle(
                    color: c.inkSoft,
                    fontSize: 12,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),

          // POS — کوچیک
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: c.paperDark,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              _posFa(word.pos),
              style: TextStyle(
                color: c.inkSoft,
                fontSize: 9.5,
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
