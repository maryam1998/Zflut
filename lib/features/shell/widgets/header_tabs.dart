import 'package:flutter/material.dart';

import '../../../app.dart';
import '../../../core/models/tab_group.dart';
import '../../../core/theme/app_theme_colors.dart';

class HeaderTabs extends StatelessWidget {
  final String activeGroupKey;
  final void Function(TabGroup) onGroupSelected;

  const HeaderTabs({
    super.key,
    required this.activeGroupKey,
    required this.onGroupSelected,
  });

  @override
  Widget build(BuildContext context) {
    final L = context.l10n;
    final c = context.appColors;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [c.headerFrom, c.headerTo],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            itemCount: kTabGroups.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final group = kTabGroups[i];
              final active = group.key == activeGroupKey;
              final label = _labelFor(L, group.labelKey);
              return _HeaderChip(
                icon: group.icon,
                label: label,
                active: active,
                headerText: c.headerText,
                onTap: () => onGroupSelected(group),
              );
            },
          ),
        ),
      ),
    );
  }

  static String _labelFor(AppLocalizations L, String key) {
    switch (key) {
      case 'group_talk':
        return L.group_talk;
      case 'group_story':
        return L.group_story;
      case 'group_words':
        return L.group_words;
      case 'group_practice':
        return L.group_practice;
      default:
        return key;
    }
  }
}

class _HeaderChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color headerText;
  final VoidCallback onTap;

  const _HeaderChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.headerText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? Colors.white.withOpacity(0.18) : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 18, color: headerText),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: headerText,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
