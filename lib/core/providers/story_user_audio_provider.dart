import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/story_audio_controller.dart';

/// معادلِ `onUserAudioStateChange` → `setStoryUserAudio` در Hope:
/// داستانِ بازِ تبِ «داستان‌ساز» کنترلرِ صوتِ آپلودیِ خودش را اینجا ثبت می‌کند
/// تا پلیرِ اصلیِ پایینِ صفحه (PlayerBar) بتواند همان صدا را پخش کند.
/// null = داستانی باز نیست (سوییچِ «صدای اپ / صدای اپلودی» هم نشان داده نمی‌شود).
final storyUserAudioProvider =
    StateProvider<StoryAudioController?>((ref) => null);

/// معادلِ playbackMode در Hope: 'tts' (صدای اپ) یا 'user' (صدای اپلودی).
final storyPlaybackModeProvider = StateProvider<String>((ref) => 'tts');
