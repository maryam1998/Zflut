import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/word_sources_provider.dart';
import '../words/widgets/word_list_view.dart';

/// تبِ «Slang» (زیرتبِ Words) — مثل Hope.
class SlangTab extends ConsumerWidget {
  const SlangTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = ref.watch(filteredSlangWordsProvider);
    final src = ref.watch(slangWordsProvider);
    return WordListView(
      listId: 'slang',
      words: words,
      hasAnyData: src.valueOrNull?.isNotEmpty ?? false,
      loading: src.isLoading,
    );
  }
}
