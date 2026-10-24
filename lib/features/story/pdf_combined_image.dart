// یک عکسِ واحد از «عکسِ اصلیِ صفحه + عکسِ ترجمه‌شده + متنِ استخراج‌شده و ترجمه‌اش (زیرِ عکس‌ها)».
// برای دکمه‌ی «ذخیره» در نمایشگرِ PDF: همه با هم در یک فایل ذخیره می‌شوند، نه جداجدا.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

Future<Uint8List> buildCombinedPageImage({
  required Uint8List orig,
  Uint8List? trans,
  required List<String> paragraphs,
  required List<String> translations,
  required bool srcRtl,
  required bool dstRtl,
  TextStyle? baseStyle,
}) async {
  Future<ui.Image> decode(Uint8List b) async {
    final c = await ui.instantiateImageCodec(b);
    final f = await c.getNextFrame();
    c.dispose();
    return f.image;
  }

  final io = await decode(orig);
  final it = trans == null ? null : await decode(trans);
  final W = io.width;
  final double ho = io.height.toDouble();
  final double ht = it == null ? 0 : it.height * (W / it.width);

  const gap = 28.0;
  const maxH = 14000.0;
  final padX = W * 0.06;
  final textW = W - 2 * padX;
  final fs = (W * 0.027).clamp(22.0, 40.0).toDouble();

  // متن‌ها: اصلی (تیره) و زیرش ترجمه (سبز)
  final tps = <TextPainter>[];
  final gapsAfter = <double>[];
  var y = gap + ho + gap + (it != null ? ht + gap : 0) + gap;
  TextPainter mk(String t, Color color, bool rtl) => TextPainter(
        text: TextSpan(
          text: t,
          style: (baseStyle ?? const TextStyle())
              .copyWith(color: color, fontSize: fs, height: 1.55),
        ),
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        textAlign: rtl ? TextAlign.right : TextAlign.left,
      )..layout(minWidth: textW, maxWidth: textW);
  for (var k = 0; k < paragraphs.length; k++) {
    final p = paragraphs[k].trim();
    if (p.isEmpty) continue;
    final a = mk(p, const Color(0xFF1A1A1A), srcRtl);
    final tr = k < translations.length ? translations[k].trim() : '';
    final b = tr.isEmpty ? null : mk(tr, const Color(0xFF0B5D3A), dstRtl);
    final need = a.height + (b?.height ?? 0) + fs * 1.1;
    if (y + need > maxH) {
      a.dispose();
      b?.dispose();
      break;
    }
    tps.add(a);
    gapsAfter.add(b == null ? fs * 0.9 : 4);
    y += a.height + (b == null ? fs * 0.9 : 4);
    if (b != null) {
      tps.add(b);
      gapsAfter.add(fs * 0.9);
      y += b.height + fs * 0.9;
    }
  }
  final H = (y + gap).ceil();

  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec, ui.Rect.fromLTWH(0, 0, W.toDouble(), H.toDouble()));
  canvas.drawRect(ui.Rect.fromLTWH(0, 0, W.toDouble(), H.toDouble()),
      ui.Paint()..color = const Color(0xFFFFFFFF));
  var cy = gap;
  canvas.drawImage(io, ui.Offset(0, cy), ui.Paint());
  cy += ho + gap;
  if (it != null) {
    canvas.drawImageRect(
      it,
      ui.Rect.fromLTWH(0, 0, it.width.toDouble(), it.height.toDouble()),
      ui.Rect.fromLTWH(0, cy, W.toDouble(), ht),
      ui.Paint()..filterQuality = FilterQuality.medium,
    );
    cy += ht + gap;
  }
  canvas.drawRect(ui.Rect.fromLTWH(padX, cy, textW, math.max(1.5, W / 700)),
      ui.Paint()..color = const Color(0xFFD4A62A));
  cy += gap;
  for (var i = 0; i < tps.length; i++) {
    tps[i].paint(canvas, ui.Offset(padX, cy));
    cy += tps[i].height + gapsAfter[i];
    tps[i].dispose();
  }

  final pic = rec.endRecording();
  final out = await pic.toImage(W, H);
  final png = await out.toByteData(format: ui.ImageByteFormat.png);
  io.dispose();
  it?.dispose();
  out.dispose();
  if (png == null) return orig;
  return png.buffer.asUint8List();
}
