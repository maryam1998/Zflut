import 'package:flutter/material.dart';

import '../shell/widgets/filter_bar.dart';
import '../words/daily_words_list.dart';

class WordsTab extends StatelessWidget {
  const WordsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const DailyWordsList();
  }
}
