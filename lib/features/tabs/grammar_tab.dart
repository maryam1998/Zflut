import 'package:flutter/material.dart';
import '_placeholder_tab.dart';

class GrammarTab extends StatelessWidget {
  const GrammarTab({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderTab(
        icon: Icons.text_format,
        title: 'گرامر',
        subtitle:
            'یادداشت‌های گرامری خودت رو بنویس،\nاز معلم هوشمند بپرس، و با تمرین جمله‌سازی تثبیت کن.',
        isAiPowered: true,
        previewChips: ['یادداشت', 'معلم هوشمند', 'تمرین جمله'],
      );
}
