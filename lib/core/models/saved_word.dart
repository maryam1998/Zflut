import 'package:flutter/foundation.dart';

@immutable
class SavedWord {
  final String word;
  final String langCode;
  final String meaning;
  final String? storyId;
  final int? pi;
  final int? si;
  final DateTime savedAt;

  /// ترجمه‌ی همه‌ی زبان‌های انتخاب‌شده (کد ← ترجمه) — برای نمایش در «دیکشنری من»
  final Map<String, String> translations;

  const SavedWord({
    required this.word,
    required this.langCode,
    required this.meaning,
    this.storyId,
    this.pi,
    this.si,
    required this.savedAt,
    this.translations = const <String, String>{},
  });

  SavedWord copyWith({String? meaning, Map<String, String>? translations}) =>
      SavedWord(
        word: word,
        langCode: langCode,
        meaning: meaning ?? this.meaning,
        storyId: storyId,
        pi: pi,
        si: si,
        savedAt: savedAt,
        translations: translations ?? this.translations,
      );

  Map<String, dynamic> toJson() => {
        'word': word,
        'langCode': langCode,
        'meaning': meaning,
        'storyId': storyId,
        'pi': pi,
        'si': si,
        'savedAt': savedAt.toIso8601String(),
        if (translations.isNotEmpty) 'translations': translations,
      };

  factory SavedWord.fromJson(Map<String, dynamic> json) => SavedWord(
        word: json['word'],
        langCode: json['langCode'],
        meaning: json['meaning'],
        storyId: json['storyId'],
        pi: json['pi'],
        si: json['si'],
        savedAt: DateTime.parse(json['savedAt']),
        translations: json['translations'] is Map
            ? {
                for (final e in (json['translations'] as Map).entries)
                  if (e.value != null && e.value.toString().trim().isNotEmpty)
                    e.key.toString(): e.value.toString()
              }
            : const <String, String>{},
      );
}
