import 'package:flutter/material.dart';

import '../../core/book/page_translate_engine.dart';
import '../../core/theme/app_theme_colors.dart';

/// نوارِ کنترلِ ترجمه‌ی کتاب: پیشرفتِ کل، شروع/توقف، مکث/ادامه،
/// «ترجمه‌ی کلِ کتاب در پس‌زمینه» و تلاشِ دوباره برای صفحه‌های ناموفق.
/// فقط خودش بازسازی می‌شود (AnimatedBuilder) — کلِ تبِ داستان rebuild نمی‌شود.
class BookTranslateBar extends StatelessWidget {
  final PageTranslateEngine engine;
  final int currentPage;
  const BookTranslateBar({
    super.key,
    required this.engine,
    required this.currentPage,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return AnimatedBuilder(
      animation: engine,
      builder: (ctx, _) {
        final total = engine.pageCount;
        final settled = engine.settledCount;
        final failed = engine.failedCount;
        final frac = total <= 0 ? 0.0 : settled / total;
        final active = engine.active;
        final paused = engine.paused;
        final status = engine.statusOf(currentPage);
        final title = !active
            ? '🌐 ترجمه‌ی عکسیِ صفحه‌ها'
            : paused
                ? '⏸ متوقفِ موقت'
                : engine.workingPage != null
                    ? '⏳ در حال ترجمه‌ی صفحه‌ی ${engine.workingPage! + 1}'
                    : '✓ آماده‌ی ترجمه‌ی صفحه‌ی بعد';

        Widget btn(String label, Color color, VoidCallback? onTap) {
          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(label,
                  style: TextStyle(
                      color: onTap == null ? c.inkSoft : color,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
          decoration: BoxDecoration(
            color: c.goldSoft.withOpacity(0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(title,
                        style: TextStyle(
                            color: c.ink,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800)),
                  ),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text('$settled / $total',
                        style: TextStyle(color: c.inkSoft, fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: frac,
                  minHeight: 6,
                  backgroundColor: c.cardBorder,
                  color: c.teal,
                ),
              ),
              if (engine.note.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(engine.note,
                      style: TextStyle(color: c.inkSoft, fontSize: 11.5)),
                ),
              if (status == PageStatus.failed)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text('ترجمه‌ی این صفحه انجام نشد',
                      style: TextStyle(color: c.rose, fontSize: 11.5)),
                ),
              Wrap(
                alignment: WrapAlignment.start,
                children: [
                  if (!active)
                    btn('شروع (از همین صفحه)', c.teal,
                        () => engine.activate(page: currentPage))
                  else
                    btn('⏹ توقف', c.rose, engine.deactivate),
                  if (active && !paused)
                    btn('⏸ مکث', c.teal, engine.pause),
                  if (active && paused)
                    btn('▶ ادامه', c.teal, engine.resume),
                  btn(
                    engine.wholeBook
                        ? '☑ کلِ کتاب (پس‌زمینه)'
                        : '☐ کلِ کتاب (پس‌زمینه)',
                    c.teal,
                    () => engine.setWholeBook(!engine.wholeBook),
                  ),
                  if (failed > 0)
                    btn('↻ تلاشِ دوباره ($failed صفحه)', c.rose,
                        engine.retryFailed),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
