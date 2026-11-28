// 📁 مسیر: lib/core/widgets/back_translation_line.dart
//
// ↩ ترجمه‌ی برگشتی: ترجمه‌ی «زبانِ مقصد» دوباره به زبانِ مادریِ کاربر برمی‌گردد (بدونِ دیدنِ جمله‌ی اصلی)
// تا کسی که زبانِ مقصد را بلد نیست بفهمد ترجمه درست رفته یا نه.
// فقط مترجمِ رایگان (بدونِ AI و بدونِ هزینه)؛ نتیجه در کشِ مترجم می‌ماند، پس هر جمله یک‌بار حساب می‌شود.
// اگر زبانِ مقصد همان زبانِ مادری باشد، یا ترجمه‌ی برگشتی نشد، هیچ‌چیز نمی‌کشد.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/ai_gateway.dart';
import '../providers/language_selection_provider.dart';
import '../providers/ai_settings_provider.dart';
import '../storage/translation_cache_db.dart';
import '../translate/translation_service.dart' show englishLangName;
import '../usage/free_limit.dart';
import '../providers/text_prefs_provider.dart';
import '../providers/translation_provider.dart';
import '../theme/app_theme_colors.dart';
import '../utils/html_entities.dart';

class BackTranslationLine extends ConsumerStatefulWidget {
  /// زبانِ ترجمه (مثلاً es / zh) و متنِ آن
  final String langCode;
  final String text;
  final bool compact;
  final double leftInset;

  /// متنِ مبدأ و زبانِ آن: اگر ترجمه‌ی برگشتی با ترجمه‌ی زبانِ مادری (ردیفِ بالا) تقریباً یکی باشد
  /// دیگر نشان داده نمی‌شود (شلوغی کم می‌شود)؛ فقط وقتی فرق دارد که ارزشِ دیدن دارد.
  final String en;
  final String sourceLang;

  /// true = همیشه نشان بده (برای «گزینه‌ی دوم»: کاربر باید قبل از انتخاب بتواند چک کند).
  final bool alwaysShow;

  const BackTranslationLine({
    super.key,
    required this.langCode,
    required this.text,
    this.en = '',
    this.sourceLang = 'en',
    this.alwaysShow = false,
    this.compact = false,
    this.leftInset = 36,
  });

  @override
  ConsumerState<BackTranslationLine> createState() =>
      _BackTranslationLineState();
}

class _BackTranslationLineState extends ConsumerState<BackTranslationLine> {
  String? _back;
  String _forKey = '';
  int _gen = 0;
  String? _meaning; // «معنی دقیق» (AI، فقط وقتی کاربر بخواهد)؛ روی گوشی کش می‌شود
  bool _loadingMeaning = false;

  static const Set<String> _rtlLangs = {'fa', 'ar', 'he', 'ur'};

  @override
  void didUpdateWidget(covariant BackTranslationLine old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text || old.langCode != widget.langCode) {
      _forKey = '';
    }
  }

  void _compute(String native) {
    final txt = widget.text.trim();
    final key = '${widget.langCode}|$native|$txt';
    if (key == _forKey) return;
    _forKey = key;
    _back = null;
    _meaning = TranslationCacheDb.instance.peek(_mKey(native));
    _loadingMeaning = false;
    final gen = ++_gen;
    if (txt.isEmpty || native.isEmpty || native == widget.langCode) return;
    () async {
      String r = '';
      try {
        // 🏷️ نام‌های خاص (Kim, Tom…) در ترجمه‌ی برگشتی خراب می‌شدند (金 → «گائو»):
        // معادلِ نام در متنِ ترجمه با خودِ نام جایگزین می‌شود تا برگشتی هم درست بماند.
        final send = await _protectNames(txt);
        r = decodeHtmlEntities((await ref
                .read(translationServiceProvider)
                .translate(
                  text: send,
                  targetLang: native,
                  sourceLang: widget.langCode,
                  aiSettings: null, // فقط رایگان؛ هزینه‌ی AI ندارد
                  aiOnlyIfSuspicious: true,
                ))
            .trim());
      } catch (_) {}
      if (!mounted || gen != _gen) return;
      setState(() => _back = (r.isEmpty || r == txt) ? null : r);
    }();
  }

  /// نرمال‌سازی برای مقایسه: بدونِ فاصله/علامت، یکسان‌سازیِ ی/ک عربی و حذفِ اعراب.
  static String _norm(String s) {
    var t = s
        .toLowerCase()
        .replaceAll('\u064A', '\u06CC')
        .replaceAll('\u0643', '\u06A9')
        .replaceAll(RegExp('[\u064B-\u065F\u0640\u200c\u200d]'), '');
    return t.replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');
  }

  /// شباهتِ دو رشته (Dice روی دوحرفی‌ها) بین ۰ و ۱.
  static double _sim(String a, String b) {
    final x = _norm(a), y = _norm(b);
    if (x.isEmpty || y.isEmpty) return 0;
    if (x == y) return 1;
    if (x.length < 2 || y.length < 2) return 0;
    final m = <String, int>{};
    for (var i = 0; i < x.length - 1; i++) {
      final g = x.substring(i, i + 2);
      m[g] = (m[g] ?? 0) + 1;
    }
    var hit = 0;
    for (var i = 0; i < y.length - 1; i++) {
      final g = y.substring(i, i + 2);
      final n = m[g] ?? 0;
      if (n > 0) {
        hit++;
        m[g] = n - 1;
      }
    }
    return 2 * hit / ((x.length - 1) + (y.length - 1));
  }

  static const Map<String, String> _literalLabel = {
    'fa': 'تحت‌اللفظی',
    'en': 'Literal',
    'ar': 'حرفي',
    'es': 'Literal',
    'de': 'Wörtlich',
    'fr': 'Littéral',
  };
  static const Map<String, String> _meaningBtn = {
    'fa': 'معنی دقیق؟',
    'en': 'Exact meaning?',
    'ar': 'المعنى الدقيق؟',
    'es': '¿Significado exacto?',
    'de': 'Genaue Bedeutung?',
    'fr': 'Sens exact ?',
  };

  static const Set<String> _titleWords = {
    'miss', 'mr', 'mrs', 'ms', 'mister', 'dr', 'doctor', 'professor', 'prof',
    'teacher', 'sir', 'madam', 'uncle', 'aunt', 'coach', 'captain',
  };
  static const Set<String> _notNames = {
    'i', "i'm", "i'll", "i've", "i'd", 'monday', 'tuesday', 'wednesday',
    'thursday', 'friday', 'saturday', 'sunday', 'january', 'february',
    'march', 'april', 'may', 'june', 'july', 'august', 'september',
    'october', 'november', 'december', 'english', 'spanish', 'german',
    'french', 'chinese', 'persian', 'arabic', 'christmas', 'ok', 'okay',
  };

  /// نام‌های خاصِ جمله‌ی مبدأ: واژه‌ی بزرگ‌حرفِ وسطِ جمله (نه اولِ جمله، نه عنوان مثل Miss/Mr).
  /// فهرستِ نام‌ها و عنوانِ قبلِ آن‌ها (یا '') برمی‌گردد.
  List<({String name, String title})> _properNames(String en) {
    final out = <({String name, String title})>[];
    final seen = <String>{};
    final re = RegExp(r"[\p{L}][\p{L}'’.\-]*", unicode: true);
    String prev = '';
    for (final m in re.allMatches(en)) {
      var w = m.group(0)!;
      w = w.replaceAll(RegExp(r"(['’]s)$"), '').replaceAll(RegExp(r'[.\-]+$'), '');
      if (w.isEmpty) continue;
      final lw = w.toLowerCase();
      final before = en.substring(0, m.start).trimRight();
      final sentenceStart =
          before.isEmpty || RegExp(r'[.!?…؟]$').hasMatch(before);
      final upper = w[0] != w[0].toLowerCase();
      final allCaps = w.length > 1 && w == w.toUpperCase();
      if (upper &&
          !allCaps &&
          !sentenceStart &&
          w.length >= 2 &&
          !_titleWords.contains(lw) &&
          !_notNames.contains(lw) &&
          seen.add(lw)) {
        out.add((name: w, title: _titleWords.contains(prev) ? prev : ''));
      }
      prev = lw;
    }
    return out;
  }

  /// معادلِ نام در متنِ ترجمه را پیدا و با خودِ نام عوض می‌کند (فقط اگر پیدا شد؛ وگرنه متن دست‌نخورده).
  Future<String> _protectNames(String txt) async {
    final en = widget.en.trim();
    if (en.isEmpty || widget.sourceLang == widget.langCode) return txt;
    final names = _properNames(en);
    if (names.isEmpty) return txt;
    final svc = ref.read(translationServiceProvider);
    Future<String> tr(String t) async {
      try {
        return decodeHtmlEntities((await svc.translate(
          text: t,
          targetLang: widget.langCode,
          sourceLang: widget.sourceLang,
          aiSettings: null,
          aiOnlyIfSuspicious: true,
        ))
            .trim());
      } catch (_) {
        return '';
      }
    }

    var send = txt;
    for (final n in names) {
      final cands = <String>[];
      final c1 = await tr(n.name);
      if (c1.isNotEmpty && c1 != n.name) cands.add(c1);
      if (n.title.isNotEmpty) {
        // «Miss Kim» → «金小姐» منهای «Miss» → «小姐» = «金»
        final phrase = await tr('${n.title[0].toUpperCase()}${n.title.substring(1)} ${n.name}');
        final tOnly = await tr('${n.title[0].toUpperCase()}${n.title.substring(1)}');
        if (phrase.isNotEmpty && tOnly.isNotEmpty && phrase.contains(tOnly)) {
          final rest = phrase.replaceFirst(tOnly, '').replaceAll(RegExp(r'[\s،,.。]'), '');
          if (rest.isNotEmpty && rest != n.name) cands.add(rest);
        }
      }
      for (final cnd in cands) {
        if (cnd.length >= 1 && send.contains(cnd)) {
          send = send.replaceAll(cnd, ' ${n.name} ');
          break;
        }
      }
    }
    return send.replaceAll(RegExp(r'[ ]{2,}'), ' ').trim();
  }

  String _mKey(String native) =>
      '__mean__::$native::${widget.langCode}::${widget.en.trim()}::${widget.text.trim()}';

  /// 💡 «معنی دقیق؟»: یک‌بار AI می‌گوید این ترجمه برای یک بومی واقعاً چه معنایی دارد (نه کلمه‌به‌کلمه)
  /// و اگر غلط/غیرطبیعی است، ترجمه‌ی بهتر پیشنهاد می‌دهد. فقط Pro؛ جواب روی گوشی کش می‌شود.
  Future<void> _askMeaning(String native) async {
    if (_loadingMeaning) return;
    if (FreeLimit.blockUnlessPro()) return;
    final key = _mKey(native);
    setState(() => _loadingMeaning = true);
    String? out;
    try {
      final svc = ref.read(translationServiceProvider);
      final ai = ref.read(aiSettingsProvider);
      final nat = englishLangName(native);
      final tgt = englishLangName(widget.langCode);
      final en = widget.en.trim();
      final prompt = StringBuffer()
        ..writeln('You are a precise translation checker.');
      if (en.isNotEmpty) {
        prompt.writeln(
            'Source (${englishLangName(widget.sourceLang)}): "$en"');
      }
      prompt
        ..writeln('Translation ($tgt): "${widget.text.trim()}"')
        ..writeln(
            'In $nat, in ONE short sentence, say what this translation really means to a native $tgt speaker in this situation (the natural meaning, not word-for-word).')
        ..writeln(
            'If the translation is wrong or unnatural, add a second line starting with ⚠ that gives a better $tgt translation.')
        ..write('Output only these lines, plain text.');
      out = (await aiGenerate(
        svc: svc,
        settings: ai,
        prompt: prompt.toString(),
        maxTokens: 300,
        retries: 1,
        timeoutMs: 20000,
        feature: Feature.chat,
      ))
          .trim();
    } catch (_) {}
    if (out != null && out.isNotEmpty) {
      await TranslationCacheDb.instance.put(key, out);
    }
    if (!mounted) return;
    final ok = out != null && out.isNotEmpty;
    setState(() {
      _loadingMeaning = false;
      if (ok && key == _mKey(native)) _meaning = out;
    });
    if (!ok) {
      final fa = native == 'fa';
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(fa ? 'پاسخی نیامد، دوباره امتحان کن' : 'No response, try again'),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final native =
        ref.watch(languageSelectionProvider.select((s) => s.native));
    if (native.isEmpty || native == widget.langCode) {
      return const SizedBox.shrink();
    }
    _compute(native);
    final b = _back;
    if (b == null) return const SizedBox.shrink();

    // ترجمه‌ی برگشتی ≈ ترجمه‌ی زبانِ مادری → یعنی همه‌چیز درست است؛ چیزی نشان نده
    if (!widget.alwaysShow && widget.en.trim().isNotEmpty) {
      String? nat;
      try {
        nat = ref
            .read(translationServiceProvider)
            .peekCached(widget.en, widget.sourceLang, native);
      } catch (_) {}
      if (nat != null && nat.trim().isNotEmpty && _sim(b, nat) >= 0.5) {
        return const SizedBox.shrink();
      }
    }

    final c = context.appColors;
    final tp = ref.watch(textPrefsProvider);
    final rtl = _rtlLangs.contains(native);
    final fs = (widget.compact ? 10.5 : 11) * tp.scaleFactor;
    final base = TextStyle(
      color: c.inkSoft.withOpacity(0.8),
      fontSize: fs,
      height: 1.3,
    );
    final label = _literalLabel[native] ?? _literalLabel['en']!;
    final btn = _meaningBtn[native] ?? _meaningBtn['en']!;
    final m = _meaning;
    return Padding(
      padding: EdgeInsets.only(left: widget.leftInset, top: 1, bottom: 2),
      child: Align(
        alignment: rtl ? Alignment.centerRight : Alignment.centerLeft,
        child: Directionality(
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.subdirectory_arrow_left_rounded,
                      size: 12, color: c.inkSoft.withOpacity(0.55)),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text.rich(
                      TextSpan(children: [
                        // ↩ برچسب: این ترجمه‌ی برگشتیِ کلمه‌به‌کلمه است، نه معنیِ اصطلاحی
                        TextSpan(
                          text: '$label: ',
                          style: base.copyWith(
                            fontWeight: FontWeight.w700,
                            fontStyle: FontStyle.italic,
                            fontSize: fs - 1,
                          ),
                        ),
                        TextSpan(text: b),
                      ]),
                      textAlign: rtl ? TextAlign.right : TextAlign.left,
                      style: base,
                    ),
                  ),
                ],
              ),
              if (m != null && m.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lightbulb_outline_rounded,
                          size: 12, color: c.gold),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          m,
                          textAlign: rtl ? TextAlign.right : TextAlign.left,
                          style: base.copyWith(
                            color: c.inkSoft,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                InkWell(
                  onTap: _loadingMeaning ? null : () => _askMeaning(native),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_loadingMeaning)
                          SizedBox(
                            width: 11,
                            height: 11,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.6, color: c.gold),
                          )
                        else
                          Icon(Icons.help_outline_rounded,
                              size: 12, color: c.gold),
                        const SizedBox(width: 4),
                        Text(
                          btn,
                          style: base.copyWith(
                            color: c.gold,
                            fontWeight: FontWeight.w700,
                            fontSize: fs - 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
