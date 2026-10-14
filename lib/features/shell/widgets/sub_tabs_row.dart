import 'package:flutter/material.dart';

import '../../../app.dart';
import '../../../core/models/tab_group.dart';
import '../../../core/models/tab_meta.dart';
import '../../../core/theme/app_theme_colors.dart';

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
      decoration: BoxDecoration(
        color: c.paperDark,
        border: Border(
          bottom: BorderSide(color: c.cardBorder, width: 1),
        ),
      ),
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        itemCount: group.tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final key = group.tabs[i];
          final meta = kTabMeta[key]!;
          final active = key == activeTabKey;
          return _SubChip(
            icon: meta.icon,
            label: _labelFor(L, meta.labelKey),
            active: active,
            c: c,
            onTap: () => onTabSelected(key),
          );
        },
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
  final dynamic c;
  final VoidCallback onTap;

  const _SubChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.c,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: active ? c.paper : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active ? c.gold.withOpacity(0.55) : Colors.transparent,
          width: 1.2,
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: c.gold.withOpacity(0.15),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 15,
                  color: active ? c.gold : c.inkSoft,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: active ? c.ink : c.inkSoft,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
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
