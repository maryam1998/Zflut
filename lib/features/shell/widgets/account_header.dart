import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
          padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
          child: Row(
            children: [
              // ═══ آیکون تنظیمات — سمت راست (شروع در RTL) ═══
              InkWell(
                onTap: onMenuTap,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(
                    Icons.settings_outlined,
                    color: c.headerText,
                    size: 22,
                  ),
                ),
              ),

              const Spacer(),

              // ═══ نام کاربر + آواتار — سمت چپ ═══
              GestureDetector(
                onTap: onAvatarTap,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: c.headerText.withOpacity(0.95),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
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
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
