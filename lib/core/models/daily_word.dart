import 'package:flutter/foundation.dart';

@immutable
class DailyWord {
  final int id;
  final String level;
  final String pos;
  final String en;
  final String fa;

  const DailyWord({
    required this.id,
    required this.level,
    required this.pos,
    required this.en,
    required this.fa,
  });

  factory DailyWord.fromJson(Map<String, dynamic> j) {
    return DailyWord(
      id: (j['id'] as num?)?.toInt() ?? 0,
      level: j['level']?.toString() ?? 'A1',
      pos: j['pos']?.toString() ?? 'other',
      en: j['en']?.toString() ?? '',
      fa: j['fa']?.toString() ?? '',
    );
  }
}
