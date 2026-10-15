import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../grammar/widgets/practice_sheet.dart';
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
      body: Column(
        children: [
          Expanded(child: child),

          // ═══ پنل تمرین گرامر — همیشه visible، بالای پلیر ═══
          const PracticeSheet(),

          // ═══ پلیر پایین صفحه ═══
          const PlayerBar(),
        ],
      ),
    );
  }
}
