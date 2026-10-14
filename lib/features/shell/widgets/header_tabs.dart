import 'package:flutter/material.dart';

import '../../../app.dart';
import '../../../core/models/tab_group.dart';
import '../../../core/theme/app_theme_colors.dart';

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

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [c.headerFrom, c.headerTo],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: c.headerTo.withOpacity(0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── ردیف بالایی: لوگو + عنوان + تنظیمات ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: onSettingsTap,
                    icon: Icon(Icons.settings_outlined, color: c.headerText),
                    tooltip: 'Settings',
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: c.headerText.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.translate,
                          size: 18,
                          color: c.headerText,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'LingoLearn',
                        style: TextStyle(
                          color: c.headerText,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── ردیف پایینی: گروه‌ها ──
            SizedBox(
              height: 52,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                itemCount: kTabGroups.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final group = kTabGroups[i];
                  final active = group.key == activeGroupKey;
                  return _HeaderChip(
                    icon: group.icon,
                    label: _labelFor(L, group.labelKey),
                    active: active,
                    headerText: c.headerText,
                    onTap: () => onGroupSelected(group),
                  );
                },
              ),
            ),
          ],
        ),
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: active
            ? Colors.white.withOpacity(0.20)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active
              ? Colors.white.withOpacity(0.35)
              : Colors.transparent,
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
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
      ),
    );
  }
}
