// 📁 مسیر: lib/features/story/word_equivalents.dart
//
// بولد کردنِ «معادلِ» لغت‌های انتخاب‌شده داخلِ ترجمه‌ها — توسط خودِ اپ (نه AI).
//
// word_highlight.dart لغت‌های انتخابی را داخلِ متنِ داستان بولد می‌کند؛ این فایل همان‌ها را
// داخلِ ترجمه‌ی هر زبان پیدا می‌کند. ورودی: برای هر لغت چند «معادلِ کاندید» (از دیکشنریِ خودِ اپ،
// لغاتِ ذخیره‌شده، ترجمه‌ی تک‌لغت یا ترجمه‌ی لغت داخلِ همان جمله). خروجی: تکه‌هایی از متنِ ترجمه
// که مجموعشان دقیقاً برابرِ متنِ اصلی است (فقط معادل‌ها استایلِ بولد دارند).
//
//  • تطبیق ریشه‌ای و بی‌حساس به صرف است:
//      فارسی: «تأثیر گذاشتن» ← «تاثیر می‌گذارد»، «کتاب» ← «کتاب‌ها»، «سلاح» ← «سلاحی»
//      اسپانیایی/…: «afectar» ← «afectan»، «diverso» ← «diversas» (بدونِ حساسیت به اکسان)
//  • فاصله و نیم‌فاصله (ZWNJ) یکی حساب می‌شوند («سیاست ها» = «سیاست‌ها»).
//  • برای چینی/ژاپنی/کره‌ای/تایلندی (بدونِ فاصله) تطبیقِ زیررشته‌ای است.
//  • اگر معادلِ چندکلمه‌ای کامل پیدا نشد، کلمه‌های محتوایی‌اش جداگانه امتحان می‌شوند
//    (فعل‌های کمکیِ پرتکرار مثل «کردن/شدن» و حروفِ اضافه هرگز بولد نمی‌شوند).
// اگر هیچ معادلی پیدا نشود، null برمی‌گردد و متن همان‌طور که هست نمایش داده می‌شود.

import 'package:flutter/material.dart';

import '../../core/widgets/selection_card.dart' show SelectableRun;
import 'word_highlight.dart' show highlightRuns;

const String _kL = r'[\p{L}\p{M}\p{N}]';

/// جایگزینِ هم‌طولِ نیم‌فاصله (ZWNJ) در متنِ «اسکلت» — تا ایندکس‌ها با متنِ اصلی یکی بماند.
const String _zw = '\uE000';

const Set<String> _spaceless = {'zh', 'ja', 'ko', 'th'};
const Set<String> _romance = {'es', 'pt', 'it', 'fr', 'ca', 'gl', 'ro'};
const Set<String> _rtlScript = {'fa', 'ur', 'ar'};

const Map<String, String> _acc = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
  'Á': 'a', 'À': 'a', 'Â': 'a', 'Ä': 'a', 'Ã': 'a',
  'É': 'e', 'È': 'e', 'Ê': 'e', 'Ë': 'e',
  'Í': 'i', 'Ì': 'i', 'Î': 'i', 'Ï': 'i',
  'Ó': 'o', 'Ò': 'o', 'Ô': 'o', 'Ö': 'o', 'Õ': 'o',
  'Ú': 'u', 'Ù': 'u', 'Û': 'u', 'Ü': 'u',
};

/// کلمه‌های بسیار پرتکرار که هیچ‌وقت به‌تنهایی «معادل» حساب نمی‌شوند.
const Set<String> _stop = {
  // فارسی
  'را', 'به', 'از', 'در', 'که', 'این', 'آن', 'با', 'برای', 'می', 'نمی', 'و', 'یا',
  'هم', 'تا', 'بر', 'کردن', 'شدن', 'دادن', 'گرفتن', 'داشتن', 'بودن', 'رفتن',
  'آمدن', 'گذاشتن', 'زدن', 'خوردن',
  // اسپانیایی / پرتغالی / ایتالیایی / فرانسوی
  'de', 'la', 'el', 'en', 'un', 'una', 'los', 'las', 'que', 'se', 'por', 'con',
  'para', 'del', 'al', 'lo', 'le', 'les', 'des', 'du', 'et', 'ou', 'di', 'da',
  'il', 'em', 'um', 'uma', 'os', 'as', 'hacer', 'tener', 'estar', 'poner',
  'faire', 'avoir', 'etre', 'fare', 'essere', 'avere',
  // انگلیسی
  'the', 'of', 'to', 'in', 'on', 'at', 'for', 'and', 'or', 'be', 'is', 'make',
  'take', 'have', 'get', 'put', 'give',
};

// ───────────────────────── کمکی‌ها ─────────────────────────

/// فقط کاراکترهای دستوریِ regex را escape می‌کند (در حالتِ unicode هر escapeِ دیگری خطاست).
String _esc(String s) => s.replaceAllMapped(
    RegExp(r'[\\^$.*+?()\[\]{}|]'), (m) => '\\${m.group(0)}');

int _letters(String s) => RegExp(r'\p{L}', unicode: true).allMatches(s).length;

/// نسخه‌ی «هم‌طولِ» متن برای تطبیق: حروفِ کوچک، بدونِ اکسان، یکسان‌سازیِ ی/ک/ا/ه عربی↔فارسی،
/// و نیم‌فاصله ← [_zw]. طولِ خروجی همیشه برابرِ ورودی است (ایندکس‌ها قابل‌انتقال‌اند).
String _skel(String s) {
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    final c = s.codeUnitAt(i);
    if (c == 0x200C) {
      b.write(_zw);
    } else if (c == 0x064A || c == 0x0649) {
      b.write('\u06CC'); // ي ى → ی
    } else if (c == 0x0643) {
      b.write('\u06A9'); // ك → ک
    } else if (c == 0x0623 || c == 0x0625 || c == 0x0671) {
      b.write('\u0627'); // أ إ ٱ → ا
    } else if (c == 0x0629) {
      b.write('\u0647'); // ة → ه
    } else {
      final a = _acc[ch];
      if (a != null) {
        b.write(a);
      } else {
        final lo = ch.toLowerCase();
        b.write(lo.length == 1 ? lo : ch);
      }
    }
  }
  return b.toString();
}

/// «معادل‌های کاندید» را از متنِ خامِ ترجمه‌ی یک لغت درمی‌آورد:
/// جدا کردن با «، , ; / |»، حذفِ توضیحِ داخلِ پرانتز و «to » ابتدای فعلِ انگلیسی.
List<String> _candidates(String raw, String lang) {
  final s = raw.replaceAll(RegExp(r'\([^)]*\)|（[^）]*）|\[[^\]]*\]'), ' ');
  final out = <String>[];
  final seen = <String>{};
  for (var c in s.split(RegExp(r'[,،;؛/|\n]+'))) {
    c = c.trim();
    if (lang == 'en') c = c.replaceFirst(RegExp(r'^to\s+', caseSensitive: false), '');
    final k = _skel(c).trim();
    if (k.isEmpty || !seen.add(k)) continue;
    if (!_spaceless.contains(lang) && _letters(k) < 3) continue;
    out.add(k);
  }
  return out;
}

/// الگوی یک کلمه‌ی معادل (ریشه + پسوندِ کوتاهِ صرفی).
String _tokPat(String tok, String lang) {
  if (_spaceless.contains(lang)) return _esc(tok);
  final n = _letters(tok);
  var stem = tok;
  var k = n >= 4 ? 3 : 0;
  if (_rtlScript.contains(lang)) {
    // مصدر: گذاشتن ← ریشه‌ی گذشته «گذاشت»
    if (n >= 4 && (tok.endsWith('تن') || tok.endsWith('دن'))) {
      stem = tok.substring(0, tok.length - 1);
    }
  } else if (_romance.contains(lang)) {
    if (n >= 5 && RegExp(r'(ar|er|ir|re)$').hasMatch(tok)) {
      stem = tok.substring(0, tok.length - 2);
    } else if (n >= 5 && tok.endsWith('s')) {
      stem = tok.substring(0, tok.length - 1);
      if (stem.length >= 4 && RegExp(r'[aeiou]$').hasMatch(stem)) {
        stem = stem.substring(0, stem.length - 1);
      }
    } else if (n >= 4 && RegExp(r'[aeiou]$').hasMatch(tok)) {
      stem = tok.substring(0, tok.length - 1);
    }
  } else {
    if (n >= 4 && RegExp(r'[ey]$').hasMatch(tok)) {
      stem = tok.substring(0, tok.length - 1);
    }
  }
  if (_letters(stem) < 3) stem = tok;
  return k > 0 ? '${_esc(stem)}$_kL{0,$k}' : _esc(stem);
}

const List<String> _faSuffix = [
  'ها', 'های', 'ای', 'ان', 'ات', 'ی', 'ام', 'اش', 'ش', 'م', 'ت', 'مان', 'تان', 'شان',
];

/// الگوی کاملِ یک معادل (چندکلمه‌ای هم می‌شود). null = نامعتبر.
String? _candPattern(String cand, String lang) {
  final toks =
      cand.split(RegExp('[\\s$_zw]+')).where((t) => t.isNotEmpty).toList();
  if (toks.isEmpty) return null;
  final body = toks.map((t) => _tokPat(t, lang)).join('[\\s$_zw]+');
  if (_spaceless.contains(lang)) return body;
  final fa = _rtlScript.contains(lang);
  final verbish = fa && RegExp(r'[تد]ن$').hasMatch(toks.last);
  final pre = (fa && verbish) ? '(?:ن?می[\\s$_zw])?' : '';
  final post = fa ? '(?:$_zw(?:${_faSuffix.join('|')})(?!$_kL))?' : '';
  return '(?<!$_kL)$pre$body$post(?!$_kL)';
}

List<List<int>> _spansOf(String sk, String pattern) {
  final out = <List<int>>[];
  try {
    for (final m in RegExp(pattern, unicode: true).allMatches(sk)) {
      if (m.end > m.start) out.add([m.start, m.end]);
    }
  } catch (_) {}
  return out;
}

/// جای معادل‌های [cands] داخلِ [sk] (اسکلتِ ترجمه).
List<List<int>> _findSpans(String sk, List<String> cands, String lang) {
  final spans = <List<int>>[];
  for (final c in cands) {
    final p = _candPattern(c, lang);
    if (p == null) continue;
    final full = _spansOf(sk, p);
    if (full.isNotEmpty) {
      spans.addAll(full);
      continue;
    }
    // معادلِ چندکلمه‌ای کامل پیدا نشد → کلمه‌های محتوایی‌اش جداگانه
    final toks =
        c.split(RegExp('[\\s$_zw]+')).where((t) => t.isNotEmpty).toList();
    if (toks.length < 2) continue;
    final minLetters =
        (_rtlScript.contains(lang) || _spaceless.contains(lang)) ? 3 : 4;
    for (final t in toks) {
      if (_letters(t) < minLetters || _stop.contains(t)) continue;
      spans.addAll(_spansOf(sk, '(?<!$_kL)${_tokPat(t, lang)}(?!$_kL)'));
    }
  }
  return spans;
}

// ───────────────────────── API ─────────────────────────

/// نتیجه‌ی بولد کردنِ معادل‌ها در یک ترجمه.
class EquivResult {
  /// تکه‌های متن (مجموع = متنِ اصلی)؛ null اگر چیزی پیدا نشد.
  final List<SelectableRun>? runs;

  /// لغت‌هایی (کلیدِ همان‌هایی که در [equivByWord] دادید) که حداقل یک معادل‌شان پیدا شد.
  final Set<String> matched;
  const EquivResult(this.runs, this.matched);
}

/// [equivByWord]: لغتِ مبدأ ← متن‌های خامِ ترجمه‌ی کاندید (هر کدام ممکن است چند معادل داشته باشد).
EquivResult equivalentRuns({
  required String text,
  required String lang,
  required Map<String, List<String>> equivByWord,
  required TextStyle boldStyle,
}) {
  if (text.isEmpty || equivByWord.isEmpty) {
    return const EquivResult(null, <String>{});
  }
  final sk = _skel(text);
  final matched = <String>{};
  final all = <List<int>>[];
  equivByWord.forEach((word, raws) {
    final cands = <String>[];
    final seen = <String>{};
    for (final r in raws) {
      for (final c in _candidates(r, lang)) {
        if (seen.add(c)) cands.add(c);
      }
    }
    if (cands.isEmpty) return;
    final sp = _findSpans(sk, cands, lang);
    if (sp.isNotEmpty) {
      matched.add(word);
      all.addAll(sp);
    }
  });
  if (all.isEmpty) return EquivResult(null, matched);

  // هم‌پوشانی‌ها: از چپ، بلندترها اول
  all.sort((a, b) => a[0] != b[0] ? a[0].compareTo(b[0]) : b[1].compareTo(a[1]));
  final spans = <List<int>>[];
  var end = -1;
  for (final s in all) {
    if (s[0] >= end) {
      spans.add(s);
      end = s[1];
    }
  }
  final out = <SelectableRun>[];
  var pos = 0;
  for (final s in spans) {
    if (s[0] > pos) out.add(SelectableRun(text.substring(pos, s[0])));
    out.add(SelectableRun(text.substring(s[0], s[1]), boldStyle));
    pos = s[1];
  }
  if (pos < text.length) out.add(SelectableRun(text.substring(pos)));
  return EquivResult(out, matched);
}

/// شکل‌هایی از [word] که واقعاً داخلِ [src] آمده (مثلاً «affect» ← «affects»)؛ خالی = در این متن نیست.
/// همان تطبیقِ بولدِ متنِ مبدأ (word_highlight.dart) است تا دقیقاً با آنچه بولد شده یکی باشد.
List<String> sourceForms(String src, String word, String srcLang) {
  final runs = highlightRuns(src, [word], srcLang, const TextStyle());
  if (runs == null) return const [];
  return [
    for (final r in runs)
      if (r.style != null) r.text,
  ];
}
