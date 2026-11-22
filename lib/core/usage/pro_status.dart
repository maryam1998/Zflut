import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ═══════════════════════════════════════════════════════════════════
// 💎 وضعیتِ Pro + قانون‌های قفلِ نسخه‌ی رایگان
// (سقف‌ها را فقط همین‌جا عوض کن)
// ═══════════════════════════════════════════════════════════════════

/// لغات: فقط N لغتِ اولِ هر دسته‌ی رایگان (پایین) باز است؛ بقیه‌ی لغاتِ آن دسته‌ها و همه‌ی دسته‌های دیگر
/// (دیکشنری من، Slang، Vocab in use) پولی‌اند ولی تعدادشان به کاربر نشان داده می‌شود.
/// ⚠️ باید با FREE_PER_GROUP در scripts/build-paid-content.mjs یکی باشد.
const int kFreeWordsPerGroup = 10;

/// فقط این دو دسته لغتِ رایگان دارند: «غذا و نوشیدنی» (food) و «خانه و زندگی روزمره» (home).
/// ⚠️ باید با FREE_GROUPS در scripts/build-paid-content.mjs یکی باشد.
const Set<String> kFreeWordGroups = {'food', 'home'};

/// «دیکشنری من»: کلِ لغاتِ بازِ کاربرِ رایگان = [kFreeWordsPerGroup] لغت از هر دسته‌ی رایگان.
const int kFreeDictionaryWords = 20;

/// (قدیمی — دیگر استفاده نمی‌شود؛ جایش kFreeWordsPerGroup است)
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
