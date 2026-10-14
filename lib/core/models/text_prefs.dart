import 'package:flutter/foundation.dart';

enum TargetBoldMode { both, text, translation, none }

@immutable
class TargetTextPrefs {
  /// درصد مقیاس (۱۰۰ = پیش‌فرض). در Dart به‌صورت scale = value/100 استفاده می‌شود.
  final int scale;
  final TargetBoldMode bold;

  const TargetTextPrefs({
    this.scale = 100,
    this.bold = TargetBoldMode.both,
  });

  double get scaleFactor => scale / 100.0;

  Map<String, dynamic> toJson() => {'scale': scale, 'bold': bold.name};

  factory TargetTextPrefs.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const TargetTextPrefs();
    final boldName = json['bold'] as String?;
    return TargetTextPrefs(
      scale: (json['scale'] is num) ? (json['scale'] as num).toInt() : 100,
      bold: TargetBoldMode.values.firstWhere(
        (b) => b.name == boldName,
        orElse: () => TargetBoldMode.both,
      ),
    );
  }
}
