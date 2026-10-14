import 'package:flutter/material.dart';

import '../../../core/theme/app_theme_colors.dart';

/// پنل تمرین گرامر — همیشه visible، بین محتوا و پلیر
/// کشیدنی: هدر رو بکش بالا/پایین → ارتفاع تغییر می‌کنه
class PracticeSheet extends StatefulWidget {
  const PracticeSheet({super.key});

  @override
  State<PracticeSheet> createState() => _PracticeSheetState();
}

class _PracticeSheetState extends State<PracticeSheet> {
  // ارتفاع: closed = فقط هدر | open = نصف صفحه
  bool _open = false;
  double _headerH = 52;
  double _viewportH = 800;
  double? _customHeight;

  // drag
  double _dragStartY = 0;
  double _dragStartHeight = 0;
  bool _dragMoved = false;
  double? _liveHeight;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _viewportH = MediaQuery.of(context).size.height;
  }

  double get _snapHeight {
    if (!_open) return _headerH;
    return _customHeight ?? _viewportH * 0.55;
  }

  double get _currentHeight => _liveHeight ?? _snapHeight;

  void _onDragStart(DragStartDetails d) {
    _dragStartY = d.globalPosition.dy;
    _dragStartHeight = _snapHeight;
    _dragMoved = false;
    setState(() => _liveHeight = _snapHeight);
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_liveHeight == null) return;
    final delta = _dragStartY - d.globalPosition.dy;
    if (delta.abs() > 4) _dragMoved = true;
    final next = (_dragStartHeight + delta)
        .clamp(_headerH, _viewportH * 0.92)
        .toDouble();
    setState(() => _liveHeight = next);
  }

  void _onDragEnd(DragEndDetails d) {
    if (_liveHeight == null) return;
    final finalH = _liveHeight!;
    setState(() {
      _liveHeight = null;
      if (!_dragMoved) {
        _open = !_open;
        _customHeight = null;
      } else if (finalH <= _headerH + 10) {
        _open = false;
        _customHeight = null;
      } else {
        _open = true;
        _customHeight = finalH;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final currentH = _currentHeight;

    return AnimatedContainer(
      duration: _liveHeight == null
          ? const Duration(milliseconds: 240)
          : Duration.zero,
      curve: Curves.easeOutCubic,
      height: currentH,
      decoration: BoxDecoration(
        color: c.paperDark,
        border: Border(
          top: BorderSide(color: c.goldSoft, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: c.ink.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: ClipRect(
        child: Column(
          children: [
            // ═══ هدر — کشیدنی ═══
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart: _onDragStart,
              onVerticalDragUpdate: _onDragUpdate,
              onVerticalDragEnd: _onDragEnd,
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
                child: Row(
                  children: [
                    // دستگیره‌ی بالا (بصری)
                    Container(
                      width: 32,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(
                      Icons.psychology_outlined,
                      size: 18,
                      color: Colors.white.withOpacity(0.9),
                    ),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'تمرین جمله‌سازی و گرامر',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Icon(
                      _open
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_up,
                      size: 20,
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
            ),

            // ═══ محتوا — وقتی بازه ═══
            if (_open && currentH > _headerH + 10)
              const Expanded(child: _GrammarPracticeContent()),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
class _GrammarPracticeContent extends StatefulWidget {
  const _GrammarPracticeContent();

  @override
  State<_GrammarPracticeContent> createState() =>
      _GrammarPracticeContentState();
}

class _GrammarPracticeContentState extends State<_GrammarPracticeContent> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;

    return Container(
      color: c.paper,
      child: Column(
        children: [
          // توضیحات
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Text(
              'یه جمله به فرانسوی بنویس؛ اگر غلط بود اصلاحش می‌کنم و کلمه‌به‌کلمه '
              'گرامرش رو توضیح می‌دم. یا هر سوال گرامری که داری — چه درباره‌ی این جمله، '
              'چه یه سوال کاملاً جدا — همین‌جا بپرس تا مثل یه معلم زبان جواب بدم.',
              style: TextStyle(color: c.inkSoft, fontSize: 12, height: 1.7),
              textAlign: TextAlign.right,
            ),
          ),
          const Spacer(),
          // کادر ارسال
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: c.teal, width: 1.5),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(6),
              child: Row(
                children: [
                  Material(
                    color: c.teal,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {},
                      child: const Padding(
                        padding: EdgeInsets.all(9),
                        child: Icon(Icons.send_rounded,
                            size: 18, color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      maxLines: null,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(color: c.ink, fontSize: 13),
                      decoration: InputDecoration(
                        hintText:
                            'جمله‌ت رو بنویس یا سوال‌ت رو بپرس...',
                        hintStyle: TextStyle(
                          color: c.inkSoft.withOpacity(0.6),
                          fontSize: 11.5,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
