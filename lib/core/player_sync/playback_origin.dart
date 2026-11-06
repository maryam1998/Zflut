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
