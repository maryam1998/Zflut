// 📁 مسیر: lib/core/translate/in_text_translation.dart
//
// 🔗 ترجمه‌ی «حالتِ تمرین» = همان ترجمه‌ی داخلِ متن.
// ردیف‌های ترجمه‌ی زیرِ لغت/مکالمه/داستان/پیام‌های AI با کلیدِ (زبانِ مبدأ، زبانِ مقصد، متن) در کشِ
// دائمی ذخیره می‌شوند (ترجمه‌ی اصلاح‌شده با ↻ هم همان‌جا می‌نشیند). تمرین هم باید از همان‌جا بخواند،
// نه اینکه دوباره از مترجمِ ماشینی بپرسد و جوابِ متفاوت بگیرد.
//
// ترتیب (دقیقاً مثلِ SyncTranslationRow):
//   ۱) ترجمه‌ی ذخیره‌شده در کش (peekCached) اگر سالم باشد
//   ۲) معنیِ از‌پیش‌معلومِ خودِ اپ (known / KnownTranslations: لغات و مکالمات)
//   ۳) متنِ چندخطی/بلند: خط‌به‌خط و تکه‌تکه (مثلِ ترجمه‌ی زیرِ پیام‌های AI)
//   ۴) در آخر خودِ سرویسِ ترجمه (که اولش هم کش را می‌بیند)

import 'dart:async';

import '../utils/html_entities.dart';
import 'known_translations.dart';
import 'translation_service.dart';

const int _kChunk = 380;

List<String> _chunks(String line) {
  final t = line.trim();
  if (t.length <= _kChunk) return [t];
  final out = <String>[];
  var cur = '';
  for (final p in t.split(RegExp(r'(?<=[.!?؟。])\s+'))) {
    if (cur.isNotEmpty && cur.length + p.length + 1 > _kChunk) {
      out.add(cur);
      cur = p;
    } else {
      cur = cur.isEmpty ? p : '$cur $p';
    }
  }
  if (cur.isNotEmpty) out.add(cur);
  return out;
}

String _plain(String t) => decodeHtmlEntities(t)
    .replaceAll(RegExp('[\u2066-\u2069]'), '')
    .replaceAll(RegExp(r'\*\*|__|`'), '')
    .replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), '')
    .replaceAll(RegExp(r'^\s*[-*•]\s+', multiLine: true), '')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();

/// ترجمه‌ی [text] از [from] به [to] — همان ترجمه‌ای که داخلِ متن نشان داده می‌شود.
/// اگر ترجمه نشد خودِ [text] برمی‌گردد (مثلِ TranslationService.translate).
Future<String> inTextTranslate({
  required TranslationService svc,
  required AiSettings ai,
  required String text,
  required String from,
  required String to,
  String known = '',
}) async {
  final src = text.trim();
  if (src.isEmpty || to.isEmpty) return text;
  if (from.isNotEmpty && from != 'auto' && from == to) return text;

  bool usable(String seg, String r) =>
      r.trim().isNotEmpty &&
      !looksLikelyMistranslated(seg, r.trim(), to, sourceLang: from);

  // ۰) 📌 ترجمه‌ی قفل‌شده‌ی کاربر (↻) همیشه مقدم است؛ بدون کنترل کیفیت و بدون معنیِ از‌پیش‌معلوم
  final pin = svc.pinned(src, to);
  if (pin != null) return decodeHtmlEntities(pin.trim());
  final plain0 = _plain(src);
  if (plain0.isNotEmpty && plain0 != src) {
    final pp = svc.pinned(plain0, to);
    if (pp != null) return decodeHtmlEntities(pp.trim());
  }

  // ۱) ترجمه‌ی ذخیره‌شده (مثلاً اصلاح‌شده با ↻)
  final saved = svc.peekCached(src, from, to);
  if (saved != null && usable(src, saved)) {
    return decodeHtmlEntities(saved.trim());
  }
  // زیرِ پیام‌های AI متن بعد از پاک‌کردنِ مارک‌داون (**، #، -) ترجمه می‌شود
  final plain = _plain(src);
  if (plain.isNotEmpty && plain != src) {
    final sp = svc.peekCached(plain, from, to);
    if (sp != null && usable(plain, sp)) return decodeHtmlEntities(sp.trim());
  }

  // ۲) معنیِ از‌پیش‌معلومِ اپ (فقط اگر به رسم‌الخطِ همین زبان باشد)
  var k = known.trim();
  if (k.isEmpty) k = (KnownTranslations.get(src, from, to) ?? '').trim();
  if (k.isNotEmpty && textMatchesScript(k, to)) return k;

  // یک تکه را از کش/سرویس می‌گیرد
  Future<String> one(String seg) async {
    final pinSeg = svc.pinned(seg, to);
    if (pinSeg != null) return decodeHtmlEntities(pinSeg.trim());
    final hit = svc.peekCached(seg, from, to);
    if (hit != null && usable(seg, hit)) {
      return decodeHtmlEntities(hit.trim());
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      String r = '';
      try {
        r = decodeHtmlEntities((await svc.translate(
                text: seg, targetLang: to, sourceLang: from, aiSettings: ai))
            .trim());
      } catch (_) {}
      if (usable(seg, r)) return r;
      if (attempt == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      }
    }
    return seg;
  }

  // ۳) متنِ چندخطی یا بلند: خط‌به‌خط/تکه‌تکه (مثلِ ترجمه‌ی زیرِ پیامِ AI)
  if (src.contains('\n') || src.length > _kChunk || plain != src) {
    final lines = plain.split('\n');
    final out = <String>[];
    var ok = 0;
    for (final l in lines) {
      if (l.trim().isEmpty) {
        out.add('');
        continue;
      }
      final parts = <String>[];
      for (final seg in _chunks(l)) {
        final r = await one(seg);
        if (r.trim() != seg.trim()) ok++;
        parts.add(r);
      }
      out.add(parts.join(' '));
    }
    if (ok == 0) return text;
    return out.join('\n').trim();
  }

  // ۴) متنِ کوتاه: یک تکه
  final r = await one(src);
  return r.trim() == src ? text : r;
}
