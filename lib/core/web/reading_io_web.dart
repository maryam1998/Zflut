// پیاده‌سازیِ وب: انتخابِ فایل، خواندن/رندرِ PDF با pdf.js و OCR با tesseract.js
// (اسکریپت‌ها اولین بار که لازم شدند از CDN بارگذاری می‌شوند).
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_util' as jsu;
import 'dart:typed_data';

class PickedFile {
  final String name;
  final Uint8List bytes;
  const PickedFile(this.name, this.bytes);
  int get size => bytes.length;
}

const String _pdfJsUrl =
    'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js';
const String _pdfWorkerUrl =
    'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js';
const String _tesseractUrl =
    'https://cdn.jsdelivr.net/npm/tesseract.js@5.1.1/dist/tesseract.min.js';

final Map<String, Future<void>> _scriptLoads = {};

Future<void> _loadScript(String url, String globalName) {
  if (jsu.hasProperty(html.window, globalName)) return Future.value();
  return _scriptLoads.putIfAbsent(url, () {
    final c = Completer<void>();
    final s = html.ScriptElement()
      ..src = url
      ..async = true;
    s.onLoad.first.then((_) => c.complete());
    s.onError.first.then((_) {
      _scriptLoads.remove(url);
      c.completeError(StateError('script load failed: $url'));
    });
    html.document.head!.append(s);
    return c.future;
  });
}

Future<List<PickedFile>> pickFiles({
  required String accept,
  bool multiple = false,
}) {
  final c = Completer<List<PickedFile>>();
  final input = html.FileUploadInputElement()
    ..accept = accept
    ..multiple = multiple;
  input.onChange.first.then((_) async {
    final out = <PickedFile>[];
    try {
      for (final f in input.files ?? <html.File>[]) {
        final r = html.FileReader();
        r.readAsArrayBuffer(f);
        await r.onLoadEnd.first;
        final res = r.result;
        final bytes = res is Uint8List
            ? res
            : Uint8List.view(res as ByteBuffer);
        out.add(PickedFile(f.name, bytes));
      }
      if (!c.isCompleted) c.complete(out);
    } catch (e) {
      if (!c.isCompleted) c.completeError(e);
    }
  });
  input.addEventListener('cancel', (_) {
    if (!c.isCompleted) c.complete(const []);
  });
  input.click();
  return c.future;
}

// ───────────────────────── OCR ─────────────────────────
const Map<String, String> _tessLang = {
  'en': 'eng',
  'es': 'spa',
  'de': 'deu',
  'fr': 'fra',
  'fa': 'fas',
  'it': 'ita',
  'ar': 'ara',
  'tr': 'tur',
  'ru': 'rus',
  'hi': 'hin',
  'zh': 'chi_sim',
  'ja': 'jpn',
  'ko': 'kor',
};

Future<String> ocrImage(Uint8List bytes, String langCode) async {
  await _loadScript(_tesseractUrl, 'Tesseract');
  final tess = jsu.getProperty(html.window, 'Tesseract');
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  try {
    final promise = jsu.callMethod(
        tess, 'recognize', [url, _tessLang[langCode] ?? 'eng']);
    final res = await jsu.promiseToFuture(promise);
    final data = jsu.getProperty(res, 'data');
    return (jsu.getProperty(data, 'text') ?? '').toString();
  } finally {
    html.Url.revokeObjectUrl(url);
  }
}

// ───────────────────────── PDF ─────────────────────────
class PdfDocHandle {
  final dynamic _doc;
  final int pageCount;
  PdfDocHandle._(this._doc, this.pageCount);

  static Future<PdfDocHandle> open(Uint8List bytes) async {
    await _loadScript(_pdfJsUrl, 'pdfjsLib');
    final lib = jsu.getProperty(html.window, 'pdfjsLib');
    jsu.setProperty(
        jsu.getProperty(lib, 'GlobalWorkerOptions'), 'workerSrc', _pdfWorkerUrl);
    final params = jsu.newObject();
    jsu.setProperty(params, 'data', bytes);
    final task = jsu.callMethod(lib, 'getDocument', [params]);
    final doc = await jsu.promiseToFuture(jsu.getProperty(task, 'promise'));
    final n = (jsu.getProperty(doc, 'numPages') as num).toInt();
    return PdfDocHandle._(doc, n);
  }

  Future<dynamic> _page(int i) =>
      jsu.promiseToFuture(jsu.callMethod(_doc, 'getPage', [i + 1]));

  Future<String> pageText(int pageIndex) async {
    final page = await _page(pageIndex);
    final content =
        await jsu.promiseToFuture(jsu.callMethod(page, 'getTextContent', []));
    final items = jsu.getProperty(content, 'items') as List;
    final sb = StringBuffer();
    for (final it in items) {
      sb.write((jsu.getProperty(it, 'str') ?? '').toString());
      final eol = jsu.getProperty(it, 'hasEOL') == true;
      sb.write(eol ? '\n' : ' ');
    }
    return sb
        .toString()
        .replaceAll(RegExp(r'-[ \t]*\n[ \t]*'), '')
        .replaceAll(RegExp(r'\s*\n\s*'), ' ')
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .trim();
  }

  Future<Uint8List> renderPage(int pageIndex, {double scale = 1.6}) async {
    final page = await _page(pageIndex);
    final vpParams = jsu.newObject();
    jsu.setProperty(vpParams, 'scale', scale);
    final viewport = jsu.callMethod(page, 'getViewport', [vpParams]);
    final w = (jsu.getProperty(viewport, 'width') as num).ceil();
    final h = (jsu.getProperty(viewport, 'height') as num).ceil();
    final canvas = html.CanvasElement(width: w, height: h);
    final rp = jsu.newObject();
    jsu.setProperty(rp, 'canvasContext', canvas.context2D);
    jsu.setProperty(rp, 'viewport', viewport);
    final task = jsu.callMethod(page, 'render', [rp]);
    await jsu.promiseToFuture(jsu.getProperty(task, 'promise'));
    final dataUrl = canvas.toDataUrl('image/jpeg', 0.88);
    return base64Decode(dataUrl.substring(dataUrl.indexOf(',') + 1));
  }

  void dispose() {
    try {
      jsu.callMethod(_doc, 'destroy', []);
    } catch (_) {}
  }
}
