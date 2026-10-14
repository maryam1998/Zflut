import 'package:flutter/material.dart';
import '_placeholder_tab.dart';

class ConversationsTab extends StatelessWidget {
  const ConversationsTab({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderTab(
        icon: Icons.forum_outlined,
        title: 'مکالمه',
        subtitle: 'مکالمات روزمره و موضوعی با ترجمه‌ی خط‌به‌خط،\nهمراه با پخش صدا و تمرین شنیداری.',
      );
}
