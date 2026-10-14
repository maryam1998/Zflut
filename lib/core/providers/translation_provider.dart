import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/local_storage.dart';
import '../translate/translation_service.dart';
import 'ai_settings_provider.dart';

final translationServiceProvider = Provider<TranslationService>((ref) {
  return TranslationService(ref.watch(sharedPrefsProvider));
});

/// ترجمه‌ی یک متن به یک زبان مقصد.
/// Riverpod این FutureProvider رو خودکار cache می‌کنه —
/// درخواست‌های تکراری با هم merge می‌شن.
final translationProvider = FutureProvider.family<String,
    ({String text, String to, String from})>((ref, args) async {
  if (args.text.trim().isEmpty) return '';
  final service = ref.watch(translationServiceProvider);
  final ai = ref.watch(aiSettingsProvider);
  return service.translate(
    text: args.text,
    targetLang: args.to,
    sourceLang: args.from,
    aiSettings: ai,
  );
});
