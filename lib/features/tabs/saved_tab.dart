import 'package:flutter/material.dart';
import '_placeholder_tab.dart';

class SavedTab extends StatelessWidget {
  const SavedTab({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderTab(
        icon: Icons.bookmark_outline,
        title: 'لغات ذخیره‌شده',
        subtitle: 'هر لغتی که موقع خواندن ذخیره کردی،\nاینجا جمع می‌شه تا در داستان بعدی استفاده کنی.',
      );
}
