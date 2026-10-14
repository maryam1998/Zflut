import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/language_selection_provider.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/theme/screen_scale.dart';

/// ردیف بالا: منو + آواتار (سمت چپ)، و زیرش «از ... به ... · نام کاربر».
/// پس‌زمینه شفاف است؛ گرادیانِ هدر در AppShell کشیده می‌شود.
class AccountHeader extends ConsumerWidget {
  final VoidCallback onMenuTap;
  final VoidCallback onAvatarTap;

  /// TODO: به نام واقعی کاربر وصل کن.
  final String userName;

  const AccountHeader({
    super.key,
    required this.onMenuTap,
    required this.onAvatarTap,
    this.userName = 'Maryam S',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final sel = ref.watch(languageSelectionProvider);

    final nativeLabel = langFaName(sel.native);
    final targetLabels = sel.targets.map(langFaName).join('، ');
    final route = targetLabels.isEmpty
        ? nativeLabel
        : 'از $nativeLabel به $targetLabels';
    final headerText = userName.isEmpty ? route : '$route · $userName';
    final initial = userName.isEmpty ? 'M' : userName.substring(0, 1);

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          context.px(26),
          context.px(34),
          context.px(34),
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // اولین فرزند در RTL سمت راستِ دومی قرار می‌گیرد؛
            // end = چپ. پس: [آواتار][منو] چسبیده به لبه‌ی چپ.
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: onAvatarTap,
                  child: Container(
                    width: context.px(70),
                    height: context.px(70),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF0E9AA7),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      initial.toUpperCase(),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: context.px(34),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: context.px(16)),
                InkWell(
                  onTap: onMenuTap,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: EdgeInsets.all(context.px(10)),
                    child: Icon(
                      Icons.menu,
                      color: c.gold,
                      size: context.px(46),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: context.px(4)),
            Text(
              headerText,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.start,
              style: TextStyle(
                color: c.headerText.withOpacity(0.92),
                fontSize: context.px(29),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
