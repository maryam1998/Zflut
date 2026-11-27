import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_prefs_provider.dart';

/// 🗂️ «گزینه‌ی دوم»: وقتی ↻ ترجمه‌ی جدیدی می‌دهد، ترجمه‌ی قبلی سر جایش می‌ماند و جدید
/// زیرش با دکمه‌ی ✓ (انتخاب) و ✕ (کنار گذاشتن) نشان داده می‌شود.
/// این ویجت فقط ظاهر است؛ منطق (انتخاب/کنار گذاشتن) را والد با TranslationService انجام می‌دهد.
class TranslationAltRow extends ConsumerWidget {
  final String alt;
  final TextDirection textDirection;
  final double fontSize;
  final Color color;
  final Color dismissColor;
  final VoidCallback onChoose;
  final VoidCallback onDismiss;

  const TranslationAltRow({
    super.key,
    required this.alt,
    required this.textDirection,
    required this.onChoose,
    required this.onDismiss,
    this.fontSize = 12,
    this.color = const Color(0xFFC9972B),
    this.dismissColor = const Color(0xFF9A9A9A),
  });

  static const Map<String, String> _label = {
    'fa': 'گزینه‌ی دوم',
    'en': 'Second option',
    'ar': 'خيار ثانٍ',
    'es': 'Segunda opción',
    'de': 'Zweite Option',
    'fr': 'Deuxième option',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.read(appPrefsProvider).uiLang;
    final label = _label[ui] ?? _label['en']!;
    final rtl = textDirection == TextDirection.rtl;
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Align(
        alignment: rtl ? Alignment.centerRight : Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                '$label: $alt',
                textDirection: textDirection,
                style: TextStyle(
                  color: color,
                  fontSize: fontSize,
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onChoose,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.check_circle_outline,
                    size: 18, color: Color(0xFF2E9E6B)),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDismiss,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.close, size: 16, color: dismissColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
