// نمایشگرِ تمام‌صفحه‌ی صفحه‌ی PDF: زومِ آزاد روی کلِ صفحه‌ی گوشی (بدونِ کادر)،
// با سه حالت: اصلی · ترجمه · متنِ استخراج‌شده (+ ذخیره‌ی متن در داستان‌ساز).
import 'dart:typed_data';

import 'package:flutter/material.dart';

Future<void> showPdfFullscreen(
  BuildContext context, {
  required Uint8List? orig,
  required Uint8List? trans,
  required String text,
  required String title,
  required Future<bool> Function() onSaveText,
  String initial = 'orig',
}) {
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => _PdfFullscreen(
        orig: orig,
        trans: trans,
        text: text,
        title: title,
        onSaveText: onSaveText,
        initial: initial,
      ),
    ),
  );
}

class _PdfFullscreen extends StatefulWidget {
  final Uint8List? orig;
  final Uint8List? trans;
  final String text;
  final String title;
  final Future<bool> Function() onSaveText;
  final String initial;
  const _PdfFullscreen({
    required this.orig,
    required this.trans,
    required this.text,
    required this.title,
    required this.onSaveText,
    required this.initial,
  });

  @override
  State<_PdfFullscreen> createState() => _PdfFullscreenState();
}

class _PdfFullscreenState extends State<_PdfFullscreen> {
  static const _gold = Color(0xFFD4A62A);
  late String _mode = widget.initial;
  final _tcOrig = TransformationController();
  final _tcTrans = TransformationController();
  Offset _tapPos = Offset.zero;
  double _fontSize = 19;
  bool _saving = false;
  bool _saved = false;

  @override
  void dispose() {
    _tcOrig.dispose();
    _tcTrans.dispose();
    super.dispose();
  }

  bool get _rtlText {
    for (final r in widget.text.runes.take(400)) {
      if ((r >= 0x0600 && r <= 0x06FF) || (r >= 0x0750 && r <= 0x077F)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    var ok = false;
    try {
      ok = await widget.onSaveText();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = ok;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'متن در داستان‌ساز ذخیره شد ✓'
          : 'ذخیره‌ی متن انجام نشد (متنی برای ذخیره نیست)'),
    ));
  }

  Widget _seg(String mode, String label, IconData icon) {
    final on = _mode == mode;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _mode = mode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: on ? _gold : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: on ? Colors.black : Colors.white70),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      color: on ? Colors.black : Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imageView(Uint8List? bytes, TransformationController tc, String empty) {
    if (bytes == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(empty,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.7)),
        ),
      );
    }
    return LayoutBuilder(builder: (ctx, bc) {
      return GestureDetector(
        onDoubleTapDown: (d) => _tapPos = d.localPosition,
        onDoubleTap: () {
          if (tc.value.getMaxScaleOnAxis() > 1.05) {
            tc.value = Matrix4.identity();
          } else {
            const s = 2.6;
            tc.value = Matrix4.identity()
              ..translate(-_tapPos.dx * (s - 1), -_tapPos.dy * (s - 1))
              ..scale(s);
          }
        },
        child: InteractiveViewer(
          transformationController: tc,
          constrained: false,
          minScale: 1,
          maxScale: 10,
          boundaryMargin: EdgeInsets.zero,
          child: SizedBox(
            width: bc.maxWidth,
            child: Image.memory(bytes,
                fit: BoxFit.fitWidth,
                width: bc.maxWidth,
                filterQuality: FilterQuality.high,
                gaplessPlayback: true),
          ),
        ),
      );
    });
  }

  Widget _textView() {
    final t = widget.text.trim();
    if (t.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text(
              'این صفحه متنِ قابل‌خواندن ندارد — احتمالاً فقط عکس است.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.7)),
        ),
      );
    }
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
            child: SelectableText(
              t,
              textDirection: _rtlText ? TextDirection.rtl : TextDirection.ltr,
              style: TextStyle(
                  color: Colors.white, fontSize: _fontSize, height: 1.9),
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'کوچک‌تر',
              icon: const Icon(Icons.text_decrease_rounded, color: Colors.white70),
              onPressed: () =>
                  setState(() => _fontSize = (_fontSize - 2).clamp(12, 40)),
            ),
            Text('${_fontSize.round()}',
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
            IconButton(
              tooltip: 'بزرگ‌تر',
              icon: const Icon(Icons.text_increase_rounded, color: Colors.white70),
              onPressed: () =>
                  setState(() => _fontSize = (_fontSize + 2).clamp(12, 40)),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    switch (_mode) {
      case 'trans':
        body = _imageView(widget.trans, _tcTrans,
            'ترجمه‌ی این صفحه هنوز آماده نیست — در نمایشگرِ اصلی ترجمه را با ▶ شروع کن.');
        break;
      case 'text':
        body = _textView();
        break;
      default:
        body = _imageView(widget.orig, _tcOrig, 'عکسِ این صفحه هنوز آماده نیست');
    }
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Text(widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      _seg('orig', 'اصلی', Icons.image_outlined),
                      _seg('trans', 'ترجمه', Icons.translate_rounded),
                      _seg('text', 'متن', Icons.notes_rounded),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Expanded(child: ClipRect(child: body)),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _gold,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _saving ? null : _save,
                    icon: Icon(_saved
                        ? Icons.check_circle_rounded
                        : Icons.bookmark_add_rounded),
                    label: Text(
                        _saving
                            ? 'در حال ذخیره…'
                            : (_saved
                                ? 'ذخیره شد — دوباره ذخیره کن'
                                : 'ذخیره‌ی متن در داستان‌ساز'),
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
