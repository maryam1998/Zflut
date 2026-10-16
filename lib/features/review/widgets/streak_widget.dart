import 'package:flutter/material.dart';

import '../../../core/neural/neural_dates.dart' show faDigits;
import '../../../core/theme/app_theme_colors.dart';
import '../models/review_stats.dart';

/// زنجیره‌ی روزانه: «🔥 X روز پشت‌سرهم» + ۷ نقطه‌ی فعالیتِ هفته.
class StreakWidget extends StatelessWidget {
  final ReviewStats stats;
  const StreakWidget({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final now = DateTime.now();
    final streak = stats.streak(now);
    final dates = stats.lastDates(now, n: 7);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Row(
        children: [
          const Text('🔥', style: TextStyle(fontSize: 30)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  streak == 0
                      ? 'هنوز زنجیره‌ای نداری'
                      : '${faDigits(streak)} روز پشت‌سرهم',
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  streak == 0
                      ? 'امروز یک جلسه مرور کن تا شروع شود'
                      : 'زنجیره را نشکن؛ هر روز حداقل یک لغت',
                  style: TextStyle(color: c.inkSoft, fontSize: 12),
                ),
              ],
            ),
          ),
          Row(
            children: [
              for (final d in dates)
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsetsDirectional.only(start: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: stats.dayStat(d).total > 0
                        ? c.gold
                        : c.paperDark,
                    border: Border.all(
                      color: stats.dayStat(d).total > 0
                          ? c.gold
                          : c.cardBorder,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
