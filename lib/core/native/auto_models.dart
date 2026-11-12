import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/linlearn_bridge.dart';
import '../models/language_selection.dart';
import '../providers/language_selection_provider.dart';
import '../storage/local_storage.dart' show sharedPrefsProvider;
import 'native_bridge.dart';

/// 📦 دانلودِ بی‌صدا و خودکارِ همه‌ی مدل‌های آفلاین (TTS / تشخیص گفتار / همگام‌سازی)
/// از لحظه‌ی باز شدنِ اپ. کاربر هیچ دیالوگ/دکمه‌ی دانلودی نمی‌بیند؛ وقتی به قابلیتی برسد
/// که مدلش هنوز کامل نشده، فقط پیامِ «در حال آماده‌سازی» می‌بیند.
///
/// مدل‌ها پشتِ‌هم (یکی‌یکی) دانلود می‌شوند تا شبکه/گوشی خفه نشود؛ اگر دانلودی شکست بخورد
/// بعداً (چند دقیقه بعد و در بازشدنِ بعدیِ اپ) دوباره تلاش می‌شود.
class AutoModels {
  AutoModels._();

  static bool _started = false;
  static bool _running = false;
  static bool _again = false;
  static Timer? _retry;

  /// یک‌بار موقعِ باز شدنِ اپ صدا زده می‌شود.
  static void start(ProviderContainer c) {
    if (_started || !NativeBridge.instance.isSupported) return;
    _started = true;
    // کمی صبر تا بالا آمدنِ اولیه‌ی اپ کند نشود
    Timer(const Duration(seconds: 4), () => kick(c));
    c.listen<LanguageSelection>(languageSelectionProvider, (prev, next) {
      if (prev == null) return;
      if (prev.native != next.native ||
          prev.targets.join(',') != next.targets.join(',')) {
        kick(c);
      }
    });
  }

  /// همین حالا (دوباره) بررسی و دانلودِ مدل‌های ناقص را شروع می‌کند.
  static void kick(ProviderContainer c) {
    if (!NativeBridge.instance.isSupported) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    unawaited(_run(c).whenComplete(() {
      _running = false;
      if (_again) {
        _again = false;
        kick(c);
      }
    }));
  }

  static List<_Pack> _wanted(ProviderContainer c) {
    final sel = c.read(languageSelectionProvider);
    final langs = <String>{
      'en',
      sel.native.trim().toLowerCase(),
      ...sel.targets.map((e) => e.trim().toLowerCase()),
    }..removeWhere((e) => e.isEmpty);

    final out = <_Pack>[];
    // ۱) تشخیص گفتار برای مکالمه‌ی صوتی با AI (Whisper) — مهم‌ترین
    out.add(const _Pack('song', 'base'));
    // ۲) صدای اپ (TTS) برای زبان‌های انتخاب‌شده
    for (final l in langs) {
      out.add(_Pack('tts', l));
    }
    // ۳) بسته‌ی همگام‌سازیِ متن و صوت (طبق کیفیتِ انتخابیِ کاربر)
    var size = 'balanced';
    try {
      size = c.read(sharedPrefsProvider).getString('syncModelSize') ?? 'balanced';
    } catch (_) {}
    out.add(_Pack('sync', size));
    // ۴) تشخیص گفتارِ زنده (ترجمه‌ی زنده) برای زبان‌های اختصاصی
    for (final l in langs) {
      if (const {'en', 'ru', 'zh', 'ko'}.contains(l)) out.add(_Pack('speech', l));
    }
    return out;
  }

  static Future<void> _run(ProviderContainer c) async {
    var incomplete = false;
    final seen = <String>{};
    for (final p in _wanted(c)) {
      if (!seen.add(p.key)) continue;
      try {
        final ok = await _ensure(p);
        if (!ok) incomplete = true;
      } catch (e) {
        incomplete = true;
        debugPrint('AutoModels ${p.key}: $e');
      }
    }
    // ناقص ماند (قطعیِ نت و...) → ۸ دقیقه بعد دوباره
    _retry?.cancel();
    if (incomplete) {
      _retry = Timer(const Duration(minutes: 8), () => kick(c));
    }
  }

  /// true = مدل آماده است (یا این دستگاه/مدل پشتیبانی نمی‌شود)
  static Future<bool> _ensure(_Pack p) async {
    var st = await LinLearnBridge.packStatus(p.kind, p.id);
    if (st == null) return true; // پشتیبانی نمی‌شود
    if (st['downloaded'] == true) return true;
    if (st['downloading'] != true) {
      final started = await LinLearnBridge.packDownload(p.kind, p.id);
      if (!started) return false;
    }
    // تا کامل شدن منتظر می‌ماند (سقف ۴۵ دقیقه) تا مدلِ بعدی هم‌زمان شروع نشود
    final deadline = DateTime.now().add(const Duration(minutes: 45));
    var idle = 0;
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(seconds: 4));
      st = await LinLearnBridge.packStatus(p.kind, p.id);
      if (st == null) return true;
      if (st['downloaded'] == true) return true;
      if (st['downloading'] != true) {
        // دانلود متوقف شد (خطا/لغو) — چند چک پشتِ‌هم برای اطمینان
        if (++idle >= 3) return false;
      } else {
        idle = 0;
      }
    }
    return false;
  }
}

class _Pack {
  final String kind;
  final String id;
  const _Pack(this.kind, this.id);
  String get key => '$kind:$id';
}
