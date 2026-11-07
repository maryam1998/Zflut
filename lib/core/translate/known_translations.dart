// 📁 مسیر: lib/core/translate/known_translations.dart
//
// ترجمه‌های «از‌پیش‌معلوم» (داده‌های خودِ اپ: لغات، مکالمات، …). کارت‌های برنامه همین‌ها را نشان می‌دهند؛
// نوتیفیکیشنِ پلیر هم باید از همین‌ها بخواند، نه اینکه جمله را دوباره با مترجمِ ماشینی ترجمه کند
// (مثلاً «patient» را «بیمار» ترجمه می‌کرد).

class KnownTranslations {
  KnownTranslations._();

  static final Map<String, String> _m = {};

  static String _norm(String s) {
    var t = s
        .replaceAll('\u2019', "'")
        .replaceAll('\u2018', "'")
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    t = t.replaceAll(RegExp(r'[.!?…]+$'), '').trim();
    return t;
  }

  static String _key(String text, String from, String to) =>
      '$from>$to|${_norm(text)}';

  static void put(String text, String from, String to, String tr) {
    if (text.trim().isEmpty || tr.trim().isEmpty) return;
    _m[_key(text, from, to)] = tr.trim();
  }

  static String? get(String text, String from, String to) {
    if (text.trim().isEmpty) return null;
    return _m[_key(text, from, to)];
  }
}
