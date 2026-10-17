// 📁 مسیر: lib/core/config/build_flavor.dart
//
// نسخه‌ی فروشگاهی با --dart-define=STORE_BUILD=true ساخته می‌شود.
// در این نسخه «دسترسی به اعلان‌ها» وجود ندارد. (Accessibility از کل پروژه حذف شده.)
const bool kStoreBuild = bool.fromEnvironment('STORE_BUILD');
