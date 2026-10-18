import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/local_storage.dart';

const String _kExampleFavKey = 'phrasebook-example-favorites-v1';

/// جمله‌ی مثال (یا ترجمه‌اش) که کاربر ⭐ زده.
class ExampleFav {
  final String text;
  final String lang;
  final String word;
  const ExampleFav({required this.text, required this.lang, required this.word});

  String get key => '$lang::$text';

  Map<String, dynamic> toJson() => {'text': text, 'lang': lang, 'word': word};

  factory ExampleFav.fromJson(Map<String, dynamic> j) => ExampleFav(
        text: (j['text'] ?? '').toString(),
        lang: (j['lang'] ?? 'en').toString(),
        word: (j['word'] ?? '').toString(),
      );
}

class ExampleFavoritesNotifier extends StateNotifier<List<ExampleFav>> {
  final LocalStorage _storage;
  ExampleFavoritesNotifier(this._storage) : super(_read(_storage));

  static List<ExampleFav> _read(LocalStorage s) {
    final raw = s.readJson(_kExampleFavKey)['items'];
    if (raw is! List) return [];
    return [
      for (final e in raw)
        if (e is Map) ExampleFav.fromJson(Map<String, dynamic>.from(e)),
    ];
  }

  bool has(String text, String lang) =>
      state.any((f) => f.key == '$lang::$text');

  Future<void> toggle(String text, String lang, String word) async {
    final t = text.trim();
    if (t.isEmpty) return;
    final key = '$lang::$t';
    final next = state.any((f) => f.key == key)
        ? state.where((f) => f.key != key).toList()
        : [ExampleFav(text: t, lang: lang, word: word), ...state];
    state = next;
    await _storage.writeJson(
        _kExampleFavKey, {'items': next.map((f) => f.toJson()).toList()});
  }
}

final exampleFavoritesProvider =
    StateNotifierProvider<ExampleFavoritesNotifier, List<ExampleFav>>(
        (ref) => ExampleFavoritesNotifier(ref.watch(localStorageProvider)));
