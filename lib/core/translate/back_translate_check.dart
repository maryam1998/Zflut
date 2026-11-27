// 📁 مسیر: lib/core/translate/back_translate_check.dart
//
// 🔁 غربالگریِ رایگان با «ترجمه‌ی برگشتی» روی گوشی (ML Kit) — قبل از رفتن سراغ AI.
//
//   ترجمه‌ی رایگانِ en→es سالم به‌نظر می‌رسد؟ پس با ML Kit دوباره es→en برمی‌گردانیم
//   و با متنِ اصلی مقایسه می‌کنیم. معنی حفظ شده = ترجمه درست = بدونِ هزینه‌ی AI.
//   مثال: «It's in the bag» → ترجمه‌ی تحت‌اللفظی → برگشتی «Everything fits in the bag» → مشکوک → AI.
//
// قوانینِ سرعت (این چک هرگز نباید کاربر را معطل کند):
//   • فقط وقتی مدلِ ML Kit برای جفتِ برعکس «از قبل دانلود شده» باشد؛ دانلودی شروع نمی‌شود.
//   • سقفِ زمانی ۱.۵ ثانیه؛ هر خطا/تایم‌اوت/غیرِ اندروید = «نامعلوم» (یعنی مثل قبل، مشکوک حساب نمی‌شود).
//   • نتیجه‌ی وضعیتِ مدل در حافظه کش می‌شود تا هر بار mlkitStatus صدا نخورد.
//
// این فایل مستقل است و فقط NativeBridge را صدا می‌زند.

import 'dart:async';

import '../native/native_bridge.dart';

const Duration _kBtTimeout = Duration(milliseconds: 1500);
const int _kBtMaxChars = 300;

// زبان‌هایی که با فاصله‌ی لاتین توکن می‌شوند و مقایسه‌ی واژه‌ایشان معنی دارد (به‌عنوان «مبدأ»)
const Set<String> _kBtSrcLangs = {'en', 'es', 'fr', 'de', 'it', 'tr'};

const Set<String> _kStop = {
  // en
  'the', 'and', 'but', 'for', 'are', 'was', 'were', 'you', 'your', 'she', 'her',
  'his', 'him', 'its', 'our', 'they', 'them', 'their', 'this', 'that', 'these',
  'those', 'with', 'from', 'have', 'has', 'had', 'will', 'would', 'can', 'could',
  'not', 'don', 'did', 'does', 'any', 'all', 'one', 'out', 'who', 'what', 'when',
  'where', 'how', 'why', 'than', 'then', 'too', 'very', 'just', 'there', 'here',
  // es / fr / de / it (پرتکرار)
  'los', 'las', 'una', 'uno', 'del', 'por', 'con', 'que', 'les', 'des', 'une',
  'est', 'pas', 'der', 'die', 'das', 'und', 'ein', 'ist', 'nicht', 'che', 'una',
  'gli', 'per', 'non', 'bir', 'bu',
};

final Map<String, int> _readyUntil = <String, int>{}; // جفت → زمانِ انقضای «آماده است»
final Map<String, int> _notReadyUntil = <String, int>{}; // جفت → تا این زمان دوباره نپرس

String _fold(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[àáâãäå]'), 'a')
    .replaceAll(RegExp('[èéêë]'), 'e')
    .replaceAll(RegExp('[ìíîï]'), 'i')
    .replaceAll(RegExp('[òóôõö]'), 'o')
    .replaceAll(RegExp('[ùúûü]'), 'u')
    .replaceAll('ñ', 'n')
    .replaceAll('ç', 'c')
    .replaceAll('ı', 'i')
    .replaceAll('ş', 's')
    .replaceAll('ğ', 'g')
    .replaceAll('ß', 'ss');

/// واژه‌های محتوایی با ریشه‌ی تقریبی (۴ حرفِ اول) — برای تحمل‌کردنِ صرف (fits/fit، running/run)
Set<String> _stems(String s) {
  final out = <String>{};
  for (final m in RegExp(r"[a-z0-9]+").allMatches(_fold(s).replaceAll(RegExp("['’]"), ''))) {
    final w = m.group(0)!;
    if (RegExp(r'^\d+$').hasMatch(w)) {
      out.add(w);
      continue;
    }
    if (w.length < 3 || _kStop.contains(w)) continue;
    out.add(w.length > 4 ? w.substring(0, 4) : w);
  }
  return out;
}

/// شباهتِ معنایی‌ِ تقریبی (۰..۱) بین متنِ اصلی و ترجمه‌ی برگشتی (ضریب Dice روی ریشه‌ی واژه‌های محتوایی).
/// null = قابل‌سنجش نیست (مثلاً واژه‌ی محتوایی ندارد).
double? backSimilarity(String original, String back) {
  final a = _stems(original);
  final b = _stems(back);
  if (a.isEmpty || b.isEmpty) return null;
  final inter = a.intersection(b).length;
  return 2 * inter / (a.length + b.length);
}

/// آستانه: جمله‌ی کوتاه سخت‌گیرتر (هر واژه‌ی اضافه/کم یعنی تغییرِ معنی)، بلند آسان‌تر (بازنویسی طبیعی است).
double _threshold(String original, String back) {
  final n = _stems(original).length > _stems(back).length
      ? _stems(original).length
      : _stems(back).length;
  if (n <= 4) return 0.6;
  if (n <= 8) return 0.5;
  return 0.4;
}

Future<bool> _modelReady(String src, String tgt) async {
  final key = '$src>$tgt';
  final now = DateTime.now().millisecondsSinceEpoch;
  if ((_readyUntil[key] ?? 0) > now) return true;
  if ((_notReadyUntil[key] ?? 0) > now) return false;
  try {
    final st = await NativeBridge.instance
        .mlkitStatus(src: src, tgt: tgt)
        .timeout(const Duration(seconds: 2));
    final ok = st['supported'] == true && st['ready'] == true;
    if (ok) {
      _readyUntil[key] = now + 10 * 60 * 1000;
    } else {
      _notReadyUntil[key] = now + 60 * 1000;
    }
    return ok;
  } catch (_) {
    _notReadyUntil[key] = now + 30 * 1000;
    return false;
  }
}

/// 🔁 آیا ترجمه‌ی [draft] (from→to) طبقِ ترجمه‌ی برگشتیِ ML Kit «معنی را خراب کرده»؟
///   true  = مشکوک (باید AI بازبینی کند)
///   false = سالم، یا چکِ برگشتی ممکن/معتبر نبود (در این حالت تصمیمِ قبلی بدونِ تغییر می‌ماند)
Future<bool> backTranslationLooksBroken(
    String src, String draft, String from, String to) async {
  try {
    if (from.isEmpty || from == 'auto' || from == to) return false;
    if (!_kBtSrcLangs.contains(from)) return false;
    final s = src.trim();
    final d = draft.trim();
    if (s.isEmpty || d.isEmpty || s.length > _kBtMaxChars || d.length > _kBtMaxChars) {
      return false;
    }
    // تک‌کلمه‌ها مترادف‌پذیرند (big/large) و مسیرِ دیکشنری دارند؛ فقط جمله/عبارت
    if (!RegExp(r'\s').hasMatch(s)) return false;

    final n = NativeBridge.instance;
    if (!n.isSupported) return false;
    if (!await _modelReady(to, from)) return false; // دانلود شروع نمی‌کنیم

    final r = await n
        .mlkitTranslate(text: d, src: to, tgt: from)
        .timeout(_kBtTimeout);
    final back = r['text'];
    if (back is! String || back.trim().isEmpty) return false;

    final sim = backSimilarity(s, back);
    if (sim == null) return false;
    return sim < _threshold(s, back);
  } catch (_) {
    return false;
  }
}
