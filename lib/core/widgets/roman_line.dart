// 📁 مسیر: lib/core/widgets/roman_line.dart
//
// 🔤 خطِ رومی‌سازی: زیرِ متنِ ترجمه، با فونتِ کوچک‌تر و رنگِ ملایم.
// اگر رومی‌سازی‌ای برای این متن نباشد (یا زبانِ مقصد همان زبانِ مادریِ کاربر باشد) هیچ‌چیز نمی‌کشد.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/language_selection_provider.dart';
import '../providers/text_prefs_provider.dart';
import '../theme/app_theme_colors.dart';
import '../translate/romanization.dart';

class RomanLine extends ConsumerStatefulWidget {
  final String langCode;
  final String text;
  final bool compact;

  /// فاصله از چپ تا هم‌ترازیِ متنِ ترجمه (زیرِ نشانِ زبان)
  final double leftInset;

  const RomanLine({
    super.key,
    required this.langCode,
    required this.text,
    this.compact = false,
    this.leftInset = 36,
  });

  @override
  ConsumerState<RomanLine> createState() => _RomanLineState();
}

class _RomanLineState extends ConsumerState<RomanLine> {
  @override
  void initState() {
    super.initState();
    if (!Romanization.isLoaded && Romanization.langs.contains(widget.langCode)) {
      Romanization.ensureLoaded().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Romanization.langs.contains(widget.langCode)) {
      return const SizedBox.shrink();
    }
    final native = ref.watch(languageSelectionProvider.select((s) => s.native));
    final roman =
        Romanization.lookup(widget.langCode, widget.text, native: native);
    if (roman == null) return const SizedBox.shrink();

    final c = context.appColors;
    final tp = ref.watch(textPrefsProvider);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Padding(
        padding: EdgeInsets.only(left: widget.leftInset, top: 1, bottom: 2),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            roman,
            textAlign: TextAlign.left,
            style: TextStyle(
              color: c.inkSoft,
              fontSize: (widget.compact ? 10.5 : 11.5) * tp.scaleFactor,
              fontStyle: FontStyle.italic,
              height: 1.25,
            ),
          ),
        ),
      ),
    );
  }
}
