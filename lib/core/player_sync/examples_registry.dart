import 'player_track.dart';

/// مثال‌های هوش مصنوعیِ «بازِ» هر لغت (پنل‌های مثالِ روی صفحه). پلیرِ لیست
/// با این اطلاعات بعد از خواندنِ هر لغت، مثال‌هایش را هم می‌خواند.
class ExamplesRegistry {
  /// true = صفِ خوانشِ پس‌زمینه (لغت ← ترجمه ← مثال ← ترجمه‌ی مثال) در حال کار است؛
  /// پنلِ مثال‌ها در این حالت مثالِ بعدی را خودش پخش نمی‌کند.
  static bool bgDriving = false;

  static final Map<String, ({String word, String lang, List<String> texts})>
      _open = {};

  static String _k(String lang, String word) =>
      '$lang::${word.trim().toLowerCase()}';

  static void set(String lang, String word, List<String> texts) {
    if (texts.isEmpty) {
      _open.remove(_k(lang, word));
    } else {
      _open[_k(lang, word)] = (word: word, lang: lang, texts: List.of(texts));
    }
  }

  static void remove(String lang, String word) {
    _open.remove(_k(lang, word));
    _chains.remove(_k(lang, word));
  }

  /// 🔗 زنجیره‌ی خوانشِ پنلِ بازِ هر لغت: مثال ۱ ← ترجمه‌هایش ← مثال ۲ ← ترجمه‌هایش …
  /// (کلیدِ پخشِ هر عضو، به ترتیب). پنل هر بار که build می‌شود ثبتش می‌کند؛
  /// تابع هنگامِ فراخوانی از حافظه‌ی مثال‌ها محاسبه می‌شود تا همیشه به‌روز باشد.
  static final Map<String,
      ({String word, String lang, List<String> Function() keys})> _chains = {};

  static void setChain(
          String lang, String word, List<String> Function() keys) =>
      _chains[_k(lang, word)] = (word: word, lang: lang, keys: keys);

  static List<String>? textsFor(String lang, String word) =>
      _open[_k(lang, word)]?.texts;

  /// صاحبِ مثالی که با این کلیدِ پخش خوانده می‌شود (یا null)
  static ({String word, String lang, int index, int count})? ownerOfKey(
      String key) {
    // اول زنجیره‌ی کامل (مثال‌ها + ترجمه‌هایشان): index/count جایگاهِ کلید در زنجیره است،
    // پس پلیرِ لیست تا آخرِ زنجیره صبر می‌کند و بعد لغتِ بعدی را می‌خواند.
    for (final c in _chains.values) {
      List<String> ks;
      try {
        ks = c.keys();
      } catch (_) {
        continue;
      }
      final i = ks.indexOf(key);
      if (i >= 0) return (word: c.word, lang: c.lang, index: i, count: ks.length);
    }
    for (final e in _open.values) {
      for (var i = 0; i < e.texts.length; i++) {
        if (PlayerTrack.keyFor(e.lang, e.texts[i]) == key) {
          return (word: e.word, lang: e.lang, index: i, count: e.texts.length);
        }
      }
    }
    return null;
  }
}
