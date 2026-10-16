import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/word_sources_provider.dart';
import '../words/widgets/word_list_view.dart';

class SlangTab extends ConsumerWidget {
  const SlangTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(slangWordsProvider).valueOrNull ?? const [];
    final words = ref.watch(filteredSlangWordsProvider);
    return WordListView(
      words: words,
      hasAnyData: all.isNotEmpty,
      loading: ref.watch(slangWordsProvider).isLoading,
    );
  }
}
