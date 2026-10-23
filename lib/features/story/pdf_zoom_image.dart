import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme_colors.dart';

/// عکسِ صفحه‌ی PDF با زوم:
///  • دو انگشت = زوم (تا ۶ برابر) و جابه‌جایی
///  • دوبار لمس = زومِ ۲٫۵ برابر روی همان نقطه / برگشت به اندازه‌ی اصلی
///  • دکمه‌ی ⤢ = نمایشِ تمام‌صفحه (زوم تا ۱۰ برابر)
class ZoomablePageImage extends StatefulWidget {
  final Uint8List bytes;
  final String label; // برچسبِ گوشه‌ی بالا («اصلی» / «ترجمه»)
  final Color accent;
  const ZoomablePageImage({
    super.key,
    required this.bytes,
    required this.label,
    required this.accent,
  });

  @override
  State<ZoomablePageImage> createState() => _ZoomablePageImageState();
}

class _ZoomablePageImageState extends State<ZoomablePageImage>
    with SingleTickerProviderStateMixin {
  final TransformationController _tc = TransformationController();
  Offset _lastTap = Offset.zero;

  @override
  void dispose() {
    _tc.dispose();
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

  void _openFull() {
    showDialog<void>(
      context: context,
      useSafeArea: false,
      builder: (ctx) => _FullScreenImage(
          bytes: widget.bytes, label: widget.label, accent: widget.accent),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Stack(
      children: [
        ClipRect(
          child: GestureDetector(
            onDoubleTapDown: (d) => _lastTap = d.localPosition,
            onDoubleTap: _doubleTap,
            child: InteractiveViewer(
              transformationController: _tc,
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
        PositionedDirectional(
          top: 4,
          end: 4,
          child: Material(
            color: c.paper.withOpacity(0.9),
            shape: CircleBorder(side: BorderSide(color: c.cardBorder)),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _openFull,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.open_in_full_rounded,
                    size: 16, color: widget.accent),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FullScreenImage extends StatelessWidget {
  final Uint8List bytes;
  final String label;
  final Color accent;
  const _FullScreenImage(
      {required this.bytes, required this.label, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 10,
              child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
            ),
          ),
          PositionedDirectional(
            top: MediaQuery.of(context).padding.top + 8,
            end: 10,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.of(context).pop(),
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(Icons.close_rounded, color: Colors.white),
                ),
              ),
            ),
          ),
          PositionedDirectional(
            top: MediaQuery.of(context).padding.top + 14,
            start: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}
