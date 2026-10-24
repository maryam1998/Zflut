import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

/// بازیگرِ «قفل‌کننده»: وقتی عکس زوم است (یا دو انگشت روی آن آمد) بلافاصله برنده‌ی
/// مسابقه‌ی ژست‌ها می‌شود تا اسکرولِ صفحه جلوی جابه‌جایی با یک انگشت را نگیرد.
class _ClaimRecognizer extends OneSequenceGestureRecognizer {
  bool Function()? eager;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer);
    if (eager?.call() ?? false) resolve(GestureDisposition.accepted);
  }

  void claim() => resolve(GestureDisposition.accepted);

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'pdfZoomClaim';
}

/// عکسِ صفحه‌ی PDF با زوم (هر عکس زومِ مستقلِ خودش را دارد):
///  • دو انگشت = زوم (تا ۶ برابر) و جابه‌جایی
///  • وقتی زوم شده: با یک انگشت در همه‌ی جهت‌ها می‌چرخی و بررسی می‌کنی
///  • دوبار لمس = زومِ ۲٫۵ برابر روی همان نقطه / برگشت به اندازه‌ی اصلی
class ZoomablePageImage extends StatefulWidget {
  final Uint8List bytes;
  final String label; // برچسبِ گوشه‌ی بالا («اصلی» / «ترجمه»)
  final Color accent;

  /// کنترلرِ زوم (اختیاری): برای ریست از بیرون. برای اصلی و ترجمه کنترلرِ جدا بدهید.
  final TransformationController? controller;

  /// اگر داده شود، دکمه‌ی «تمام‌صفحه» گوشه‌ی عکس نشان داده می‌شود.
  final VoidCallback? onExpand;
  const ZoomablePageImage({
    super.key,
    required this.bytes,
    required this.label,
    required this.accent,
    this.controller,
    this.onExpand,
  });

  @override
  State<ZoomablePageImage> createState() => _ZoomablePageImageState();
}

class _ZoomablePageImageState extends State<ZoomablePageImage> {
  late final TransformationController _tc;
  late final bool _ownsTc;
  final GlobalKey _boxKey = GlobalKey();
  final Map<int, Offset> _pts = {};
  _ClaimRecognizer? _claim;
  Offset _downPos = Offset.zero;
  Duration _downAt = Duration.zero;
  bool _moved = false;
  Duration _lastTapAt = const Duration(days: -1);
  Offset _lastTapPos = Offset.zero;

  static const double _maxScale = 6;

  @override
  void initState() {
    super.initState();
    _ownsTc = widget.controller == null;
    _tc = widget.controller ?? TransformationController();
  }

  @override
  void dispose() {
    if (_ownsTc) _tc.dispose();
    super.dispose();
  }

  double get _scale => _tc.value.getMaxScaleOnAxis();

  Size? get _size {
    final o = _boxKey.currentContext?.findRenderObject();
    return o is RenderBox && o.hasSize ? o.size : null;
  }

  void _set(double s, double tx, double ty) {
    final sz = _size;
    if (s <= 1.001) {
      _tc.value = Matrix4.identity();
      return;
    }
    if (sz != null) {
      tx = tx.clamp(sz.width * (1 - s), 0.0).toDouble();
      ty = ty.clamp(sz.height * (1 - s), 0.0).toDouble();
    }
    _tc.value = Matrix4.identity()
      ..translate(tx, ty)
      ..scale(s);
  }

  /// زوم با ضریبِ [k] حولِ نقطه‌ی [fPrev] و انتقالِ آن به [fCur]
  void _apply(double k, Offset fPrev, Offset fCur) {
    final s = _scale;
    final m = _tc.value;
    final tx = m.entry(0, 3), ty = m.entry(1, 3);
    final ns = (s * k).clamp(1.0, _maxScale).toDouble();
    final k2 = ns / s;
    _set(ns, fCur.dx - (fPrev.dx - tx) * k2, fCur.dy - (fPrev.dy - ty) * k2);
  }

  void _doubleTap(Offset p) {
    if (_scale > 1.05) {
      _tc.value = Matrix4.identity();
      return;
    }
    const s = 2.5;
    _set(s, -p.dx * (s - 1), -p.dy * (s - 1));
  }

  void _down(PointerDownEvent e) {
    _pts[e.pointer] = e.localPosition;
    if (_pts.length == 1) {
      _downPos = e.localPosition;
      _downAt = e.timeStamp;
      _moved = false;
    } else {
      _moved = true;
      _claim?.claim();
    }
  }

  void _move(PointerMoveEvent e) {
    final old = _pts[e.pointer];
    if (old == null) return;
    final cur = e.localPosition;
    if ((cur - _downPos).distance > 18) _moved = true;
    if (_pts.length == 1) {
      if (_scale > 1.01) _apply(1, old, cur);
      _pts[e.pointer] = cur;
    } else {
      final ids = _pts.keys.take(2).toList();
      final prevA = _pts[ids[0]]!, prevB = _pts[ids[1]]!;
      _pts[e.pointer] = cur;
      final curA = _pts[ids[0]]!, curB = _pts[ids[1]]!;
      final d0 = (prevA - prevB).distance;
      final d1 = (curA - curB).distance;
      if (d0 > 1) {
        _apply(d1 / d0, (prevA + prevB) / 2, (curA + curB) / 2);
      }
    }
  }

  void _up(PointerEvent e) {
    final single = _pts.length == 1;
    _pts.remove(e.pointer);
    if (e is PointerUpEvent && single && !_moved) {
      final dt = e.timeStamp - _downAt;
      if (dt < const Duration(milliseconds: 300)) {
        final p = e.localPosition;
        if (e.timeStamp - _lastTapAt < const Duration(milliseconds: 320) &&
            (p - _lastTapPos).distance < 40) {
          _lastTapAt = const Duration(days: -1);
          _doubleTap(p);
        } else {
          _lastTapAt = e.timeStamp;
          _lastTapPos = p;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRect(
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              _ClaimRecognizer:
                  GestureRecognizerFactoryWithHandlers<_ClaimRecognizer>(
                () => _ClaimRecognizer(),
                (r) {
                  r.eager = () => _scale > 1.01;
                  _claim = r;
                },
              ),
            },
            child: Listener(
              onPointerDown: _down,
              onPointerMove: _move,
              onPointerUp: _up,
              onPointerCancel: _up,
              child: ValueListenableBuilder<Matrix4>(
                valueListenable: _tc,
                builder: (_, m, child) => Transform(
                  transform: m,
                  alignment: Alignment.topLeft,
                  child: child,
                ),
                child: SizedBox(
                  key: _boxKey,
                  width: double.infinity,
                  child: Image.memory(widget.bytes,
                      fit: BoxFit.fitWidth,
                      width: double.infinity,
                      gaplessPlayback: true),
                ),
              ),
            ),
          ),
        ),
        if (widget.onExpand != null)
          PositionedDirectional(
            top: 6,
            end: 6,
            child: Material(
              color: Colors.black.withOpacity(0.55),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: widget.onExpand,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.fullscreen_rounded,
                      size: 22, color: Colors.white),
                ),
              ),
            ),
          ),
        PositionedDirectional(
          top: 6,
          start: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: widget.accent.withOpacity(0.92),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(widget.label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800)),
          ),
        ),
      ],
    );
  }
}
