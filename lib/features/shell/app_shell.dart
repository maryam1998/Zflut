import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/mascot/mascot_pin_provider.dart';
import '../../core/theme/app_theme_colors.dart';
import '../grammar/widgets/practice_sheet.dart';
import 'widgets/lingova_mascot.dart';
import 'widgets/player_bar.dart';

/// پوستهٔ اپ. مثل Hope هدر/تب‌ها اینجا ثابت نیستند؛ هر تب آن‌ها را
/// (ShellHeader) به‌عنوان اولین آیتمِ لیستِ خودش نشان می‌دهد تا با اسکرول
/// بالا برود. فقط پنل تمرین و پلیر پایینِ صفحه ثابت می‌مانند.
class AppShell extends ConsumerWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    return Scaffold(
      backgroundColor: c.paper,
      // هر لمس/اسکرول = «تعامل» (برای پیام‌های یادآوریِ آدمک)
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => MascotActivity.mark(),
        onPointerMove: (_) => MascotActivity.mark(),
        onPointerSignal: (_) => MascotActivity.mark(),
        child: NotificationListener<ScrollNotification>(
          onNotification: (_) {
            MascotActivity.mark();
            return false;
          },
          child: Stack(
            children: [
              Column(
                children: [
                  // جای نوارِ آدمک — همان ۴۰px که در Hope داخل هدر بود
                  const SizedBox(height: 40),
                  Expanded(child: child),

                  // ═══ پنل تمرین گرامر — همیشه visible، بالای پلیر ═══
                  const PracticeSheet(),

                  // ═══ پلیر پایین صفحه ═══
                  const PlayerBar(),
                ],
              ),
              // ═══ آدمکِ Lingova (نوار بالا + حباب‌ها) ═══
              const Positioned.fill(child: LingovaMascotLayer()),
            ],
          ),
        ),
      ),
    );
  }
}
