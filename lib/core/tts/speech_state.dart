enum SpeechStatus { idle, playing, paused }

class SpeechState {
  final String? key;
  final SpeechStatus status;
  final int chunkIndex;
  final int total;
  final double rate;

  /// 0 = خاموش | 2 = دوبار | 3 = سه‌بار | -1 = بی‌نهایت
  final int globalRepeat;
  final bool muted;
  final String? error;

  /// A-B state: 'idle' | 'waitingB' | 'looping'
  final String abState;
  final int? abChunkA;
  final int? abChunkB;

  const SpeechState({
    this.key,
    this.status = SpeechStatus.idle,
    this.chunkIndex = 0,
    this.total = 0,
    this.rate = 1.0,
    this.globalRepeat = 0,
    this.muted = false,
    this.error,
    this.abState = 'idle',
    this.abChunkA,
    this.abChunkB,
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
    String? abState,
    int? abChunkA,
    int? abChunkB,
    bool clearAB = false,
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
        abState: abState ?? this.abState,
        abChunkA: clearAB ? null : (abChunkA ?? this.abChunkA),
        abChunkB: clearAB ? null : (abChunkB ?? this.abChunkB),
      );
}
