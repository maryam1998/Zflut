import '../usage/pro_status.dart';
import 'paid_content.dart';
import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;

import '../models/daily_word.dart';

List<Map<String, dynamic>> _parseWords(String raw) {
  final list = jsonDecode(raw) as List<dynamic>;
  return [for (final e in list) e as Map<String, dynamic>];
}

/// ترتیبِ اصلیِ لغت در فایلِ منبع (فیلدِ `o`؛ اگر نبود، آخر می‌رود).
int _orderOf(Map<String, dynamic> m) => (m['o'] as num?)?.toInt() ?? 1 << 30;

/// خواندنِ فایلِ لغات از assets. دیکُد کردنِ JSON (مثلاً ۱٫۲ مگابایتِ
/// Vocabulary in Use) در isolate جدا انجام می‌شود تا رابط کاربری هنگ نکند؛
/// خودِ نمایشِ لیست هم ۶۰تا۶۰تا (صفحه‌بندیِ تدریجی) است.
///
/// 💎 [paidList] ('daily' | 'slang' | 'vocab'): فایلِ داخلِ اپ فقط ده لغتِ رایگانِ هر دسته را دارد؛
/// اگر کاربر Pro باشد بقیه‌ی لغات از Worker (کش‌شده در گوشی) گرفته و با ترتیبِ اصلیِ فایل (`o`)
/// با لغاتِ رایگان ادغام می‌شود.
Future<List<DailyWord>> loadWordsAsset(String asset, {String? paidList}) async {
  final raw = await rootBundle.loadString(asset);
  final free = await compute(_parseWords, raw);
  List<DailyWord> toWords(List<Map<String, dynamic>> l) =>
      [for (final m in l) DailyWord.fromJson(m)];
  if (paidList == null || !ProStatus.isPro) return toWords(free);
  final paid = await PaidContent.words(paidList);
  if (paid == null || paid.isEmpty) return toWords(free);
  final all = <Map<String, dynamic>>[
    ...free,
    for (final e in paid) e as Map<String, dynamic>,
  ];
  // مرتب‌سازیِ پایدار (ترتیبِ برابرها حفظ می‌شود) تا لیست مثلِ فایلِ کامل بماند
  final idx = List<int>.generate(all.length, (i) => i);
  idx.sort((a, b) {
    final c = _orderOf(all[a]).compareTo(_orderOf(all[b]));
    return c != 0 ? c : a.compareTo(b);
  });
  // اگر به هر دلیل لغتی هم در فایلِ رایگان و هم در محتوای پولی بود، یک‌بار بیاید
  final seen = <int>{};
  final out = <DailyWord>[];
  for (final i in idx) {
    final w = DailyWord.fromJson(all[i]);
    if (w.id != 0 && !seen.add(w.id)) continue;
    out.add(w);
  }
  return out;
}
