import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/filter_state.dart';

class WordsFilterNotifier extends StateNotifier<WordsFilterState> {
  WordsFilterNotifier() : super(const WordsFilterState());

  void setLevel(String level) =>
      state = state.copyWith(level: level);

  void setQuery(String q) =>
      state = state.copyWith(query: q);

  void setSort(SortMode sort) =>
      state = state.copyWith(sort: sort);

  void reset() => state = const WordsFilterState();
}

final wordsFilterProvider =
    StateNotifierProvider<WordsFilterNotifier, WordsFilterState>((ref) {
  return WordsFilterNotifier();
});
