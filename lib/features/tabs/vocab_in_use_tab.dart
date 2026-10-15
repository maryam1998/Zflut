import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/word_sources_provider.dart';
import '../words/widgets/word_list_view.dart';

class VocabInUseTab extends ConsumerWidget {
  const VocabInUseTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(vocabInUseWordsProvider).valueOrNull ?? const [];
    final words = ref.watch(filteredVocabInUseWordsProvider);
    return WordListView(
      words: words,
      hasAnyData: all.isNotEmpty,
    );
  }
}
