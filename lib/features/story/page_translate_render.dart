// ساختنِ «عکسِ صفحه‌ی ترجمه‌شده»: متنِ اصلیِ هر بلوک با رنگِ پس‌زمینه‌ی اطرافش
// پوشانده می‌شه و ترجمه جاش نوشته می‌شه؛ بقیه‌ی عکس (تصویرها، نقاشی‌ها، رنگ‌ها) دست‌نخورده می‌مونه.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../core/web/ocr_block.dart';

int _median(List<int> v) {
  if (v.isEmpty) return 255;
  v.sort();
  return v[v.length ~/ 2];
}

Future<Uint8List> renderTranslatedPage({
  required Uint8List pageImage,
  required List<OcrBlock> blocks,
  required List<String> translations,
  required bool rtl,
  TextStyle? baseStyle,
}) async {
  final codec = await ui.instantiateImageCodec(pageImage);
  final frame = await codec.getNextFrame();
  final img = frame.image;
  final W = img.width, H = img.height;
  final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (bd == null) return pageImage;
  final px = bd.buffer.asUint8List();

  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec, ui.Rect.fromLTWH(0, 0, W.toDouble(), H.toDouble()));
  canvas.drawImage(img, ui.Offset.zero, ui.Paint());

  for (var k = 0; k < blocks.length && k < translations.length; k++) {
    final tr = translations[k].trim();
    if (tr.isEmpty) continue;
    final b = blocks[k];
    var x0 = (b.left * W).floor() - 2;
    var y0 = (b.top * H).floor() - 2;
    var x1 = ((b.left + b.width) * W).ceil() + 2;
    var y1 = ((b.top + b.height) * H).ceil() + 2;
    x0 = x0.clamp(0, W - 1);
    y0 = y0.clamp(0, H - 1);
    x1 = x1.clamp(x0 + 1, W);
    y1 = y1.clamp(y0 + 1, H);
    final bw = x1 - x0, bh = y1 - y0;
    if (bw < 6 || bh < 6) continue;

    // رنگِ پس‌زمینه = میانه‌ی پیکسل‌های یک حلقه‌ی باریک بیرونِ کادر
    final rs = <int>[], gs = <int>[], bs = <int>[];
    void sample(int x, int y) {
      if (x < 0 || y < 0 || x >= W || y >= H) return;
      final o = (y * W + x) * 4;
      rs.add(px[o]);
      gs.add(px[o + 1]);
      bs.add(px[o + 2]);
    }

    const ring = 3;
    for (var x = x0; x < x1; x += 2) {
      sample(x, y0 - ring);
      sample(x, y1 + ring - 1);
    }
    for (var y = y0; y < y1; y += 2) {
      sample(x0 - ring, y);
      sample(x1 + ring - 1, y);
    }
    final br = _median(rs), bgc = _median(gs), bb = _median(bs);

    // رنگِ متنِ اصلی = پیکسل‌هایی که از پس‌زمینه دورترن
    var maxD = 0;
    final step = math.max(1, math.min(bw, bh) ~/ 40);
    int dist(int o) =>
        (px[o] - br).abs() + (px[o + 1] - bgc).abs() + (px[o + 2] - bb).abs();
    for (var y = y0; y < y1; y += step) {
      for (var x = x0; x < x1; x += step) {
        final d = dist((y * W + x) * 4);
        if (d > maxD) maxD = d;
      }
    }
    Color textColor;
    final lum = (0.299 * br + 0.587 * bgc + 0.114 * bb) / 255;
    if (maxD < 90) {
      textColor = lum > 0.5 ? const Color(0xFF111111) : const Color(0xFFFFFFFF);
    } else {
      var sr = 0, sg = 0, sb = 0, n = 0;
      final thr = maxD * 0.75;
      for (var y = y0; y < y1; y += step) {
        for (var x = x0; x < x1; x += step) {
          final o = (y * W + x) * 4;
          if (dist(o) >= thr) {
            sr += px[o];
            sg += px[o + 1];
            sb += px[o + 2];
            n++;
          }
        }
      }
      textColor = n == 0
          ? (lum > 0.5 ? const Color(0xFF111111) : const Color(0xFFFFFFFF))
          : Color.fromARGB(255, sr ~/ n, sg ~/ n, sb ~/ n);
    }

    canvas.drawRect(
      ui.Rect.fromLTRB(x0.toDouble(), y0.toDouble(), x1.toDouble(), y1.toDouble()),
      ui.Paint()..color = Color.fromARGB(255, br, bgc, bb),
    );

    // بزرگ‌ترین اندازه‌ی فونتی که ترجمه توی همین کادر جا بشه
    // تیترها/خطِ تکی می‌تونن بزرگ باشن؛ پاراگراف‌های بلند سقفِ کوچک‌تری دارن
    var size = math.min(bh.toDouble() * 0.9, bh < 160 ? 110.0 : 44.0);
    TextPainter? tp;
    while (true) {
      tp = TextPainter(
        text: TextSpan(
          text: tr,
          style: (baseStyle ?? const TextStyle()).copyWith(
            color: textColor,
            fontSize: size,
            height: 1.15,
          ),
        ),
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        textAlign: rtl ? TextAlign.right : TextAlign.left,
      )..layout(minWidth: bw.toDouble(), maxWidth: bw.toDouble());
      if (tp.height <= bh * 1.04 || size <= 7) break;
      size = size * 0.92;
    }
    canvas.save();
    canvas.clipRect(ui.Rect.fromLTWH(
        x0.toDouble(), y0.toDouble(), bw.toDouble(), bh.toDouble() + 6));
    final dy = y0.toDouble() + math.max(0.0, (bh - tp.height) / 2);
    tp.paint(canvas, ui.Offset(x0.toDouble(), dy));
    canvas.restore();
    tp.dispose();
  }

  final pic = rec.endRecording();
  final out = await pic.toImage(W, H);
  final png = await out.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  out.dispose();
  return png == null ? pageImage : png.buffer.asUint8List();
}
