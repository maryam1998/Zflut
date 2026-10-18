import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/tab_group.dart';
import 'account_header.dart';
import 'header_tabs.dart';
import 'language_picker.dart';
import 'settings_sheet.dart';
import 'sub_tabs_row.dart';

/// هدر + زبان‌ها + گروه‌ها + زیرتب‌ها.
///
/// مثل Hope: این بخش «داخلِ خودِ محتوا» است. هر تب آن را به‌عنوان اولین
/// آیتمِ لیستِ اسکرول‌شوندهٔ خودش می‌گذارد، پس همراهِ اسکرول بالا می‌رود
/// و فقط وقتی به ابتدای لیست برگردی دیده می‌شود. (بدون NestedScrollView،
/// بدون شناور/snap → اسکرول روان و بدون هماهنگی‌های اضافی.)
class ShellHeader extends StatelessWidget {
  const ShellHeader({super.key});

  // بدون حساسیت به حروف: مسیر '/vocab-in-use' ↔ کلید 'vocabInUse'
  static String _normalize(String key) =>
      key.replaceAll('-', '').toLowerCase();

  static String routeOf(String tabKey) {
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

  @override
  Widget build(BuildContext context) {
    final loc = GoRouterState.of(context).matchedLocation;
    final tabKey = _normalize(loc.replaceFirst('/', ''));

    final currentGroup = kTabGroups.firstWhere(
      (g) => g.tabs.any((t) => _normalize(t) == tabKey),
      orElse: () => kTabGroups.first,
    );
    final hasSubtabs = currentGroup.tabs.length > 1;
    // کلیدِ واقعیِ تبِ فعال (مثلاً 'vocabInUse') برای هایلایت در زیرتب‌ها
    final activeTab = currentGroup.tabs.firstWhere(
      (t) => _normalize(t) == tabKey,
      orElse: () => currentGroup.tabs.first,
    );

    // هدرِ شل همیشه راست‌چین می‌ماند (آواتار راست، منو چپ) — حتی وقتی
    // محتوای تب برای زبانِ رابطِ انگلیسی/اروپایی چپ‌به‌راست است.
    return Directionality(
      textDirection: TextDirection.rtl,
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
          onGroupSelected: (group) => context.go(routeOf(group.tabs.first)),
          onSettingsTap: () => SettingsSheet.show(context),
        ),
        if (hasSubtabs)
          SubTabsRow(
            group: currentGroup,
            activeTabKey: activeTab,
            onTabSelected: (tab) => context.go(routeOf(tab)),
          ),
      ],
    ));
  }
}
