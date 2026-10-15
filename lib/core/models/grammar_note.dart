import 'package:flutter/foundation.dart';

@immutable
class GrammarNote {
  final String id;
  final String word;
  final String sentence;
  final String markdown;
  final String langCode;
  final DateTime savedAt;

  const GrammarNote({
    required this.id,
    required this.word,
    required this.sentence,
    required this.markdown,
    required this.langCode,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'word': word,
        'sentence': sentence,
        'markdown': markdown,
        'langCode': langCode,
        'savedAt': savedAt.toIso8601String(),
      };

  factory GrammarNote.fromJson(Map<String, dynamic> json) => GrammarNote(
        id: json['id'],
        word: json['word'],
        sentence: json['sentence'],
        markdown: json['markdown'],
        langCode: json['langCode'],
        savedAt: DateTime.parse(json['savedAt']),
      );
}
