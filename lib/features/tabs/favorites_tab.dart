import 'package:flutter/material.dart';
import '_placeholder_tab.dart';

class FavoritesTab extends StatelessWidget {
  const FavoritesTab({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderTab(
        icon: Icons.favorite_outline,
        title: 'منتخب‌ها',
        subtitle: 'لغات و عبارت‌هایی که با ⭐ علامت زدی،\nهمه‌شون اینجا جمع می‌شن.',
      );
}
