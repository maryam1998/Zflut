import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/daily_word.dart';

/// مرحله‌ی «Primary School» در تبِ «دیکشنری من».
/// null = حالتِ عادی (همه‌ی لغات)، [kStagePrimary] = لغاتِ مدرسه‌ایِ A1.
const String kStagePrimary = 'primary';

/// برچسبِ چیپ (برای تغییرِ اسم فقط همین‌جا را عوض کن)
const String kPrimaryChipLabel = 'Primary School';

final wordsStageProvider = StateProvider<String?>((ref) => null);

/// سطحِ انتخاب‌شده‌ی مرحله‌ی Primary در تبِ لغات: 'A1' یا 'A2'
final primaryLevelProvider = StateProvider<String>((ref) => 'A1');

/// موضوعِ بازِ مرحله‌ی Primary (null = شبکه‌ی موضوع‌ها)
final primaryTopicProvider = StateProvider<String?>((ref) => null);

class PrimaryTopic {
  final String key;
  final String fa;
  final String en;
  final List<DailyWord> words;

  /// گروهِ موضوع در شبکه (مثلاً 'school' یا 'life')؛ خالی = بدونِ گروه‌بندی
  final String group;
  const PrimaryTopic({
    required this.key,
    required this.fa,
    required this.en,
    required this.words,
    this.group = '',
  });

  String label(String ui) => ui == 'fa' ? fa : en;
}

Future<List<PrimaryTopic>> _loadPrimaryTopics(String asset) async {
  try {
    final raw = await rootBundle.loadString(asset);
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final out = <PrimaryTopic>[];
    for (final t in (j['topics'] as List<dynamic>)) {
      final m = t as Map<String, dynamic>;
      out.add(PrimaryTopic(
        key: m['key']?.toString() ?? '',
        fa: m['fa']?.toString() ?? '',
        en: m['en']?.toString() ?? '',
        group: m['group']?.toString() ?? '',
        words: [
          for (final w in (m['words'] as List<dynamic>))
            DailyWord.fromJson(w as Map<String, dynamic>),
        ],
      ));
    }
    return out;
  } catch (_) {
    return const <PrimaryTopic>[];
  }
}

/// موضوع‌های Primary A1 از `assets/data/primary_a1.json`.
/// شناسه‌ی لغاتِ موجود همان شناسه‌ی اصلی است (علاقه‌مندی/خوانده‌شده یکی می‌ماند)،
/// لغاتِ جدید شناسه‌ی ۹۰۰۰۰۱ به بالا دارند.
final primaryA1TopicsProvider = FutureProvider<List<PrimaryTopic>>(
    (ref) => _loadPrimaryTopics('assets/data/primary_a1.json'));

/// موضوع‌های Primary A2 از `assets/data/primary_a2.json` (لغاتِ جدید: ۹۱۰۰۰۱ به بالا).
final primaryA2TopicsProvider = FutureProvider<List<PrimaryTopic>>(
    (ref) => _loadPrimaryTopics('assets/data/primary_a2.json'));

/// موضوع‌های سطحِ انتخاب‌شده (A1 یا A2)
final primaryTopicsProvider = Provider<AsyncValue<List<PrimaryTopic>>>((ref) {
  return ref.watch(ref.watch(primaryLevelProvider) == 'A2'
      ? primaryA2TopicsProvider
      : primaryA1TopicsProvider);
});

/// همه‌ی لغاتِ Primary (سطحِ انتخاب‌شده) بدونِ تکرار (لغتی که در دو موضوع هست یک‌بار می‌آید).
final primaryA1AllWordsProvider = Provider<List<DailyWord>>((ref) {
  final topics =
      ref.watch(primaryTopicsProvider).valueOrNull ?? const <PrimaryTopic>[];
  final seen = <String>{};
  final out = <DailyWord>[];
  for (final t in topics) {
    for (final w in t.words) {
      if (seen.add(w.sid)) out.add(w);
    }
  }
  return out;
});
