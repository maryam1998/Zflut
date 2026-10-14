import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/conversation_provider.dart';
import '../../core/providers/words_filter_provider.dart';
import '../words/widgets/word_list_view.dart';

class VocabInUseTab extends ConsumerWidget {
  const VocabInUseTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = ref.watch(filteredDailyWordsProvider);
    final all = ref.watch(allDailyWordsProvider);
    return WordListView(
      words: words,
      hasAnyData: all.isNotEmpty,
    );
  }
}
