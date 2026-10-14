import 'package:flutter/material.dart';
import '_placeholder_tab.dart';

class SlangTab extends StatelessWidget {
  const SlangTab({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderTab(
        icon: Icons.format_quote_outlined,
        title: 'اصطلاحات عامیانه',
        subtitle:
            'اسلنگ‌ها و اصطلاحات روزمره‌ی زبان‌های مقصد،\nبا معنی، مثال و تلفظ صحیح.',
        previewChips: ['انگلیسی', 'اسپانیایی', 'فرانسوی'],
      );
}
