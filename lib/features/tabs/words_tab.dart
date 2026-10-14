import 'package:flutter/material.dart';

import '../shell/widgets/filter_bar.dart';
import '../words/daily_words_list.dart';

class WordsTab extends StatelessWidget {
  const WordsTab({super.key});

  @override
  Widget build(BuildContext context) {
    // Filter + List رو در یک CustomScrollView می‌گذاریم
    // تا وقتی کاربر لیست رو می‌کشه، Search هم باهاش بره بالا.
    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(
          child: FilterBar(
            searchHint: 'جستجوی لغت...',
            showLevels: true,
            showSort: true,
          ),
        ),
        const SliverFillRemaining(
          hasScrollBody: true,
          child: DailyWordsList(),
        ),
      ],
    );
  }
}
