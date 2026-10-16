import 'package:flutter/material.dart';

import '../../../core/constants/app_themes.dart';
import '../../../core/neural/neural_dates.dart' show faDigits;
import '../../../core/theme/app_theme_colors.dart';
import '../models/review_item.dart';

/// سه دکمه‌ی ارزیابی: 😰 سخت (قرمز) / 😊 خوب (زرد) / 😎 آسان (سبز)
class RatingButtons extends StatelessWidget {
  final ReviewItem item;
  final void Function(ReviewRating rating) onRate;

  const RatingButtons({super.key, required this.item, required this.onRate});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final now = DateTime.now();
    String when(ReviewRating r) =>
        '${faDigits(item.rated(r, now).intervalDays)} روز بعد';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Row(
        children: [
          Expanded(
            child: _RatingButton(
              emoji: '😰',
              label: 'سخت',
              hint: when(ReviewRating.hard),
              color: c.rose,
              onTap: () => onRate(ReviewRating.hard),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _RatingButton(
              emoji: '😊',
              label: 'خوب',
              hint: when(ReviewRating.good),
              color: c.gold,
              onTap: () => onRate(ReviewRating.good),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _RatingButton(
              emoji: '😎',
              label: 'آسان',
              hint: when(ReviewRating.easy),
              color: AppFixedColors.readDoneCheck1,
              onTap: () => onRate(ReviewRating.easy),
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingButton extends StatelessWidget {
  final String emoji;
  final String label;
  final String hint;
  final Color color;
  final VoidCallback onTap;

  const _RatingButton({
    required this.emoji,
    required this.label,
    required this.hint,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Material(
      color: color.withOpacity(0.16),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color, width: 1.4),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: c.ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                hint,
                style: TextStyle(color: c.inkSoft, fontSize: 10.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
