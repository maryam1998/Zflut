import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../auth/worker_auth.dart';
import 'pro_status.dart';
import '../tts/tts_config.dart';

/// بخش‌هایی که در نسخه‌ی رایگان سقفِ «کل عمر» دارند (نامِ بخش = همان کلیدِ Worker).
class Feature {
  static const example = 'example'; // مثال‌ساز (AI)
  static const grammar = 'grammar'; // گرامر (AI)
  static const story = 'story'; // داستان‌ساز (AI)
  static const chat = 'chat'; // چت (AI)
  static const videocall = 'videocall'; // ویدیوکال AI
  static const live = 'live'; // ترجمه‌ی زنده
  static const magnifier = 'magnifier'; // ذره‌بین
  static const storyImport = 'import'; // ایمپورتِ تبِ داستان‌ساز (PDF/عکس/SRT/لینک/متن) — ۲ بارِ رایگان
  static const popup = 'popup'; // کادرِ پاپِ انتخابِ لغت/محدوده (ذخیره برای داستان بعدی و…) — ۳ بارِ رایگان
  // ترجمه‌ی یوتیوب: Worker خودش از رویِ مسیرِ درخواست‌ها تشخیص می‌دهد.
}

/// Worker کد 402 داد: سقفِ استفاده‌ی رایگانِ این بخش تمام شده.
class FreeLimitException implements Exception {
  final String feature;
  const FreeLimitException(this.feature);
  @override
  String toString() => 'FreeLimitException($feature)';
}

class FreeLimit {
  FreeLimit._();

  static const String messageFa =
      'سقف استفاده‌ی رایگان از این بخش تمام شده. برای استفاده‌ی نامحدود، نسخه‌ی Pro را بخرید.';
  static const String messageEn =
      "You've reached the free usage limit for this feature. Buy Pro for unlimited use.";

  static const String lockedFa =
      'این بخش مخصوص نسخه‌ی Pro است. برای دسترسی کامل، نسخه‌ی Pro را بخرید.';
  static const String lockedEn =
      'This content is available with Pro. Upgrade to unlock full access.';

  static String message(String lang) => lang == 'fa' ? messageFa : messageEn;

  /// محتوای قفل‌شده (لغتِ بعد از ۳۰ام، موضوعِ پولیِ مکالمه) — همان پنجره، با پیامِ «مخصوص Pro».
  static void reportLocked() => report('locked');
  static String lockedMessage(String lang) =>
      lang == 'fa' ? lockedFa : lockedEn;

  /// هر بار که زیاد شود، پنجره‌ی «سقف تمام شد» نشان داده می‌شود (FreeLimitHost).
  static final ValueNotifier<int> tick = ValueNotifier<int>(0);
  static String lastFeature = '';

  static void report(String feature) {
    lastFeature = feature;
    tick.value++;
  }

  /// شناسه‌ی یک «استفاده‌ی منطقی»؛ تلاش‌های دوباره‌ی همان درخواست دوباره شمرده نمی‌شوند.
  static String newUseId() {
    final r = math.Random();
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
        '${r.nextInt(1 << 30).toRadixString(36)}';
  }

  static final Dio _dio = Dio();

  /// بخش‌هایی که سقفشان در همین اجرای اپ تمام‌شده‌اند (برای اینکه قبل از باز کردنِ فایل‌انتخاب‌گر هم بشود پنجره‌ی Pro را نشان داد).
  static final Set<String> _exhausted = <String>{};

  /// بخش‌هایی که «کلاً Pro» هستند (داستان‌ساز، گرامرِ AI): true = کاربر Pro نیست،
  /// پنجره‌ی «مخصوص Pro» نشان داده شد و کار باید متوقف شود.
  static bool blockUnlessPro() {
    if (ProStatus.isPro) return false;
    reportLocked();
    return true;
  }

  /// فقط چک (بدونِ شمارش): اگر سقفِ رایگانِ این بخش قبلاً تمام شده، پنجره را نشان می‌دهد و true برمی‌گرداند.
  static bool blockIfExhausted(String feature) {
    if (ProStatus.isPro || !_exhausted.contains(feature)) return false;
    report(feature);
    return true;
  }

  /// یک «استفاده» از بخشِ دارایِ سهمیه‌ی رایگان (ایمپورت، کادرِ پاپ). Pro/VIP همیشه مجاز.
  /// true = مجاز؛ false = سقف تمام شده و پنجره‌ی Pro نشان داده شد.
  static Future<bool> useOrBlock(String feature) async {
    if (ProStatus.isPro) return true;
    if (blockIfExhausted(feature)) return false;
    return consume(feature);
  }

  /// شروعِ یک استفاده برای بخش‌هایی که درخواستِ AI ندارند (ذره‌بین، ترجمه‌ی زنده).
  /// true = مجاز؛ false = سقف تمام شده (پنجره‌ی پیام خودکار نشان داده می‌شود).
  /// اگر اینترنت/سرور مشکل داشت، کاربر الکی قفل نمی‌شود (true).
  static Future<bool> consume(String feature) async {
    Future<Response<dynamic>> once() => _dio.post<dynamic>(
          '${TtsConfig.backendUrl}/api/use',
          data: {'feature': feature, 'id': newUseId()},
          options: Options(
            headers: WorkerAuth.headers,
            contentType: 'application/json',
            sendTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 8),
            validateStatus: (_) => true,
          ),
        );
    try {
      await WorkerAuth.ensureFresh();
      var res = await once();
      if (res.statusCode == 401) {
        await WorkerAuth.refresh();
        res = await once();
      }
      if (res.statusCode == 402) {
        _exhausted.add(feature);
        report(feature);
        return false;
      }
    } catch (e) {
      debugPrint('FreeLimit.consume($feature): $e');
    }
    return true;
  }
}

/// پنجره‌ی «سقف استفاده‌ی رایگان تمام شده». بدونِ نیاز به Navigator/context: روی کلِ اپ می‌نشیند.
class FreeLimitHost extends StatefulWidget {
  final Widget child;
  const FreeLimitHost({super.key, required this.child});

  @override
  State<FreeLimitHost> createState() => _FreeLimitHostState();
}

class _FreeLimitHostState extends State<FreeLimitHost> {
  bool _show = false;
  int _seen = FreeLimit.tick.value;

  @override
  void initState() {
    super.initState();
    FreeLimit.tick.addListener(_onTick);
  }

  @override
  void dispose() {
    FreeLimit.tick.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() {
    if (FreeLimit.tick.value == _seen) return;
    _seen = FreeLimit.tick.value;
    if (mounted) setState(() => _show = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return widget.child;
    final lastLocked = FreeLimit.lastFeature == 'locked';
    final lang = Localizations.maybeLocaleOf(context)?.languageCode ?? 'fa';
    final fa = lang == 'fa';
    final theme = Theme.of(context);
    void close() => setState(() => _show = false);
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: GestureDetector(
            onTap: close,
            child: ColoredBox(
              color: Colors.black54,
              child: Center(
                child: GestureDetector(
                  onTap: () {},
                  child: Directionality(
                    textDirection: fa ? TextDirection.rtl : TextDirection.ltr,
                    child: Material(
                      color: theme.colorScheme.surface,
                      elevation: 8,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: 300,
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text('💎',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 34)),
                            const SizedBox(height: 10),
                            Text(
                              lastLocked
                                  ? FreeLimit.lockedMessage(lang)
                                  : FreeLimit.message(lang),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.6,
                                color: theme.colorScheme.onSurface,
                                decoration: TextDecoration.none,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 14),
                            FilledButton(
                              onPressed: close,
                              child: Text(fa ? 'باشه' : 'OK'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
