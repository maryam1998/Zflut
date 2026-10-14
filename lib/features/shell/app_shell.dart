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
    final hasSubtabs = currentGroup.tabs.length > 1;

    return Scaffold(
      backgroundColor: c.paper,
      body: NestedScrollView(
        // ═════════════════════════════════════════════════════════════
        // رفتار هدر دقیقاً مثل وب‌اپ: هدر «جزوِ خودِ صفحه»ست، نه شناور.
        //   • اسکرول به پایین → هدر همراهِ محتوا از بالا بیرون می‌رود
        //   • اسکرول به بالا  → هدر فقط وقتی دیده می‌شود که به بالای صفحه برسی
        // ارتفاعِ هدر دیگر حدسی/ثابت نیست (قبلاً با context.px جور درنمی‌آمد و
        // هدر بریده/پنهان می‌شد)؛ ارتفاعِ واقعیِ ویجت‌ها استفاده می‌شود.
        // ═════════════════════════════════════════════════════════════
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverToBoxAdapter(
            // RepaintBoundary: هدر یک‌بار رسم و به‌صورت لایه جابه‌جا می‌شود،
            // پس موقعِ اسکرول هزینه‌ی رسمِ دوباره ندارد.
            child: RepaintBoundary(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [c.headerTo, c.headerFrom],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
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
          ),
        ],
        // بدون AnimatedSwitcher: در زمانِ فید، دو لیست هم‌زمان به یک
        // PrimaryScrollController وصل می‌شدند (خطا/لگ). روتر هم بدون انیمیشن است.
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
