// ═══ فایل کامل app_shell.dart ═══

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
      body: Stack(
        children: [
          // ═══ محتوای اصلی ═══
          NestedScrollView(
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

          // ═══ پنل تمرین گرامر — شناور روی همه‌چیز ═══
          PracticeSheet(
            onClose: () {},
            child: const _GrammarPracticeContent(),
          ),
        ],
      ),
      // ═══ پلیر پایین ═══
      bottomNavigationBar: const PlayerBar(),
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

// ═══════════════════════════════════════════════════════════════════
// محتوای پنل تمرین گرامر — توی PracticeSheet رندر می‌شه
// ═══════════════════════════════════════════════════════════════════
class _GrammarPracticeContent extends StatefulWidget {
  const _GrammarPracticeContent();

  @override
  State<_GrammarPracticeContent> createState() =>
      _GrammarPracticeContentState();
}

class _GrammarPracticeContentState extends State<_GrammarPracticeContent> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;

    return Container(
      color: c.paper,
      child: Column(
        children: [
          // توضیحات
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'یه جمله به فرانسوی بنویس؛ اگر غلط بود اصلاحش می‌کنم و کلمه‌به‌کلمه گرامرش رو توضیح می‌دم. '
              'یا هر سوال گرامری که داری — چه درباره‌ی این جمله، چه یه سوال کاملاً جدا — همین‌جا بپرس '
              'تا مثل یه معلم زبان جواب بدم.',
              style: TextStyle(color: c.inkSoft, fontSize: 12, height: 1.7),
              textAlign: TextAlign.right,
            ),
          ),

          // فضای پیام‌ها (فعلاً خالی)
          const Spacer(),

          // ═══ کادر ارسال ═══
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Container(
              decoration: BoxDecoration(
                color: c.paper,
                border: Border.all(color: c.teal, width: 1.5),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(6),
              child: Row(
                children: [
                  // دکمه‌ی ارسال (اول در RTL = سمت راست)
                  Material(
                    color: c.teal,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {},
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(Icons.send, size: 18, color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      maxLines: null,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(color: c.ink, fontSize: 13),
                      decoration: InputDecoration(
                        hintText:
                            'Enter برای خط جدید) جمله‌ت رو بنویس یا سوال‌ت رو بپرس (برای ارسال دکمه رو بزن',
                        hintStyle: TextStyle(
                          color: c.inkSoft.withOpacity(0.6),
                          fontSize: 11.5,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
