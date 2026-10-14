import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/tab_group.dart';
import '../../core/theme/app_theme_colors.dart';
import 'widgets/header_tabs.dart';
import 'widgets/sub_tabs_row.dart';

/// قالب اصلیِ بعد از ورود — معادلِ PhrasebookMain.
/// فقط ساختار هدر + ردیف زیرتب‌ها + محتوای تب جاری.
/// پلیر پایین، ماسکات، انتخاب متن، و بقیه‌ی موارد سراسری در فازهای بعدی.
class AppShell extends ConsumerStatefulWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  // گروه فعال از URL جاری استنباط می‌شود.
  String _activeGroupKey = kTabGroups.first.key;

  @override
  Widget build(BuildContext context) {
    final loc = GoRouterState.of(context).matchedLocation;
    final tabKey = _normalize(loc.replaceFirst('/', ''));

    // گروه جاری از tabKey.
    final currentGroup = kTabGroups.firstWhere(
      (g) => g.tabs.any((t) => _normalize(t) == tabKey),
      orElse: () => kTabGroups.first,
    );
    _activeGroupKey = currentGroup.key;

    final c = context.appColors;

    return Scaffold(
      backgroundColor: c.paper,
      body: Column(
        children: [
          HeaderTabs(
            activeGroupKey: _activeGroupKey,
            onGroupSelected: (group) {
              // اولین تبِ گروه را باز می‌کنیم.
              final firstTab = group.tabs.first;
              context.go(_routeOf(firstTab));
            },
          ),
          if (currentGroup.tabs.length > 1)
            SubTabsRow(
              group: currentGroup,
              activeTabKey: currentGroup.tabs.firstWhere(
                (t) => _normalize(t) == tabKey,
                orElse: () => currentGroup.tabs.first,
              ),
              onTabSelected: (tab) => context.go(_routeOf(tab)),
            ),
          Expanded(child: widget.child),
        ],
      ),
    );
  }

  static String _normalize(String key) => key.replaceAll('-', '').toLowerCase();

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
