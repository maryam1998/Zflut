import 'package:flutter/material.dart';
import '_placeholder_tab.dart';

class ReviewTab extends StatelessWidget {
  const ReviewTab({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderTab(
        icon: Icons.repeat,
        title: 'مرور با جعبه‌ی لایتنر',
        subtitle:
            'سیستم مرور هوشمند در فواصل زمانی بهینه،\nلغات رو از حافظه‌ی کوتاه‌مدت به بلندمدت منتقل می‌کنه.',
        previewChips: ['امروز', 'این هفته', 'یاد گرفته'],
      );
}
