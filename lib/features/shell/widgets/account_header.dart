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
    final sel = ref.watch(languageSelectionProvider);
    String labelOf(String code) {
      for (final l in kSupportedLanguages) {
        if (l.code == code) return l.faLabel;
      }
      return code.toUpperCase();
    }

    // «از فارسی به آلمانی، انگلیسی» — همیشه فارسی و راست‌به‌چپ (مثل Hope)
    final fromTo =
        'از ${labelOf(sel.native)} به ${sel.targets.map(labelOf).join('، ')}';

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
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
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
                    textDirection: TextDirection.rtl,
                    textAlign: TextAlign.start,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      height: 1.35,
                      color: c.headerText.withOpacity(0.9),
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
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
