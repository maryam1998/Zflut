import 'package:flutter/material.dart';

import '../../core/theme/app_theme_colors.dart';

class PlaceholderTab extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const PlaceholderTab({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;

    return Stack(
      children: [
        // الگوی نقطه‌چین ظریف به‌عنوان پس‌زمینه
        Positioned.fill(
          child: CustomPaint(
            painter: _DotsPainter(color: c.inkSoft.withOpacity(0.08)),
          ),
        ),

        Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // آیکون دایره‌ای با گرادیانت طلایی
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        c.gold.withOpacity(0.18),
                        c.teal.withOpacity(0.12),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(
                      color: c.gold.withOpacity(0.35),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(icon, size: 42, color: c.gold),
                ),
                const SizedBox(height: 24),

                // عنوان
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    fontFamily: Theme.of(context).textTheme.titleLarge?.fontFamily,
                  ),
                ),
                const SizedBox(height: 10),

                // توضیح
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: c.inkSoft,
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 24),

                // نشان «به‌زودی»
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: c.gold.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: c.gold.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome, size: 14, color: c.gold),
                      const SizedBox(width: 6),
                      Text(
                        'به‌زودی',
                        style: TextStyle(
                          color: c.gold,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// پس‌زمینه‌ی نقطه‌چینِ ظریف.
class _DotsPainter extends CustomPainter {
  final Color color;
  _DotsPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const spacing = 24.0;
    const radius = 1.2;

    for (double y = 0; y < size.height; y += spacing) {
      for (double x = 0; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) => old.color != color;
}
