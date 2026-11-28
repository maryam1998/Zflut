// 📁 مسیر: lib/core/translate/translate_hints.dart
//
// 🎓 راهنمای ترجمه برای Worker: «سطحِ» جمله (A1..C2) و «خطِ قبلیِ همان مکالمه».
// UI قبل از ساختنِ ردیف‌های ترجمه [put] را صدا می‌زند؛ ai_first_translator موقعِ ساختنِ درخواستِ AI
// ([level] / [context]) را می‌خواند و به‌صورت level/context (یا levels/contexts در batch) می‌فرستد.
// Worker از آن فقط برای فهمِ معنی استفاده می‌کند (کلیدِ کشِ مشترک عوض نمی‌شود).
// حافظه‌ای و سبک است؛ هیچ‌چیز ذخیره‌ی دائمی نمی‌شود.

class TranslateHints {
  TranslateHints._();

  static const int _kMax = 2000;
  static final Map<String, ({String level, String context, String next})> _m =
      <String, ({String level, String context, String next})>{};

  static String _k(String text) => text.trim();

  /// ثبتِ راهنما برای یک متن. مقدارِ خالی = بدونِ راهنما.
  static void put(String text,
      {String level = '', String context = '', String next = ''}) {
    final k = _k(text);
    if (k.isEmpty) return;
    final lv = level.trim().toUpperCase();
    final cx = context.trim();
    final nx = next.trim();
    if (lv.isEmpty && cx.isEmpty && nx.isEmpty) return;
    if (_m.length >= _kMax) _m.remove(_m.keys.first); // قدیمی‌ترین را بینداز
    _m[k] = (
      level: lv,
      context: cx.length > 300 ? cx.substring(0, 300) : cx,
      next: nx.length > 300 ? nx.substring(0, 300) : nx,
    );
  }

  static String level(String text) => _m[_k(text)]?.level ?? '';
  static String context(String text) => _m[_k(text)]?.context ?? '';

  /// 🎓 خطِ بعدیِ همان مکالمه (برای فهمیدنِ معنیِ درستِ کلماتِ چندمعنی)
  static String next(String text) => _m[_k(text)]?.next ?? '';
}
