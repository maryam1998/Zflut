import 'package:flutter/material.dart';
import '../../../core/theme/app_theme_colors.dart';

class NeuralPathDialog extends StatelessWidget {
  final String word;
  final String langCode;

  const NeuralPathDialog({
    super.key,
    required this.word,
    required this.langCode,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: c.paper,
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // هدر
            Row(
              children: [
                Icon(Icons.hub, color: c.teal, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'مسیر عصبی این لغت',
                    style: TextStyle(
                      color: c.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: c.inkSoft),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // کلمه
            Text(
              word,
              style: TextStyle(
                color: c.gold,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 20),

            // دایره‌های وضعیت (یادگیری / تثبیت)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatusCircle(label: 'یادگیری', count: 0, c: c),
                _StatusCircle(label: 'تثبیت', count: 0, c: c),
              ],
            ),
            const SizedBox(height: 20),

            // رشته‌های ساخته شده
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.paperDark,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.cardBorder),
              ),
              child: Column(
                children: [
                  Text(
                    'رشته‌های ساخته‌شده',
                    style: TextStyle(color: c.inkSoft, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '0',
                    style: TextStyle(
                      color: c.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            Text(
              'هنوز مسیر عصبی برای این لغت شکل نگرفته — همین امروز انجامش بده.',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.inkSoft, fontSize: 12),
            ),
            const SizedBox(height: 20),

            // دکمه ثبت امروز
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  // منطق ثبت تکرار
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('امروز ثبت شد!'),
                        duration: Duration(seconds: 1)),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.teal,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text(
                  '✨ امروز انجام دادم',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // دکمه تقویم
            TextButton(
              onPressed: () {
                // نمایش تقویم
              },
              child: Text(
                'نمایش تقویم این مسیر',
                style: TextStyle(color: c.inkSoft, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCircle extends StatelessWidget {
  final String label;
  final int count;
  final dynamic c;

  const _StatusCircle(
      {required this.label, required this.count, required this.c});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.paperDark,
            border: Border.all(color: c.cardBorder, width: 2),
          ),
          alignment: Alignment.center,
          child: Text(
            '$count',
            style: TextStyle(color: c.ink, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(color: c.inkSoft, fontSize: 12)),
      ],
    );
  }
}
