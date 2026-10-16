import 'package:flutter/material.dart';

import '../../../core/neural/neural_dates.dart' show faDigits;
import '../../../core/theme/app_theme_colors.dart';
import '../models/review_stats.dart';

/// نمودار ستونی ۷ روز اخیر (تعداد مرورها) — با CustomPainter.
/// قدیمی‌ترین روز سمت راست، امروز سمت چپ (جهت RTL).
class WeeklyChart extends StatelessWidget {
  final ReviewStats stats;
  const WeeklyChart({super.key, required this.stats});

  // DateTime.weekday: ۱=دوشنبه … ۷=یکشنبه
  static const Map<int, String> _dayLabels = {
    6: 'ش',
    7: 'ی',
    1: 'د',
    2: 'س',
    3: 'چ',
    4: 'پ',
    5: 'ج',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final now = DateTime.now();
    final dates = stats.lastDates(now, n: 7);
    final values = [for (final d in dates) stats.dayStat(d).total];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          SizedBox(
            height: 120,
            width: double.infinity,
            child: CustomPaint(
              painter: _BarsPainter(
                values: values,
                barColor: c.teal.withOpacity(0.75),
                todayColor: c.gold,
                gridColor: c.cardBorder,
                textColor: c.inkSoft,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 0; i < dates.length; i++)
                Expanded(
                  child: Text(
                    _dayLabels[dates[i].weekday] ?? '',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: i == dates.length - 1 ? c.ink : c.inkSoft,
                      fontSize: 12,
                      fontWeight: i == dates.length - 1
                          ? FontWeight.w800
                          : FontWeight.w500,
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

class _BarsPainter extends CustomPainter {
  final List<int> values; // قدیمی‌ترین اول
  final Color barColor;
  final Color todayColor;
  final Color gridColor;
  final Color textColor;

  _BarsPainter({
    required this.values,
    required this.barColor,
    required this.todayColor,
    required this.gridColor,
    required this.textColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n == 0) return;

    const topPad = 18.0; // جا برای عدد بالای ستون
    final chartH = size.height - topPad;
    final slot = size.width / n;
    final barW = slot * 0.5;
    final maxV = values.fold<int>(1, (a, b) => b > a ? b : a);

    // خط پایه
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      grid,
    );

    for (var i = 0; i < n; i++) {
      final v = values[i];
      // RTL: i=0 (قدیمی‌ترین) سمت راست
      final cx = size.width - (i + 0.5) * slot;
      final isToday = i == n - 1;
      final h = v == 0 ? 3.0 : (v / maxV) * chartH;
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(cx - barW / 2, size.height - h, barW, h),
        topLeft: const Radius.circular(6),
        topRight: const Radius.circular(6),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..color = v == 0
              ? gridColor
              : (isToday ? todayColor : barColor),
      );

      if (v > 0) {
        final tp = TextPainter(
          text: TextSpan(
            text: faDigits(v),
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.rtl,
        )..layout();
        tp.paint(canvas, Offset(cx - tp.width / 2, size.height - h - tp.height - 2));
      }
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.values != values ||
      old.barColor != barColor ||
      old.todayColor != todayColor ||
      old.gridColor != gridColor ||
      old.textColor != textColor;
}
