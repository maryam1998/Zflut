import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../core/constants/supported_languages.dart';
import '../../core/mascot/mascot_pin_provider.dart';
import '../../core/sync/cloud_sync.dart';
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

    // ☁️ مدل‌هایی که با حساب دانلود شده بودند ولی روی این دستگاه نیستند
    ref.listen<List<String>>(missingPacksProvider, (prev, next) {
      if (next.isEmpty) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) _askRestore(context, ref, next);
      });
    });

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

String _packLabel(String id) {
  final i = id.indexOf(':');
  if (i <= 0) return id;
  final kind = id.substring(0, i);
  final pid = id.substring(i + 1);
  String lang(String code) {
    for (final l in kSupportedLanguages) {
      if (l.code == code) return l.faLabel;
    }
    return code.toUpperCase();
  }

  switch (kind) {
    case 'tts':
      return 'صدای آفلاین — ${lang(pid)}';
    case 'speech':
      return 'تشخیص گفتار — ${lang(pid)}';
    case 'song':
      return 'مدل آهنگ (Whisper) — $pid';
    default:
      return id;
  }
}

Future<void> _askRestore(
    BuildContext context, WidgetRef ref, List<String> ids) async {
  final L = context.l10n;
  final sync = ref.read(cloudSyncProvider);
  final yes = await showDialog<bool>(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text(L.sync_restore_title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(L.sync_restore_body),
              const SizedBox(height: 10),
              for (final id in ids) Text('• ${_packLabel(id)}'),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(L.sync_restore_later)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(L.sync_restore_download)),
        ],
      ),
    ),
  );
  if (yes == true) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(L.sync_restore_started)));
    }
    unawaited(sync.restorePacks(ids));
  } else {
    sync.dismissMissing(ids);
  }
}
