import 'dart:async';

import '../ai/ai_gateway.dart';
import 'translation_service.dart';

// ═══════════════════════════════════════════════════════════════════
// ترجمه‌ی داستان‌ساز / خوانشِ داستان: مترجم رایگان + بازبینیِ AI «فقط برای
// ترجمه‌های مشکوک» + کشِ دائمی
//
// ریشه‌ی مشکل قبلی:
//  • ناظرِ AI فقط با چکِ سبکِ looksLikelyMistranslated فعال می‌شد (خالی، همان
//    متن مبدأ، نسبتِ طولِ خیلی عجیب) و ترجمه‌های ناقص/نیمه‌ترجمه‌شده رد می‌شدند.
//  • سقفِ توکنِ ناظر ۸۰ بود؛ برای یک پاراگراف، اصلاح وسط جمله بریده می‌شد.
//
// حالا:
//  ۱. کشِ بازبینی‌شده (rv1) → فوری.
//  ۲. ترجمه‌ی رایگان (کش‌دار، بدون AI).
//  ۳. چکِ «مشکوک» گسترده‌تر (رایگان، همگام): کلماتِ ترجمه‌نشده‌ی لاتین در
//     زبانِ غیرلاتین، عددِ جاافتاده، جمله‌های جاافتاده، تکرارِ حلقه‌ای، نسبتِ
//     طول و موارد قبلی.
//  ۴. فقط اگر مشکوک بود → یک بار بازبینیِ AI (با سقفِ توکنِ کافی)؛ نتیجه در
//     کشِ rv1 ذخیره می‌شود. ترجمه‌ی سالم هرگز AI نمی‌خورد.
//  ۵. دکمه‌ی ↻ (fresh): کاربر خودش خواسته → همیشه بازبینیِ AI.
// ═══════════════════════════════════════════════════════════════════

const String _kNs = 'rv1';
const int _kReviewTimeoutMs = 20000;

final Map<String, Future<String>> _inflight = {};

String _ns(String from) => '$_kNs:${from.isEmpty ? 'auto' : from}';

/// خواندنِ همگام از کشِ بازبینی‌شده (null اگر نبود)
String? peekReviewed(
        TranslationService svc, String text, String from, String to) =>
    svc.peekCached(text, _ns(from), to);

/// هیچ‌وقت exception نمی‌دهد؛ در بدترین حالت متن اصلی را برمی‌گرداند.
/// [fresh] = true (دکمه‌ی ↻): کش را دور بزن و همیشه با AI بازبینی کن.
Future<String> reviewedTranslate({
  required TranslationService svc,
  required AiSettings? ai,
  required String text,
  required String from,
  required String to,
  bool fresh = false,
  String? previous,
}) {
  if (text.trim().isEmpty || to.isEmpty) return Future.value(text);
  if (from.isNotEmpty && from != 'auto' && from == to) {
    return Future.value(text);
  }
  if (fresh) {
    return _run(svc, ai, text, from, to, true, previous);
  }
  final hit = svc.peekCached(text, _ns(from), to);
  if (hit != null) return Future.value(hit);
  final key = '${_ns(from)}::$to::$text';
  final running = _inflight[key];
  if (running != null) return running;
  final f = _run(svc, ai, text, from, to, false, previous)
      .whenComplete(() => _inflight.remove(key));
  _inflight[key] = f;
  return f;
}

// ───────────────────────── تشخیصِ «مشکوک» ─────────────────────────

const Set<String> _nonLatinTargets = {
  'fa', 'ar', 'ur', 'he', 'ru', 'uk', 'bg', 'el', 'hi', 'bn', 'th', 'zh',
  'ja', 'ko',
};
const Set<String> _cjkLike = {'zh', 'ja', 'ko', 'th'};

String _asciiDigits(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0x06F0 && r <= 0x06F9) {
      b.writeCharCode(r - 0x06F0 + 0x30);
    } else if (r >= 0x0660 && r <= 0x0669) {
      b.writeCharCode(r - 0x0660 + 0x30);
    } else {
      b.writeCharCode(r);
    }
  }
  return b.toString();
}

/// بررسیِ رایگان و همگامِ ترجمه — true = مشکوک، باید AI بازبینی کند.
bool _suspicious(String src, String draft, String from, String to) {
  final d = draft.trim();
  if (d.isEmpty || d.toLowerCase() == src.toLowerCase()) return true;
  if (looksLikelyMistranslated(src, d, to, sourceLang: from)) return true;

  // ۱. کلمه‌های لاتینِ ترجمه‌نشده در زبانِ مقصدِ غیرلاتین (نام‌های خاصِ مبدأ مجازند)
  if (_nonLatinTargets.contains(to)) {
    final srcWords = RegExp(r'[A-Za-z]{3,}')
        .allMatches(src)
        .map((m) => m.group(0)!.toLowerCase())
        .toSet();
    final latin = RegExp(r'[A-Za-z]{3,}')
        .allMatches(d)
        .map((m) => m.group(0)!.toLowerCase())
        .where((w) => !srcWords.contains(w))
        .length;
    final total = d.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    if (latin >= 2 && total > 0 && latin / total > 0.3) return true;
  }

  // ۲. عددی که در ترجمه نیست
  final dd = _asciiDigits(d);
  for (final m in RegExp(r'\d+').allMatches(_asciiDigits(src))) {
    if (!dd.contains(m.group(0)!)) return true;
  }

  // ۳. نسبتِ طولِ مشکوک (برای زبان‌های CJK/تایی معنی ندارد)
  if (src.length >= 40 && !_cjkLike.contains(to) && !_cjkLike.contains(from)) {
    final ratio = d.length / src.length;
    if (ratio < 0.45 || ratio > 2.6) return true;
  }

  // ۴. جمله‌های جاافتاده (ترجمه‌ی بریده)
  final enders = RegExp(r'[.!?؟…]+');
  final sc = enders.allMatches(src).length;
  if (sc >= 3 && enders.allMatches(d).length < sc * 0.5) return true;

  // ۵. تکرارِ حلقه‌ای (۴ توکنِ مساویِ پشت‌سرهم)
  final toks = d.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  var run = 1;
  for (var i = 1; i < toks.length; i++) {
    run = toks[i] == toks[i - 1] ? run + 1 : 1;
    if (run >= 4) return true;
  }
  return false;
}

// ───────────────────────── اجرا ─────────────────────────

Future<String> _run(TranslationService svc, AiSettings? ai, String text,
    String from, String to, bool fresh, String? previous) async {
  final src = text.trim();
  // بدونِ هیچ حرفی (فقط عدد/علامت) → ترجمه‌ای لازم نیست
  if (!RegExp(r'\p{L}', unicode: true).hasMatch(src)) return text;

  // ۱. ترجمه‌ی رایگان (بدونِ ناظرِ داخلیِ سرویس؛ ناظرِ ما پایین است)
  var draft = '';
  try {
    draft = fresh
        ? (await svc.retranslate(
                text: src,
                targetLang: to,
                sourceLang: from.isEmpty || from == 'auto' ? 'en' : from))
            .trim()
        : (await svc.translate(text: src, targetLang: to, sourceLang: from))
            .trim();
  } catch (_) {}

  final suspicious = _suspicious(src, draft, from, to);
  final draftUsable = draft.isNotEmpty && draft != src;

  // ۲. ترجمه‌ی سالم → همان؛ AI صدا زده نمی‌شود (مگر ↻)
  if (!fresh && !suspicious) return draft;
  if (ai == null) return draftUsable ? draft : src;

  // ۳. فقط مشکوک‌ها (یا ↻) → بازبینیِ AI
  try {
    final reviewed = await _review(
            svc, ai, src, draftUsable ? draft : '', from, to,
            previous: previous)
        .timeout(const Duration(seconds: 45));
    if (reviewed.isNotEmpty) {
      await svc.cachePut(src, _ns(from), to, reviewed);
      return reviewed;
    }
  } catch (_) {}
  return draftUsable ? draft : src;
}

Future<String> _review(TranslationService svc, AiSettings ai, String src,
    String draft, String from, String to,
    {String? previous}) async {
  final toName = englishLangName(to);
  final fromName = (from.isEmpty || from == 'auto')
      ? 'the source language'
      : englishLangName(from);
  final prev = previous?.trim() ?? '';

  final b = StringBuffer()
    ..writeln('You are a professional literary translator and proofreader.')
    ..writeln('Source language: $fromName. Target language: $toName.')
    ..writeln()
    ..writeln('Source text:')
    ..writeln('<<<')
    ..writeln(src)
    ..writeln('>>>');
  if (draft.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Draft machine translation (suspected to be wrong or incomplete):')
      ..writeln('<<<')
      ..writeln(draft)
      ..writeln('>>>');
  }
  if (prev.isNotEmpty) {
    b
      ..writeln()
      ..writeln('The user rejected this earlier translation, so do NOT repeat it:')
      ..writeln('<<<')
      ..writeln(prev)
      ..writeln('>>>');
  }
  b
    ..writeln()
    ..writeln(draft.isNotEmpty
        ? 'Task: compare the draft with the source and fix every mistranslation, '
            'untranslated word, missing or added meaning, and word-for-word phrasing. '
        : 'Task: translate the source text. ')
    ..writeln('Translate idioms and phrasal verbs by their real meaning. '
        'The result must read as natural, fluent $toName written by a native '
        'speaker, in the same tone and register as the source. '
        'Keep names, numbers and punctuation. Do not summarize or omit anything.')
    ..writeln()
    ..write('Output ONLY the final $toName translation as plain text — no quotes, '
        'no notes, no labels, no explanation.');

  // سقفِ توکنِ کافیِ پاراگراف (قبلاً ۸۰ بود و اصلاح را وسطِ جمله می‌برید)
  final maxTokens = (src.length * 1.3 + 128).round().clamp(192, 1500).toInt();

  bool sane(String r) {
    final t = r.trim();
    if (t.isEmpty) return false;
    if (RegExp(r'^(OK|YES|NO)\.?$', caseSensitive: false).hasMatch(t)) {
      return false;
    }
    if (looksLikelyMistranslated(src, t, to, sourceLang: from)) return false;
    if (t.length > src.length * 3.5 + 40) return false;
    return true;
  }

  var out = await aiGenerate(
    svc: svc,
    settings: ai,
    prompt: b.toString(),
    maxTokens: maxTokens,
    retries: 1,
    timeoutMs: _kReviewTimeoutMs,
    extraCheck: sane,
  );
  out = out.replaceAll(RegExp("^[\"'«»“”]+|[\"'«»“”\\s]+\$"), '').trim();
  return sane(out) ? out : '';
}
