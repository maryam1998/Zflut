import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/tab_group.dart';
import '../../core/theme/app_theme_colors.dart';
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

    return Scaffold(
      backgroundColor: c.paper,
      // ═══════════════════════════════════════════════════════════════
      // NestedScrollView: هدر با اسکرول کاربر می‌ره بالا، با برگشت به بالا
      // دوباره ظاهر می‌شه. دقیقاً همون رفتاری که در نسخه‌ی وب داشتی.
      //
      // • headerSliverBuilder → همه‌ی هدر (حساب + زبان + تب‌ها)
      // • body → محتوای تب که اسکرول داخلی خودش رو داره
      //
      // محتوای هر تب (مثل WordsTab) باید یک CustomScrollView / ListView
      // باشه که از PrimaryScrollController استفاده می‌کنه (پیش‌فرض).
      // ═══════════════════════════════════════════════════════════════
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverToBoxAdapter(
              child: AccountHeader(
                onMenuTap: () => SettingsSheet.show(context),
                onAvatarTap: () => SettingsSheet.show(context),
              ),
            ),
            const SliverToBoxAdapter(
              child: LanguagePicker(),
            ),
            SliverToBoxAdapter(
              child: HeaderTabs(
                activeGroupKey: currentGroup.key,
                onGroupSelected: (group) {
                  context.go(_routeOf(group.tabs.first));
                },
                onSettingsTap: () => SettingsSheet.show(context),
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
            // پایین‌ترین لایه‌ی هدر یک خط جداکننده‌ی ظریف برای وضوح
            SliverToBoxAdapter(
              child: Container(
                height: 1,
                color: c.cardBorder.withOpacity(0.5),
              ),
            ),
          ];
        },
        body: AnimatedSwitcher(
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
