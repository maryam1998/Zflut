import '../usage/pro_status.dart';
import 'paid_content.dart';
import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;

import '../models/daily_word.dart';

List<DailyWord> _parseWords(String raw) {
  final list = jsonDecode(raw) as List<dynamic>;
  return list
      .map((e) => DailyWord.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);
}

/// خواندنِ فایلِ لغات از assets. دیکُد کردنِ JSON (مثلاً ۱٫۲ مگابایتِ
/// Vocabulary in Use) در isolate جدا انجام می‌شود تا رابط کاربری هنگ نکند؛
/// خودِ نمایشِ لیست هم ۶۰تا۶۰تا (صفحه‌بندیِ تدریجی) است.
///
/// 💎 [paidList] ('daily' | 'slang' | 'vocab'): فایلِ داخلِ اپ فقط ۳۰ لغتِ رایگان دارد؛
/// اگر کاربر Pro باشد بقیه‌ی لغات از Worker (کش‌شده در گوشی) به انتهای لیست اضافه می‌شود.
Future<List<DailyWord>> loadWordsAsset(String asset, {String? paidList}) async {
  final raw = await rootBundle.loadString(asset);
  final free = await compute(_parseWords, raw);
  if (paidList == null || !ProStatus.isPro) return free;
  final paid = await PaidContent.words(paidList);
  if (paid == null || paid.isEmpty) return free;
  return [
    ...free,
    for (final e in paid) DailyWord.fromJson(e as Map<String, dynamic>),
  ];
}
