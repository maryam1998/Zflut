import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────
// آدمکِ جدیدِ Lingova (ماسکوتِ سه‌بعدی/خمیری) — لایه‌های جداگانه‌ی PSD:
//   سرِ نیمرخ + سرِ روبرو + بدن + گردن و لگن (پرکننده) + دست + مشت + چوبِ اشاره‌گر + دو پا
// همه‌چیز در «مختصاتِ بوم ۶۴۰×۶۴۰ِ PSD» کشیده می‌شود و یک‌جا به جعبه‌ی ۳۰×۳۸ِ آدمک
// (همان جای آدمکِ قبلی) کوچک می‌شود.
// ─────────────────────────────────────────────────────────────────────────

/// بارگذاریِ تصاویرِ لایه‌ها (یک بار برای کل برنامه)
class MascotSprites {
  MascotSprites._();

  static const _names = [
    'body', 'neck', 'hip', 'arm', 'hand', 'stick',
    'head_side', 'head_front', 'leg_a', 'leg_b',
  ];

  static Map<String, ui.Image>? images;
  static Future<void>? _loading;

  static Future<void> load() => _loading ??= _doLoad();

  static Future<void> _doLoad() async {
    try {
      final out = <String, ui.Image>{};
      for (final n in _names) {
        final data = await rootBundle.load('assets/mascot/$n.png');
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        final frame = await codec.getNextFrame();
        out[n] = frame.image;
      }
      images = out;
    } catch (e) {
      debugPrint('mascot sprites load error: $e');
      _loading = null; // دفعه‌ی بعد دوباره تلاش شود
    }
  }
}

/// جایگاهِ هر لایه روی بومِ PSD (x, y, عرض, ارتفاع) — شاملِ حاشیه‌ی نرم‌کننده‌ی لبه‌ها
class _Box {
  final double x, y, w, h;
  const _Box(this.x, this.y, this.w, this.h);
}

const _boxes = <String, _Box>{
  'body': _Box(231, 233, 167, 244),
  'neck': _Box(274, 219, 84, 46),
  'hip': _Box(280, 438, 76, 56),
  'arm': _Box(290, 256, 73, 207),
  'hand': _Box(232, 382, 35, 72),
  'stick': _Box(373, 166, 96, 233),
  'head_side': _Box(207, 47, 222, 212),
  'head_front': _Box(216, 47, 204, 212),
  'leg_a': _Box(205, 425, 128, 172),
  'leg_b': _Box(302, 427, 111, 168),
};

// نقاطِ لولا (مختصاتِ بوم)
const _hipA = Offset(293, 462);
const _hipB = Offset(336, 464);
const _shoulder = Offset(325, 270);
const _stickGrip = Offset(386, 385); // جایی از چوب که در مشت می‌نشیند
const double _armLen = 175; // شانه تا مشت
const double _headCx = 318; // مرکزِ افقیِ هر دو سر
const Offset _neckPivot = Offset(318, 249);

// مقیاسِ بوم → جعبه‌ی ۳۰×۳۸ (سر از y≈۰٫۵ تا کفشِ پا y≈۳۵٫۵؛ مثلِ آدمکِ قبلی)
const double _k = 35 / 530;
const double _originX = 15 - 315 * _k;
const double _originY = 0.5 - 57 * _k;

class MascotPainter extends CustomPainter {
  /// در حال قدم زدن؟ (false = ایستاده/مکث/تذکر)
  final bool walking;
  final int ms;

  /// ۰ = سرِ نیمرخ، ۱ = سرِ روبرو (حینِ چرخش بین این دو است)
  final double look;

  /// ۰ = دست پایین، ۱ = دستِ اشاره‌گر بالا (تذکر)
  final double alertK;

  const MascotPainter({
    required this.walking,
    required this.ms,
    required this.look,
    required this.alertK,
  });

  void _img(Canvas c, String name, {double dx = 0, double dy = 0, Paint? p}) {
    final im = MascotSprites.images?[name];
    final b = _boxes[name];
    if (im == null || b == null) return;
    c.drawImageRect(
      im,
      Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble()),
      Rect.fromLTWH(b.x + dx, b.y + dy, b.w, b.h),
      p ?? _paint,
    );
  }

  static final Paint _paint = Paint()
    ..filterQuality = FilterQuality.high
    ..isAntiAlias = true;

  void _rot(Canvas c, Offset pivot, double deg, VoidCallback draw) {
    c.save();
    c.translate(pivot.dx, pivot.dy);
    c.rotate(deg * math.pi / 180);
    c.translate(-pivot.dx, -pivot.dy);
    draw();
    c.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (MascotSprites.images == null) return;

    canvas.save();
    canvas.translate(_originX, _originY);
    canvas.scale(_k);

    // ───── راه رفتن: پاها با حرکتِ نرم + بالا‌پایین شدنِ (Bobbing) بدن
    final t = (ms % 700) / 700.0;
    final s = walking ? math.sin(2 * math.pi * t) : 0.0;
    final bob = walking ? -8.0 * (1 + math.cos(4 * math.pi * t)) / 2 : 0.0;
    // کمی نفس کشیدن وقتی ایستاده
    final breath = walking ? 0.0 : -1.5 * math.sin(2 * math.pi * (ms % 2400) / 2400);
    final dy = bob + breath;

    // پاها (پشتِ بدن): دو پا خلافِ هم دور لولای خودشان می‌چرخند
    _rot(canvas, _hipB, -16 * s, () => _img(canvas, 'leg_b'));
    _rot(canvas, _hipA, 16 * s, () => _img(canvas, 'leg_a'));

    // ───── دست + چوبِ اشاره‌گر
    // تذکر: دست از شانه به سمتِ جلو بالا می‌آید و چوب در مشت می‌نشیند؛ چند بار تکان می‌خورد
    final wag = math.sin(2 * math.pi * (ms % 460) / 460.0);
    final armDeg = alertK * (34 + 8 * wag);
    final stickK = alertK; // ۰ = پشتِ بدن (حالتِ عادی)، ۱ = در مشت
    final a = armDeg * math.pi / 180;
    final hand = Offset(
      _shoulder.dx - _armLen * math.sin(a),
      _shoulder.dy + dy + _armLen * math.cos(a),
    );
    final stickShift = Offset(
      (hand.dx - _stickGrip.dx) * stickK,
      (hand.dy - (_stickGrip.dy + dy)) * stickK,
    );
    final stickDeg = stickK * (-50 + 7 * math.sin(2 * math.pi * (ms % 460) / 460.0 + 1.2));
    void drawStick() {
      canvas.save();
      canvas.translate(stickShift.dx, stickShift.dy);
      _rot(canvas, Offset(_stickGrip.dx, _stickGrip.dy + dy), stickDeg,
          () => _img(canvas, 'stick', dy: dy));
      canvas.restore();
    }

    if (stickK < 0.5) drawStick(); // پشتِ بدن

    // لگن (هم‌رنگِ شلوار): فاصله‌ی بین تنه و پاها را موقعِ چرخشِ پاها می‌پوشاند
    _img(canvas, 'hip', dy: dy);

    // ───── بدن + پرکننده‌ی گردن (تا موقعِ چرخشِ سر زیرِ گردن خالی دیده نشود)
    _img(canvas, 'body', dy: dy);
    _img(canvas, 'neck', dy: dy);
    _rot(canvas, Offset(_shoulder.dx, _shoulder.dy + dy), armDeg,
        () => _img(canvas, 'arm', dy: dy));
    _img(canvas, 'hand', dy: dy);

    if (stickK >= 0.5) drawStick(); // در مشت، جلوی بدن

    // ───── سر: چرخشِ نیمرخ ⇄ روبرو (فشرده شدنِ افقی، تعویضِ تصویر در میانه)
    final p = look.clamp(0.0, 1.0);
    final sx = 0.14 + 0.86 * math.cos(math.pi * p).abs();
    final hop = -7 * math.sin(math.pi * p); // پرشِ کوچک موقعِ چرخش
    canvas.save();
    canvas.translate(_headCx, _neckPivot.dy);
    canvas.scale(sx, 1);
    canvas.translate(-_headCx, -_neckPivot.dy);
    _img(canvas, p < 0.5 ? 'head_side' : 'head_front', dy: dy + hop);
    canvas.restore();

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant MascotPainter old) => true;
}
