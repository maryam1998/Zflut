import 'package:flutter/material.dart';

import '../../../app.dart';
import '../../../core/models/tab_group.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/theme/screen_scale.dart';

/// چهار تبِ اصلی — هم‌عرض، کل عرض صفحه را پر می‌کنند (مثل اسکرین‌شات).
class HeaderTabs extends StatelessWidget {
  final String activeGroupKey;
  final void Function(TabGroup) onGroupSelected;
  final VoidCallback onSettingsTap;

  const HeaderTabs({
    super.key,
    required this.activeGroupKey,
    required this.onGroupSelected,
    required this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    final L = context.l10n;
    final c = context.appColors;

    final children = <Widget>[];
    for (var i = 0; i < kTabGroups.length; i++) {
      final group = kTabGroups[i];
      if (i > 0) children.add(SizedBox(width: context.px(13)));
      children.add(
        Expanded(
          child: _HeaderChip(
            // تب‌های هوش مصنوعی آیکن ستاره‌ای می‌گیرند (به‌جای بج AI)
            icon: group.isAiPowered ? Icons.auto_awesome : group.icon,
            label: _labelFor(L, group.labelKey),
            active: group.key == activeGroupKey,
            c: c,
            onTap: () => onGroupSelected(group),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.px(34)),
      child: SizedBox(
        height: context.px(92),
        child: Row(children: children),
      ),
    );
  }

  static String _labelFor(AppLocalizations L, String key) {
    switch (key) {
      case 'group_talk':     return L.group_talk;
      case 'group_story':    return L.group_story;
      case 'group_words':    return L.group_words;
      case 'group_practice': return L.group_practice;
      default:               return key;
    }
  }
}

class _HeaderChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final dynamic c;
  final VoidCallback onTap;

  const _HeaderChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.c,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color fg = active ? c.headerText as Color : c.ink as Color;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(horizontal: context.px(14)),
        decoration: BoxDecoration(
          // فعال: تیره (headerTo)، غیرفعال: کرمِ تیره (paperDark)
          color: active ? c.headerTo as Color : c.paperDark as Color,
          borderRadius: BorderRadius.circular(999),
        ),
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: context.px(40), color: fg),
              SizedBox(width: context.px(12)),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: fg,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w700,
                  fontSize: context.px(31),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
