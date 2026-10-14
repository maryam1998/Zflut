import 'package:flutter/material.dart';

import '../../core/theme/app_theme_colors.dart';

class PlaceholderTab extends StatelessWidget {
  final String label;
  const PlaceholderTab({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Center(
      child: Text(
        '$label — به‌زودی',
        style: TextStyle(color: c.inkSoft, fontSize: 16),
      ),
    );
  }
}
