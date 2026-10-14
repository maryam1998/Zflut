import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/tab_group.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/screen_scale.dart';
import 'widgets/account_header.dart';
import 'widgets/header_tabs.dart';
import 'widgets/language_picker.dart';
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

    // کل هدر (حساب، زبان‌ها، تب‌های اصلی، زیرتب‌ها) همراه محتوا اسکرول می‌شود
    // تا فضای بیشتری برای لیست بماند. NestedScrollView: ابتدا هدر بالا می‌رود،
    // بعد لیستِ تب اسکرول می‌شود (و برعکس).
    return Scaffold(
      backgroundColor: c.paper,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverToBoxAdapter(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [c.headerTo, c.headerFrom],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AccountHeader(
                    onMenuTap: () => SettingsSheet.show(context),
                    onAvatarTap: () => SettingsSheet.show(context),
                  ),
                  const LanguagePicker(),
                  HeaderTabs(
                    activeGroupKey: currentGroup.key,
                    onGroupSelected: (group) {
                      context.go(_routeOf(group.tabs.first));
                    },
                    onSettingsTap: () => SettingsSheet.show(context),
                  ),
                  SizedBox(height: context.px(42)),
                ],
              ),
            ),
          ),
          if (currentGroup.tabs.length > 1)
            SliverToBoxAdapter(
              child: SubTabsRow(
                group: currentGroup,
                activeTabKey: _normalize(tabKey),
                onTabSelected: (tab) => context.go(_routeOf(tab)),
              ),
            ),
        ],
        // بدون AnimatedSwitcher: دو تب نباید هم‌زمان به یک
        // PrimaryScrollController وصل شوند.
        body: KeyedSubtree(
          key: ValueKey(tabKey),
          child: widget.child,
        ),
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
