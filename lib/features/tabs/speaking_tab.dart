import 'package:flutter/material.dart';
import '_placeholder_tab.dart';

class SpeakingTab extends StatelessWidget {
  const SpeakingTab({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderTab(
        icon: Icons.mic_none_outlined,
        title: 'تمرین مکالمه',
        subtitle: 'با معلم هوشمند مکالمه کن، تلفظت رو بسنج،\nو بازخورد فوری بگیر.',
      );
}
