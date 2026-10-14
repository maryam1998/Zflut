import 'package:flutter/material.dart';
import '_placeholder_tab.dart';

class ReviewTab extends StatelessWidget {
  const ReviewTab({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderTab(
        icon: Icons.inventory_2_outlined,
        title: 'مرور',
        subtitle: 'سیستم جعبه‌ی لایتنر برای مرور هوشمند لغات\nدر فواصل زمانی بهینه‌شده.',
      );
}
