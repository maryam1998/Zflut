import '../translate/known_translations.dart';
import 'package:flutter/foundation.dart';

@immutable
class ConversationLine {
  final String en;
  /// ترجمه‌ی از‌پیش‌معلوم (اختیاری). جمله‌های جدید فقط en دارند و سیستمِ ترجمه‌ی اپ ترجمه می‌کند.
  final String fa;
  final String level;

  const ConversationLine({
    required this.en,
    this.fa = '',
    required this.level,
  });

  factory ConversationLine.fromJson(Map<String, dynamic> j) {
    final en = j['en']?.toString() ?? '';
    final fa = j['fa']?.toString() ?? '';
    KnownTranslations.put(en, 'en', 'fa', fa);
    return ConversationLine(
      en: en,
      fa: fa,
      level: j['level']?.toString() ?? 'A1',
    );
  }
}

@immutable
class ConversationScenario {
  final String scenario;
  final String? context;
  final List<ConversationLine> speakerA;
  final List<ConversationLine> speakerB;

  const ConversationScenario({
    required this.scenario,
    this.context,
    required this.speakerA,
    required this.speakerB,
  });

  factory ConversationScenario.fromJson(Map<String, dynamic> j) {
    return ConversationScenario(
      scenario: j['scenario']?.toString() ?? '',
      context: j['context']?.toString(),
      speakerA: (j['speakerA'] as List<dynamic>? ?? [])
          .map((e) => ConversationLine.fromJson(e as Map<String, dynamic>))
          .toList(),
      speakerB: (j['speakerB'] as List<dynamic>? ?? [])
          .map((e) => ConversationLine.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

@immutable
class ConversationTopic {
  /// شناسه‌ی ثابتِ موضوع (نامِ فایل / ردیفِ D1) — مثلاً d-greetings-and-small-talk
  final String id;

  /// 'daily' | 'thematic'
  final String kind;
  final String topic;

  /// برای موضوعِ «خالی» (فقط نام، لود تنبل) لیستِ خالی است؛ با بازشدنِ موضوع پر می‌شود.
  final List<ConversationScenario> scenarios;

  const ConversationTopic({
    this.id = '',
    this.kind = '',
    required this.topic,
    required this.scenarios,
  });

  factory ConversationTopic.fromJson(Map<String, dynamic> j,
      {String id = '', String kind = ''}) {
    return ConversationTopic(
      id: id,
      kind: kind,
      topic: j['topic']?.toString() ?? '',
      scenarios: (j['scenarios'] as List<dynamic>? ?? [])
          .map((e) => ConversationScenario.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
