import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/language_selection_provider.dart';
import '../../../core/theme/app_theme_colors.dart';

class AccountHeader extends ConsumerWidget {
  final VoidCallback onMenuTap;
  final VoidCallback onAvatarTap;

  const AccountHeader({
    super.key,
    required this.onMenuTap,
    required this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final sel = ref.watch(languageSelectionProvider);

    // متنِ «از انگلیسی به فارسی» — با نام زبان‌ها
    final nativeLabel = _langFa(sel.native);
    final targetLabel = sel.primaryTarget != null
        ? _langFa(sel.primaryTarget!)
        : '—';

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
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              // منوی همبرگری
              InkWell(
                onTap: onMenuTap,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.menu,
                    color: c.headerText,
                    size: 24,
                  ),
                ),
              ),

              const Spacer(),

              // «از X به Y» + آواتار
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        'از $nativeLabel به $targetLabel',
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          color: c.headerText.withOpacity(0.85),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // آواتار
                    GestureDetector(
                      onTap: onAvatarTap,
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c.headerText.withOpacity(0.18),
                          border: Border.all(
                            color: c.headerText.withOpacity(0.35),
                            width: 1.5,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'M',
                          style: TextStyle(
                            color: c.headerText,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _langFa(String code) {
    switch (code) {
      case 'fa': return 'فارسی';
      case 'en': return 'انگلیسی';
      case 'ar': return 'عربی';
      case 'de': return 'آلمانی';
      case 'es': return 'اسپانیایی';
      case 'fr': return 'فرانسوی';
      case 'it': return 'ایتالیایی';
      case 'ru': return 'روسی';
      case 'tr': return 'ترکی';
      case 'hi': return 'هندی';
      case 'zh': return 'چینی';
      case 'ja': return 'ژاپنی';
      case 'ko': return 'کره‌ای';
      default:   return code.toUpperCase();
    }
  }
}
