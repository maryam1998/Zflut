import 'package:flutter/material.dart';

@immutable
class TabGroup {
  final String key;
  final String labelKey;
  final IconData icon;
  final List<String> tabs;
  final bool isAiPowered;   // 👈 جدید

  const TabGroup({
    required this.key,
    required this.labelKey,
    required this.icon,
    required this.tabs,
    this.isAiPowered = false,
  });
}

const List<TabGroup> kTabGroups = [
  TabGroup(
    key: 'talk',
    labelKey: 'group_talk',
    icon: Icons.chat_bubble_outline,
    tabs: ['conversations', 'speaking', 'grammar'],
  ),
  TabGroup(
    key: 'story',
    labelKey: 'group_story',
    icon: Icons.feather,              // 👈 بهتر از Sparkles
    tabs: ['story', 'saved'],
    isAiPowered: true,                // 👈 AI دارد
  ),
  TabGroup(
    key: 'words',
    labelKey: 'group_words',
    icon: Icons.menu_book_outlined,
    tabs: ['words', 'vocabInUse', 'slang', 'favorites'],
  ),
  TabGroup(
    key: 'practice',
    labelKey: 'group_practice',
    icon: Icons.repeat,               // 👈 بهتر از Boxes
    tabs: ['review'],
  ),
];
