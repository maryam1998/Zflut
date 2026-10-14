import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/tab_group.dart';
import '../../core/providers/language_selection_provider.dart';
import '../../core/theme/app_theme_colors.dart';
import '../grammar/widgets/practice_sheet.dart';
import 'widgets/account_header.dart';
import 'widgets/header_tabs.dart';
import 'widgets/language_picker.dart';
import 'widgets/player_bar.dart';
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

    final currentGroup = kTabGroups.firstWhere(
      (g) => g.tabs.any((t) => _normalize(t) == tabKey),
      orElse: () => kTabGroups.first,
    );

    final c = context.appColors;
    final sel = ref.watch(languageSelectionProvider);
    final hasSubtabs = currentGroup.tabs.length > 1;
    final hasChips = sel.targets.length > 1;

    final headerHeight = 56.0 +
        168.0 +
        (hasChips ? 66.0 : 0.0) +
        60.0 +
        (hasSubtabs ? 48.0 : 0.0);

    return Scaffold(
      backgroundColor: c.paper,
      body: Column(
        children: [
          // محتوای اصلی
          Expanded(
            child: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) {
                return [
                  SliverAppBar(
                    floating: true,
                    snap: true,
                    pinned: false,
                    automaticallyImplyLeading: false,
                    expandedHeight: headerHeight,
                    toolbarHeight: headerHeight,
                    backgroundColor: Colors.transparent,
                    surfaceTintColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    elevation: 0,
                    scrolledUnderElevation: 0,
                    flexibleSpace: FlexibleSpaceBar(
                      collapseMode: CollapseMode.none,
                      background: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AccountHeader(
                            onMenuTap: () => SettingsSheet.show(context),
                            onAvatarTap: () => SettingsSheet.show(context),
                            userName: null,
                          ),
                          const LanguagePicker(),
                          HeaderTabs(
                            activeGroupKey: currentGroup.key,
                            onGroupSelected: (group) {
                              context.go(_routeOf(group.tabs.first));
                            },
                            onSettingsTap: () => SettingsSheet.show(context),
                          ),
                          if (hasSubtabs)
                            SubTabsRow(
                              group: currentGroup,
                              activeTabKey: _normalize(tabKey),
                              onTabSelected: (tab) => context.go(_routeOf(tab)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ];
              },
              body: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: KeyedSubtree(
                  key: ValueKey(tabKey),
                  child: widget.child,
                ),
              ),
            ),
          ),

          // ═══ پنل تمرین گرامر — همیشه visible، بالای پلیر ═══
          const PracticeSheet(),

          // ═══ پلیر پایین صفحه ═══
          const PlayerBar(),
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
