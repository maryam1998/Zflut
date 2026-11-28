// 📁 مسیر: lib/core/widgets/back_translation_line.dart
//
// ↩ ترجمه‌ی برگشتی: ترجمه‌ی «زبانِ مقصد» دوباره به زبانِ مادریِ کاربر برمی‌گردد (بدونِ دیدنِ جمله‌ی اصلی)
// تا کسی که زبانِ مقصد را بلد نیست بفهمد ترجمه درست رفته یا نه.
// فقط مترجمِ رایگان (بدونِ AI و بدونِ هزینه)؛ نتیجه در کشِ مترجم می‌ماند، پس هر جمله یک‌بار حساب می‌شود.
// اگر زبانِ مقصد همان زبانِ مادری باشد، یا ترجمه‌ی برگشتی نشد، هیچ‌چیز نمی‌کشد.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/language_selection_provider.dart';
import '../providers/text_prefs_provider.dart';
import '../providers/translation_provider.dart';
import '../theme/app_theme_colors.dart';
import '../utils/html_entities.dart';

class BackTranslationLine extends ConsumerStatefulWidget {
  /// زبانِ ترجمه (مثلاً es / zh) و متنِ آن
  final String langCode;
  final String text;
  final bool compact;
  final double leftInset;

  /// متنِ مبدأ و زبانِ آن: اگر ترجمه‌ی برگشتی با ترجمه‌ی زبانِ مادری (ردیفِ بالا) تقریباً یکی باشد
  /// دیگر نشان داده نمی‌شود (شلوغی کم می‌شود)؛ فقط وقتی فرق دارد که ارزشِ دیدن دارد.
  final String en;
  final String sourceLang;

  /// true = همیشه نشان بده (برای «گزینه‌ی دوم»: کاربر باید قبل از انتخاب بتواند چک کند).
  final bool alwaysShow;

  const BackTranslationLine({
    super.key,
    required this.langCode,
    required this.text,
    this.en = '',
    this.sourceLang = 'en',
    this.alwaysShow = false,
    this.compact = false,
    this.leftInset = 36,
  });

  @override
  ConsumerState<BackTranslationLine> createState() =>
      _BackTranslationLineState();
}

class _BackTranslationLineState extends ConsumerState<BackTranslationLine> {
  String? _back;
  String _forKey = '';
  int _gen = 0;

  static const Set<String> _rtlLangs = {'fa', 'ar', 'he', 'ur'};

  @override
  void didUpdateWidget(covariant BackTranslationLine old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text || old.langCode != widget.langCode) {
      _forKey = '';
    }
  }

  void _compute(String native) {
    final txt = widget.text.trim();
    final key = '${widget.langCode}|$native|$txt';
    if (key == _forKey) return;
    _forKey = key;
    _back = null;
    final gen = ++_gen;
    if (txt.isEmpty || native.isEmpty || native == widget.langCode) return;
    () async {
      String r = '';
      try {
        r = decodeHtmlEntities((await ref
                .read(translationServiceProvider)
                .translate(
                  text: txt,
                  targetLang: native,
                  sourceLang: widget.langCode,
                  aiSettings: null, // فقط رایگان؛ هزینه‌ی AI ندارد
                  aiOnlyIfSuspicious: true,
                ))
            .trim());
      } catch (_) {}
      if (!mounted || gen != _gen) return;
      setState(() => _back = (r.isEmpty || r == txt) ? null : r);
    }();
  }

  /// نرمال‌سازی برای مقایسه: بدونِ فاصله/علامت، یکسان‌سازیِ ی/ک عربی و حذفِ اعراب.
  static String _norm(String s) {
    var t = s
        .toLowerCase()
        .replaceAll('\u064A', '\u06CC')
        .replaceAll('\u0643', '\u06A9')
        .replaceAll(RegExp('[\u064B-\u065F\u0640\u200c\u200d]'), '');
    return t.replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');
  }

  /// شباهتِ دو رشته (Dice روی دوحرفی‌ها) بین ۰ و ۱.
  static double _sim(String a, String b) {
    final x = _norm(a), y = _norm(b);
    if (x.isEmpty || y.isEmpty) return 0;
    if (x == y) return 1;
    if (x.length < 2 || y.length < 2) return 0;
    final m = <String, int>{};
    for (var i = 0; i < x.length - 1; i++) {
      final g = x.substring(i, i + 2);
      m[g] = (m[g] ?? 0) + 1;
    }
    var hit = 0;
    for (var i = 0; i < y.length - 1; i++) {
      final g = y.substring(i, i + 2);
      final n = m[g] ?? 0;
      if (n > 0) {
        hit++;
        m[g] = n - 1;
      }
    }
    return 2 * hit / ((x.length - 1) + (y.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final native =
        ref.watch(languageSelectionProvider.select((s) => s.native));
    if (native.isEmpty || native == widget.langCode) {
      return const SizedBox.shrink();
    }
    _compute(native);
    final b = _back;
    if (b == null) return const SizedBox.shrink();

    // ترجمه‌ی برگشتی ≈ ترجمه‌ی زبانِ مادری → یعنی همه‌چیز درست است؛ چیزی نشان نده
    if (!widget.alwaysShow && widget.en.trim().isNotEmpty) {
      String? nat;
      try {
        nat = ref
            .read(translationServiceProvider)
            .peekCached(widget.en, widget.sourceLang, native);
      } catch (_) {}
      if (nat != null && nat.trim().isNotEmpty && _sim(b, nat) >= 0.5) {
        return const SizedBox.shrink();
      }
    }

    final c = context.appColors;
    final tp = ref.watch(textPrefsProvider);
    final rtl = _rtlLangs.contains(native);
    return Padding(
      padding: EdgeInsets.only(left: widget.leftInset, top: 1, bottom: 2),
      child: Align(
        alignment: rtl ? Alignment.centerRight : Alignment.centerLeft,
        child: Directionality(
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.subdirectory_arrow_left_rounded,
                  size: 12, color: c.inkSoft.withOpacity(0.55)),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  b,
                  textAlign: rtl ? TextAlign.right : TextAlign.left,
                  style: TextStyle(
                    color: c.inkSoft.withOpacity(0.8),
                    fontSize: (widget.compact ? 10.5 : 11) * tp.scaleFactor,
                    height: 1.3,
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
