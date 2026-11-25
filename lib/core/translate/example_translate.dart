// 📁 مسیر: lib/core/translate/example_translate.dart
//
// ترجمه‌ی مثال‌ها (مثال‌ساز / مثال‌های ذخیره‌شده) — همان منطقِ بقیه‌ی بخش‌ها:
//   ۱. کش (پین‌شده / کشِ گوشی)                         → فوری، بدونِ شبکه و AI
//   ۲. ترجمه‌ی رایگان (کشِ مشترک ← ML Kit ← مترجم‌های آنلاین)
//   ۳. فقط اگر «مشکوک» بود → AI، از مسیرِ دسته‌ای (/api/translate-batch)
// ترجمه‌ی سالم هیچ‌وقت AI نمی‌خورد (forceVerify حذف شد).

import 'ai_first_translator.dart';
import 'reviewed_translate.dart' show isSuspiciousTranslation;
import 'translation_service.dart';

/// هیچ‌وقت exception نمی‌دهد؛ اگر چیزی پیدا نشد '' برمی‌گرداند.
/// [onDraft]: وقتی ترجمه‌ی رایگان آماده شد ولی مشکوک است و AI در راه است، برای نمایشِ فوری صدا زده می‌شود.
Future<String> translateExample({
  required TranslationService svc,
  required AiSettings? ai,
  required String text,
  required String from,
  required String to,
  void Function(String draft)? onDraft,
}) async {
  final src = text.trim();
  if (src.isEmpty || to.isEmpty) return '';
  if (from.isNotEmpty && from != 'auto' && from == to) return src;

  // ۱. کش — مقدارِ کش‌شده معتبر حساب می‌شود (دوباره مشکوک‌یابی نمی‌شود تا AI تکرار نشود)
  try {
    final hit = svc.peekCached(src, from, to)?.trim() ?? '';
    if (hit.isNotEmpty && hit != src) return hit;
  } catch (_) {}

  // ۲. ترجمه‌ی رایگان (بدونِ AI)
  var draft = '';
  try {
    draft = (await svc.translate(text: src, targetLang: to, sourceLang: from))
        .trim();
  } catch (_) {}
  final usable = draft.isNotEmpty && draft != src;
  final suspicious =
      !usable || isSuspiciousTranslation(src, draft, from, to);
  if (!suspicious || ai == null) return usable ? draft : '';

  // ۳. مشکوک → AI دسته‌ای (تا آماده شدن، پیش‌نویس نشان داده می‌شود)
  if (usable && onDraft != null) {
    try {
      onDraft(draft);
    } catch (_) {}
  }
  String? r;
  try {
    r = await AiFirstTranslator.askAiBatched(
        svc: svc, base: ai.baseUrl, text: src, from: from, to: to);
  } catch (_) {}
  final v = r?.trim() ?? '';
  if (v.isNotEmpty && v != src) {
    try {
      await svc.cachePut(src, from, to, v);
    } catch (_) {}
    return v;
  }
  return usable ? draft : '';
}
