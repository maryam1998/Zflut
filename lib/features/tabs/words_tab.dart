import 'package:flutter/material.dart';

import '../shell/widgets/filter_bar.dart';
import '../words/daily_words_list.dart';

class WordsTab extends StatelessWidget {
  const WordsTab({super.key});

  @override
  Widget build(BuildContext context) {
    // یک CustomScrollView واحد (داخل NestedScrollViewِ شل):
    // فیلتر + لیست با هم اسکرول می‌شوند، و هدر اپ هم با همین اسکرول بالا می‌رود.
    return const CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: FilterBar(
            searchHint: 'جستجوی لغت...',
            showLevels: true,
            showSort: true,
          ),
        ),
        DailyWordsList(),
      ],
    );
  }
}
