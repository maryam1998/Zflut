import 'package:flutter/material.dart';
import '_placeholder_tab.dart';

class WordsTab extends StatelessWidget {
  const WordsTab({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderTab(
        icon: Icons.menu_book_outlined,
        title: 'لغات',
        subtitle: 'لیست کامل لغات A تا Z با سطح‌بندی CEFR،\nجستجو، فیلتر سطح و علامت‌گذاری خوانده‌شده.',
      );
}
