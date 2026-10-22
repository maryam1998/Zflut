import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/word_sources_provider.dart';
import '../words/widgets/word_list_view.dart';

/// تبِ «Vocab in use» (زیرتبِ Words) — مثل Hope.
class VocabInUseTab extends ConsumerWidget {
  const VocabInUseTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = ref.watch(filteredVocabInUseWordsProvider);
    final src = ref.watch(vocabInUseWordsProvider);
    return WordListView(
      listId: 'vocab-in-use',
      words: words,
      hasAnyData: src.valueOrNull?.isNotEmpty ?? false,
      loading: src.isLoading,
    );
  }
}
