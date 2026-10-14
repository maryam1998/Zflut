import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/providers/app_prefs_provider.dart';
import 'core/storage/local_storage.dart' show sharedPrefsProvider;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // سیستم‌چین مثل نسخه‌ی وب که RTL را در HTML ریشه اعمال می‌کند.
  SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Supabase — مقداردهی اولیه (کلید publishable؛ کلید AI هرگز این‌جا نیست).
  // مقادیر واقعی را بعداً از --dart-define می‌گیریم.
  await Supabase.initialize(
    url: const String.fromEnvironment('SUPABASE_URL'),
    anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
  );

  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        // SharedPreferences را از قبل می‌سازیم تا خواندن prefs سنکرون باشد.
        sharedPrefsProvider.overrideWithValue(prefs),
      ],
      child: const LingoLearnApp(),
    ),
  );
}
