import 'dart:math' as math;
import 'dart:typed_data' show Float64List;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────
// آدمکِ جدیدِ Lingova (ماسکوتِ سه‌بعدی/خمیری) — لایه‌های جداگانه‌ی PSD:
//   سرِ کروی (۱۴ فریمِ چرخش: چشم/دهان/گونه روی کره می‌لغزند) + بدن + گردن و لگن (پرکننده) + دست + مشت + چوبِ اشاره‌گر + دو پا
// همه‌چیز در «مختصاتِ بوم ۶۴۰×۶۴۰ِ PSD» کشیده می‌شود و یک‌جا به جعبه‌ی ۳۰×۳۸ِ آدمک
// (همان جای آدمکِ قبلی) کوچک می‌شود.
// ─────────────────────────────────────────────────────────────────────────

/// بارگذاریِ تصاویرِ لایه‌ها (یک بار برای کل برنامه)
class MascotSprites {
  MascotSprites._();

  /// تعدادِ فریم‌های چرخشِ سر (۰° = روبرو … ۷۸° = تقریباً نیمرخ؛ هر فریم ۶°)
  static const headFrames = 14;
  static const double headStepDeg = 6;

  static final _names = [
    'body', 'neck', 'hip', 'arm', 'hand', 'stick', 'leg_a', 'leg_b',
    for (var i = 0; i < headFrames; i++) 'head_${i.toString().padLeft(2, '0')}',
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
  'leg_a': _Box(205, 425, 128, 172),
  'leg_b': _Box(302, 427, 111, 168),
};

// نقاطِ لولا (مختصاتِ بوم)
const _hipA = Offset(293, 462);
const _hipB = Offset(336, 464);
const _shoulder = Offset(325, 270);
const _stickGrip = Offset(386, 385); // جایی از چوب که در مشت می‌نشیند
const double _armLen = 175; // شانه تا مشت

// جعبه‌ی فریم‌های سر (کره‌ی ۱۹۲ پیکسلی + ۱۰ پیکسل حاشیه‌ی نرمِ لبه؛ مرکز = (۳۱۸، ۱۵۳))
const _headBox = _Box(212, 47, 212, 212);

// ───── راه رفتن (چرخه‌ی گام با «پای ثابت روی زمین»)
// کفِ کفشِ هر پا در حالتِ PSD (مرجعِ کاشتنِ پا روی زمین)
const Offset _footA = Offset(257.4, 585);
const Offset _footB = Offset(363.1, 583);
const double _stride = 44; // نیم‌گام (کوچک‌تر + گامِ سریع‌تر: هر فریمِ کلیدی ≈ ۰٫۱۵–۰٫۲ ثانیه): فاصله‌ی پا تا زیرِ لگن در ابتدا/انتهای تماس با زمین
const double _stanceFrac = 0.6; // سهمِ فازِ تماسِ پا با زمین در یک چرخه
const double _liftH = 22; // ارتفاعِ بلند شدنِ پا در فازِ آویز
const double _groundY = 586; // خطِ زمین (مختصاتِ بوم)
const double _hipCx = 315; // مرکزِ لگن: پاها موقعِ عبور از کنارِ هم دقیقاً زیرِ همین نقطه می‌رسند

/// طولِ مسیرِ طی‌شده‌ی آدمک (پیکسلِ UI) در یک چرخه‌ی کاملِ گام. فاز بر اساسِ «مسافت» جلو می‌رود
/// نه زمان؛ پس پای ثابت دقیقاً هم‌سرعتِ زمین می‌لغزد و پا «اسکیت» نمی‌زند.
const double kMascotCyclePx = (2 * _stride / _stanceFrac) * (35 / 530);

// مقیاسِ بوم → جعبه‌ی ۳۰×۳۸ (سر از y≈۰٫۵ تا کفشِ پا y≈۳۵٫۵؛ مثلِ آدمکِ قبلی)
const double _k = 35 / 530;
const double _originX = 15 - 315 * _k;
const double _originY = 0.5 - 57 * _k;

// ───── هم‌اندازه کردنِ دو پا
// تصویرِ پای راست (leg_b) در PSD ≈ ۱۲٪ کوتاه‌تر و کمی باریک‌تر از پای چپ (leg_a) است و همین باعث «لنگیدن» می‌شد.
// leg_b دورِ لولای خودش در امتدادِ محورِ اصلیِ پا (۶۲٫۸°) و در عرض ×۱٫۰۳ بزرگ می‌شود
// تا طولِ «لولا تا کفِ پا»ی آن دقیقاً با leg_a برابر شود (۱۲۸ پیکسلِ بوم).
// ⚠️ مقدارِ قبلی ۱٫۱۴ بود که پای راست را ≈۸٪ بلندتر از چپ می‌کرد (۱۳۸ در برابر ۱۲۸) و
// همین باعثِ بالا/پایین رفتنِ نامتقارنِ لگن و «لنگیدن» می‌شد؛ مقدارِ درست ۱٫۰۵ است.
const double _legBAxisDeg = 62.8;
const double _legBAlong = 1.05;
const double _legBAcross = 1.03;

/// ماتریسِ ۲×۲ِ اصلاحِ اندازه‌ی یک پا: [m00, m01, m11] (m10 = m01)؛ پایی که نیاز ندارد null.
List<double>? _legFix(String name) {
  if (name != 'leg_b') return null;
  final t = _legBAxisDeg * math.pi / 180;
  final s = math.sin(t), c = math.cos(t);
  return [
    _legBAlong * c * c + _legBAcross * s * s,
    (_legBAlong - _legBAcross) * s * c,
    _legBAlong * s * s + _legBAcross * c * c,
  ];
}

/// بردارِ لولا→کفِ پا بعد از اصلاحِ اندازه
Offset _legR(String name, Offset hip, Offset foot) {
  final r = foot - hip;
  final m = _legFix(name);
  if (m == null) return r;
  return Offset(m[0] * r.dx + m[1] * r.dy, m[1] * r.dx + m[2] * r.dy);
}

class _Step {
  final double f; // جلو بودنِ پا نسبت به لگن (مثبت = رو به جلو)
  final double lift; // ارتفاعِ پا از زمین
  final bool stance; // روی زمین؟
  const _Step(this.f, this.lift, this.stance);
}

double _smooth(double t) => t * t * (3 - 2 * t);

_Step _gait(double u, double amp) {
  u = u - u.floorToDouble();
  if (u < _stanceFrac) {
    // پای ثابت: با سرعتِ یکنواخت نسبت به بدن به عقب می‌رود
    return _Step(amp * (1 - 2 * u / _stanceFrac), 0, true);
  }
  // آویز: پا با کمانی به جلو می‌آید
  final w = (u - _stanceFrac) / (1 - _stanceFrac);
  return _Step(amp * (-1 + 2 * _smooth(w)),
      _liftH * (amp / _stride) * math.sin(math.pi * w), false);
}

class MascotPainter extends CustomPainter {
  /// فازِ گام (۰..∞؛ بخشِ کسری = جای‌گاه در چرخه) — بر اساسِ مسافتِ پیموده‌شده
  final double phase;

  /// ۰ = ایستاده، ۱ = در حال قدم زدن (برای ورود/خروجِ نرم)
  final double walkK;
  final int ms;

  /// ۰ = سرِ روبرو، ۱ = سرِ نیمرخ (چرخشِ پیوسته با ۱۴ فریم)
  final double turn;

  /// ۰ = دست پایین، ۱ = دستِ اشاره‌گر بالا (تذکر)
  final double alertK;

  const MascotPainter({
    required this.phase,
    required this.walkK,
    required this.ms,
    required this.turn,
    required this.alertK,
  });

  static final Paint _paint = Paint()
    ..filterQuality = FilterQuality.high
    ..isAntiAlias = true;

  void _draw(Canvas c, String name, _Box b, {double dy = 0, Paint? p}) {
    final im = MascotSprites.images?[name];
    if (im == null) return;
    c.drawImageRect(
      im,
      Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble()),
      Rect.fromLTWH(b.x, b.y + dy, b.w, b.h),
      p ?? _paint,
    );
  }

  void _img(Canvas c, String name, {double dy = 0}) {
    final b = _boxes[name];
    if (b != null) _draw(c, name, b, dy: dy);
  }

  void _rot(Canvas c, Offset pivot, double deg, VoidCallback draw) {
    c.save();
    c.translate(pivot.dx, pivot.dy);
    c.rotate(deg * math.pi / 180);
    c.translate(-pivot.dx, -pivot.dy);
    draw();
    c.restore();
  }

  /// یک پا: دورِ لولا می‌چرخد تا جهتش به هدف برسد، سپس طوری جابه‌جا می‌شود که کف کفش
  /// دقیقاً روی نقطه‌ی هدف (زمین/کمانِ آویز) بنشیند.
  /// فاصله‌ی افقیِ هدفِ پا تا لولای «خودِ همان پا».
  /// ⚠️ قبلاً هر دو پا حولِ یک نقطه‌ی مشترک (_hipCx) می‌چرخیدند؛ ولی لولای دو پا در PSD
  /// ۴۳ پیکسل از هم فاصله دارند (۲۹۳ و ۳۳۶). نتیجه: در یکی از دو نیم‌گام پاها کنار هم
  /// (فاصله‌ی ≈۳۰) و در نیم‌گامِ دیگر کاملاً باز (≈۱۱۶) فرود می‌آمدند و لگن یک‌بار ≈۱۳ پیکسل
  /// فرو می‌رفت و یک‌بار نه ← «لنگیدن». حالا هر پا حولِ لولای خودش و با دامنه‌ی یکسان می‌چرخد
  /// (دو نیم‌گام دقیقاً قرینه‌ی هم). در حالتِ ایستاده (walkK=۰) همان حالتِ قبلی
  /// (پاها زیرِ _hipCx) می‌ماند و با شروعِ قدم زدن نرم عوض می‌شود.
  ///
  /// ⚠️ اما اگر پاها حولِ لولای خودشان تاب بخورند، بازه‌ی حرکتِ کفِ پاها هم ۴۳ پیکسل از هم جدا
  /// می‌شود: یک پا تا ۴۴ پیکسل جلوتر از مرکز می‌رفت و پای دیگر فقط تا نزدیکِ مرکز؛ نتیجه این‌که
  /// یک پا «ثابت» دیده می‌شد و فقط پای دیگر جلو می‌رفت. پس «نقطه‌ی فرودِ کفِ پا» برای هر دو پا
  /// دورِ یک مرکزِ مشترک (_hipCx) و با دامنه‌ی برابر می‌چرخد؛ هر پا همچنان حولِ لولای خودش
  /// می‌چرخد (فقط زاویه‌اش عوض می‌شود). در ایستادن (f=۰) همان حالتِ قبلی است.
  double _reachDx(Offset hip, _Step g) => (_hipCx - hip.dx) - g.f;

  /// فاصله‌ی افقیِ نقطه‌ی تماس تا لولا فقط برای محاسبه‌ی «پایین آمدنِ لگن» (همان فرمولِ قبلی؛
  /// نوسانِ لگن بدونِ تغییر می‌ماند).
  double _needDx(Offset hip, _Step g) =>
      (_hipCx - hip.dx) * (1 - walkK) - g.f;

  void _leg(Canvas c, String name, Offset hip, Offset foot, _Step g, double drop) {
    final h = Offset(hip.dx, hip.dy + drop);
    final tgt = Offset(hip.dx + _reachDx(hip, g), _groundY - g.lift);
    final r = _legR(name, hip, foot);
    final t = tgt - h;
    final phi = math.atan2(t.dy, t.dx) - math.atan2(r.dy, r.dx);
    final cp = math.cos(phi), sp = math.sin(phi);
    final rr = Offset(r.dx * cp - r.dy * sp, r.dx * sp + r.dy * cp);
    final d = tgt - (h + rr);
    c.save();
    c.translate(h.dx + d.dx, h.dy + d.dy);
    c.rotate(phi);
    final fix = _legFix(name);
    if (fix != null) {
      c.transform(Float64List.fromList(<double>[
        fix[0], fix[1], 0, 0, //
        fix[1], fix[2], 0, 0, //
        0, 0, 1, 0, //
        0, 0, 0, 1,
      ]));
    }
    c.translate(-hip.dx, -hip.dy);
    _img(c, name);
    c.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (MascotSprites.images == null) return;

    canvas.save();
    canvas.translate(_originX, _originY);
    canvas.scale(_k);

    // ───── راه رفتن
    final amp = _stride * walkK;
    final ga = _gait(phase, amp);
    final gb = _gait(phase + 0.5, amp);
    // لگن به اندازه‌ای پایین می‌آید که پای ثابت (که دورتر از زیرِ لگن است) کشیده شود → بالا/پایینِ طبیعی
    double need(String nm, _Step g, Offset foot, Offset hip) {
      if (!g.stance) return -1e9;
      final len = _legR(nm, hip, foot).distance;
      final dx = _needDx(hip, g); // فاصله‌ی افقیِ لگنِ این پا تا نقطه‌ی تماس
      return _groundY - math.sqrt(math.max(len * len - dx * dx, 1));
    }

    final hy = math.max(need('leg_a', ga, _footA, _hipA), need('leg_b', gb, _footB, _hipB));
    final drop = (hy - 463).clamp(-6.0, 16.0).toDouble();
    // نفس کشیدنِ آرام وقتی ایستاده
    final breath = (1 - walkK) * -1.4 * math.sin(2 * math.pi * (ms % 2600) / 2600);
    final dy = drop + breath;

    // پاها (پشتِ بدن)
    _leg(canvas, 'leg_b', _hipB, _footB, gb, drop);
    _leg(canvas, 'leg_a', _hipA, _footA, ga, drop);

    // تنه و سر کمی به جلو خم می‌شوند (دورِ لگن)
    canvas.save();
    final lean = -1.6 * walkK;
    canvas.translate(315, 463 + dy);
    canvas.rotate(lean * math.pi / 180);
    canvas.translate(-315, -(463 + dy));

    // لگن (هم‌رنگِ شلوار): فاصله‌ی بین تنه و پاها را می‌پوشاند
    _img(canvas, 'hip', dy: dy);

    // ───── دست + چوبِ اشاره‌گر
    final wag = math.sin(2 * math.pi * (ms % 460) / 460.0);
    final armSwing = -12 * math.cos(2 * math.pi * phase) * walkK; // خلافِ پای جلو
    final armDeg = alertK * (34 + 8 * wag) + (1 - alertK) * armSwing;
    final stickK = alertK; // ۰ = پشتِ بدن، ۱ = در مشت
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

    // ───── بدن + پرکننده‌ی گردن
    _img(canvas, 'body', dy: dy);
    _img(canvas, 'neck', dy: dy);
    _rot(canvas, Offset(_shoulder.dx, _shoulder.dy + dy), armDeg,
        () => _img(canvas, 'arm', dy: dy));
    // دستِ دورتر (مشتِ لبه‌ی جلو) خلافِ دستِ نزدیک تاب می‌خورد
    _rot(canvas, Offset(252, 392 + dy), -armSwing * (1 - alertK),
        () => _img(canvas, 'hand', dy: dy));

    if (stickK >= 0.5) drawStick(); // در مشت، جلوی بدن

    // ───── سر: چرخشِ پیوسته با ۱۴ فریمِ کره (چشم/دهان/گونه روی کره می‌لغزند)
    final e = _smooth(turn.clamp(0.0, 1.0).toDouble());
    final pos = e * (MascotSprites.headFrames - 1);
    final i0 = pos.floor().clamp(0, MascotSprites.headFrames - 1).toInt();
    final i1 = math.min(i0 + 1, MascotSprites.headFrames - 1);
    final fr = pos - i0;
    final hop = -5 * math.sin(math.pi * e); // پرشِ کوچک موقعِ چرخش
    String nm(int i) => 'head_${i.toString().padLeft(2, '0')}';
    _draw(canvas, nm(i0), _headBox, dy: dy + hop);
    if (i1 != i0 && fr > 0.01) {
      final p = Paint()
        ..filterQuality = FilterQuality.high
        ..isAntiAlias = true
        ..color = Color.fromARGB((fr * 255).round(), 255, 255, 255);
      _draw(canvas, nm(i1), _headBox, dy: dy + hop, p: p);
    }
    canvas.restore(); // lean

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant MascotPainter old) => true;
}
