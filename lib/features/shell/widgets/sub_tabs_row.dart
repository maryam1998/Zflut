import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app.dart';
import '../../../core/models/tab_group.dart';
import '../../../core/models/tab_meta.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/theme/screen_scale.dart';

class SubTabsRow extends StatelessWidget {
  final TabGroup group;
  final String activeTabKey;
  final void Function(String tabKey) onTabSelected;

  const SubTabsRow({
    super.key,
    required this.group,
    required this.activeTabKey,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    final L = context.l10n;
    final c = context.appColors;

    return Container(
      color: c.paperDark,
      height: context.px(140),
      // همه‌ی زیرتب‌ها همیشه کاملاً در صفحه دیده می‌شوند (بدون اسکرول افقی):
      // هر تب سهمِ مساوی می‌گیرد و اگر جا کم بود، محتوایش کوچک می‌شود.
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: context.px(20),
          vertical: context.px(26),
        ),
        child: LayoutBuilder(builder: (ctx, box) {
          final gap = context.px(10);
          final n = group.tabs.length;
          final chipW = (box.maxWidth - gap * (n - 1)) / n;
          // پهنای قابل‌استفاده‌ی داخل هر چیپ (منهای پدینگ و حاشیه)
          final inner = chipW - context.px(14) * 2 - context.px(2) * 2;
          final base = DefaultTextStyle.of(ctx).style;

          // طبیعی‌ترین پهنای محتوای هر تب؛ یک مقیاسِ مشترک برای همه‌ی تب‌ها
          // انتخاب می‌شود تا اندازه‌ی آیکون/متن در همه یکسان بماند.
          var scale = 1.0;
          for (final key in group.tabs) {
            final meta = kTabMeta[key]!;
            final tp = TextPainter(
              text: TextSpan(
                text: _labelFor(L, meta.labelKey),
                style: base.copyWith(
                  fontSize: context.px(31),
                  fontWeight: FontWeight.w700,
                ),
              ),
              textDirection: Directionality.of(ctx),
              maxLines: 1,
            )..layout();
            var w = context.px(38) + context.px(14) + tp.width;
            if (meta.isAiPowered) {
              final ai = TextPainter(
                text: TextSpan(
                  text: 'AI',
                  style: base.copyWith(
                    fontSize: context.px(18),
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
                textDirection: TextDirection.ltr,
                maxLines: 1,
              )..layout();
              w += context.px(10) + ai.width + context.px(10) * 2;
            }
            if (w > inner) scale = math.min(scale, inner / w);
          }
          if (scale < 1) scale *= 0.97; // کمی فاصله‌ی اطمینان

          return Row(
            children: [
              for (var i = 0; i < n; i++) ...[
                if (i > 0) SizedBox(width: gap),
                Expanded(
                  child: Builder(builder: (_) {
                    final key = group.tabs[i];
                    final meta = kTabMeta[key]!;
                    return _SubChip(
                      icon: meta.icon,
                      label: _labelFor(L, meta.labelKey),
                      active: key == activeTabKey,
                      isAi: meta.isAiPowered,
                      scale: scale,
                      c: c,
                      onTap: () => onTabSelected(key),
                    );
                  }),
                ),
              ],
            ],
          );
        }),
      ),
    );
  }

  static String _labelFor(AppLocalizations L, String key) {
    switch (key) {
      case 'tab_conversations': return L.tab_conversations;
      case 'tab_story':         return L.tab_story;
      case 'tab_saved':         return L.tab_saved;
      case 'tab_grammar':       return L.tab_grammar;
      case 'tab_speaking':      return L.tab_speaking;
      case 'tab_words':         return L.tab_words;
      case 'tab_vocab_in_use':  return L.tab_vocab_in_use;
      case 'tab_slang':         return L.tab_slang;
      case 'tab_favorites':     return L.tab_favorites;
      case 'tab_review':        return L.tab_review;
      default:                  return key;
    }
  }
}

class _SubChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final bool isAi;
  final double scale;
  final dynamic c;
  final VoidCallback onTap;

  const _SubChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.isAi,
    required this.scale,
    required this.c,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // مثل اسکرین‌شات: نوار کرم (paperDark)؛ تبِ غیرفعال تخت و بدون پس‌زمینه،
    // تبِ فعال یک پیلِ کرمِ روشن‌تر با حاشیهٔ طلایی و آیکونِ طلایی.
    final Color ink = c.ink as Color;
    final Color soft = c.inkSoft as Color;
    final Color gold = c.gold as Color;
    final Color fg = active ? ink : soft;
    final Color iconColor = active ? gold : soft;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: active ? c.paper as Color : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active ? gold : Colors.transparent,
          width: context.px(2),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: context.px(14)),
            child: Center(
             child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: context.px(38) * scale, color: iconColor),
                SizedBox(width: context.px(14) * scale),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: context.px(31) * scale,
                    color: fg,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
                if (isAi) ...[
                  SizedBox(width: context.px(10) * scale),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: context.px(10) * scale,
                      vertical: context.px(3) * scale,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF8B7CF6), Color(0xFF6366F1)],
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'AI',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: context.px(18) * scale,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ],
              ],
              ),
             ),
            ),
          ),
        ),
      ),
    );
  }
}
