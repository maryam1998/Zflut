// 📁 مسیر: lib/core/story/long_text_prep.dart
//
// آماده‌سازیِ متن‌های خیلی بلند (مثلاً کتابِ ۴۰۰ صفحه‌ای) برای خوانش.
// همه‌ی توابعِ این فایل «خالص» و top-level هستند تا با compute() در یک isolate
// جدا اجرا شوند و ترد اصلیِ برنامه (UI) هیچ‌وقت قفل نشود.

import 'dart:math' as math;

const int kMaxWordsPerSentence = 40;
const int kSentencesPerParagraph = 5;

final RegExp _reDigitDot = RegExp(r'(\d)\.(?=\d)');
final RegExp _reSentence = RegExp(r'[^.!?؟。！]+[.!?؟。！]*');
final RegExp _reSpaces = RegExp(r'\s+');
final RegExp _reNonAlnum = RegExp(r'[^\p{L}\p{N}]', unicode: true);
final RegExp _reLatinWord = RegExp(r'[a-zàâäçèéêëîïôöùûüÿñßışğî]+');

/// شکستنِ متن به جمله (همان رفتارِ قبلیِ _splitSentences در story_tab).
List<String> splitSentencesText(String text) {
  final t = text.trim();
  if (t.isEmpty) return const [];
  final protectedT =
      t.replaceAllMapped(_reDigitDot, (m) => '${m[1]}\u0001');
  final raw = _reSentence
      .allMatches(protectedT)
      .map((m) => m.group(0)!.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  final parts = (raw.isEmpty ? [protectedT] : raw)
      .map((e) => e.replaceAll('\u0001', '.').replaceAll(_reSpaces, ' ').trim())
      .where((e) => e.isNotEmpty)
      .toList();
  final out = <String>[];
  for (final part in parts) {
    // جمله‌ی کمتر از ۸۰ حرف حتماً کمتر از ۴۰ کلمه است — نیازی به شکستن نیست
    if (part.length < 80) {
      out.add(part);
      continue;
    }
    final words = part.split(_reSpaces).where((w) => w.isNotEmpty).toList();
    if (words.length <= kMaxWordsPerSentence) {
      out.add(part);
      continue;
    }
    for (var i = 0; i < words.length; i += kMaxWordsPerSentence) {
      final end = i + kMaxWordsPerSentence > words.length
          ? words.length
          : i + kMaxWordsPerSentence;
      out.add(words.sublist(i, end).join(' '));
    }
  }
  return out;
}

/// تشخیصِ زبانِ متن از روی خطِ نوشتاری (فقط ۳۰ هزار حرفِ اول بررسی می‌شود).
String detectTextLang(String text, String fallback) {
  final sample = text.length > 30000 ? text.substring(0, 30000) : text;
  var arabic = 0, cyr = 0, deva = 0, kana = 0, hangul = 0, cjk = 0, latin = 0;
  var persian = 0;
  for (final r in sample.runes) {
    if (r >= 0x0600 && r <= 0x06FF) {
      arabic++;
      if (r == 0x067E || r == 0x0686 || r == 0x0698 || r == 0x06AF) {
        persian++;
      }
    } else if (r >= 0x0400 && r <= 0x04FF) {
      cyr++;
    } else if (r >= 0x0900 && r <= 0x097F) {
      deva++;
    } else if (r >= 0x3040 && r <= 0x30FF) {
      kana++;
    } else if (r >= 0xAC00 && r <= 0xD7AF) {
      hangul++;
    } else if (r >= 0x4E00 && r <= 0x9FFF) {
      cjk++;
    } else if ((r >= 0x41 && r <= 0x5A) ||
        (r >= 0x61 && r <= 0x7A) ||
        (r >= 0xC0 && r <= 0x24F)) {
      latin++;
    }
  }
  final mx = [arabic, cyr, deva, kana, hangul, cjk, latin]
      .reduce((a, b) => a > b ? a : b);
  if (mx == 0) return fallback;
  if (mx == arabic) return persian > 0 ? 'fa' : 'ar';
  if (mx == cyr) return 'ru';
  if (mx == deva) return 'hi';
  if (mx == kana) return 'ja';
  if (mx == hangul) return 'ko';
  if (mx == cjk) return kana > 0 ? 'ja' : 'zh';
  const stop = <String, List<String>>{
    'de': ['der','die','das','und','ist','nicht','mit','für','ein','eine','sie','auf','was','wie','wenn','aber','auch','sich','dass','ich'],
    'es': ['el','la','los','las','de','que','y','en','no','es','un','una','para','por','con','su','del','al','se','lo'],
    'fr': ['le','la','les','et','est','une','des','dans','pour','que','qui','ne','pas','ce','vous','je','nous','avec','au','un'],
    'it': ['il','la','di','che','è','un','una','per','non','con','gli','le','sono','questo','questa','del','alla','si','mi','ma'],
    'tr': ['ve','bir','bu','için','ile','de','da','çok','ama','ne','gibi','daha','var','yok','ben','sen','biz','onun','şey','değil'],
    'en': ['the','and','is','to','of','in','that','it','was','for','on','with','he','she','you','this','but','not','are','as'],
  };
  final words = _reLatinWord
      .allMatches(sample.toLowerCase())
      .map((m) => m.group(0)!)
      .toSet();
  var bestCode = fallback;
  var bestScore = 0;
  stop.forEach((code, list) {
    final sc = list.where(words.contains).length;
    if (sc > bestScore) {
      bestScore = sc;
      bestCode = code;
    }
  });
  if (bestScore > 0) return bestCode;
  const latinLangs = ['en', 'es', 'de', 'fr', 'it', 'tr'];
  return latinLangs.contains(fallback) ? fallback : 'en';
}

/// حدسِ سطحِ CEFR (فقط روی ۴۰ هزار حرفِ اولِ متن — برای متن‌های بلند کافی است).
String detectTextCefr(String text) {
  var t = text.trim();
  if (t.isEmpty) return 'A2';
  if (t.length > 40000) t = t.substring(0, 40000);
  final sentences = splitSentencesText(t);
  final words = t.split(_reSpaces).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty || sentences.isEmpty) return 'A2';
  final clean = words
      .map((w) => w.replaceAll(_reNonAlnum, ''))
      .where((w) => w.isNotEmpty)
      .toList();
  if (clean.isEmpty) return 'A2';
  final avgSentence = words.length / sentences.length;
  final avgWord = clean.fold<int>(0, (a, w) => a + w.length) / clean.length;
  final longRatio = clean.where((w) => w.length >= 7).length / clean.length;
  final uniqueRatio =
      clean.map((w) => w.toLowerCase()).toSet().length / clean.length;
  final score = avgSentence + avgWord * 3.0 + longRatio * 40 + uniqueRatio * 15;
  if (score < 14) return 'A1';
  if (score < 19) return 'A2';
  if (score < 24) return 'B1';
  if (score < 29) return 'B2';
  if (score < 34) return 'C1';
  return 'C2';
}

/// ورودیِ compute: {'raw': String, 'fallback': String, 'maxSentences': int}
/// خروجی (Map ساده تا بین isolateها بدونِ مشکل منتقل شود):
/// {'paras': List<String>, 'lang': String, 'level': String, 'title': String,
///  'sentences': int, 'truncated': bool}
Map<String, Object?> prepareLongText(Map<String, Object?> args) {
  final raw = (args['raw'] ?? '') as String;
  final fallback = (args['fallback'] ?? 'en') as String;
  final maxSentences = (args['maxSentences'] as int?) ?? 60000;
  var sentences = splitSentencesText(raw);
  var truncated = false;
  if (sentences.length > maxSentences) {
    sentences = sentences.sublist(0, maxSentences);
    truncated = true;
  }
  final paras = <String>[];
  for (var i = 0; i < sentences.length; i += kSentencesPerParagraph) {
    final end = math.min(i + kSentencesPerParagraph, sentences.length);
    paras.add(sentences.sublist(i, end).join(' '));
  }
  return <String, Object?>{
    'paras': paras,
    'lang': detectTextLang(raw, fallback),
    'level': detectTextCefr(raw),
    'title': sentences.isEmpty
        ? ''
        : sentences.first.split(_reSpaces).take(6).join(' '),
    'sentences': sentences.length,
    'truncated': truncated,
  };
}
