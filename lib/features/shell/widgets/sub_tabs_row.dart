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
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsetsDirectional.fromSTEB(
          context.px(34),
          context.px(26),
          context.px(17),
          context.px(26),
        ),
        itemCount: group.tabs.length,
        separatorBuilder: (_, __) => SizedBox(width: context.px(17)),
        itemBuilder: (_, i) {
          final key = group.tabs[i];
          final meta = kTabMeta[key]!;
          final active = key == activeTabKey;
          return _SubChip(
            icon: meta.icon,
            label: _labelFor(L, meta.labelKey),
            active: active,
            isAi: meta.isAiPowered,
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
  final bool isAi;
  final dynamic c;
  final VoidCallback onTap;

  const _SubChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.isAi,
    required this.c,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color ink = c.ink as Color;
    final Color fg = active ? c.headerText as Color : ink;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: active
            ? c.headerTo as Color
            : (c.paper as Color).withOpacity(0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active
              ? c.headerTo as Color
              : (c.cardBorder as Color).withOpacity(0.7),
          width: context.px(2),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: context.px(34)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: context.px(38), color: fg),
                SizedBox(width: context.px(14)),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: context.px(31),
                    color: fg,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
                if (isAi) ...[
                  SizedBox(width: context.px(10)),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: context.px(10),
                      vertical: context.px(3),
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
                        fontSize: context.px(18),
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
    );
  }
}
