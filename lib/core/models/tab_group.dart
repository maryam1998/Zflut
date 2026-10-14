import 'package:flutter/material.dart';

/// معادلِ TAB_GROUPS در appPrefs.js — ۴ گروه.
@immutable
class TabGroup {
  final String key;
  final String labelKey;         // کلید ARB
  final IconData icon;
  final List<String> tabs;       // کلیدهای TabMeta

  const TabGroup({
    required this.key,
    required this.labelKey,
    required this.icon,
    required this.tabs,
  });
}

const List<TabGroup> kTabGroups = [
  TabGroup(
    key: 'talk',
    labelKey: 'group_talk',
    icon: Icons.forum,
    tabs: ['conversations', 'speaking', 'grammar'],
  ),
  TabGroup(
    key: 'story',
    labelKey: 'group_story',
    icon: Icons.auto_awesome,
    tabs: ['story', 'saved'],
  ),
  TabGroup(
    key: 'words',
    labelKey: 'group_words',
    icon: Icons.menu_book,
    tabs: ['words', 'vocabInUse', 'slang', 'favorites'],
  ),
  TabGroup(
    key: 'practice',
    labelKey: 'group_practice',
    icon: Icons.inventory_2,
    tabs: ['review'],
  ),
];

TabGroup groupOfTab(String tabKey) {
  return kTabGroups.firstWhere(
    (g) => g.tabs.contains(tabKey),
    orElse: () => kTabGroups.first,
  );
}
