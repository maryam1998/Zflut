import 'dart:typed_data';

/// نسخه‌ی غیر-وب (فعلاً فقط وب پشتیبانی می‌شود).
class PickedFile {
  final String name;
  final Uint8List bytes;
  const PickedFile(this.name, this.bytes);
  int get size => bytes.length;
}

Future<List<PickedFile>> pickFiles({
  required String accept,
  bool multiple = false,
}) async =>
    throw UnsupportedError('web only');

/// OCR یک عکس (tesseract.js)
Future<String> ocrImage(Uint8List bytes, String langCode) async =>
    throw UnsupportedError('web only');

/// سندِ PDF (pdf.js)
class PdfDocHandle {
  int get pageCount => 0;

  static Future<PdfDocHandle> open(Uint8List bytes) async =>
      throw UnsupportedError('web only');

  Future<String> pageText(int pageIndex) async =>
      throw UnsupportedError('web only');

  Future<Uint8List> renderPage(int pageIndex, {double scale = 1.6}) async =>
      throw UnsupportedError('web only');

  void dispose() {}
}
