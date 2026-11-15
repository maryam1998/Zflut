// 📁 مسیر: lib/features/story/word_highlight.dart
//
// بولد کردنِ لغت‌های انتخاب‌شده داخلِ متنِ داستان — توسط خودِ اپ (نه AI).
//  • عبارت‌های چندکلمه‌ای و لغت‌های بلندتر اول تطبیق می‌خورند
//  • صرف‌های ساده هم پیدا می‌شوند (go → goes / going، study → studies، رفت → رفتم)
//  • برای چینی/ژاپنی/کره‌ای/تایلندی (بدونِ فاصله) تطبیقِ زیررشته‌ای است
// خروجی null = چیزی پیدا نشد (متن همان‌طور که هست نمایش داده شود).

import 'package:flutter/material.dart';

import '../../core/widgets/selection_card.dart' show SelectableRun;

const Set<String> _spaceless = {'zh', 'ja', 'ko', 'th'};
const String _kLetter = r'[\p{L}\p{M}\p{N}\u200c]';

final Map<String, RegExp?> _cache = {};

String _escapeWord(String w) {
  var e = RegExp.escape(w);
  e = e.replaceAllMapped(RegExp(r'\s+'), (_) => r'\s+');
  e = e.replaceAllMapped(RegExp("['’]"), (_) => "['’]");
  return e;
}

/// الگوی یک لغت/عبارت؛ برای لغتِ اولِ هر عبارت (اگر ≥۴ حرف) پسوندِ کوتاهِ صرفی مجاز است.
String _alt(String raw, bool spaceless) {
  final t = raw.trim();
  if (t.isEmpty) return '';
  if (spaceless) return _escapeWord(t);
  final toks = t.split(RegExp(r'\s+'));
  final first = toks.first;
  final rest = toks.length > 1 ? toks.sublist(1).map(_escapeWord).join(r'\s+') : '';
  final letters = RegExp(r'\p{L}', unicode: true).allMatches(first).length;
  String head;
  var suffix = false;
  if (letters >= 4) {
    final stems = <String>{_escapeWord(first)};
    final lower = first.toLowerCase();
    if (lower.endsWith('e') && first.length > 3) {
      stems.add(_escapeWord(first.substring(0, first.length - 1)));
    }
    if (lower.endsWith('y') && first.length > 3) {
      stems.add(_escapeWord(first.substring(0, first.length - 1)));
    }
    head = stems.length == 1 ? stems.first : '(?:${stems.join('|')})';
    suffix = true;
  } else {
    head = _escapeWord(first);
  }
  final tail = rest.isEmpty ? '' : r'\s+' + rest;
  if (suffix && rest.isEmpty) return '$head$_kLetter{0,3}';
  if (suffix) return '$head$_kLetter{0,3}$tail';
  return '$head$tail';
}

RegExp? _build(List<String> words, String lang) {
  final spaceless = _spaceless.contains(lang);
  final seen = <String>{};
  final list = <String>[];
  for (final w in words) {
    final t = w.trim();
    if (t.isEmpty || !seen.add(t.toLowerCase())) continue;
    list.add(t);
  }
  if (list.isEmpty) return null;
  list.sort((a, b) => b.length.compareTo(a.length));
  final alts = list.map((w) => _alt(w, spaceless)).where((a) => a.isNotEmpty);
  if (alts.isEmpty) return null;
  final body = '(?:${alts.join('|')})';
  final pattern =
      spaceless ? body : '(?<!$_kLetter)$body(?!$_kLetter)';
  try {
    return RegExp(pattern, unicode: true, caseSensitive: false);
  } catch (_) {
    return null;
  }
}

/// تکه‌های متن با لغت‌های بولد؛ مجموعِ متنِ تکه‌ها دقیقاً برابرِ [text] است.
List<SelectableRun>? highlightRuns(
    String text, List<String> words, String lang, TextStyle boldStyle) {
  if (words.isEmpty || text.isEmpty) return null;
  final key = '$lang|${words.join('\u0001')}';
  final re = _cache.putIfAbsent(key, () {
    if (_cache.length > 200) _cache.clear();
    return _build(words, lang);
  });
  if (re == null) return null;
  final ms = re.allMatches(text).where((m) => m.end > m.start).toList();
  if (ms.isEmpty) return null;
  final out = <SelectableRun>[];
  var pos = 0;
  for (final m in ms) {
    if (m.start > pos) out.add(SelectableRun(text.substring(pos, m.start)));
    out.add(SelectableRun(text.substring(m.start, m.end), boldStyle));
    pos = m.end;
  }
  if (pos < text.length) out.add(SelectableRun(text.substring(pos)));
  return out;
}
