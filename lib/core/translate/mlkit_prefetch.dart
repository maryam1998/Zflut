import 'dart:async';

import '../native/native_bridge.dart';

/// 📥 دانلودِ پیش‌دستانه‌ی مدل‌های ترجمه‌ی ML Kit (فقط اندروید).
///
/// وقتی کاربر زبان‌هایش را انتخاب می‌کند (مادری + مقصدها) همان لحظه مدلِ هر زبان در پس‌زمینه دانلود می‌شود
/// تا اولین ترجمه‌ی آفلاین/بی‌هزینه آماده باشد و Worker/AI کمتر صدا زده شود.
///
/// • ML Kit بینِ هر دو زبان از «انگلیسی» واسطه می‌سازد؛ پس دانلودِ جفتِ en→X برای هر زبانِ X هم مدلِ X را می‌آورد
///   و هم انگلیسی را (مدل‌ها بینِ جفت‌ها مشترک‌اند، دوباره دانلود نمی‌شوند).
/// • پشتِ‌هم (یکی‌یکی) و بی‌صدا؛ هیچ خطایی بالا نمی‌آید. چند تغییرِ پشتِ‌هم (تیک‌زدنِ سریعِ زبان‌ها) یک‌بار حساب می‌شود.
/// • [wifiOnly] = true برای «جبرانِ» شروعِ برنامه (کاربرِ قدیمی)؛ false وقتی کاربر همین الان زبان‌ها را انتخاب کرده.
class MlKitPrefetch {
  MlKitPrefetch._();

  static const Duration _debounce = Duration(seconds: 2);
  static const int _maxLangs = 8; // سقفِ ایمنی؛ بیشتر از این در یک نوبت دانلود نمی‌شود

  static Timer? _timer;
  static bool _running = false;
  static bool _again = false;
  static List<String> _pending = const [];
  static bool _pendingWifiOnly = false;
  static final Set<String> _failedThisSession = <String>{};

  /// زبان‌ها: مادری + مقصدها. فراخوانی ارزان است؛ کارِ واقعی بعد از [_debounce] شروع می‌شود.
  static void schedule(String native, List<String> targets, {bool wifiOnly = false}) {
    if (!NativeBridge.instance.isSupported) return;
    final langs = <String>{};
    for (final c in [native, ...targets]) {
      final t = c.trim().toLowerCase();
      if (t.isNotEmpty && t != 'en') langs.add(t);
    }
    if (langs.isEmpty) return;
    _pending = langs.take(_maxLangs).toList();
    // اگر هر درخواستِ منتظر «همین الان از کاربر» بوده، Wi‑Fi-only نشود
    _pendingWifiOnly = _timer?.isActive == true ? (_pendingWifiOnly && wifiOnly) : wifiOnly;
    _timer?.cancel();
    _timer = Timer(_debounce, () => unawaited(_run()));
  }

  static Future<void> _run() async {
    if (_running) {
      _again = true; // وسطِ دانلود بودیم؛ بعد از تمام‌شدن یک دورِ دیگر
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        final langs = List<String>.from(_pending);
        final wifiOnly = _pendingWifiOnly;
        final n = NativeBridge.instance;
        for (final lang in langs) {
          if (_failedThisSession.contains(lang)) continue;
          try {
            final st = await n
                .mlkitStatus(src: 'en', tgt: lang)
                .timeout(const Duration(seconds: 6));
            if (st['supported'] != true) continue; // زبانِ پشتیبانی‌نشده
            if (st['ready'] == true || st['downloading'] == true) continue;
            await n.mlkitDownload(src: 'en', tgt: lang, wifiOnly: wifiOnly);
          } catch (_) {
            // قطعیِ شبکه/«already downloading»؛ فقط برای همین نشست دوباره امتحان نشود
            _failedThisSession.add(lang);
          }
        }
      } while (_again);
    } finally {
      _running = false;
    }
  }
}
