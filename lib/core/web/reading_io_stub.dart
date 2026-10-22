// پیاده‌سازیِ اندروید / iOS / دسکتاپ برای انتخابِ فایل، PDF و OCR
// (نسخه‌ی وب در reading_io_web.dart است؛ انتخابِ بینِ این دو با import مشروط انجام می‌شود).
//
//   • انتخابِ فایل : file_picker
//   • متنِ PDF     : syncfusion_flutter_pdf
//   • عکسِ صفحه    : pdfx
//   • OCR عکس     : google_mlkit_text_recognition (روی خودِ گوشی، بدونِ اینترنت)
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

class PickedFile {
  final String name;
  final Uint8List bytes;
  const PickedFile(this.name, this.bytes);
  int get size => bytes.length;
}

/// [accept] همان رشته‌های `accept` در وب: `application/pdf` ، `image/*` ، `audio/*`
Future<List<PickedFile>> pickFiles({
  required String accept,
  bool multiple = false,
}) async {
  FileType type = FileType.any;
  List<String>? exts;
  if (accept.contains('pdf')) {
    type = FileType.custom;
    exts = const ['pdf'];
  } else if (accept.startsWith('image')) {
    type = FileType.image;
  } else if (accept.startsWith('audio')) {
    type = FileType.audio;
  } else if (accept.contains('.srt')) {
    type = FileType.any; // بعضی گوشی‌ها پسوندِ srt را نمی‌شناسند
  }
  final res = await FilePicker.platform.pickFiles(
    type: type,
    allowedExtensions: exts,
    allowMultiple: multiple,
    withData: true,
  );
  if (res == null) return const [];
  final out = <PickedFile>[];
  for (final f in res.files) {
    Uint8List? b = f.bytes;
    if (b == null && f.path != null) b = await File(f.path!).readAsBytes();
    if (b != null) out.add(PickedFile(f.name, b));
  }
  return out;
}

/// نشستِ OCR با ML Kit. ML Kit فقط این خط‌ها را می‌خواند:
/// لاتین (انگلیسی/آلمانی/اسپانیایی/فرانسوی/…)، چینی، ژاپنی، کره‌ای، دوناگری.
/// عربی/فارسی را ML Kit پشتیبانی نمی‌کند — برایشان خطایِ واضح می‌دهیم.
/// کدِ زبان‌های بیرون از ML Kit → نامِ فایلِ Tesseract
const Map<String, String> _tessCodes = {
  'fa': 'fas',
  'ar': 'ara',
  'ur': 'urd',
  'he': 'heb',
  'ru': 'rus',
  'uk': 'ukr',
  'el': 'ell',
  'th': 'tha',
};

bool _prefetchRunning = false;

/// دانلودِ بی‌صدای فایل‌های OCR (فارسی/عربی/روسی/…) در پس‌زمینه.
/// بدونِ هیچ تنظیم و پیامی: اگر اینترنت نبود هر ۶۰ ثانیه دوباره تلاش می‌کنه تا کامل شه.
void prefetchOcrData() {
  if (_prefetchRunning) return;
  _prefetchRunning = true;
  unawaited(() async {
    try {
      for (var attempt = 0; attempt < 40; attempt++) {
        var allOk = true;
        for (final code in _tessCodes.values) {
          try {
            await _ensureTessData(code);
          } catch (_) {
            allOk = false;
            break;
          }
        }
        if (allOk) return;
        await Future<void>.delayed(const Duration(seconds: 60));
      }
    } finally {
      _prefetchRunning = false;
    }
  }());
}

/// فایلِ زبان (حدودِ ۱ تا ۴ مگابایت) بار اول دانلود و برای همیشه نگه داشته می‌شه.
Future<void> _ensureTessData(String code) async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory('${docs.path}/tessdata');
  if (!await dir.exists()) await dir.create(recursive: true);
  for (final c in [code, 'eng']) {
    final f = File('${dir.path}/$c.traineddata');
    if (await f.exists() && await f.length() > 100000) continue;
    final tmp = File('${f.path}.part');
    await Dio().download(
      'https://github.com/tesseract-ocr/tessdata_fast/raw/main/$c.traineddata',
      tmp.path,
      options: Options(receiveTimeout: const Duration(minutes: 3)),
    );
    await tmp.rename(f.path);
  }
}

class OcrSession {
  final TextRecognitionScript _primary;
  final bool _unsupportedLang;
  final String _lang;
  final Map<TextRecognitionScript, TextRecognizer> _recs = {};
  OcrSession._(this._primary, this._unsupportedLang, this._lang);

  /// null = ML Kit این خط را ندارد (عربی/فارسی/سیریلیک/…)
  static TextRecognitionScript? _scriptFor(String lang) {
    switch (lang) {
      case 'zh':
        return TextRecognitionScript.chinese;
      case 'ja':
        return TextRecognitionScript.japanese;
      case 'ko':
        return TextRecognitionScript.korean;
      case 'hi':
      case 'mr':
      case 'ne':
        return TextRecognitionScript.devanagiri;
      case 'ar':
      case 'fa':
      case 'ur':
      case 'he':
      case 'ru':
      case 'uk':
      case 'el':
      case 'th':
        return null;
      default:
        return TextRecognitionScript.latin;
    }
  }

  /// قبلاً برای زبانِ فارسی/عربی/روسی همان اول خطا می‌داد، حتی اگر عکس
  /// انگلیسی بود. حالا همیشه با لاتین (و در صورتِ خالی بودن، با بقیه‌ی خط‌ها) می‌خونه.
  static Future<OcrSession> open(String langCode) async {
    final sc = _scriptFor(langCode);
    return OcrSession._(
        sc ?? TextRecognitionScript.latin, sc == null, langCode);
  }

  TextRecognizer _rec(TextRecognitionScript sc) =>
      _recs.putIfAbsent(sc, () => TextRecognizer(script: sc));

  static String _clean(String t) => t
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\s*\n\s*'), ' ')
      .trim();

  Future<String> recognize(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final f = File(
        '${dir.path}/ocr_${DateTime.now().microsecondsSinceEpoch}.jpg');
    await f.writeAsBytes(bytes, flush: true);
    try {
      final tess = _tessCodes[_lang];
      if (tess != null) {
        // فارسی/عربی/روسی/…: Tesseract (به‌همراهِ انگلیسی برای متنِ قاطی)
        await _ensureTessData(tess);
        final raw = await FlutterTesseractOcr.extractText(
          f.path,
          language: '$tess+eng',
          args: {'psm': '6', 'preserve_interword_spaces': '1'},
        );
        final t = _clean(raw);
        if (t.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '').length >=
            3) {
          return t;
        }
      }
      final input = InputImage.fromFilePath(f.path);
      final order = <TextRecognitionScript>[
        _primary,
        for (final s in const [
          TextRecognitionScript.latin,
          TextRecognitionScript.devanagiri,
          TextRecognitionScript.chinese,
          TextRecognitionScript.japanese,
          TextRecognitionScript.korean,
        ])
          if (s != _primary) s,
      ];
      Object? lastErr;
      for (final sc in order) {
        try {
          final r = await _rec(sc).processImage(input);
          final t = _clean(r.text);
          if (t.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '').length >=
              3) {
            return t;
          }
        } catch (e) {
          lastErr = e;
        }
      }
      if (_unsupportedLang) {
        // عکس هیچ متنِ لاتینی/چینی/… نداشت و زبانش هم از ML Kit بیرونه
        throw UnsupportedError('ocr-script:$_lang');
      }
      if (lastErr != null && lastErr is! UnsupportedError) {
        // همه‌ی تلاش‌ها خطای واقعی بودن (مثلاً مدلِ زبان دانلود نشد)
        // ignore: only_throw_errors
        throw lastErr;
      }
      return '';
    } finally {
      try {
        await f.delete();
      } catch (_) {}
    }
  }

  Future<void> close() async {
    for (final r in _recs.values) {
      try {
        await r.close();
      } catch (_) {}
    }
    _recs.clear();
  }
}

/// سندِ PDF: متن با Syncfusion، عکسِ صفحه با pdfx.
class PdfDocHandle {
  final sf.PdfDocument _text;
  final pdfx.PdfDocument _img;
  PdfDocHandle._(this._text, this._img);

  int get pageCount => _img.pagesCount;

  static Future<PdfDocHandle> open(Uint8List bytes) async {
    final t = sf.PdfDocument(inputBytes: bytes);
    final i = await pdfx.PdfDocument.openData(bytes);
    return PdfDocHandle._(t, i);
  }

  Future<String> pageText(int pageIndex) async {
    final raw = sf.PdfTextExtractor(_text)
        .extractText(startPageIndex: pageIndex, endPageIndex: pageIndex);
    return _normalizePdfText(raw);
  }

  /// خط‌شکستن‌های وسطِ جمله حذف می‌شن (هر کلمه خطِ جدا نشه)؛
  /// خط خالی = پاراگراف می‌مونه. خط‌تیره‌ی آخرِ سطر هم به کلمه وصل می‌شه.
  static String _normalizePdfText(String raw) {
    var t = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    t = t.replaceAll(RegExp(r'[\u00A0\t ]+'), ' ');
    t = t.replaceAllMapped(
        RegExp(r'(\p{L})-\n(\p{Ll})', unicode: true), (m) => '${m[1]}${m[2]}');
    t = t.replaceAll(RegExp(r'\n[ ]*\n+'), '\u0002');
    t = t.replaceAll(RegExp(r'[ ]*\n[ ]*'), ' ');
    t = t.replaceAll('\u0002', '\n\n');
    return t.replaceAll(RegExp(r' {2,}'), ' ').trim();
  }

  Future<Uint8List> renderPage(int pageIndex, {double scale = 1.6}) async {
    final page = await _img.getPage(pageIndex + 1);
    try {
      final w = page.width * scale;
      final h = page.height * scale;
      final out = await page.render(
        width: w,
        height: h,
        format: pdfx.PdfPageImageFormat.png,
        backgroundColor: '#FFFFFF',
      );
      if (out == null) throw StateError('render failed');
      return out.bytes;
    } finally {
      await page.close();
    }
  }

  void dispose() {
    try {
      _text.dispose();
    } catch (_) {}
    try {
      _img.close();
    } catch (_) {}
  }
}
