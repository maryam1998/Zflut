import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/tab_group.dart';
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
    final hasSubtabs = currentGroup.tabs.length > 1;

    return Scaffold(
      backgroundColor: c.paper,
      body: Column(
        children: [
          // محتوای اصلی
          Expanded(
            child: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) {
                return [
                  // مثل Hope: هدر، گروه‌ها و زیرتب‌ها بخشی از خودِ محتوا هستند
                  // و همراه اسکرول بالا می‌روند و کاملاً محو می‌شوند؛ فقط وقتی
                  // دوباره به بالای صفحه برسی نمایش داده می‌شوند (نه شناور/snap).
                  SliverToBoxAdapter(
                    child: Column(
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
