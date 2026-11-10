import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ═══════════════════════════════════════════════════════════════════
// 💎 وضعیتِ Pro + قانون‌های قفلِ نسخه‌ی رایگان
// (سقف‌ها را فقط همین‌جا عوض کن)
// ═══════════════════════════════════════════════════════════════════

/// لغات: فقط N لغتِ اولِ هر لیست (دیکشنری، اسلنگ، Vocab in use) رایگان است.
const int kFreeWordCount = 30;

/// مکالمه: فقط این موضوع‌ها (Greeting و Introduction) رایگان‌اند …
const Set<String> kFreeConversationTopics = {
  'Greetings and Small Talk',
  'Introducing People',
};

/// … و فقط جمله‌های همین سطح داخلشان.
const String kFreeConversationLevel = 'A1';

class ProStatus {
  ProStatus._();

  /// Worker هنگامِ ورود/تازه‌سازیِ نشست می‌گوید کاربر Pro/VIP هست یا نه.
  static final ValueNotifier<bool> pro = ValueNotifier<bool>(false);
  static bool get isPro => pro.value;

  static bool topicLocked(String topic) =>
      !isPro && !kFreeConversationTopics.contains(topic);
}

/// برای ویجت‌ها: با عوض‌شدنِ وضعیتِ Pro دوباره build می‌شوند.
final isProProvider = Provider<bool>((ref) {
  void l() => ref.invalidateSelf();
  ProStatus.pro.addListener(l);
  ref.onDispose(() => ProStatus.pro.removeListener(l));
  return ProStatus.pro.value;
});
