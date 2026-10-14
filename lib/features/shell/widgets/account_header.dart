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

    final nativeLabel = langFaName(sel.native);
    final targetLabels = sel.targets.map(langFaName).join('، ');
    final headerText = targetLabels.isEmpty
        ? nativeLabel
        : 'از $nativeLabel به $targetLabels';

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
          padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
          child: Row(
            children: [
              // ═══ منوی تنظیمات — سمت راست (شروع در RTL) ═══
              InkWell(
                onTap: onMenuTap,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.menu,
                    color: c.headerText,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 4),

              // ═══ متن «از ... به ...» ═══
              Expanded(
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(start: 4),
                  child: Text(
                    headerText,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.start,
                    style: TextStyle(
                      color: c.headerText.withOpacity(0.92),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // ═══ آواتار — سمت چپ (پایان در RTL) ═══
              GestureDetector(
                onTap: onAvatarTap,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        c.headerText.withOpacity(0.30),
                        c.headerText.withOpacity(0.15),
                      ],
                    ),
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
      ),
    );
  }
}
