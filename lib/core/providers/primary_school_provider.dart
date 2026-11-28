import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/paid_content.dart';
import '../models/daily_word.dart';
import '../usage/pro_status.dart';

/// مرحله‌ی «Primary School» در تبِ «دیکشنری من».
/// null = حالتِ عادی (همه‌ی لغات)، [kStagePrimary] = لغاتِ مدرسه‌ایِ A1.
const String kStagePrimary = 'primary';

/// مقاطعِ تحصیلیِ بعدی (فعلاً خالی؛ لغاتِ جدید بعداً اضافه می‌شود).
/// این‌ها به CEFR وصل نیستند و لغاتِ B2/C1/C2 را نشان نمی‌دهند.
const String kStageUpper = 'upper'; // Upper Secondary / Pre-University
const String kStageUniversity = 'university'; // University & Adults

/// برچسبِ چیپ (برای تغییرِ اسم فقط همین‌جا را عوض کن)
const String kPrimaryChipLabel = 'Primary School'; // A2
const String kPreschoolChipLabel = 'Preschool'; // A1
const String kLowerSecondaryChipLabel = 'Lower Secondary'; // B1
const String kUpperSecondaryChipLabel = 'Upper Secondary / Pre-University';
const String kUniversityChipLabel = 'University & Adults';

final wordsStageProvider = StateProvider<String?>((ref) => null);

/// سطحِ انتخاب‌شده‌ی مرحله‌ی Primary در تبِ لغات: 'A1'، 'A2' یا 'B1'
final primaryLevelProvider = StateProvider<String>((ref) => 'A1');

/// موضوعِ بازِ مرحله‌ی Primary (null = شبکه‌ی موضوع‌ها)
final primaryTopicProvider = StateProvider<String?>((ref) => null);

class PrimaryTopic {
  final String key;
  final String fa;
  final String en;
  final List<DailyWord> words;

  /// تعدادِ لغاتِ موضوع. برای کاربرِ رایگان [words] خالی است (محتوا پولی و فقط روی سرور)،
  /// ولی تعداد از ایندکسِ کوچکِ داخلِ اپ می‌آید تا کارتِ قفل‌شده نشان داده شود.
  final int count;

  /// گروهِ موضوع در شبکه (مثلاً 'school' یا 'life')؛ خالی = بدونِ گروه‌بندی
  final String group;
  const PrimaryTopic({
    required this.key,
    required this.fa,
    required this.en,
    required this.words,
    int? count,
    this.group = '',
  }) : count = count ?? words.length;

  String label(String ui) => ui == 'fa' ? fa : en;
}

/// 🎒 Education stage پولی است:
///   • Pro → کلِ لغات از Worker (کشِ گوشی؛ بعد از اولین دانلود آفلاین هم باز می‌شود)
///   • رایگان → فقط نام و تعدادِ موضوع‌ها از `assets/data/primary_index.json` (کارتِ قفل‌شده)
/// اگر Pro باشد و نه کش باشد نه دانلود شود، [PrimaryUnavailable] پرتاب می‌شود تا صفحه
/// به‌جای چرخشِ بی‌پایان دکمه‌ی «تلاش دوباره» نشان دهد.
class PrimaryUnavailable implements Exception {
  const PrimaryUnavailable();
  @override
  String toString() => 'PrimaryUnavailable';
}

Future<List<PrimaryTopic>> _loadPrimaryTopics(String level) async {
  if (ProStatus.isPro) {
    final j = await PaidContent.blob('primary-${level.toLowerCase()}');
    final list = j?['topics'];
    if (list is! List) throw const PrimaryUnavailable();
    final out = <PrimaryTopic>[];
    for (final t in list) {
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
  }
  try {
    final raw = await rootBundle.loadString('assets/data/primary_index.json');
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final list = (j['levels'] as Map<String, dynamic>)[level.toUpperCase()];
    return [
      for (final t in (list as List<dynamic>))
        PrimaryTopic(
          key: (t as Map)['key']?.toString() ?? '',
          fa: t['fa']?.toString() ?? '',
          en: t['en']?.toString() ?? '',
          group: t['group']?.toString() ?? '',
          words: const <DailyWord>[],
          count: (t['n'] as num?)?.toInt() ?? 0,
        ),
    ];
  } catch (_) {
    return const <PrimaryTopic>[];
  }
}

/// موضوع‌های Preschool (A1) — منبع: paid-content/education/primary-a1.json (روی سرور).
/// شناسه‌ی لغاتِ موجود همان شناسه‌ی اصلی است (علاقه‌مندی/خوانده‌شده یکی می‌ماند)،
/// لغاتِ جدید شناسه‌ی ۹۰۰۰۰۱ به بالا دارند.
/// با عوض‌شدنِ وضعیتِ Pro یا به‌روزشدنِ محتوای پولی دوباره بارگذاری می‌شود.
FutureProvider<List<PrimaryTopic>> _levelProvider(String level) =>
    FutureProvider<List<PrimaryTopic>>((ref) {
      ref.watch(isProProvider);
      ref.watch(paidRevisionProvider);
      return _loadPrimaryTopics(level);
    });

final primaryA1TopicsProvider = _levelProvider('A1');

/// موضوع‌های Primary A2 (لغاتِ جدید: ۹۱۰۰۰۱ به بالا).
final primaryA2TopicsProvider = _levelProvider('A2');

/// موضوع‌های Lower Secondary ▸ B1 (لغاتِ جدید: ۹۳۰۰۰۱ به بالا).
final primaryB1TopicsProvider = _levelProvider('B1');

/// موضوع‌های سطحِ انتخاب‌شده (A1، A2 یا B1)
final primaryTopicsProvider = Provider<AsyncValue<List<PrimaryTopic>>>((ref) {
  switch (ref.watch(primaryLevelProvider)) {
    case 'B1':
      return ref.watch(primaryB1TopicsProvider);
    case 'A2':
      return ref.watch(primaryA2TopicsProvider);
    default:
      return ref.watch(primaryA1TopicsProvider);
  }
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
