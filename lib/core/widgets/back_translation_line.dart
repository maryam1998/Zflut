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

  const BackTranslationLine({
    super.key,
    required this.langCode,
    required this.text,
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

    final c = context.appColors;
    final tp = ref.watch(textPrefsProvider);
    final rtl = _rtlLangs.contains(native);
    return Padding(
      padding: EdgeInsets.only(left: widget.leftInset, top: 1, bottom: 2),
      child: Align(
        alignment: rtl ? Alignment.centerRight : Alignment.centerLeft,
        child: Directionality(
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: Text(
            '↩ $b',
            textAlign: rtl ? TextAlign.right : TextAlign.left,
            style: TextStyle(
              color: c.inkSoft,
              fontSize: (widget.compact ? 11 : 12) * tp.scaleFactor,
              height: 1.3,
            ),
          ),
        ),
      ),
    );
  }
}
