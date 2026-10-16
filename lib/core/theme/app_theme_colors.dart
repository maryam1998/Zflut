// 📁 مسیر: lib/core/theme/app_theme_colors.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_appearance.dart';
import '../providers/app_prefs_provider.dart';

/// رنگ‌های تم فعلی — از appPrefs خوانده می‌شوند
class AppThemeColorsExt {
  final Color paper;
  final Color paperDark;
  final Color ink;
  final Color inkSoft;
  final Color gold;
  final Color goldSoft;
  final Color teal;
  final Color rose;
  final Color cardBorder;
  final Color headerFrom;
  final Color headerTo;
  final Color headerText;

  const AppThemeColorsExt({
    required this.paper,
    required this.paperDark,
    required this.ink,
    required this.inkSoft,
    required this.gold,
    required this.goldSoft,
    required this.teal,
    required this.rose,
    required this.cardBorder,
    required this.headerFrom,
    required this.headerTo,
    required this.headerText,
  });

  factory AppThemeColorsExt.fromDef(AppThemeDef def) => AppThemeColorsExt(
        paper: def.paper,
        paperDark: def.paperDark,
        ink: def.ink,
        inkSoft: def.inkSoft,
        gold: def.gold,
        goldSoft: def.goldSoft,
        teal: def.teal,
        rose: def.rose,
        cardBorder: def.cardBorder,
        headerFrom: def.headerFrom,
        headerTo: def.headerTo,
        headerText: def.headerText,
      );
}

/// Extension تا بتوانیم `c = context.appColors` بنویسیم
extension AppThemeColorsX on BuildContext {
  AppThemeColorsExt get appColors {
    final container = ProviderScope.containerOf(this, listen: false);
    final prefs = container.read(appPrefsProvider);
    final themeDef = kAppThemes[prefs.theme] ?? kAppThemes['vintage']!;
    return AppThemeColorsExt.fromDef(themeDef);
  }
}

/// Provider برای ConsumerWidget
final appThemeColorsProvider = Provider<AppThemeColorsExt>((ref) {
  final prefs = ref.watch(appPrefsProvider);
  final themeDef = kAppThemes[prefs.theme] ?? kAppThemes['vintage']!;
  return AppThemeColorsExt.fromDef(themeDef);
});
