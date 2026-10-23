import 'dart:typed_data';

import 'package:flutter/material.dart';

/// عکسِ صفحه‌ی PDF با زوم:
///  • دو انگشت = زوم (تا ۶ برابر) و جابه‌جایی
///  • دوبار لمس = زومِ ۲٫۵ برابر روی همان نقطه / برگشت به اندازه‌ی اصلی
class ZoomablePageImage extends StatefulWidget {
  final Uint8List bytes;
  final String label; // برچسبِ گوشه‌ی بالا («اصلی» / «ترجمه»)
  final Color accent;

  /// کنترلرِ مشترکِ زوم: اگر عکسِ اصلی و ترجمه یکی بدهند، زوم/جابه‌جاییِ هر دو همزمان می‌شود.
  final TransformationController? controller;
  const ZoomablePageImage({
    super.key,
    required this.bytes,
    required this.label,
    required this.accent,
    this.controller,
  });

  @override
  State<ZoomablePageImage> createState() => _ZoomablePageImageState();
}

class _ZoomablePageImageState extends State<ZoomablePageImage>
    with SingleTickerProviderStateMixin {
  late final TransformationController _tc;
  late final bool _ownsTc;
  Offset _lastTap = Offset.zero;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _ownsTc = widget.controller == null;
    _tc = widget.controller ?? TransformationController();
    _zoomed = _tc.value.getMaxScaleOnAxis() > 1.01;
    _tc.addListener(_onTc);
  }

  // فقط وقتی زوم شده، یک انگشت عکس را جابه‌جا می‌کند؛ در حالتِ عادی اسکرولِ صفحه آزاد است
  void _onTc() {
    final z = _tc.value.getMaxScaleOnAxis() > 1.01;
    if (z != _zoomed && mounted) setState(() => _zoomed = z);
  }

  @override
  void dispose() {
    _tc.removeListener(_onTc);
    if (_ownsTc) _tc.dispose();
    super.dispose();
  }

  void _doubleTap() {
    if (_tc.value.getMaxScaleOnAxis() > 1.05) {
      _tc.value = Matrix4.identity();
      return;
    }
    const s = 2.5;
    final p = _lastTap;
    _tc.value = Matrix4.identity()
      ..translate(-p.dx * (s - 1), -p.dy * (s - 1))
      ..scale(s);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRect(
          child: GestureDetector(
            onDoubleTapDown: (d) => _lastTap = d.localPosition,
            onDoubleTap: _doubleTap,
            child: InteractiveViewer(
              transformationController: _tc,
              panEnabled: _zoomed,
              minScale: 1,
              maxScale: 6,
              child: Image.memory(widget.bytes,
                  fit: BoxFit.fitWidth,
                  width: double.infinity,
                  gaplessPlayback: true),
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
