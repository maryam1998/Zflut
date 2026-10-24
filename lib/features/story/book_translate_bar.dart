import 'package:flutter/material.dart';

import '../../core/book/page_translate_engine.dart';
import '../../core/theme/app_theme_colors.dart';
import 'story_i18n.dart';

/// نوارِ کنترلِ ترجمه‌ی کتاب (پیشرفته): پیشرفتِ کل + دکمه‌های گردِ ▶ شروع/ادامه · ⏸ مکث · ⏹ توقف.
///
///  • ⏹ توقف: ترجمه‌ی خودکار می‌ایستد و محلِ توقف یادش می‌ماند؛
///  • ▶ ادامه: از همان‌جا (اولین صفحه‌ی ناتمام) ترجمه ادامه پیدا می‌کند و نمایشگر
///    هم به همان صفحه می‌رود ([onJump]) تا ادامه‌ی ترجمه‌ی عکسی را ببینی.
/// فقط خودش بازسازی می‌شود (AnimatedBuilder) — کلِ تبِ داستان rebuild نمی‌شود.
class BookTranslateBar extends StatelessWidget {
  final PageTranslateEngine engine;
  final int currentPage;

  /// بعد از «ادامه»: نمایشگر را به این صفحه ببر (از صفر).
  final ValueChanged<int>? onJump;

  const BookTranslateBar({
    super.key,
    required this.engine,
    required this.currentPage,
    this.onJump,
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
        final resumeAt = engine.resumePage;
        final canResume = engine.canResume;
        final allDone = total > 0 && settled >= total;

        final title = !active
            ? (canResume
                ? stTr(ctx, 'barStopped', n: resumeAt! + 1)
                : allDone
                    ? stTr(ctx, 'barAllDone')
                    : stTr(ctx, 'barIdle'))
            : paused
                ? stTr(ctx, 'barPaused')
                : engine.workingPage != null
                    ? stTr(ctx, 'barWorking', n: engine.workingPage! + 1)
                    : stTr(ctx, 'barReady');

        // یادداشتِ موتور (فارسیِ ثابت) → زبانِ رابط؛ «در حال ترجمه…» تکراریِ عنوان است
        String noteText() {
          final n = engine.note;
          if (n.startsWith('در حال ترجمه')) return '';
          if (n.startsWith('ترجمه‌ی همه‌ی صفحه‌ها')) return stTr(ctx, 'noteAllDone');
          if (n.startsWith('چند صفحه‌ی پشت‌سرهم')) return stTr(ctx, 'noteNet');
          if (n == 'متوقف شد') return stTr(ctx, 'noteStopped');
          return n;
        }

        final noteStr = noteText();

        // دکمه‌ی اصلی (بزرگ): شروع / ادامه / مکث
        late final IconData mainIcon;
        late final String mainLabel;
        late final VoidCallback? mainTap;
        if (!active && canResume) {
          mainIcon = Icons.play_arrow_rounded;
          mainLabel = stTr(ctx, 'resumeFrom', n: resumeAt! + 1);
          mainTap = () {
            engine.activate(page: resumeAt);
            onJump?.call(resumeAt);
          };
        } else if (!active) {
          mainIcon = Icons.play_arrow_rounded;
          mainLabel = allDone ? stTr(ctx, 'retranslate') : stTr(ctx, 'startHere');
          mainTap = allDone ? null : () => engine.activate(page: currentPage);
        } else if (paused) {
          mainIcon = Icons.play_arrow_rounded;
          mainLabel = stTr(ctx, 'resume');
          mainTap = engine.resume;
        } else {
          mainIcon = Icons.pause_rounded;
          mainLabel = stTr(ctx, 'pause');
          mainTap = engine.pause;
        }

        return Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          decoration: BoxDecoration(
            color: c.goldSoft.withOpacity(0.5),
            borderRadius: BorderRadius.circular(14),
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
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: frac,
                  minHeight: 4,
                  backgroundColor: c.cardBorder,
                  color: c.teal,
                ),
              ),
              if (noteStr.isNotEmpty && active)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(noteStr,
                      style: TextStyle(color: c.inkSoft, fontSize: 11.5)),
                ),
              if (status == PageStatus.failed)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(stTr(ctx, 'pageFailed'),
                      style: TextStyle(color: c.rose, fontSize: 11.5)),
                ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _RoundBtn(
                    icon: mainIcon,
                    color: c.gold,
                    filled: true,
                    size: 38,
                    busy: active && !paused && engine.workingPage != null,
                    tooltip: mainLabel,
                    onTap: mainTap,
                  ),
                  const SizedBox(width: 8),
                  _RoundBtn(
                    icon: Icons.stop_rounded,
                    color: c.rose,
                    size: 34,
                    tooltip: stTr(ctx, 'stopTip'),
                    onTap: active ? engine.deactivate : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      mainLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: c.ink,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _PillBtn(
                    icon: engine.wholeBook
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    label: stTr(ctx, 'wholeBook'),
                    color: c.teal,
                    on: engine.wholeBook,
                    onTap: () => engine.setWholeBook(!engine.wholeBook),
                  ),
                  if (failed > 0)
                    _PillBtn(
                      icon: Icons.refresh_rounded,
                      label: stTr(ctx, 'retry', n: failed),
                      color: c.rose,
                      on: false,
                      onTap: engine.retryFailed,
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool filled;
  final bool busy;
  final double size;
  final String tooltip;
  final VoidCallback? onTap;

  const _RoundBtn({
    required this.icon,
    required this.color,
    required this.size,
    required this.tooltip,
    required this.onTap,
    this.filled = false,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final fg = filled && enabled ? Colors.white : color;
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: enabled ? 1 : 0.38,
        child: Material(
          color: filled && enabled ? color : color.withOpacity(0.12),
          shape: CircleBorder(
              side: BorderSide(color: color.withOpacity(0.6), width: 1.3)),
          elevation: filled && enabled ? 3 : 0,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: size,
              height: size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (busy)
                    SizedBox(
                      width: size - 8,
                      height: size - 8,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white.withOpacity(0.85)),
                    ),
                  Icon(icon, size: size * 0.55, color: fg),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PillBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool on;
  final VoidCallback onTap;

  const _PillBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.on,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: on ? color.withOpacity(0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withOpacity(0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
