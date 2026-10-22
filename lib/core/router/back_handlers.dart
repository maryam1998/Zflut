/// دکمه‌ی «بازگشت» گوشی: قبل از اینکه AppShell به تبِ قبلی برگردد یا از برنامه خارج شود،
/// ویجت‌هایی که حالتِ درونی دارند (مثلاً داستانِ بازشده داخل تب) می‌توانند آن را بگیرند.
/// هر ویجت [add] می‌کند و در dispose [remove]؛ آخرین ثبت‌شده اول پرسیده می‌شود.
/// تابع اگر کاری کرد (مثلاً پنل را بست) باید true برگرداند.
class BackHandlers {
  BackHandlers._();

  static final List<bool Function()> _handlers = [];

  static void add(bool Function() h) => _handlers.add(h);

  static void remove(bool Function() h) => _handlers.remove(h);

  /// true = یکی از ویجت‌ها بازگشت را مصرف کرد.
  static bool handle() {
    for (final h in _handlers.reversed.toList()) {
      if (h()) return true;
    }
    return false;
  }
}
