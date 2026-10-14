enum SpeechStatus { idle, playing, paused }

class SpeechState {
  final String? key;
  final SpeechStatus status;
  final int chunkIndex;
  final int total;
  final double rate;
  /// 0=off, 2, 3, -1=∞
  final int globalRepeat;
  final bool muted;
  final String? error;

  const SpeechState({
    this.key,
    this.status = SpeechStatus.idle,
    this.chunkIndex = 0,
    this.total = 0,
    this.rate = 1.0,
    this.globalRepeat = 0,
    this.muted = false,
    this.error,
  });

  SpeechState copyWith({
    String? key,
    bool clearKey = false,
    SpeechStatus? status,
    int? chunkIndex,
    int? total,
    double? rate,
    int? globalRepeat,
    bool? muted,
    String? error,
    bool clearError = false,
  }) =>
      SpeechState(
        key: clearKey ? null : (key ?? this.key),
        status: status ?? this.status,
        chunkIndex: chunkIndex ?? this.chunkIndex,
        total: total ?? this.total,
        rate: rate ?? this.rate,
        globalRepeat: globalRepeat ?? this.globalRepeat,
        muted: muted ?? this.muted,
        error: clearError ? null : (error ?? this.error),
      );
}
