import 'package:flutter/material.dart';

import '../../core/theme/app_theme_colors.dart';
import 'story_i18n.dart';

/// نوارِ پیشرفته‌ی «صفحه‌ی قبل / بعد» برای نمایشگرِ PDFِ ساخت‌داستان.
///
/// • دکمه‌های گرد: اول ⏮ · قبل ‹ · بعد › · آخر ⏭ (فلش‌ها خودکار با جهتِ RTL/LTR می‌چرخند)
/// • نگه‌داشتنِ طولانیِ ‹ یا › = پرش ۵ صفحه‌ای
/// • لمسِ شمارنده‌ی وسط ← پنجره‌ی «رفتن به صفحه‌ی …»
/// • نوارِ پیشرفتِ باریک (کشیدن/لمس = پرش به همان نقطه)
/// • وقتی صفحه در حالِ بارگذاری است، به‌جای فلش چرخنده نشان می‌دهد
class PdfPageNavBar extends StatelessWidget {
  final int index; // صفحه‌ی فعلی (از ۰)
  final int count;
  final bool busy;
  final ValueChanged<int> onGo;

  const PdfPageNavBar({
    super.key,
    required this.index,
    required this.count,
    required this.busy,
    required this.onGo,
  });

  void _go(int i) {
    if (busy || count <= 0) return;
    final t = i.clamp(0, count - 1);
    if (t != index) onGo(t);
  }

  Future<void> _jumpDialog(BuildContext context) async {
    if (count <= 1) return;
    final c = context.appColors;
    final ctrl = TextEditingController(text: '${index + 1}');
    final res = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.paper,
        title: Text(stTr(ctx, 'gotoTitle', n: count),
            style: TextStyle(color: c.ink, fontSize: 15)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          style: TextStyle(color: c.ink, fontSize: 18),
          onSubmitted: (v) => Navigator.pop(ctx, int.tryParse(v.trim())),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(stTr(ctx, 'cancel'), style: TextStyle(color: c.inkSoft)),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, int.tryParse(ctrl.text.trim())),
            child: Text(stTr(ctx, 'go'), style: TextStyle(color: c.teal)),
          ),
        ],
      ),
    );
    if (res != null) _go(res - 1);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final atFirst = index <= 0;
    final atLast = index >= count - 1;
    final frac = count <= 1 ? 1.0 : (index + 1) / count;

    return Container(
      padding: const EdgeInsets.fromLTRB(6, 3, 6, 3),
      decoration: BoxDecoration(
        color: c.goldSoft.withOpacity(0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.cardBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _NavCircle(
                icon: Icons.first_page_rounded,
                color: c.teal,
                small: true,
                tooltip: stTr(context, 'firstTip'),
                onTap: atFirst || busy ? null : () => _go(0),
              ),
              const SizedBox(width: 6),
              _NavCircle(
                icon: Icons.arrow_back_ios_new_rounded,
                color: c.teal,
                busy: busy,
                tooltip: stTr(context, 'prevTip'),
                onTap: atFirst || busy ? null : () => _go(index - 1),
                onLong: atFirst || busy ? null : () => _go(index - 5),
              ),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _jumpDialog(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(
                            '${index + 1} / $count',
                            style: TextStyle(
                              color: c.ink,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              _NavCircle(
                icon: Icons.arrow_forward_ios_rounded,
                color: c.teal,
                filled: true,
                busy: busy,
                tooltip: stTr(context, 'nextTip'),
                onTap: atLast || busy ? null : () => _go(index + 1),
                onLong: atLast || busy ? null : () => _go(index + 5),
              ),
              const SizedBox(width: 6),
              _NavCircle(
                icon: Icons.last_page_rounded,
                color: c.teal,
                small: true,
                tooltip: stTr(context, 'lastTip'),
                onTap: atLast || busy ? null : () => _go(count - 1),
              ),
            ],
          ),
          const SizedBox(height: 0),
          // نوارِ پیشرفت (با لمس/کشیدن به آن نقطه می‌پرد)
          LayoutBuilder(builder: (ctx, bc) {
            void jumpTo(double dx) {
              if (count <= 1 || bc.maxWidth <= 0) return;
              final ltr = Directionality.of(ctx) == TextDirection.ltr;
              var f = (dx / bc.maxWidth).clamp(0.0, 1.0);
              if (!ltr) f = 1 - f;
              _go((f * count).floor().clamp(0, count - 1));
            }

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => jumpTo(d.localPosition.dx),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: frac,
                    minHeight: 4,
                    backgroundColor: c.cardBorder.withOpacity(0.45),
                    valueColor: AlwaysStoppedAnimation(c.gold),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _NavCircle extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final VoidCallback? onLong;
  final bool filled;
  final bool small;
  final bool busy;
  final String tooltip;

  const _NavCircle({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.tooltip,
    this.onLong,
    this.filled = false,
    this.small = false,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final d = small ? 28.0 : 34.0;
    final fg = filled && enabled ? Colors.white : color;
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: enabled ? 1 : 0.35,
        child: Material(
          color: filled && enabled ? color : color.withOpacity(0.12),
          shape: CircleBorder(
            side: BorderSide(color: color.withOpacity(0.55), width: 1.2),
          ),
          elevation: filled && enabled ? 2 : 0,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            onLongPress: onLong,
            child: SizedBox(
              width: d,
              height: d,
              child: Center(
                child: busy && !small
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: fg),
                      )
                    : Icon(icon, size: small ? 16 : 18, color: fg),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
