import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/daily_word.dart';
import '../../core/providers/conversation_provider.dart';
import '../../core/providers/words_filter_provider.dart';
import '../../core/theme/app_theme_colors.dart';

/// لیست لغات روزمره با فیلتر و جستجو.
class DailyWordsList extends ConsumerWidget {
  const DailyWordsList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final all = ref.watch(allDailyWordsProvider);
    final filter = ref.watch(wordsFilterProvider);

    // فیلتر روی لیست
    var list = all.where((w) {
      if (filter.level != 'all' && w.level != filter.level) return false;
      if (filter.query.trim().isNotEmpty) {
        final q = filter.query.trim().toLowerCase();
        if (!w.en.toLowerCase().contains(q) && !w.fa.contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();

    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.gold.withOpacity(0.10),
                  border: Border.all(
                    color: c.gold.withOpacity(0.3),
                    width: 1.5,
                  ),
                ),
                child: Icon(Icons.search_off, size: 34, color: c.gold),
              ),
              const SizedBox(height: 18),
              Text(
                all.isEmpty ? 'داده‌ای بارگذاری نشد' : 'چیزی پیدا نشد',
                style: TextStyle(
                  color: c.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                all.isEmpty
                    ? 'فایل daily_words.json را چک کن.'
                    : 'فیلتر سطح یا جستجو را تغییر بده.',
                style: TextStyle(color: c.inkSoft, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final w = list[i];
        return _WordCard(word: w);
      },
    );
  }
}

class _WordCard extends StatelessWidget {
  final DailyWord word;
  const _WordCard({required this.word});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.cardBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: c.ink.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // سطح
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _levelColor(word.level).withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              word.level,
              style: TextStyle(
                color: _levelColor(word.level),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // کلمه + معنی
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  word.en,
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  word.fa,
                  style: TextStyle(
                    color: c.inkSoft,
                    fontSize: 13.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),

          // نقش دستوری
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: c.paperDark,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _posFa(word.pos),
              style: TextStyle(
                color: c.inkSoft,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
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
