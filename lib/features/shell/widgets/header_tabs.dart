import 'package:flutter/material.dart';

import '../../../core/theme/app_theme_colors.dart';

class HeaderTabs extends StatelessWidget {
  final VoidCallback onSettingsTap;

  const HeaderTabs({
    super.key,
    required this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [c.headerFrom, c.headerTo],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: c.headerTo.withOpacity(0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 60,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                // سمت شروع: لوگو + نام
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              c.headerText.withOpacity(0.25),
                              c.headerText.withOpacity(0.10),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: c.headerText.withOpacity(0.20),
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          Icons.translate_rounded,
                          size: 20,
                          color: c.headerText,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'LingoLearn',
                        style: TextStyle(
                          color: c.headerText,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // سمت پایان: تنظیمات
                IconButton(
                  onPressed: onSettingsTap,
                  icon: Icon(
                    Icons.settings_outlined,
                    color: c.headerText,
                    size: 22,
                  ),
                  tooltip: 'Settings',
                  splashRadius: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
