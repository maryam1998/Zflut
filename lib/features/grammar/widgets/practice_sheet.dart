import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme_colors.dart';

/// پنل تمرین جمله‌سازی — کشیدنی و قابل جابجایی
class PracticeSheet extends ConsumerStatefulWidget {
  final Widget child;
  final VoidCallback? onClose;
  final bool initiallyOpen;

  const PracticeSheet({
    super.key,
    required this.child,
    this.onClose,
    this.initiallyOpen = false,
  });

  @override
  ConsumerState<PracticeSheet> createState() => _PracticeSheetState();
}

class _PracticeSheetState extends ConsumerState<PracticeSheet> {
  // ارتفاع
  bool _open = false;
  double _headerH = 56;
  double _viewportH = 800;
  double? _customHeight; // ارتفاع دلخواه کاربر بعد از کشیدن

  // جابجایی
  Offset _offset = Offset.zero;
  Offset? _dragOffset;

  // drag state
  double _dragStartY = 0;
  double _dragStartHeight = 0;
  bool _dragMoved = false;

  // move state
  Offset _moveStart = Offset.zero;
  Offset _moveStartOffset = Offset.zero;

  @override
  void initState() {
    super.initState();
    _open = widget.initiallyOpen;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _viewportH = MediaQuery.of(context).size.height;
  }

  double get _snapHeight {
    if (!_open) return _headerH;
    return _customHeight ?? _viewportH * 0.55;
  }

  double get _currentHeight {
    final live = _dragOffset;
    if (live != null) return live.dy; // dy برای ارتفاع موقت
    return _snapHeight;
  }

  bool get _moved => _offset.dx != 0 || _offset.dy != 0;

  // ═══════════════════════════════════════════════════════════════════
  // کشیدن هدر برای تغییر ارتفاع
  // ═══════════════════════════════════════════════════════════════════
  void _onHeightDragStart(DragStartDetails d) {
    _dragStartY = d.globalPosition.dy;
    _dragStartHeight = _snapHeight;
    _dragMoved = false;
    _dragOffset = Offset(0, _snapHeight);
  }

  void _onHeightDragUpdate(DragUpdateDetails d) {
    if (_dragOffset == null) return;
    final delta = _dragStartY - d.globalPosition.dy;
    if (delta.abs() > 4) _dragMoved = true;
    final next = (_dragStartHeight + delta)
        .clamp(_headerH, _viewportH * 0.92)
        .toDouble();
    setState(() => _dragOffset = Offset(0, next));
  }

  void _onHeightDragEnd(DragEndDetails d) {
    if (_dragOffset == null) return;
    final finalH = _dragOffset!.dy;
    setState(() {
      _dragOffset = null;
      if (!_dragMoved) {
        _open = !_open;
        _customHeight = null;
      } else if (finalH <= _headerH + 8) {
        // کشیدنِ کامل به پایین → بستن
        _open = false;
        _customHeight = null;
        widget.onClose?.call();
      } else {
        _open = true;
        _customHeight = finalH;
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════
  // کشیدن دستگیره‌ی نقطه‌ای برای جابجایی
  // ═══════════════════════════════════════════════════════════════════
  void _onMoveDragStart(DragStartDetails d) {
    _moveStart = d.globalPosition;
    _moveStartOffset = _offset;
    _dragOffset = null;
  }

  void _onMoveDragUpdate(DragUpdateDetails d) {
    final dx = d.globalPosition.dx - _moveStart.dx;
    final dy = d.globalPosition.dy - _moveStart.dy;
    final panelH = _currentHeight;
    final screenW = MediaQuery.of(context).size.width;

    // محدوده‌های مجاز
    final maxX = screenW - 60;
    final minX = -maxX;
    final maxY = 0.0;
    final minY = -(_viewportH - panelH);

    setState(() {
      _dragOffset = Offset(
        (_moveStartOffset.dx + dx).clamp(minX, maxX),
        (_moveStartOffset.dy + dy).clamp(minY, maxY),
      );
    });
  }

  void _onMoveDragEnd(DragEndDetails d) {
    if (_dragOffset == null) return;
    setState(() {
      _offset = _dragOffset!;
      _dragOffset = null;
    });
  }

  void _resetPosition() {
    setState(() {
      _offset = Offset.zero;
      _dragOffset = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final liveOffset = _dragOffset ?? _offset;
    final currentH = _currentHeight;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Transform.translate(
        offset: liveOffset,
        child: AnimatedContainer(
          duration: (_dragOffset == null && _moveDragEnded)
              ? const Duration(milliseconds: 240)
              : Duration.zero,
          curve: Curves.easeOutCubic,
          height: currentH,
          decoration: BoxDecoration(
            color: c.paperDark,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            border: Border.all(color: c.goldSoft, width: 1),
            boxShadow: [
              BoxShadow(
                color: c.ink.withOpacity(0.15),
                blurRadius: 14,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Column(
              children: [
                // ═══ هدر گرادیانتی — هم کشیدن برای ارتفاع، هم دکمه‌ی بستن ═══
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragStart: _onHeightDragStart,
                  onVerticalDragUpdate: _onHeightDragUpdate,
                  onVerticalDragEnd: _onHeightDragEnd,
                  onTap: () => setState(() {
                    _open = !_open;
                    _customHeight = null;
                  }),
                  child: Container(
                    height: _headerH,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [c.headerFrom, c.headerTo],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // دستگیره‌ی بالا
                        Container(
                          width: 36,
                          height: 4,
                          margin: const EdgeInsets.only(top: 6, bottom: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.55),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Expanded(
                          child: Row(
                            children: [
                              // دکمه‌ی جابجایی (نقطه‌ای)
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onPanStart: _onMoveDragStart,
                                onPanUpdate: _onMoveDragUpdate,
                                onPanEnd: _onMoveDragEnd,
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CustomPaint(
                                      painter: _DotsPainter(
                                          color: Colors.white.withOpacity(0.85)),
                                    ),
                                  ),
                                ),
                              ),
                              // دکمه‌ی ریست موقعیت
                              if (_moved)
                                GestureDetector(
                                  onTap: _resetPosition,
                                  child: Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white.withOpacity(0.18),
                                    ),
                                    child: const Icon(Icons.refresh,
                                        size: 14, color: Colors.white),
                                  ),
                                ),
                              const SizedBox(width: 6),
                              const Icon(Icons.chat_bubble_outline,
                                  size: 16, color: Colors.white),
                              const SizedBox(width: 6),
                              const Expanded(
                                child: Text(
                                  'تمرین جمله‌سازی و گرامر',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Icon(
                                _open
                                    ? Icons.keyboard_arrow_down
                                    : Icons.keyboard_arrow_up,
                                size: 18,
                                color: Colors.white,
                              ),
                              // دکمه بستن
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _open = false;
                                    _customHeight = null;
                                  });
                                  widget.onClose?.call();
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Icon(Icons.close,
                                      size: 16,
                                      color: Colors.white.withOpacity(0.9)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ═══ محتوا — فقط وقتی بازه ═══
                if (_open && currentH > _headerH + 10)
                  Expanded(child: widget.child),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _moveDragEnded = false;
}

class _DotsPainter extends CustomPainter {
  final Color color;
  _DotsPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const spacing = 6.0;
    const radius = 1.8;
    for (double y = 3; y < size.height; y += spacing) {
      for (double x = 3; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) => old.color != color;
}
