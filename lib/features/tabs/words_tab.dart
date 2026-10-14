import 'package:flutter/material.dart';
import '_placeholder_tab.dart';

class WordsTab extends StatelessWidget {
  const WordsTab({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderTab(
        icon: Icons.menu_book_outlined,
        title: 'دیکشنری من',
        subtitle:
            'لیست کامل لغات A تا Z با سطح‌بندی CEFR،\nجستجو، فیلتر سطح و علامت‌گذاری خوانده‌شده.',
        previewChips: ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'],
      );
}
