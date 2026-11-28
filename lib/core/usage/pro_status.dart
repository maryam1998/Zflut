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

/// «دیکشنری من»: فقط دسته‌ی «غذا و نوشیدنی» (food) لغتِ رایگان دارد.
/// (Vocabulary in use ← فقط «سلامت و بیماری» و Slang ← فقط «مردم و شخصیت»؛ آن‌ها از روی assets/ایندکس کار می‌کنند.)
/// ⚠️ باید با FREE_GROUPS.daily در scripts/build-paid-content.mjs یکی باشد.
const Set<String> kFreeWordGroups = {'food'};

/// «دیکشنری من»: کلِ لغاتِ بازِ کاربرِ رایگان = [kFreeWordsPerGroup] لغت از هر دسته‌ی رایگان.
const int kFreeDictionaryWords = 20;

/// (قدیمی — دیگر استفاده نمی‌شود؛ جایش kFreeWordsPerGroup است)
const int kFreeWordCount = 30;

/// مکالمه (تب Talk): فقط همین موضوع رایگان است …
const Set<String> kFreeConversationTopics = {
  'Greetings and Small Talk',
};

/// … و فقط جمله‌های همین سطح داخلشان.
const String kFreeConversationLevel = 'A1';

class ProStatus {
  ProStatus._();

  /// Worker هنگامِ ورود/تازه‌سازیِ نشست می‌گوید کاربر Pro/VIP هست یا نه.
  static final ValueNotifier<bool> pro = ValueNotifier<bool>(false);
  static bool get isPro => pro.value;

  /// 🔒 موضوعِ مکالمه برای کاربرِ رایگان قفل است مگر در [kFreeConversationTopics] باشد.
  /// (مکالمه‌های مرحله‌های تحصیلی / Education stage هم پولی‌اند.)
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
