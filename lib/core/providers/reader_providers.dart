import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/saved_word.dart';
import '../models/grammar_note.dart';

// وضعیت ذخیره‌سازی لغات (برای دکمه Save for next story)
class SavedWordsNotifier extends StateNotifier<List<SavedWord>> {
  SavedWordsNotifier() : super([]);

  void toggleSave(SavedWord word) {
    final exists = state.any((w) => w.word == word.word && w.langCode == word.langCode);
    if (exists) {
      state = state.where((w) => !(w.word == word.word && w.langCode == word.langCode)).toList();
    } else {
      state = [...state, word];
    }
  }

  bool isSaved(String word, String langCode) {
    return state.any((w) => w.word == word && w.langCode == langCode);
  }
}
final savedWordsProvider = StateNotifierProvider<SavedWordsNotifier, List<SavedWord>>((ref) => SavedWordsNotifier());

// وضعیت یادداشت‌های گرامر
class GrammarNotesNotifier extends StateNotifier<List<GrammarNote>> {
  GrammarNotesNotifier() : super([]);

  void addNote(GrammarNote note) {
    state = [note, ...state];
  }
}
final grammarNotesProvider = StateNotifierProvider<GrammarNotesNotifier, List<GrammarNote>>((ref) => GrammarNotesNotifier());

// وضعیت جعبه لایتنر (به صورت ساده شده)
class LeitnerNotifier extends StateNotifier<List<SavedWord>> {
  LeitnerNotifier() : super([]);

  void addToLeitner(SavedWord word) {
    if (!state.any((w) => w.word == word.word)) {
      state = [...state, word];
    }
  }
}
final leitnerProvider = StateNotifierProvider<LeitnerNotifier, List<SavedWord>>((ref) => LeitnerNotifier());
