import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// «پخش از کجا شروع شد؟» — تب (مسیر) + حالتِ درونیِ تب (مثلاً موضوع/سناریو
/// یا شناسه‌ی داستان) که متنِ در حال پخش در آن است.
/// SyncPlayScope وقتی متنِ خودش پخش شود این را ثبت می‌کند و دکمه‌ی پخشِ پلیر
/// با لمسِ چندثانیه‌ای (long-press) با آن به همان تب و همان خط برمی‌گردد.
@immutable
class PlaybackOrigin {
  /// مسیرِ تب، مثلاً '/conversations'
  final String route;

  /// کلیدِ متنِ در حال پخش در SpeechController
  final String key;

  /// حالتِ درونیِ تب برای بازگردانی (هر تب خودش می‌خواند)
  final Map<String, Object?> extra;

  const PlaybackOrigin(this.route, this.key, [this.extra = const {}]);
}

/// آخرین مبدأ ثبت‌شده‌ی پخش.
final playbackOriginProvider = StateProvider<PlaybackOrigin?>((ref) => null);

/// درخواستِ بازگردانیِ حالتِ درونیِ تب. تبی که مالِ [PlaybackOrigin.route] است
/// آن را اعمال می‌کند و بعد null می‌کند.
final tabRestoreProvider = StateProvider<PlaybackOrigin?>((ref) => null);

/// هر بار که زیاد شود، اسکوپِ فعال به خطِ در حال پخش اسکرول می‌کند.
final revealActiveTickProvider = StateProvider<int>((ref) => 0);

/// 📍 درخواستِ پرش به یک آیتمِ مشخص (شناسه‌ی آیتم) در تبِ باز؛ مثلاً از نمودارِ
/// زمانِ گوش‌دادن. اسکوپی که آیتم را دارد اسکرول می‌کند و آن را null می‌کند.
final revealItemProvider = StateProvider<String?>((ref) => null);

/// 🖍 محدوده‌ی «خوانده‌شده» که از نمودارِ زمانِ گوش‌دادن نشان داده می‌شود.
/// آیتم‌های این مجموعه (شناسه‌ی جمله/لغت) با همان رنگِ هایلایتِ پلیر پس‌زمینه می‌گیرند؛
/// بعد از چند ثانیه [fading] روشن می‌شود (محو شدنِ آرام) و بعد کلِ حالت null می‌شود.
@immutable
class ReadHighlight {
  final Set<String> ids;
  final bool fading;
  const ReadHighlight(this.ids, {this.fading = false});
}

final readHighlightProvider = StateProvider<ReadHighlight?>((ref) => null);

int _readHlToken = 0;

/// محدوده‌ی خوانده‌شده را ~۶ ثانیه کامل نشان می‌دهد، بعد ~۳ ثانیه محو می‌کند.
/// [startAfter] برای وقتی است که اول باید به تبِ مقصد رفت و آیتم‌ها ساخته شوند.
void showReadHighlight(ProviderContainer c, Iterable<String> ids,
    {Duration startAfter = const Duration(milliseconds: 500)}) {
  final set = ids.toSet();
  if (set.isEmpty) return;
  final token = ++_readHlToken;
  Future.delayed(startAfter, () {
    if (token != _readHlToken) return;
    try {
      c.read(readHighlightProvider.notifier).state = ReadHighlight(set);
    } catch (_) {
      return;
    }
    Future.delayed(const Duration(seconds: 6), () {
      if (token != _readHlToken) return;
      try {
        c.read(readHighlightProvider.notifier).state =
            ReadHighlight(set, fading: true);
      } catch (_) {}
      Future.delayed(const Duration(milliseconds: 3200), () {
        if (token != _readHlToken) return;
        try {
          c.read(readHighlightProvider.notifier).state = null;
        } catch (_) {}
      });
    });
  });
}
