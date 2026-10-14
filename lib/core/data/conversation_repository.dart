import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/conversation.dart';

class ConversationRepository {
  ConversationRepository._();
  static final ConversationRepository instance = ConversationRepository._();

  List<ConversationTopic> _daily = const [];
  List<ConversationTopic> _thematic = const [];
  bool _loaded = false;
  String? _error;

  List<ConversationTopic> get daily => _daily;
  List<ConversationTopic> get thematic => _thematic;
  List<ConversationTopic> get all => [..._daily, ..._thematic];
  bool get isLoaded => _loaded;
  String? get error => _error;
  int get totalTopics => _daily.length + _thematic.length;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final dailyRaw = await rootBundle
          .loadString('assets/data/daily_conversations.json');
      final thematicRaw = await rootBundle
          .loadString('assets/data/thematic_conversations.json');

      _daily = (jsonDecode(dailyRaw) as List<dynamic>)
          .map((e) => ConversationTopic.fromJson(e as Map<String, dynamic>))
          .toList();
      _thematic = (jsonDecode(thematicRaw) as List<dynamic>)
          .map((e) => ConversationTopic.fromJson(e as Map<String, dynamic>))
          .toList();

      _loaded = true;
      _error = null;
    } catch (e) {
      _error = e.toString();
      _loaded = false;
    }
  }
}
