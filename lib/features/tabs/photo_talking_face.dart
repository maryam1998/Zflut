import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

// ═══════════════════════════════════════════════════════════════════
// چهره‌ی عکس‌دارِ سخنگو برای «ویدیو کال»
//
// یک عکسِ واقعی (مثلاً شخصیتِ ساخته‌شده با هوش مصنوعی) تمام‌قاب نشان داده می‌شود و
// موقعِ حرف‌زدن «فکِ پایین» عکس با یک مشِ نرم پایین می‌آید؛ داخلِ دهان پیدا می‌شود
// و لب‌ها باز و بسته می‌شوند. حرکتِ لب دقیقاً با صدا هم‌زمان (lip-sync) نیست، ولی
// واضح و طبیعی دیده می‌شود. به‌علاوه سر کمی تکان می‌خورد و نفس می‌کشد.
//
// برای اضافه کردنِ شخصیتِ عکس‌دارِ جدید:
//   ۱) عکس را در assets/personas/ بگذار (چهره‌ی روبه‌رو، لبخندِ دندان‌دار بهتر است)
//   ۲) یک PhotoFaceSpec با مختصاتِ دهانِ همان عکس (به پیکسل) بساز و در kPhotoFaces بگذار
//   ۳) در AiPersona مقدارِ asset را برابرِ مسیرِ عکس بده
// ═══════════════════════════════════════════════════════════════════

/// مشخصاتِ یک عکس. همه‌ی مختصات به پیکسلِ «اندازه‌ی مرجع» (refW × refH) هستند
/// و اگر عکس بعداً کوچک/بزرگ شود خودکار مقیاس می‌گیرند.
class PhotoFaceSpec {
  /// عکسِ اصلیِ تمام‌قاب
  final String asset;

  /// برشِ مربعیِ صورت برای آواتارهای کوچک (لیستِ شخصیت‌ها و …)
  final String avatar;
  final double refW, refH;

  /// مرکزِ دهان (x)، نصفِ عرضِ دهان، y گوشه‌ی لب‌ها، y خطِ لبِ بالا/پایین در وسطِ دهان
  /// (جایی که فک از آن‌جا «بریده» می‌شود: لبه‌ی پایینِ دندان‌های بالا)
  final double mouthX, mouthHalfW, cornerY, seamY;

  /// مستطیلِ ناحیه‌ای که مش روی آن کار می‌کند (دهان + چانه)
  final double patchLeft, patchRight, patchTop, patchBottom;

  /// بیشترین بازشدگیِ دهان (پیکسلِ مرجع)
  final double maxOpen;

  /// نقطه‌ای از عکس که باید وسطِ قاب بیفتد (حوالیِ بینی) و جای آن در ارتفاعِ قاب (۰..۱)
  final double focusX, focusY, focusAt;

  /// بزرگ‌نمایی قاب (برای عکس‌هایی که صورتشان کوچک است)
  final double zoom;

  const PhotoFaceSpec({
    required this.asset,
    required this.avatar,
    required this.refW,
    required this.refH,
    required this.mouthX,
    required this.mouthHalfW,
    required this.cornerY,
    required this.seamY,
    required this.patchLeft,
    required this.patchRight,
    required this.patchTop,
    required this.patchBottom,
    required this.maxOpen,
    required this.focusX,
    required this.focusY,
    this.focusAt = 0.46,
    this.zoom = 1.045,
  });
}

/// «Ryan» — عکسِ assets/personas/ryan.jpg (۱۳۴۴×۸۹۶)
const PhotoFaceSpec kRyanFace = PhotoFaceSpec(
  asset: 'assets/personas/ryan.jpg',
  avatar: 'assets/personas/ryan_avatar.jpg',
  refW: 1344,
  refH: 896,
  mouthX: 737,
  mouthHalfW: 78,
  cornerY: 476,
  seamY: 495,
  patchLeft: 590,
  patchRight: 885,
  patchTop: 425,
  patchBottom: 575,
  maxOpen: 26,
  focusX: 735,
  focusY: 400,
);

/// «Sara» — عکسِ assets/personas/sara.jpg (۱۰۲۴×۱۰۲۴)
const PhotoFaceSpec kSaraFace = PhotoFaceSpec(
  asset: 'assets/personas/sara.jpg',
  avatar: 'assets/personas/sara_avatar.jpg',
  refW: 1024,
  refH: 1024,
  mouthX: 501,
  mouthHalfW: 81,
  cornerY: 544,
  seamY: 563,
  patchLeft: 372,
  patchRight: 630,
  patchTop: 528,
  patchBottom: 655,
  maxOpen: 25,
  focusX: 500,
  focusY: 470,
);

/// «Anna» — عکسِ assets/personas/anna.jpg (۱۰۲۴×۱۰۲۴)
const PhotoFaceSpec kAnnaFace = PhotoFaceSpec(
  asset: 'assets/personas/anna.jpg',
  avatar: 'assets/personas/anna_avatar.jpg',
  refW: 1024,
  refH: 1024,
  mouthX: 506,
  mouthHalfW: 66,
  cornerY: 481,
  seamY: 488,
  patchLeft: 386,
  patchRight: 626,
  patchTop: 455,
  patchBottom: 568,
  maxOpen: 22,
  focusX: 500,
  focusY: 400,
);

/// «Sofia» — عکسِ assets/personas/sofia.jpg (۱۰۲۴×۱۰۲۴)
const PhotoFaceSpec kSofiaFace = PhotoFaceSpec(
  asset: 'assets/personas/sofia.jpg',
  avatar: 'assets/personas/sofia_avatar.jpg',
  refW: 1024,
  refH: 1024,
  mouthX: 516,
  mouthHalfW: 52,
  cornerY: 429,
  seamY: 434,
  patchLeft: 436,
  patchRight: 596,
  patchTop: 412,
  patchBottom: 498,
  maxOpen: 17,
  focusX: 516,
  focusY: 380,
  zoom: 1.45,
);

/// «Daniel» — عکسِ assets/personas/daniel.jpg (۱۰۲۴×۱۰۲۴)
const PhotoFaceSpec kDanielFace = PhotoFaceSpec(
  asset: 'assets/personas/daniel.jpg',
  avatar: 'assets/personas/daniel_avatar.jpg',
  refW: 1024,
  refH: 1024,
  mouthX: 521,
  mouthHalfW: 80,
  cornerY: 583,
  seamY: 592,
  patchLeft: 395,
  patchRight: 647,
  patchTop: 566,
  patchBottom: 700,
  maxOpen: 22,
  focusX: 520,
  focusY: 500,
);

/// «Liam» (باریستا) — عکسِ assets/personas/liam.jpg (۱۰۲۴×۱۰۲۴)
const PhotoFaceSpec kLiamFace = PhotoFaceSpec(
  asset: 'assets/personas/liam.jpg',
  avatar: 'assets/personas/liam_avatar.jpg',
  refW: 1024,
  refH: 1024,
  mouthX: 528,
  mouthHalfW: 58,
  cornerY: 417,
  seamY: 421,
  patchLeft: 430,
  patchRight: 626,
  patchTop: 398,
  patchBottom: 505,
  maxOpen: 19,
  focusX: 528,
  focusY: 340,
);

const Map<String, PhotoFaceSpec> kPhotoFaces = {
  'assets/personas/ryan.jpg': kRyanFace,
  'assets/personas/sara.jpg': kSaraFace,
  'assets/personas/anna.jpg': kAnnaFace,
  'assets/personas/sofia.jpg': kSofiaFace,
  'assets/personas/daniel.jpg': kDanielFace,
  'assets/personas/liam.jpg': kLiamFace,
};

/// حالتِ دهان در یک لحظه: open = بازشدگیِ فک (۰..۱)، round = گردیِ لب مثلِ «او» (۰..۱)
class MouthShape {
  final double open;
  final double round;
  const MouthShape(this.open, this.round);
}

final Map<String, Future<ui.Image>> _photoCache = {};

Future<ui.Image> _loadPhoto(String asset) {
  return _photoCache.putIfAbsent(asset, () async {
    final data = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    final frame = await codec.getNextFrame();
    return frame.image;
  });
}

/// عکسِ تمام‌قابِ سخنگو. [mouth] = null یعنی ساکت (فقط نفس‌کشیدنِ ملایم).
/// [time] ثانیه است و فقط برای حرکتِ ملایمِ سر استفاده می‌شود.
class PhotoTalkingFace extends StatefulWidget {
  final PhotoFaceSpec spec;
  final MouthShape? mouth;
  final bool speaking;
  final double time;

  const PhotoTalkingFace({
    super.key,
    required this.spec,
    required this.mouth,
    required this.speaking,
    required this.time,
  });

  @override
  State<PhotoTalkingFace> createState() => _PhotoTalkingFaceState();
}

class _PhotoTalkingFaceState extends State<PhotoTalkingFace> {
  ui.Image? _img;
  ui.ImageShader? _shader;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PhotoTalkingFace old) {
    super.didUpdateWidget(old);
    if (old.spec.asset != widget.spec.asset) {
      _shader?.dispose();
      _shader = null;
      _img = null;
      _load();
    }
  }

  Future<void> _load() async {
    final asset = widget.spec.asset;
    try {
      final im = await _loadPhoto(asset);
      if (!mounted || asset != widget.spec.asset) return;
      setState(() {
        _img = im;
        _shader = ui.ImageShader(
          im,
          TileMode.clamp,
          TileMode.clamp,
          Matrix4.identity().storage,
          filterQuality: FilterQuality.medium,
        );
      });
    } catch (_) {
      _photoCache.remove(asset);
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final im = _img;
    final sh = _shader;
    if (im == null || sh == null) {
      // تا لحظه‌ی آماده شدنِ تصویر، همان عکس ثابت
      return Image.asset(
        widget.spec.asset,
        fit: BoxFit.cover,
        alignment: const Alignment(0.1, 0),
        gaplessPlayback: true,
      );
    }
    return CustomPaint(
      size: Size.infinite,
      painter: _PhotoFacePainter(
        image: im,
        shader: sh,
        spec: widget.spec,
        mouth: widget.mouth,
        speaking: widget.speaking,
        t: widget.time,
      ),
    );
  }
}

class _PhotoFacePainter extends CustomPainter {
  final ui.Image image;
  final ui.ImageShader shader;
  final PhotoFaceSpec spec;
  final MouthShape? mouth;
  final bool speaking;
  final double t;

  const _PhotoFacePainter({
    required this.image,
    required this.shader,
    required this.spec,
    required this.mouth,
    required this.speaking,
    required this.t,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final sp = spec;
    final k = image.width / sp.refW; // مرجع → پیکسلِ واقعیِ تصویر
    final iw = image.width.toDouble(), ih = image.height.toDouble();

    // ── قاب: «cover» با کمی زوم، و صورت دور از زیرنویسِ پایین ──
    final zoom = sp.zoom; // ثابت: عکس هیچ تکان/زومِ ریزی نمی‌خورد
    final s = math.max(size.width / iw, size.height / ih) * zoom;
    final fx = sp.focusX * k, fy = sp.focusY * k;
    var ox = size.width * 0.5 - fx * s;
    var oy = size.height * sp.focusAt - fy * s;
    ox = ox.clamp(size.width - iw * s, 0.0).toDouble();
    oy = oy.clamp(size.height - ih * s, 0.0).toDouble();

    final m = mouth;
    final open = m == null ? 0.0 : m.open.clamp(0.0, 1.0).toDouble();
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(ox, oy);
    canvas.scale(s);

    // عکسِ پایه (با همان شیدرِ مش تا لبه‌ی ناحیه دیده نشود)
    final basePaint = Paint()..shader = shader;
    canvas.drawRect(Rect.fromLTWH(0, 0, iw, ih), basePaint);

    if (m != null && (open > 0.015 || m.round > 0.015)) {
      _paintMouth(canvas, m, k, basePaint);
    }
    canvas.restore();
  }

  void _paintMouth(Canvas canvas, MouthShape m, double k, Paint texPaint) {
    final sp = spec;
    const nx = 36; // ستون‌ها
    const nUp = 5; // ردیف‌های بالای خطِ لب (ثابت)
    const nLo = 12; // ردیف‌های پایینِ خطِ لب (فک)
    const rowsPerCol = (nUp + 1) + (nLo + 1);
    const cols = nx + 1;

    final cx = sp.mouthX * k;
    final hw = sp.mouthHalfW * k;
    final cornerY = sp.cornerY * k;
    final seamC = sp.seamY * k;
    final yTop = sp.patchTop * k;
    final yEnd = sp.patchBottom * k;
    final x0 = sp.patchLeft * k;
    final x1 = sp.patchRight * k;
    final d = sp.maxOpen * k * m.open.clamp(0.0, 1.0);
    final rnd = m.round.clamp(0.0, 1.0).toDouble();
    final yc = (cornerY + seamC) / 2;
    final yr = yc - yTop;

    // خطِ لب: وسطِ دهان پایین‌تر و گوشه‌ها بالاتر (مثلِ لبخند)
    double seamAt(double x) {
      final u = (x - cx) / hw;
      final v = 1 - u * u;
      return v > 0 ? cornerY + (seamC - cornerY) * v : cornerY;
    }

    // جمع‌شدنِ افقیِ دهان برای «او» (صفر روی لبه‌های ناحیه)
    double dxAt(double sx, double sy) {
      if (rnd <= 0) return 0;
      final u = (sx - cx) / (hw * 1.9);
      final wx = 1 - u * u;
      if (wx <= 0) return 0;
      final v = (sy - yc) / yr;
      final wy = 1 - v * v;
      if (wy <= 0) return 0;
      return -(sx - cx) * 0.22 * rnd * wx * wy;
    }

    final pos = Float32List(cols * rowsPerCol * 2);
    final tex = Float32List(cols * rowsPerCol * 2);
    var o = 0;
    void put(double px, double py, double sx, double sy) {
      pos[o] = px;
      pos[o + 1] = py;
      tex[o] = sx;
      tex[o + 1] = sy;
      o += 2;
    }

    for (var i = 0; i < cols; i++) {
      final sx = x0 + (x1 - x0) * i / nx;
      final s = seamAt(sx);
      // بالای خطِ لب: ثابت (فقط جمع‌شدنِ افقی)
      for (var j = 0; j <= nUp; j++) {
        final sy = yTop + (s - yTop) * j / nUp;
        put(sx + dxAt(sx, sy), sy, sx, sy);
      }
      // پایینِ خطِ لب: فک پایین می‌آید؛ در ته به صفر برمی‌گردد و عرضش با عمق بیشتر می‌شود
      for (var j = 0; j <= nLo; j++) {
        final tt = j / nLo;
        final sy = s + (yEnd - s) * tt;
        final w = 0.5 * (1 + math.cos(math.pi * tt));
        final u = (sx - cx) / (hw * (1.05 + 0.9 * tt));
        final g = u * u < 1 ? 1 - u * u : 0.0;
        put(sx + dxAt(sx, sy), sy + d * g * w, sx, sy);
      }
    }

    // مثلث‌ها
    final idx = Uint16List(nx * (nUp + nLo) * 6);
    var q = 0;
    for (var i = 0; i < nx; i++) {
      final a0 = i * rowsPerCol;
      final b0 = (i + 1) * rowsPerCol;
      void quads(int from, int count) {
        for (var j = from; j < from + count; j++) {
          final a = a0 + j, b = b0 + j, c = a + 1, e = b + 1;
          idx[q++] = a;
          idx[q++] = b;
          idx[q++] = c;
          idx[q++] = b;
          idx[q++] = e;
          idx[q++] = c;
        }
      }

      quads(0, nUp);
      quads(nUp + 1, nLo);
    }

    // داخلِ دهان: بینِ لبه‌ی پایینِ بالا و لبه‌ی بالایِ فک (کمی زیرِ مش‌ها می‌رود)
    // وقتی دهان فقط کمی باز است داخلِ تیره مثلِ «یک خطِ باریک» دیده می‌شد؛
    // پس تا حدِ مشخصی اصلاً کشیده نمی‌شود و بعد نرم محو/آشکار می‌شود.
    final inner = ((d / k - 2.0) / 5.0).clamp(0.0, 1.0).toDouble();
    if (inner > 0.01) {
      final path = Path();
      for (var i = 0; i < cols; i++) {
        final p = (i * rowsPerCol + nUp) * 2;
        final px = pos[p], py = pos[p + 1] - 0.8;
        if (i == 0) {
          path.moveTo(px, py);
        } else {
          path.lineTo(px, py);
        }
      }
      for (var i = cols - 1; i >= 0; i--) {
        final p = (i * rowsPerCol + nUp + 1) * 2;
        path.lineTo(pos[p], pos[p + 1] + 0.8);
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..isAntiAlias = true
          ..shader = ui.Gradient.linear(
            Offset(cx, seamC),
            Offset(cx, seamC + d + 1),
            [
              const Color(0xFF241210).withOpacity(inner),
              const Color(0xFF331816).withOpacity(inner),
              const Color(0xFF5A2B28).withOpacity(inner),
            ],
            const [0.0, 0.5, 1.0],
          )
          // لبه‌ی نرم تا داخلِ دهان مثلِ برشِ تیز/مصنوعی دیده نشود
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.9),
      );
    }

    final verts = ui.Vertices.raw(
      ui.VertexMode.triangles,
      pos,
      textureCoordinates: tex,
      indices: idx,
    );
    canvas.drawVertices(verts, BlendMode.srcOver, texPaint);
    verts.dispose();
  }

  @override
  bool shouldRepaint(_PhotoFacePainter o) => true;
}
