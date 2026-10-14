class TextChunk {
  final int start;
  final int end;
  final String text;
  const TextChunk({required this.start, required this.end, required this.text});
}

class SentenceSplitter {
  static List<TextChunk> split(String text) {
    if (text.isEmpty) return [];

    final re = RegExp(r'[^.!?؟。！]+[.!?؟。！]*');
    final out = <TextChunk>[];

    for (final m in re.allMatches(text)) {
      final raw = m.group(0)!;
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;
      final start = m.start + raw.indexOf(trimmed[0]);
      out.add(TextChunk(
        start: start,
        end: start + trimmed.length,
        text: trimmed,
      ));
    }

    if (out.isEmpty) {
      return [TextChunk(start: 0, end: text.length, text: text)];
    }
    return out;
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
