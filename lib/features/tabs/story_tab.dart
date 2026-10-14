import 'package:flutter/material.dart';
import '_placeholder_tab.dart';

class StoryTab extends StatelessWidget {
  const StoryTab({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderTab(
        icon: Icons.auto_awesome_outlined,
        title: 'داستان‌ساز',
        subtitle: 'با هوش مصنوعی داستان بساز، لغات انتخاب کن،\nاز PDF یا لینک وارد کن، و با صدا بخون.',
      );
}
