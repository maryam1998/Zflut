import '../models/daily_word.dart';
import 'word_asset_loader.dart';

class DailyWordsRepository {
  DailyWordsRepository._();
  static final DailyWordsRepository instance = DailyWordsRepository._();

  List<DailyWord> _words = const [];
  bool _loaded = false;
  String? _error;

  List<DailyWord> get words => _words;
  bool get isLoaded => _loaded;
  String? get error => _error;

  Future<void>? _inflight;

  /// فقط یک‌بار اجرا می‌شود؛ فراخوانی‌های هم‌زمان همان Future را می‌گیرند.
  /// [force] = دوباره از نو بارگذاری کن (وقتی Pro شد/محتوای پولی به‌روز شد).
  Future<void> load({bool force = false}) {
    if (force) {
      _loaded = false;
      _inflight = null;
    }
    return _inflight ??= _doLoad();
  }

  Future<void> _doLoad() async {
    if (_loaded) return;
    try {
      _words = await loadWordsAsset('assets/data/daily_words.json',
          paidList: 'daily');
      _loaded = true;
      _error = null;
    } catch (e) {
      _error = e.toString();
      _loaded = false;
      _inflight = null; // بار بعد دوباره تلاش شود
    }
  }
}
