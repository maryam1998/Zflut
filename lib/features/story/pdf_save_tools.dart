// ذخیره‌ی عکسِ صفحه (PNG) و ساختنِ فایلِ PDF از عکسِ صفحه‌ها در نمایشگرِ PDFِ داستان‌ساز.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

/// ذخیره‌ی بایت‌ها با پنجره‌ی «ذخیره» سیستم. true = ذخیره شد، false = کاربر لغو کرد.
Future<bool> saveBytesToDevice({
  required String fileName,
  required Uint8List bytes,
  required String ext,
}) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'ذخیره',
    fileName: fileName,
    bytes: bytes,
    type: FileType.custom,
    allowedExtensions: [ext],
  );
  // روی وب مسیر برنمی‌گردد؛ روی موبایل null یعنی لغو
  return path != null || kIsWeb;
}

/// از لیستِ عکس‌ها (PNG/JPEG) یک PDF می‌سازد؛ اندازه‌ی هر صفحه = اندازه‌ی همان عکس.
Future<Uint8List> imagesToPdf(List<Uint8List> images,
    {double pxPerPoint = 2.0}) async {
  final doc = sf.PdfDocument();
  doc.pageSettings.margins.all = 0;
  for (final img in images) {
    final codec = await ui.instantiateImageCodec(img);
    final fr = await codec.getNextFrame();
    final w = fr.image.width / pxPerPoint;
    final h = fr.image.height / pxPerPoint;
    fr.image.dispose();
    codec.dispose();
    doc.pageSettings.size = ui.Size(w, h);
    final page = doc.pages.add();
    page.graphics.drawImage(sf.PdfBitmap(img), ui.Rect.fromLTWH(0, 0, w, h));
  }
  final out = await doc.save();
  doc.dispose();
  return Uint8List.fromList(out);
}
