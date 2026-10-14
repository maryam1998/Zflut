import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/daily_word.dart';

class DailyWordsRepository {
  DailyWordsRepository._();
  static final DailyWordsRepository instance = DailyWordsRepository._();

  List<DailyWord> _words = const [];
  bool _loaded = false;
  String? _error;

  List<DailyWord> get words => _words;
  bool get isLoaded => _loaded;
  String? get error => _error;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final raw = await rootBundle.loadString('assets/data/daily_words.json');
      _words = (jsonDecode(raw) as List<dynamic>)
          .map((e) => DailyWord.fromJson(e as Map<String, dynamic>))
          .toList();
      _loaded = true;
      _error = null;
    } catch (e) {
      _error = e.toString();
      _loaded = false;
    }
  }
}
