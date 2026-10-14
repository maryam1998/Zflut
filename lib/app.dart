import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/constants/app_fonts.dart';
import 'core/constants/app_font_sizes.dart';
import 'core/providers/app_prefs_provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/theme_builder.dart';
import 'l10n/app_localizations.dart';

class LingoLearnApp extends ConsumerWidget {
  const LingoLearnApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(appPrefsProvider);
    final router = ref.watch(appRouterProvider);
    final themePreset = kAppThemes[prefs.theme]!;
    final fontPreset = kAppFonts[prefs.font]!;
    final sizePreset = kAppFontSizes[prefs.fontSize]!;

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (ctx) => AppLocalizations.of(ctx).app_title,
      theme: buildAppTheme(themePreset, fontPreset),
      locale: Locale(prefs.uiLang),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // جهت اپ بر اساس زبان رابط تعیین می‌شود (fa/ar = rtl).
      builder: (context, child) {
        final locale = Localizations.localeOf(context).languageCode;
        final dir = (locale == 'fa' || locale == 'ar')
            ? TextDirection.rtl
            : TextDirection.ltr;
        return Directionality(
          textDirection: dir,
          child: MediaQuery(
            // جایگزین CSS zoom در نسخه‌ی وب.
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(sizePreset.scale),
            ),
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      routerConfig: router,
    );
  }
}

// دسترسی راحت به AppLocalizations بدون !، فقط برای خوانایی.
extension AppL10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
