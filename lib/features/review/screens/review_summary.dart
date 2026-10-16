import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/neural/neural_dates.dart' show faDigits;
import '../../../core/theme/app_theme_colors.dart';
import '../providers/review_provider.dart';
import '../providers/review_session_provider.dart';
import 'review_session.dart';

/// خلاصه‌ی پایان جلسه.
class ReviewSummaryScreen extends ConsumerWidget {
  const ReviewSummaryScreen({super.key});

  static String _duration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    if (m == 0) return '${faDigits(s)} ثانیه';
    return '${faDigits(m)} دقیقه و ${faDigits(s)} ثانیه';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final s = ref.watch(reviewSessionProvider);
    final due = ref.watch(dueReviewProvider);
    final total = s.correct + s.wrong;

    void again() {
      if (due.isEmpty) return;
      ref.read(reviewSessionProvider.notifier).start(due);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const ReviewSessionScreen()),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: c.paper,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Spacer(),
                const Text('🎉', style: TextStyle(fontSize: 64)),
                const SizedBox(height: 12),
                Text(
                  'آفرین! جلسه تمام شد',
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${faDigits(total)} لغت در ${_duration(s.elapsed)}',
                  style: TextStyle(color: c.inkSoft, fontSize: 14),
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: _Stat(
                        label: 'درست',
                        value: s.correct,
                        color: const Color(0xFF3F9B72),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Stat(
                        label: 'غلط',
                        value: s.wrong,
                        color: c.rose,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Stat(
                        label: 'یاد گرفته',
                        value: s.learned,
                        color: c.gold,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: due.isEmpty ? null : again,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: c.gold,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      due.isEmpty
                          ? 'لغتی برای مرور دوباره نمانده'
                          : 'مرور دوباره (${faDigits(due.length)})',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.ink,
                      side: BorderSide(color: c.cardBorder),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'بازگشت به داشبورد',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _Stat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Text(
            faDigits(value),
            style: TextStyle(
              color: c.ink,
              fontSize: 30,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: c.inkSoft, fontSize: 13)),
        ],
      ),
    );
  }
}
