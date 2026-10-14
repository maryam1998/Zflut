import 'package:flutter/material.dart';

/// معادلِ TAB_META در appPrefs.js.
@immutable
class TabMeta {
  final String key;
  final String labelKey;   // کلید ARB
  final IconData icon;
  final String route;      // برای go_router

  const TabMeta({
    required this.key,
    required this.labelKey,
    required this.icon,
    required this.route,
  });
}

const List<TabMeta> kTabMetaList = [
  TabMeta(key: 'conversations', labelKey: 'tab_conversations', icon: Icons.forum,          route: '/conversations'),
  TabMeta(key: 'story',         labelKey: 'tab_story',         icon: Icons.auto_awesome,   route: '/story'),
  TabMeta(key: 'saved',         labelKey: 'tab_saved',         icon: Icons.bookmark,       route: '/saved'),
  TabMeta(key: 'grammar',       labelKey: 'tab_grammar',       icon: Icons.spellcheck,     route: '/grammar'),
  TabMeta(key: 'speaking',      labelKey: 'tab_speaking',      icon: Icons.mic,            route: '/speaking'),
  TabMeta(key: 'words',         labelKey: 'tab_words',         icon: Icons.menu_book,      route: '/words'),
  TabMeta(key: 'vocabInUse',    labelKey: 'tab_vocab_in_use',  icon: Icons.layers,         route: '/vocab-in-use'),
  TabMeta(key: 'slang',         labelKey: 'tab_slang',         icon: Icons.format_quote,   route: '/slang'),
  TabMeta(key: 'favorites',     labelKey: 'tab_favorites',     icon: Icons.favorite,       route: '/favorites'),
  TabMeta(key: 'review',        labelKey: 'tab_review',        icon: Icons.inventory_2,    route: '/review'),
];

final Map<String, TabMeta> kTabMeta = {
  for (final m in kTabMetaList) m.key: m,
};
