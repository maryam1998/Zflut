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

/// ✂️ اگر متن وسطِ جمله بریده شده، جمله‌ی ناقصِ آخر را حذف می‌کند (بدونِ تماسِ دوباره با AI).
/// فقط وقتی اعمال می‌شود که حداقل ۶۰٪ متن بماند؛ وگرنه متن دست‌نخورده برمی‌گردد.
String trimIncompleteTail(String s) {
  final t = s.trimRight();
  if (!aiLooksCutOff(t)) return s;
  Match? last;
  for (final m in RegExp('[.!?؟…。][\\)\\]»"”\'’*]*').allMatches(t)) {
    last = m;
  }
  if (last == null || last.end < t.length * 0.6) return s;
  return t.substring(0, last.end).trimRight();
}
