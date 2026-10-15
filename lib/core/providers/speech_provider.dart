import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tts/speech_controller.dart';
import '../tts/speech_state.dart';
import 'voice_prefs_provider.dart';

final speechControllerProvider =
    StateNotifierProvider<SpeechController, SpeechState>((ref) {
  return SpeechController(
    // صدای انتخاب‌شده‌ی کاربر برای هر زبان (در صورت وجود)
    voicePref: (lang) => ref.read(voicePrefsProvider)[lang],
  );
});
