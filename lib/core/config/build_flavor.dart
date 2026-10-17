// 📁 مسیر: lib/core/config/build_flavor.dart
//
// نسخه‌ی فروشگاهی با --dart-define=STORE_BUILD=true ساخته می‌شود.
// در این نسخه Accessibility و «دسترسی به اعلان‌ها» وجود ندارد.
const bool kStoreBuild = bool.fromEnvironment('STORE_BUILD');
