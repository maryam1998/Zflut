import 'package:flutter/material.dart';
import '_placeholder_tab.dart';

class VocabInUseTab extends StatelessWidget {
  const VocabInUseTab({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderTab(
        icon: Icons.layers_outlined,
        title: 'لغات کاربردی',
        subtitle: 'لغات در قالب جمله‌های واقعی با تمرین‌های\nچندگزینه‌ای و کاربرد در موقعیت‌های روزمره.',
      );
}
