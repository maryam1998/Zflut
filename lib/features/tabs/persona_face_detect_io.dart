import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path_provider/path_provider.dart';

// ═══════════════════════════════════════════════════════════════════
// عکسِ گالریِ کاربر → «چهره‌ی سخنگو» مثلِ Ryan
//
//   ۱) عکسِ اصلی (بدونِ برش و بدونِ تغییرِ پس‌زمینه) با عرضِ حداکثر ۱۰۸۰ پیکسل به‌صورتِ PNG
//      در پوشه‌ی اسنادِ برنامه ذخیره می‌شود (persona_photos/)
//   ۲) ML Kit روی همان فایل خطِ لب‌ها و چانه را پیدا می‌کند (آفلاین)
//   ۳) از آن‌ها مختصاتِ دهان در قالبِ PhotoFaceSpec ساخته می‌شود؛ همان موتورِ حرکتِ لبِ Ryan
//      (PhotoTalkingFace) روی عکسِ کاربر اجرا می‌شود
// ═══════════════════════════════════════════════════════════════════

Future<Directory> _dir() async {
  final base = await getApplicationDocumentsDirectory();
  final d = Directory('${base.path}/persona_photos');
  if (!await d.exists()) await d.create(recursive: true);
  return d;
}

/// خروجی: نامِ فایلِ ذخیره‌شده + مختصاتِ دهان (کلیدها در PhotoFaceSpec.fromMap).
/// اگر چهره/لب پیدا نشد null (و فایل پاک می‌شود).
Future<({String file, Map<String, double> face})?> detectPersonaFace(
    Uint8List original) async {
  File? out;
  FaceDetector? detector;
  try {
    // عرضِ حداکثر ۱۰۸۰ (بزرگ‌تر نمی‌شود). EXIF را خودِ کدکِ Flutter اعمال می‌کند، پس همان چیزی
    // ذخیره می‌شود که در پیش‌نمایشِ برش دیده شد و ML Kit هم روی همان فایل (بدونِ EXIF) کار می‌کند.
    final codec = await ui.instantiateImageCodec(original,
        targetWidth: 1080, allowUpscaling: false);
    final frame = await codec.getNextFrame();
    final im = frame.image;
    final w = im.width.toDouble(), h = im.height.toDouble();
    final bd = await im.toByteData(format: ui.ImageByteFormat.png);
    im.dispose();
    codec.dispose();
    if (bd == null) return null;

    final dir = await _dir();
    final name = 'f${DateTime.now().millisecondsSinceEpoch}.png';
    out = File('${dir.path}/$name');
    await out.writeAsBytes(bd.buffer.asUint8List(), flush: true);

    detector = FaceDetector(
      options: FaceDetectorOptions(
        enableContours: true,
        performanceMode: FaceDetectorMode.accurate,
        minFaceSize: 0.1,
      ),
    );
    final faces = await detector.processImage(InputImage.fromFilePath(out.path));
    if (faces.isEmpty) {
      await _safeDelete(out);
      return null;
    }
    // بزرگ‌ترین چهره
    faces.sort((a, b) => (b.boundingBox.width * b.boundingBox.height)
        .compareTo(a.boundingBox.width * a.boundingBox.height));
    final face = faces.first;

    List<math.Point<int>> pts(FaceContourType t) =>
        face.contours[t]?.points ?? const <math.Point<int>>[];
    final up = pts(FaceContourType.upperLipTop);
    final ub = pts(FaceContourType.upperLipBottom);
    final lt = pts(FaceContourType.lowerLipTop);
    final lb = pts(FaceContourType.lowerLipBottom);
    if (up.isEmpty || ub.isEmpty || lt.isEmpty || lb.isEmpty) {
      await _safeDelete(out);
      return null;
    }
    final all = [...up, ...ub, ...lt, ...lb];

    var minX = all.first.x.toDouble(), maxX = minX;
    var left = all.first, right = all.first;
    var topY = all.first.y.toDouble();
    for (final p in all) {
      if (p.x < left.x) left = p;
      if (p.x > right.x) right = p;
      minX = math.min(minX, p.x.toDouble());
      maxX = math.max(maxX, p.x.toDouble());
      topY = math.min(topY, p.y.toDouble());
    }
    final hw = (maxX - minX) / 2;
    if (hw < 8) {
      await _safeDelete(out);
      return null; // دهان آن‌قدر کوچک است که حرکتش دیده نمی‌شود
    }
    final mouthX = (minX + maxX) / 2;
    final cornerY = (left.y + right.y) / 2;

    double centralMeanY(List<math.Point<int>> l) {
      final c = l.where((p) => (p.x - mouthX).abs() <= 0.35 * hw).toList();
      final src = c.isEmpty ? l : c;
      return src.fold<double>(0, (s, p) => s + p.y) / src.length;
    }

    final yU = centralMeanY(ub); // لبِ پایینیِ لبِ بالا
    final yL = centralMeanY(lt); // لبِ بالاییِ لبِ پایین
    final gap = yL - yU;
    final open = gap > 0.15 * hw; // دهان در عکسِ اصلی باز است
    var seamY = open ? yU : (yU + yL) / 2;
    seamY = seamY.clamp(cornerY - 0.25 * hw, cornerY + 0.9 * hw).toDouble();

    // چانه (پایین‌ترین نقطه‌ی کانتورِ صورت)
    double? chinY;
    for (final p in pts(FaceContourType.face)) {
      chinY = chinY == null ? p.y.toDouble() : math.max(chinY, p.y.toDouble());
    }
    var pBottom = seamY + 1.4 * hw;
    if (chinY != null) pBottom = math.min(pBottom, chinY + 0.10 * hw);
    pBottom = math.max(pBottom, seamY + 0.8 * hw);
    pBottom = math.min(pBottom, h - 1);

    final pLeft = math.max(0.0, mouthX - 1.55 * hw);
    final pRight = math.min(w, mouthX + 1.55 * hw);
    final pTop = math.max(0.0, topY - 0.12 * hw);

    // نقطه‌ی مرکزِ قاب = پلِ بینی
    final nose = pts(FaceContourType.noseBridge);
    final bb = face.boundingBox;
    final fx = nose.isEmpty
        ? bb.center.dx
        : nose.fold<double>(0, (s, p) => s + p.x) / nose.length;
    final fy = nose.isEmpty
        ? bb.top + bb.height * 0.5
        : nose.fold<double>(0, (s, p) => s + p.y) / nose.length;

    // صورتِ کوچک کمی بزرگ‌نمایی می‌شود (حداکثر ۱.۳۵ تا پس‌زمینه زیاد عوض نشود)
    final ratio = bb.width / math.min(w, h);
    final zoom = ratio >= 0.45 ? 1.045 : (0.45 / ratio).clamp(1.045, 1.35);

    return (
      file: name,
      face: <String, double>{
        'w': w,
        'h': h,
        'mx': mouthX,
        'mhw': hw,
        'cy': cornerY,
        'sy': seamY,
        'pl': pLeft,
        'pr': pRight,
        'pt': pTop,
        'pb': pBottom,
        'mo': (open ? 0.21 : 0.30) * hw,
        'fx': fx,
        'fy': fy,
        'z': zoom.toDouble(),
      },
    );
  } catch (_) {
    if (out != null) await _safeDelete(out);
    return null;
  } finally {
    try {
      await detector?.close();
    } catch (_) {}
  }
}

Future<void> _safeDelete(File f) async {
  try {
    if (await f.exists()) await f.delete();
  } catch (_) {}
}

Future<Uint8List?> loadPersonaPhotoBytes(String file) async {
  try {
    final f = File('${(await _dir()).path}/$file');
    if (!await f.exists()) return null;
    return await f.readAsBytes();
  } catch (_) {
    return null;
  }
}

Future<void> deletePersonaPhoto(String file) async {
  if (file.isEmpty) return;
  try {
    await _safeDelete(File('${(await _dir()).path}/$file'));
  } catch (_) {}
}
