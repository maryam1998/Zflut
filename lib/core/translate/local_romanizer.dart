// 📁 مسیر: lib/core/translate/local_romanizer.dart
//
// 🔤 رومی‌سازیِ «روی خودِ گوشی» برای هندی و روسی (بدونِ شبکه، بدونِ AI، فوری).
// پورتِ دقیقِ romanize_hi / romanize_ru از scripts/romanize-static.py (همان خروجیِ فایلِ ثابت).
//
// کجا استفاده می‌شود: فقط به‌عنوانِ «جایگزینِ آخر» در Romanization.lookup؛
// یعنی اگر Worker رومی‌سازی داده بود (یا در فایلِ ثابت بود) همان نشان داده می‌شود،
// وگرنه (ترجمه از کش/فایلِ داخلِ اپ آمده و Worker صدا زده نشده) این جا خالی را پر می‌کند.
// چینی: پین‌یینِ همراهِ تُن با بسته‌ی lpinyin (فرهنگ‌لغتِ داخلِ بسته).
// ژاپنی: روماجی با بسته‌ی kuroshiro (غیرهمگام). convert برای ژاپنی اولین بار null می‌دهد، تبدیل را در پس‌زمینه انجام می‌دهد،
// و بعد با LocalRomanizer.updates به RomanLine خبر می‌دهد تا دوباره بسازد. کره‌ای همچنان فقط از Worker/فایلِ ثابت.

import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint;
import 'package:kuroshiro/kuroshiro.dart';
import 'package:lpinyin/lpinyin.dart';

class LocalRomanizer {
  LocalRomanizer._();

  static const Set<String> langs = {'hi', 'ru', 'zh', 'ja'};

  static final Map<String, String> _memo = <String, String>{};

  /// خوانشِ لاتینِ [text] یا null. همگام و سریع (نتیجه کش می‌شود).
  static String? convert(String lang, String text) {
    if (!langs.contains(lang)) return null;
    if (lang == 'ja') return _jaLookup(text); // غیرهمگام: از کش، وگرنه null + تبدیل در پس‌زمینه
    final key = '$lang|$text';
    final hit = _memo[key];
    if (hit != null) return hit.isEmpty ? null : hit;
    String out;
    try {
      out = lang == 'hi' ? _hi(text) : (lang == 'zh' ? _zh(text) : _ruConvert(text));
    } catch (_) {
      out = '';
    }
    if (_memo.length > 800) _memo.remove(_memo.keys.first);
    _memo[key] = out;
    return out.isEmpty ? null : out;
  }

  // ───────────────────────── پس‌پردازشِ مشترک ─────────────────────────
  static const Map<String, String> _punct = {
    '。': '. ', '｡': '. ', '．': '. ', '।': '. ', '॥': '. ',
    '，': ', ', '、': ', ', '､': ', ',
    '！': '! ', '？': '? ', '：': ': ', '；': '; ',
    '（': ' (', '）': ') ', '［': ' [', '］': '] ',
    '“': '"', '”': '"', '«': '"', '»': '"', '‘': "'", '’': "'",
    '—': ' - ', '–': '-',
    '०': '0', '१': '1', '२': '2', '३': '3', '४': '4',
    '५': '5', '६': '6', '७': '7', '८': '8', '९': '9',
  };

  static final RegExp _wsRe = RegExp(r'\s+');
  static final RegExp _spBeforeRe = RegExp(r'\s+([,.!?;:)\]])');
  static final RegExp _spAfterOpenRe = RegExp(r'([(\[])\s+');
  static final RegExp _quoteSpRe = RegExp(r'"\s+(?=[,.!?;:])');
  static final RegExp _capRe =
      RegExp(r'''(^|[.!?…]\s+)(["(\[]?)([A-Za-z])''');

  static String _tidy(String s0) {
    final sb = StringBuffer();
    for (var i = 0; i < s0.length; i++) {
      final ch = s0[i];
      sb.write(_punct[ch] ?? ch);
    }
    var s = sb.toString();
    s = s.replaceAll(_wsRe, ' ');
    s = s.replaceAllMapped(_spBeforeRe, (m) => m[1]!);
    s = s.replaceAllMapped(_spAfterOpenRe, (m) => m[1]!);
    s = s.replaceAll(_quoteSpRe, '"');
    s = s.trim();
    s = s.replaceAllMapped(
        _capRe, (m) => '${m[1]}${m[2]}${m[3]!.toUpperCase()}');
    return s;
  }

  // ───────────────────────── هندی ─────────────────────────
  static const Map<String, String> _hiVowels = {
    'अ': 'a', 'आ': 'aa', 'इ': 'i', 'ई': 'ee', 'उ': 'u', 'ऊ': 'oo', 'ऋ': 'ri',
    'ए': 'e', 'ऐ': 'ai', 'ओ': 'o', 'औ': 'au', 'ऑ': 'o', 'ऍ': 'e',
  };
  static const Map<String, String> _hiMatras = {
    'ा': 'aa', 'ि': 'i', 'ी': 'ee', 'ु': 'u', 'ू': 'oo', 'ृ': 'ri',
    'े': 'e', 'ै': 'ai', 'ो': 'o', 'ौ': 'au', 'ॉ': 'o', 'ॅ': 'e',
  };
  static const Map<String, String> _hiCons = {
    'क': 'k', 'ख': 'kh', 'ग': 'g', 'घ': 'gh', 'ङ': 'ng',
    'च': 'ch', 'छ': 'chh', 'ज': 'j', 'झ': 'jh', 'ञ': 'ny',
    'ट': 't', 'ठ': 'th', 'ड': 'd', 'ढ': 'dh', 'ण': 'n',
    'त': 't', 'थ': 'th', 'द': 'd', 'ध': 'dh', 'न': 'n',
    'प': 'p', 'फ': 'ph', 'ब': 'b', 'भ': 'bh', 'म': 'm',
    'य': 'y', 'र': 'r', 'ल': 'l', 'व': 'v', 'श': 'sh', 'ष': 'sh', 'स': 's', 'ह': 'h',
    'ळ': 'l',
  };
  static const Map<String, String> _hiNukta = {
    'क': 'q', 'ख': 'kh', 'ग': 'g', 'ज': 'z', 'ड': 'r', 'ढ': 'rh', 'फ': 'f', 'य': 'y',
  };
  // حرف‌های «از پیش ترکیب‌شده» (क़ ख़ …) ← پایه + نقطه
  static const Map<String, String> _nuktaPre = {
    '\u0958': '\u0915', '\u0959': '\u0916', '\u095A': '\u0917', '\u095B': '\u091C',
    '\u095C': '\u0921', '\u095D': '\u0922', '\u095E': '\u092B', '\u095F': '\u092F',
  };
  static const String _virama = '\u094D';
  static const String _nukta = '\u093C';
  static const Map<String, String> _nasals = {'ं': 'n', 'ँ': 'n', 'ः': 'h'};
  static const Set<String> _labials = {'प', 'फ', 'ब', 'भ', 'म'};
  static final RegExp _devaRe = RegExp(r'[\u0900-\u097F]+');

  static String _hi(String text) =>
      _tidy(text.replaceAllMapped(_devaRe, (m) => _hiWord(m[0]!)));

  static String _hiWord(String word0) {
    var word = word0;
    _nuktaPre.forEach((k, v) => word = word.replaceAll(k, v + _nukta));

    final units = <_Unit>[];
    List<String>? cons; // خوشه‌ی همخوانِ هجای در حالِ ساخت
    var open = false; // بعد از virama

    void flush(String? vowel) {
      final c = cons;
      if (c != null) {
        units.add(_Unit(c.join(), c.length > 1, vowel, ''));
        cons = null;
        open = false;
      }
    }

    final n = word.length;
    var i = 0;
    while (i < n) {
      final ch = word[i];
      final base = _hiCons[ch];
      if (base != null) {
        var rom = base;
        if (i + 1 < n && word[i + 1] == _nukta) {
          rom = _hiNukta[ch] ?? rom;
          i++;
        }
        final c = cons;
        if (c != null && open) {
          c.add(rom);
          open = false;
        } else {
          flush(null);
          cons = <String>[rom];
          open = false;
        }
      } else if (ch == _virama) {
        if (cons != null) open = true;
      } else if (_hiMatras.containsKey(ch)) {
        flush(_hiMatras[ch]);
      } else if (_hiVowels.containsKey(ch)) {
        flush(null);
        units.add(_Unit('', false, _hiVowels[ch], ''));
      } else if (_nasals.containsKey(ch)) {
        flush(null);
        if (units.isNotEmpty) {
          final nxt = i + 1 < n ? word[i + 1] : '';
          units.last.nasal =
              (ch == 'ं' && _labials.contains(nxt)) ? 'm' : _nasals[ch]!;
        }
      } else if (ch == _nukta) {
        // نقطه‌ی تنها: نادیده
      } else {
        flush(null);
        units.add(_Unit(ch, false, '', ''));
      }
      i++;
    }
    final rest = cons;
    if (rest != null) {
      if (open) {
        units.add(_Unit(rest.join(), rest.length > 1, '', ''));
        cons = null;
      } else {
        flush(null);
      }
    }

    // ── حذفِ schwa ──
    bool isSchwa(_Unit u) => u.v == null && u.on.isNotEmpty;
    if (units.length > 1 && isSchwa(units.last) && units.last.nasal.isEmpty) {
      units.last.v = '';
    }
    for (var k = units.length - 2; k > 0; k--) {
      final u = units[k];
      final prev = units[k - 1];
      final nxt = units[k + 1];
      if (!isSchwa(u) || u.nasal.isNotEmpty || u.cl) continue;
      if (prev.v == '') continue;
      if (nxt.v == '' || nxt.cl) continue;
      u.v = '';
    }

    final out = StringBuffer();
    final last = units.length - 1;
    for (var idx = 0; idx <= last; idx++) {
      final u = units[idx];
      var v = (u.v == null && u.on.isNotEmpty) ? 'a' : (u.v ?? '');
      if (v == 'aa' && idx == last && u.on.isNotEmpty && u.nasal.isEmpty) {
        v = 'a'; // کا → ka
      } else if (v == 'ee' && (idx == last || (u.on.isEmpty && idx > 0))) {
        v = 'i'; // भी → bhi ، हुई → hui
      } else if (v == 'e' && u.nasal == 'n') {
        v = 'ei'; // में → mein
      }
      out.write(u.on + v + u.nasal);
    }
    return out.toString();
  }

  // ───────────────────────── چینی (پین‌یین) ─────────────────────────
  static final RegExp _hanRe = RegExp(r'[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF]+');

  static String _zh(String text) {
    final r = text.replaceAllMapped(_hanRe, (m) {
      final py = PinyinHelper.getPinyin(
        m[0]!,
        separator: ' ',
        format: PinyinFormat.WITH_TONE_MARK,
      );
      return ' $py ';
    });
    return _tidy(r);
  }

  // ───────────────────────── ژاپنی (روماجی با kuroshiro) ─────────────────────────
  /// هر بار که یک رومی‌سازیِ ژاپنی آماده شد یک واحد زیاد می‌شود (RomanLine گوش می‌دهد).
  static final ValueNotifier<int> updates = ValueNotifier<int>(0);

  static final Map<String, String> _jaMemo = <String, String>{};
  static final Set<String> _jaPending = <String>{};
  static Kuroshiro? _kuro;
  static Future<void>? _kuroInit;
  static DateTime _jaRetryAfter = DateTime.fromMillisecondsSinceEpoch(0);
  static final RegExp _jaRe =
      RegExp(r'[\u3040-\u30FF\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF\uFF66-\uFF9F]');

  static String? _jaLookup(String text) {
    if (!_jaRe.hasMatch(text)) return null; // هیچ حرفِ ژاپنی‌ای نیست
    final hit = _jaMemo[text];
    if (hit != null) return hit.isEmpty ? null : hit;
    _jaSchedule(text);
    return null;
  }

  static void _jaSchedule(String text) {
    if (_jaPending.contains(text)) return;
    if (DateTime.now().isBefore(_jaRetryAfter)) return; // بعد از خطا چند ثانیه صبر
    _jaPending.add(text);
    () async {
      try {
        if (_kuro == null) {
          final k = Kuroshiro();
          _kuroInit ??= k.init();
          await _kuroInit;
          _kuro = k;
        }
        final r = await _kuro!.convert(
          text,
          to: ConvertTo.romaji,
          mode: ConvertMode.spaced,
        );
        final out = _tidy(r);
        if (_jaMemo.length > 800) _jaMemo.remove(_jaMemo.keys.first);
        _jaMemo[text] = out;
        updates.value++;
      } catch (e) {
        debugPrint('LocalRomanizer(ja): $e');
        _kuroInit = null; // دفعه‌ی بعد دوباره تلاش شود
        _jaRetryAfter = DateTime.now().add(const Duration(seconds: 30));
      } finally {
        _jaPending.remove(text);
      }
    }();
  }

  // ───────────────────────── روسی ─────────────────────────
  static const Map<String, String> _ru = {
    'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'ё': 'yo', 'ж': 'zh', 'з': 'z', 'и': 'i',
    'й': 'y', 'к': 'k', 'л': 'l', 'м': 'm', 'н': 'n', 'о': 'o', 'п': 'p', 'р': 'r', 'с': 's',
    'т': 't', 'у': 'u', 'ф': 'f', 'х': 'kh', 'ц': 'ts', 'ч': 'ch', 'ш': 'sh', 'щ': 'shch',
    'ъ': '', 'ы': 'y', 'ь': '', 'э': 'e', 'ю': 'yu', 'я': 'ya',
  };
  static const Set<String> _ruVowelSigns = {
    'а', 'е', 'ё', 'и', 'о', 'у', 'э', 'ю', 'я', 'ъ', 'ь',
  };
  static final RegExp _letterRe = RegExp(r'\p{L}', unicode: true);

  static bool _isAlpha(String s) => s.isNotEmpty && _letterRe.hasMatch(s);
  static bool _isUpper(String s) => s != s.toLowerCase();

  static String _ruConvert(String text) {
    final out = StringBuffer();
    final n = text.length;
    for (var i = 0; i < n; i++) {
      final ch = text[i];
      final low = ch.toLowerCase();
      String rep;
      if (low == 'е') {
        final prev = i > 0 ? text[i - 1].toLowerCase() : '';
        rep = (!_isAlpha(prev) || _ruVowelSigns.contains(prev)) ? 'ye' : 'e';
      } else if (_ru.containsKey(low)) {
        rep = _ru[low]!;
      } else {
        out.write(ch);
        continue;
      }
      if (ch != low && rep.isNotEmpty) {
        final nxt = i + 1 < n ? text[i + 1] : '';
        final prv = i > 0 ? text[i - 1] : '';
        final allCaps =
            (_isAlpha(nxt) && _isUpper(nxt)) || (_isAlpha(prv) && _isUpper(prv));
        rep = (allCaps && rep.length > 1)
            ? rep.toUpperCase()
            : rep[0].toUpperCase() + rep.substring(1);
      }
      out.write(rep);
    }
    return _tidy(out.toString());
  }
}

class _Unit {
  String on; // همخوان(ها)
  bool cl; // خوشه (بیش از یک همخوان)
  String? v; // null = schwa، '' = بدونِ مصوت
  String nasal;
  _Unit(this.on, this.cl, this.v, this.nasal);
}
