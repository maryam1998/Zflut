// 📁 مسیر: lib/core/ai/cutoff_guard.dart
//
// ✂️ تشخیصِ جوابِ AI که وسطِ جمله بریده شده (سقفِ توکن تمام شده). Worker نشانه‌ی «بریده‌شدن» برنمی‌گرداند،
// پس فقط از روی متن حدس می‌زنیم: جواب بلند است و آخرین نویسه علامتِ پایان/بسته‌شدن نیست.

/// true = جواب احتمالاً وسطِ جمله تمام شده.
bool aiLooksCutOff(String s) {
  final t = s.trim();
  if (t.length < 120) return false;
  final last = t.codeUnitAt(t.length - 1);
  if (last > 0x2E00) return false; // ایموجی/CJK/علامت‌های خاص
  return !'.!?؟…。)]»"”\'’*`:'.contains(t[t.length - 1]);
}
