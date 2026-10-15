import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/supported_languages.dart';
import '../../../core/providers/language_selection_provider.dart';
import '../../../core/theme/app_theme_colors.dart';

class AccountHeader extends ConsumerWidget {
  final VoidCallback onMenuTap;
  final VoidCallback onAvatarTap;
  final String? userName;

  const AccountHeader({
    super.key,
    required this.onMenuTap,
    required this.onAvatarTap,
    this.userName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final name = (userName ?? 'مهمان').trim();
    final sel = ref.watch(languageSelectionProvider);
    final lang = Localizations.localeOf(context).languageCode;
    final rtlUi = lang == 'fa' || lang == 'ar';
    String labelOf(String code) {
      for (final l in kSupportedLanguages) {
        if (l.code == code) return rtlUi ? l.faLabel : l.enLabel;
      }
      return code.toUpperCase();
    }

    final fromTo = rtlUi
        ? 'از ${labelOf(sel.native)} به ${sel.targets.map(labelOf).join('، ')}'
        : 'From ${labelOf(sel.native)} to ${sel.targets.map(labelOf).join(', ')}';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '؟';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [c.headerFrom, c.headerTo],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              // ═══ منوی همبرگری (تنظیمات) — بالا سمت راست ═══
              InkWell(
                onTap: onMenuTap,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(
                    Icons.menu,
                    color: c.headerText,
                    size: 26,
                  ),
                ),
              ),

              // ═══ «از زبان مبدا به زبان‌های مقصد» — کنار همبرگری ═══
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    fromTo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.headerText.withOpacity(0.9),
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              // ═══ آواتار — سمت چپ ═══
              GestureDetector(
                onTap: onAvatarTap,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        c.headerText.withOpacity(0.35),
                        c.headerText.withOpacity(0.18),
                      ],
                    ),
                    border: Border.all(
                      color: c.headerText.withOpacity(0.4),
                      width: 1.5,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initial,
                    style: TextStyle(
                      color: c.headerText,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
