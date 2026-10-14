import 'package:flutter/material.dart';
import '_placeholder_tab.dart';

class ConversationsTab extends StatelessWidget {
  const ConversationsTab({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderTab(
        icon: Icons.chat_bubble_outline,
        title: 'مکالمه',
        subtitle:
            'مکالمات روزمره و موضوعی با ترجمه‌ی خط‌به‌خط،\nپخش صدا، سرعت دلخواه و تمرین شنیداری.',
        previewChips: ['روزمره', 'فرودگاه', 'رستوران', 'خرید', 'اضطراری'],
      );
}
