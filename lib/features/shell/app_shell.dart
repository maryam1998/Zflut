import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/tab_group.dart';
import '../../core/theme/app_theme_colors.dart';
import 'widgets/bottom_nav.dart';
import 'widgets/header_tabs.dart';
import 'widgets/settings_sheet.dart';
import 'widgets/sub_tabs_row.dart';

class AppShell extends ConsumerStatefulWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  @override
  Widget build(BuildContext context) {
    final loc = GoRouterState.of(context).matchedLocation;
    final tabKey = loc.replaceFirst('/', '').replaceAll('-', '');

    // تشخیص گروه فعال از مسیر جاری
    final currentGroup = kTabGroups.firstWhere(
      (g) => g.tabs.any((t) => _normalize(t) == tabKey),
      orElse: () => kTabGroups.first,
    );

    final c = context.appColors;

    return Scaffold(
      backgroundColor: c.paper,
      body: Column(
        children: [
          // ── هدر تک‌ردیفی ──
          HeaderTabs(
            onSettingsTap: () => SettingsSheet.show(context),
          ),

          // ── زیرتب‌ها (فقط اگر گروه > ۱ تب) ──
          if (currentGroup.tabs.length > 1)
            SubTabsRow(
              group: currentGroup,
              activeTabKey: _normalize(tabKey),
              onTabSelected: (tab) => context.go(_routeOf(tab)),
            ),

          // ── محتوا ──
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: child,
              ),
              child: KeyedSubtree(
                key: ValueKey(tabKey),
                child: widget.child,
              ),
            ),
          ),

          // ── Bottom Navigation ──
          AppBottomNav(
            activeGroupKey: currentGroup.key,
            onGroupSelected: (group) {
              context.go(_routeOf(group.tabs.first));
            },
          ),
        ],
      ),
    );
  }

  static String _normalize(String key) => key.replaceAll('-', '');

  String _routeOf(String tabKey) {
    switch (tabKey) {
      case 'conversations': return '/conversations';
      case 'story':         return '/story';
      case 'saved':         return '/saved';
      case 'grammar':       return '/grammar';
      case 'speaking':      return '/speaking';
      case 'words':         return '/words';
      case 'vocabInUse':    return '/vocab-in-use';
      case 'slang':         return '/slang';
      case 'favorites':     return '/favorites';
      case 'review':        return '/review';
      default:              return '/story';
    }
  }
}
