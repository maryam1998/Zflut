import 'package:flutter/material.dart';
import '_placeholder_tab.dart';

class GrammarTab extends StatelessWidget {
  const GrammarTab({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderTab(
        icon: Icons.spellcheck,
        title: 'گرامر',
        subtitle: 'یادداشت‌های گرامری، پرسش از معلم هوشمند،\nو تمرین ساخت جمله با ساختارهای جدید.',
      );
}
