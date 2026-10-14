import 'package:flutter/material.dart';
import '_placeholder_tab.dart';

class StoryTab extends StatelessWidget {
  const StoryTab({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderTab(
        icon: Icons.auto_stories,
        title: 'داستان‌ساز',
        subtitle:
            'با هوش مصنوعی داستان شخصی‌سازی‌شده بساز،\nاز PDF، عکس، لینک یا متن وارد کن، و با صدا بخوان.',
        isAiPowered: true,
        previewChips: ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'],
      );
}
