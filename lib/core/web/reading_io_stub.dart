// پیاده‌سازیِ اندروید / iOS / دسکتاپ برای انتخابِ فایل، PDF و OCR
// (نسخه‌ی وب در reading_io_web.dart است؛ انتخابِ بینِ این دو با import مشروط انجام می‌شود).
//
//   • انتخابِ فایل : file_picker
//   • متنِ PDF     : syncfusion_flutter_pdf
//   • عکسِ صفحه    : pdfx
//   • OCR عکس     : google_mlkit_text_recognition (روی خودِ گوشی، بدونِ اینترنت)
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import 'ocr_block.dart';

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

  // ───── بلوک‌های متن + مختصاتشون (برای ترجمه‌ی عکسیِ صفحه) ─────
  static String _unescapeHtml(String t) => t
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'");

  static bool _hasLetters(String t) =>
      RegExp(r'\p{L}', unicode: true).allMatches(t).length >= 2;

  /// فقط خطِ‌های hOCR (Tesseract) رو با مختصاتشون درمیاره
  List<OcrBlock> _parseHocr(String hocr, int W, int H) {
    final re = RegExp(
        r"""<span[^>]*class=['"]ocr_(?:line|caption|textfloat|header)['"][^>]*title=['"]bbox (\d+) (\d+) (\d+) (\d+)""");
    final ms = re.allMatches(hocr).toList();
    final out = <OcrBlock>[];
    for (var i = 0; i < ms.length; i++) {
      final m = ms[i];
      final end = i + 1 < ms.length ? ms[i + 1].start : hocr.length;
      final seg = hocr.substring(m.end, end);
      final text = _unescapeHtml(seg
              .replaceFirst(RegExp(r'^[^>]*>'), '')
              .replaceAll(RegExp(r'<[^>]*>'), ' '))
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (!_hasLetters(text)) continue;
      final x0 = int.parse(m.group(1)!), y0 = int.parse(m.group(2)!);
      final x1 = int.parse(m.group(3)!), y1 = int.parse(m.group(4)!);
      if (x1 <= x0 || y1 <= y0) continue;
      out.add(OcrBlock(text, x0 / W, y0 / H, (x1 - x0) / W, (y1 - y0) / H));
    }
    return out;
  }

  Future<List<OcrBlock>> recognizeBlocks(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final fr = await codec.getNextFrame();
    final W = fr.image.width, H = fr.image.height;
    fr.image.dispose();
    final dir = await getTemporaryDirectory();
    final f = File(
        '${dir.path}/ocrb_${DateTime.now().microsecondsSinceEpoch}.jpg');
    await f.writeAsBytes(bytes, flush: true);
    try {
      final tess = _tessCodes[_lang];
      if (tess != null) {
        await _ensureTessData(tess);
        final hocr = await FlutterTesseractOcr.extractHocr(
          f.path,
          language: '$tess+eng',
          args: {'psm': '3', 'preserve_interword_spaces': '1'},
        );
        final blocks = _parseHocr(hocr, W, H);
        if (blocks.isNotEmpty) return blocks;
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
          final out = <OcrBlock>[];
          for (final b in r.blocks) {
            final t = _clean(b.text);
            if (!_hasLetters(t)) continue;
            final rc = b.boundingBox;
            out.add(OcrBlock(t, rc.left / W, rc.top / H, rc.width / W,
                rc.height / H));
          }
          if (out.isNotEmpty) return out;
        } catch (e) {
          lastErr = e;
        }
      }
      if (_unsupportedLang) throw UnsupportedError('ocr-script:$_lang');
      if (lastErr != null && lastErr is! UnsupportedError) {
        // ignore: only_throw_errors
        throw lastErr;
      }
      return const [];
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

/// سندِ PDF: متن با Syncfusion (در یک isolateِ جدا)، عکسِ صفحه با pdfx.
///
/// باز کردنِ یک PDFِ ۴۰۰ صفحه‌ای با Syncfusion روی ترد اصلی چند ثانیه UI را قفل
/// می‌کرد (ANR). حالا تجزیه‌ی PDF و استخراجِ متنِ هر صفحه کاملاً در یک isolate
/// جدا انجام می‌شود و UI روان می‌ماند.
class PdfDocHandle {
  final _PdfTextWorker _text;
  final pdfx.PdfDocument _img;
  PdfDocHandle._(this._text, this._img);

  int get pageCount => _img.pagesCount;

  static Future<PdfDocHandle> open(Uint8List bytes) async {
    final i = await pdfx.PdfDocument.openData(bytes);
    try {
      final t = await _PdfTextWorker.spawn(bytes);
      return PdfDocHandle._(t, i);
    } catch (e) {
      await i.close();
      rethrow;
    }
  }

  Future<String> pageText(int pageIndex) => _text.pageText(pageIndex);

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

/// خط‌شکستن‌های وسطِ جمله حذف می‌شن (هر کلمه خطِ جدا نشه)؛
/// خط خالی = پاراگراف می‌مونه. خط‌تیره‌ی آخرِ سطر هم به کلمه وصل می‌شه.
String _normalizePdfText(String raw) {
  var t = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  t = t.replaceAll(RegExp(r'[\u00A0\t ]+'), ' ');
  t = t.replaceAllMapped(
      RegExp(r'(\p{L})-\n(\p{Ll})', unicode: true), (m) => '${m[1]}${m[2]}');
  t = t.replaceAll(RegExp(r'\n[ ]*\n+'), '\u0002');
  t = t.replaceAll(RegExp(r'[ ]*\n[ ]*'), ' ');
  t = t.replaceAll('\u0002', '\n\n');
  return t.replaceAll(RegExp(r' {2,}'), ' ').trim();
}

/// isolateِ دائمی که PDF را یک‌بار باز می‌کند و متنِ صفحه‌ها را بر حسبِ درخواست می‌دهد.
class _PdfTextWorker {
  final Isolate _isolate;
  final SendPort _cmd;
  final ReceivePort _resp;
  final Completer<String?> _openAck = Completer<String?>();
  final Map<int, Completer<String>> _pending = <int, Completer<String>>{};
  int _nextId = 0;
  bool _closed = false;

  _PdfTextWorker._(this._isolate, this._cmd, this._resp) {
    _resp.listen((dynamic m) {
      if (m is! List || m.isEmpty) return;
      if (m[0] == 'opened') {
        if (!_openAck.isCompleted) {
          _openAck.complete(m.length > 1 && m[1] != null ? m[1].toString() : null);
        }
        return;
      }
      if (m.length == 3 && m[0] is int) {
        final c = _pending.remove(m[0] as int);
        if (c == null || c.isCompleted) return;
        c.complete((m[1] ?? '').toString());
      }
    });
  }

  static Future<_PdfTextWorker> spawn(Uint8List bytes) async {
    final ready = ReceivePort();
    final iso = await Isolate.spawn<SendPort>(_pdfTextMain, ready.sendPort);
    SendPort cmd;
    try {
      final first = await ready.first.timeout(const Duration(seconds: 20));
      cmd = first as SendPort;
    } catch (e) {
      iso.kill(priority: Isolate.immediate);
      ready.close();
      rethrow;
    }
    ready.close();
    final w = _PdfTextWorker._(iso, cmd, ReceivePort());
    cmd.send(<Object?>[
      'open',
      TransferableTypedData.fromList(<TypedData>[bytes]),
      w._resp.sendPort,
    ]);
    String? err;
    try {
      err = await w._openAck.future.timeout(const Duration(seconds: 90));
    } catch (e) {
      w.dispose();
      rethrow;
    }
    if (err != null) {
      w.dispose();
      throw StateError(err);
    }
    return w;
  }

  Future<String> pageText(int index) {
    if (_closed) return Future<String>.value('');
    final id = _nextId++;
    final c = Completer<String>();
    _pending[id] = c;
    _cmd.send(<Object?>['text', id, index]);
    return c.future.timeout(const Duration(seconds: 60), onTimeout: () {
      _pending.remove(id);
      return '';
    });
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.complete('');
    }
    _pending.clear();
    try {
      _cmd.send(<Object?>['close']);
    } catch (_) {}
    _isolate.kill(priority: Isolate.beforeNextEvent);
    _resp.close();
  }
}

/// نقطه‌ی ورودیِ isolate (باید top-level باشد).
void _pdfTextMain(SendPort ready) {
  final port = ReceivePort();
  ready.send(port.sendPort);
  sf.PdfDocument? doc;
  SendPort? reply;
  port.listen((dynamic m) {
    if (m is! List || m.isEmpty) return;
    final op = m[0];
    if (op == 'open') {
      reply = m[2] as SendPort;
      try {
        final data =
            (m[1] as TransferableTypedData).materialize().asUint8List();
        doc = sf.PdfDocument(inputBytes: data);
        reply!.send(<Object?>['opened', null]);
      } catch (e) {
        reply?.send(<Object?>['opened', e.toString()]);
      }
    } else if (op == 'text') {
      final id = m[1] as int;
      final idx = m[2] as int;
      final d = doc;
      reply?.send(<Object?>[id, d == null ? '' : _safeExtract(d, idx), null]);
    } else if (op == 'close') {
      try {
        doc?.dispose();
      } catch (_) {}
      port.close();
    }
  });
}

String _safeExtract(sf.PdfDocument d, int idx) {
  try {
    final raw = sf.PdfTextExtractor(d)
        .extractText(startPageIndex: idx, endPageIndex: idx);
    return _normalizePdfText(raw);
  } catch (_) {
    return '';
  }
}

/// فایل‌های موقتِ OCR که از اجراهای قبلی (کرش/ANR) مانده‌اند پاک می‌شوند.
Future<void> cleanOcrTemp() async {
  try {
    final tmp = await getTemporaryDirectory();
    final cutoff = DateTime.now().subtract(const Duration(minutes: 30));
    await for (final e in tmp.list(followLinks: false)) {
      if (e is! File) continue;
      final n = e.path.split(Platform.pathSeparator).last;
      if (!(n.startsWith('ocr_') || n.startsWith('ocrb_'))) continue;
      try {
        final st = await e.stat();
        if (st.modified.isBefore(cutoff)) await e.delete();
      } catch (_) {}
    }
  } catch (_) {}
}
