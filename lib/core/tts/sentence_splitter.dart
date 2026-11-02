class TextChunk {
  final int start;
  final int end;
  final String text;
  const TextChunk({required this.start, required this.end, required this.text});
}

class SentenceSplitter {
  /// [boundaries]: آفست‌های شروعِ «آیتم»ها (مثلاً هر خطِ مکالمه) — مثل
  /// sentenceBoundaries در Hope تضمین می‌کند دو آیتمِ جدا، حتی اگر علامت
  /// نگارشی وسطشان نباشد/قاطی شود، هرگز در یک جمله (chunk) ادغام نشوند.
  static List<TextChunk> split(String text, {List<int>? boundaries}) {
    if (text.isEmpty) return [];

    // نقطه‌ی بین دو رقم (3.5 / 1.200) پایان جمله نیست: با یک نویسه‌ی هم‌طول جایگزین
    // می‌شود تا آفست‌ها دست‌نخورده بمانند. «…» و «؟/？/।/۔» هم پایانِ جمله حساب می‌شوند.
    final prot = text.replaceAllMapped(
        RegExp(r'(\d)\.(?=\d)'), (m) => '${m[1]}\u0001');
    final re = RegExp(r'[^.!?؟。！？…।۔]+[.!?؟。！？…।۔]*');
    var out = <TextChunk>[];

    for (final m in re.allMatches(prot)) {
      final raw = text.substring(m.start, m.end);
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;
      final start = m.start + raw.indexOf(trimmed[0]);
      _addLong(out, text, start, start + trimmed.length);
    }

    if (out.isEmpty) {
      return [TextChunk(start: 0, end: text.length, text: text)];
    }

    if (boundaries != null && boundaries.isNotEmpty) {
      final sorted = boundaries
          .where((b) => b > 0 && b < text.length)
          .toSet()
          .toList()
        ..sort();
      if (sorted.isNotEmpty) {
        final res = <TextChunk>[];
        for (final ch in out) {
          var from = ch.start;
          for (final b in sorted) {
            if (b <= from) continue;
            if (b >= ch.end) break;
            _addPiece(res, text, from, b);
            from = b;
          }
          _addPiece(res, text, from, ch.end);
        }
        out = res;
      }
    }
    return out;
  }

  static void _addPiece(List<TextChunk> res, String text, int from, int to) {
    final raw = text.substring(from, to);
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return;
    final start = from + raw.indexOf(trimmed[0]);
    _addLong(res, text, start, start + trimmed.length);
  }

  /// بیشترین طولِ یک تکه برای موتورِ صدا. جمله‌ی خیلی بلندِ بدون نقطه (مثلاً متنِ
  /// ساخته‌شده با هوش مصنوعی) در موتورِ گوشی/آنلاین گاهی کلاً خوانده نمی‌شد؛ این‌جا
  /// ترجیحاً سرِ ویرگول/نقطه‌ویرگول/دونقطه و وگرنه سرِ فاصله شکسته می‌شود.
  static const int _maxChunk = 220;
  static const int _minCut = 90;

  static void _addLong(List<TextChunk> res, String text, int start, int end) {
    var from = start;
    while (end - from > _maxChunk + 30) {
      final limit = from + _maxChunk;
      var cut = -1;
      for (var i = limit; i >= from + _minCut; i--) {
        final ch = text[i - 1];
        if (ch == ',' || ch == ';' || ch == ':' || ch == '،' || ch == '؛') {
          cut = i;
          break;
        }
      }
      if (cut < 0) {
        for (var i = limit; i >= from + _minCut; i--) {
          if (text[i - 1] == ' ' || text[i - 1] == '\n') {
            cut = i;
            break;
          }
        }
      }
      if (cut < 0) cut = limit;
      final raw = text.substring(from, cut);
      final trimmed = raw.trim();
      if (trimmed.isNotEmpty) {
        final st = from + raw.indexOf(trimmed[0]);
        res.add(TextChunk(start: st, end: st + trimmed.length, text: trimmed));
      }
      from = cut;
    }
    final raw = text.substring(from, end);
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return;
    final st = from + raw.indexOf(trimmed[0]);
    res.add(TextChunk(start: st, end: st + trimmed.length, text: trimmed));
  }

  /// متن رو برای TTS تمیز می‌کنه
  static String sanitize(String s) {
    return s
        .replaceAll(RegExp(r'\bhttps?:\/\/\S+', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'[\u2066-\u2069\u200B-\u200F\u061C\uFEFF]'), '')
        .replaceAll(RegExp(r'[\p{Extended_Pictographic}]', unicode: true), '')
        .replaceAll(RegExp(r'[«»‹›„‟""]'), '')
        .replaceAll(RegExp(r'[*_~`]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
