import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/level_chips.dart';
import '../../core/constants/supported_languages.dart';
import '../../core/providers/ai_settings_provider.dart';
import '../../core/providers/conversation_provider.dart';
import '../../core/providers/language_selection_provider.dart';
import '../../core/providers/reader_providers.dart';
import '../../core/models/text_prefs.dart';
import '../../core/native/native_bridge.dart';
import '../../core/providers/story_library_provider.dart';
import '../../core/providers/text_prefs_provider.dart';
import '../../core/providers/translation_provider.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../core/translate/translation_service.dart'
    show runWithConcurrencyLimit;
import '../../core/web/reading_io_stub.dart'
    if (dart.library.html) '../../core/web/reading_io_web.dart';
import 'package:flutter/gestures.dart';
import '../../core/audio/story_audio_controller.dart';
import '../../core/storage/local_storage.dart' show sharedPrefsProvider;
import '../story/srt_translator_tool.dart';
import '../story/story_audio_bar.dart';
import '_hope_panel.dart';

// ═══════════════════════════════════════════════════════════════════
// تب «داستان‌ساز» — هم‌شکل StoryBuilder.jsx در Hope
// عنوان، سوئیچ دوقسمتی (ساخت داستان / کتابخانه‌ی من)، کارت تنظیمات
// (زبان و سطح، نوع محتوا، طول)، کارت انتخاب لغت، دکمه‌ی «داستان بساز».
// ═══════════════════════════════════════════════════════════════════

class _Opt {
  final String key;
  final String label;
  final String prompt;
  const _Opt(this.key, this.label, this.prompt);
}

const List<_Opt> _kContentTypes = [
  _Opt('general', 'عمومی', 'a general, everyday short story'),
  _Opt('news', 'خبری', 'a short news-style report, written like a news article'),
  _Opt('psychology', 'روان‌شناسی',
      'a short piece exploring a psychology or self-understanding theme'),
  _Opt('children', 'کودکانه', "a simple, gentle children's story"),
  _Opt('funny', 'خنده‌دار',
      'a lighthearted, funny, comedic story with a humorous twist'),
  _Opt('mystery', 'رازآلود و ترسناک',
      'a suspenseful, mysterious, slightly scary story with an eerie atmosphere'),
  _Opt('crime', 'جنایی',
      'a crime/detective story involving an investigation or mystery to solve'),
  _Opt('scientific', 'علمی',
      'a short popular-science explainer written as a narrative'),
  _Opt('conversational', 'مکالمه‌ای',
      'a natural back-and-forth dialogue between two people'),
  _Opt('philosophical', 'فلسفی',
      'a short philosophical reflection or thought experiment'),
  _Opt('metaphysical', 'متافیزیکی',
      'a short metaphysical/speculative piece about existence, mind, or reality'),
];

class _Len {
  final String key;
  final String label;
  final String paragraphs;
  final String hint;
  final int tokens;
  const _Len(this.key, this.label, this.paragraphs, this.hint, this.tokens);
}

const List<_Len> _kLengths = [
  _Len('short', 'کوتاه', '1-2', 'short, roughly 4-6 sentences per paragraph',
      1100),
  _Len('medium', 'متوسط', '2-3', 'medium length, roughly 5-8 sentences per paragraph',
      1900),
  _Len('long', 'بلند', '4-6', 'long, roughly 6-10 sentences per paragraph',
      3200),
];

String _enName(String code) {
  for (final l in kSupportedLanguages) {
    if (l.code == code) return l.enLabel;
  }
  return code;
}

String _contentLabel(String key) {
  if (key == 'reading') return 'خوانش';
  for (final c in _kContentTypes) {
    if (c.key == key) return c.label;
  }
  return 'عمومی';
}

String _stripThink(String t) => t
    .replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '')
    .replaceAll(RegExp(r'<think>[\s\S]*$', caseSensitive: false), '')
    .trim();


// ───────────── کمکی‌های وارد کردنِ متن برای خوانش (پورتِ ساده‌ی Hope) ─────────────
const int _kSentencesPerParagraph = 5;
const int _kMaxImportSentences = 2000;
const int _kMaxWordsPerSentence = 40;

List<String> _splitSentences(String text) {
  final t = text.trim();
  if (t.isEmpty) return const [];
  final protectedT =
      t.replaceAllMapped(RegExp(r'(\d)\.(?=\d)'), (m) => '${m[1]}\u0001');
  final raw = RegExp(r'[^.!?؟。！]+[.!?؟。！]*')
      .allMatches(protectedT)
      .map((m) => m.group(0)!.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  final parts = (raw.isEmpty ? [protectedT] : raw)
      .map((e) => e.replaceAll('\u0001', '.'))
      .toList();
  final out = <String>[];
  for (final part in parts) {
    final words = part.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length <= _kMaxWordsPerSentence) {
      out.add(part);
      continue;
    }
    for (var i = 0; i < words.length; i += _kMaxWordsPerSentence) {
      final end = i + _kMaxWordsPerSentence > words.length
          ? words.length
          : i + _kMaxWordsPerSentence;
      out.add(words.sublist(i, end).join(' '));
    }
  }
  return out;
}

/// تشخیصِ سادته‌ی زبانِ متن از روی خطِ نوشتاری.
String _detectLang(String text, String fallback) {
  var arabic = 0, cyr = 0, deva = 0, kana = 0, hangul = 0, cjk = 0, latin = 0;
  var persian = 0;
  for (final r in text.runes) {
    if (r >= 0x0600 && r <= 0x06FF) {
      arabic++;
      if (r == 0x067E || r == 0x0686 || r == 0x0698 || r == 0x06AF) {
        persian++;
      }
    } else if (r >= 0x0400 && r <= 0x04FF) {
      cyr++;
    } else if (r >= 0x0900 && r <= 0x097F) {
      deva++;
    } else if (r >= 0x3040 && r <= 0x30FF) {
      kana++;
    } else if (r >= 0xAC00 && r <= 0xD7AF) {
      hangul++;
    } else if (r >= 0x4E00 && r <= 0x9FFF) {
      cjk++;
    } else if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A) ||
        (r >= 0xC0 && r <= 0x24F)) {
      latin++;
    }
  }
  final max = [arabic, cyr, deva, kana, hangul, cjk, latin]
      .reduce((a, b) => a > b ? a : b);
  if (max == 0) return fallback;
  if (max == arabic) return persian > 0 ? 'fa' : 'ar';
  if (max == cyr) return 'ru';
  if (max == deva) return 'hi';
  if (max == kana) return 'ja';
  if (max == hangul) return 'ko';
  if (max == cjk) return kana > 0 ? 'ja' : 'zh';
  // زبان‌های لاتین: شمارشِ کلماتِ خیلی پرتکرار (مثلِ Hope)
  const stop = <String, List<String>>{
    'de': ['der','die','das','und','ist','nicht','mit','für','ein','eine','sie','auf','was','wie','wenn','aber','auch','sich','dass','ich'],
    'es': ['el','la','los','las','de','que','y','en','no','es','un','una','para','por','con','su','del','al','se','lo'],
    'fr': ['le','la','les','et','est','une','des','dans','pour','que','qui','ne','pas','ce','vous','je','nous','avec','au','un'],
    'it': ['il','la','di','che','è','un','una','per','non','con','gli','le','sono','questo','questa','del','alla','si','mi','ma'],
    'tr': ['ve','bir','bu','için','ile','de','da','çok','ama','ne','gibi','daha','var','yok','ben','sen','biz','onun','şey','değil'],
    'en': ['the','and','is','to','of','in','that','it','was','for','on','with','he','she','you','this','but','not','are','as'],
  };
  final words = RegExp(r'[a-zàâäçèéêëîïôöùûüÿñßışğî]+')
      .allMatches(text.toLowerCase())
      .map((m) => m.group(0)!)
      .toSet();
  var bestCode = fallback;
  var bestScore = 0;
  stop.forEach((code, list) {
    final sc = list.where(words.contains).length;
    if (sc > bestScore) {
      bestScore = sc;
      bestCode = code;
    }
  });
  if (bestScore > 0) return bestCode;
  const latinLangs = ['en', 'es', 'de', 'fr', 'it', 'tr'];
  return latinLangs.contains(fallback) ? fallback : 'en';
}

/// حدسِ سطحِ CEFR از روی خودِ متن (همان فرمولِ detectTextCEFRLevel در Hope).
String _detectCefr(String text) {
  final t = text.trim();
  if (t.isEmpty) return 'A2';
  final sentences = _splitSentences(t);
  final words = t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty || sentences.isEmpty) return 'A2';
  final clean = words
      .map((w) => w.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), ''))
      .where((w) => w.isNotEmpty)
      .toList();
  if (clean.isEmpty) return 'A2';
  final avgSentence = words.length / sentences.length;
  final avgWord = clean.fold<int>(0, (a, w) => a + w.length) / clean.length;
  final longRatio = clean.where((w) => w.length >= 7).length / clean.length;
  final uniqueRatio = clean.map((w) => w.toLowerCase()).toSet().length / clean.length;
  final score = avgSentence + avgWord * 3.0 + longRatio * 40 + uniqueRatio * 15;
  if (score < 14) return 'A1';
  if (score < 19) return 'A2';
  if (score < 24) return 'B1';
  if (score < 29) return 'B2';
  if (score < 34) return 'C1';
  return 'C2';
}

String _decodeEntities(String s) => s
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&apos;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final n = int.tryParse(m[1]!);
      return n == null ? '' : String.fromCharCode(n);
    });

/// متنِ اصلیِ یک صفحه‌ی وب (بدونِ منو/فوتر/اسکریپت).
String _extractMainBodyText(String html) {
  var h = html;
  for (final tag in [
    'script', 'style', 'noscript', 'nav', 'header', 'footer', 'aside',
    'form', 'svg', 'iframe'
  ]) {
    h = h.replaceAll(
        RegExp('<$tag[\\s\\S]*?</$tag>', caseSensitive: false), ' ');
  }
  h = h.replaceAll(RegExp(r'<!--[\s\S]*?-->'), ' ');
  for (final tag in ['article', 'main']) {
    final m = RegExp('<$tag[\\s\\S]*?</$tag>', caseSensitive: false)
        .firstMatch(h);
    if (m != null &&
        m.group(0)!.replaceAll(RegExp(r'<[^>]+>'), ' ').trim().length > 200) {
      h = m.group(0)!;
      break;
    }
  }
  final blocks = RegExp(r'<(p|h1|h2|h3|li)[^>]*>([\s\S]*?)</\1>',
          caseSensitive: false)
      .allMatches(h)
      .map((m) => _decodeEntities(m.group(2)!.replaceAll(RegExp(r'<[^>]+>'), ' '))
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim())
      .where((e) => e.length > 1)
      .toList();
  if (blocks.isNotEmpty) {
    return blocks
        .map((b) => RegExp(r'[.!?؟。！:]$').hasMatch(b) ? b : '$b.')
        .join(' ');
  }
  return _decodeEntities(h.replaceAll(RegExp(r'<[^>]+>'), ' '))
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class _Match {
  final String word;
  final bool saved;
  const _Match(this.word, this.saved);
}

class StoryTab extends ConsumerStatefulWidget {
  const StoryTab({super.key});

  @override
  ConsumerState<StoryTab> createState() => _StoryTabState();
}

class _StoryTabState extends ConsumerState<StoryTab> {
  bool _showLibrary = false;

  String _storyLang = 'en';
  bool _langTouched = false;
  String _level = 'B1';
  String _contentType = 'general';
  String _length = 'medium';

  final List<String> _words = [];
  final _custom = TextEditingController();
  final _query = TextEditingController();
  bool _translating = false;
  String _note = '';

  bool _generating = false;
  String _error = '';
  SavedStory? _result;

  // زبان‌های ترجمه‌ی همزمانِ داستان
  final Set<String> _transLangs = {};
  bool _transTouched = false;
  bool _storyTranslating = false;

  // وارد کردنِ لینک / متن برای خوانش
  bool _showLink = false;
  bool _showPaste = false;
  bool _linkBusy = false;
  String _importError = '';
  // متنِ واردشده برای خوانش (مثلِ Hope: ذخیره‌ی خودکار نداره، تدریجی ترجمه می‌شه)
  static const int _kParaPage = 15;
  SavedStory? _reading;
  int _visibleParas = _kParaPage;
  final Map<String, List<String>> _readTrans = {};
  bool _readTranslating = false;
  bool _readSaved = false;

  bool _pdfReadBusy = false;
  bool _imgReadBusy = false;
  String _importProgress = '';

  // نمایشگرِ PDF با عکسِ اصلی + ترجمه
  bool _pdfViewBusy = false;
  PdfDocHandle? _pdfDoc;
  String _pdfTitle = '';
  int _pdfIndex = 0;
  bool _pdfPageBusy = false;
  bool _pdfShowOrig = false;
  final Map<int, Uint8List> _pdfImages = {};
  final Map<int, String> _pdfTexts = {};
  final Map<int, String> _pdfTrans = {};
  final _linkCtrl = TextEditingController();
  final _pasteCtrl = TextEditingController();

  // صوتِ آپلودیِ هر داستان (کلید = id داستان) + همگام‌سازیِ هایلایت با متن
  final Map<String, StoryAudioController> _audioCtrls = {};
  final Map<String, List<TapGestureRecognizer>> _tapRecs = {};
  final Map<String, int> _lastScrolled = {};
  final Map<String, List<GlobalKey>> _paraKeys = {};

  String _libLevel = 'all';
  final _libSearch = TextEditingController();
  String? _openStoryId;

  @override
  void initState() {
    super.initState();
    final d = ref.read(storyDraftProvider);
    if (d != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _consumeDraft(d);
      });
    }
  }

  @override
  void dispose() {
    _custom.dispose();
    _query.dispose();
    _libSearch.dispose();
    _linkCtrl.dispose();
    _pasteCtrl.dispose();
    _pdfDoc?.dispose();
    for (final l in _tapRecs.values) {
      for (final r in l) {
        r.dispose();
      }
    }
    for (final a in _audioCtrls.values) {
      a.dispose();
    }
    super.dispose();
  }

  void _consumeDraft(StoryDraft d) {
    setState(() {
      _showLibrary = false;
      _storyLang = d.langCode;
      _langTouched = true;
      for (final w in d.words) {
        if (!_words.contains(w)) _words.add(w);
      }
    });
    ref.read(storyDraftProvider.notifier).state = null;
  }

  String _activeLang(List<String> targets) {
    if (_langTouched) return _storyLang;
    return targets.isNotEmpty ? targets.first : 'en';
  }

  // ───────────── افزودن لغت ─────────────
  Future<void> _addCustom(String lang) async {
    final raw = _custom.text.trim();
    if (raw.isEmpty || _translating) return;
    setState(() {
      _translating = true;
      _note = '';
    });
    var word = raw;
    try {
      final t = (await ref.read(translationServiceProvider).translate(
                text: raw,
                targetLang: lang,
                sourceLang: 'auto',
                aiSettings: ref.read(aiSettingsProvider),
              ))
          .trim();
      if (t.isNotEmpty) word = t;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _translating = false;
      if (!_words.contains(word)) _words.add(word);
      _custom.clear();
      _note = word != raw ? '«$raw» ← «$word»' : '';
    });
  }

  void _toggleWord(String w) {
    setState(() {
      if (!_words.remove(w)) _words.add(w);
    });
  }

  List<_Match> _matches(String lang) {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final out = <_Match>[];
    final seen = <String>{};
    for (final w in ref.read(savedWordsProvider)) {
      if (w.langCode == lang && w.word.toLowerCase().contains(q)) {
        if (seen.add(w.word.toLowerCase())) out.add(_Match(w.word, true));
      }
    }
    if (lang == 'en' || lang == 'fa') {
      for (final d in ref.read(allDailyWordsProvider)) {
        final t = lang == 'en' ? d.en : d.fa;
        if (t.isEmpty || !t.toLowerCase().contains(q)) continue;
        if (seen.add(t.toLowerCase())) out.add(_Match(t, false));
        if (out.length >= 40) break;
      }
    }
    return out;
  }

  // ───────────── ساخت داستان ─────────────
  Future<void> _generate(String lang) async {
    if (_words.isEmpty || _generating) return;
    setState(() {
      _generating = true;
      _error = '';
    });
    final ct = _kContentTypes.firstWhere((c) => c.key == _contentType);
    final ln = _kLengths.firstWhere((l) => l.key == _length);
    final langLabel = _enName(lang);
    final prompt = 'Write ${ct.prompt} in $langLabel at CEFR level $_level.\n'
        'Length: ${ln.paragraphs} paragraphs, ${ln.hint}.\n'
        'You MUST naturally use ALL of these words/phrases (in the exact form given): '
        '${_words.join(', ')}.\n'
        'Output format: the first line must be "TITLE: <a short title in $langLabel>", '
        'then the story text. Plain text only — paragraphs separated by a blank line, '
        'no markdown, no translations, no notes, no word lists.';
    try {
      final raw = await ref.read(translationServiceProvider).callAI(
            prompt: prompt,
            maxTokens: ln.tokens,
            retries: 1,
            settings: ref.read(aiSettingsProvider),
            timeoutMs: 90000,
          );
      var text = _stripThink(raw);
      if (text.isEmpty) throw Exception('empty');
      var title = '';
      final m = RegExp(r'^\s*TITLE:\s*(.+)$',
              multiLine: true, caseSensitive: false)
          .firstMatch(text);
      if (m != null) {
        title = m.group(1)!.replaceAll('*', '').trim();
        text = text.replaceFirst(m.group(0)!, '').trim();
      }
      text = text
          .replaceAll('**', '')
          .replaceAll(RegExp(r'^#+\s*', multiLine: true), '')
          .trim();
      if (title.isEmpty) {
        final first = text.split(RegExp(r'\s+')).take(6).join(' ');
        title = first;
      }
      final story = SavedStory(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: title,
        text: text,
        langCode: lang,
        level: _level,
        contentType: _contentType,
        words: List<String>.from(_words),
        createdAt: DateTime.now(),
      );
      if (!mounted) return;
      _finishStory(story);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error =
          'ساخت داستان انجام نشد. اینترنتت رو چک کن و دوباره امتحان کن.');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }


  // ───────────── ذخیره + ترجمه‌ی همزمانِ داستان ─────────────
  Set<String> _effectiveTransLangs() {
    if (_transTouched) return _transLangs;
    final native = ref.read(languageSelectionProvider).native;
    return {native};
  }

  void _finishStory(SavedStory story) {
    ref.read(storyLibraryProvider.notifier).add(story);
    setState(() {
      _result = story;
      _reading = null;
      _readTrans.clear();
    });
    unawaited(_translateStory(story));
  }

  Future<void> _translateStory(SavedStory story) async {
    final langs =
        _effectiveTransLangs().where((l) => l != story.langCode).toList();
    if (langs.isEmpty) return;
    final paras = story.text
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (paras.isEmpty) return;
    if (mounted) setState(() => _storyTranslating = true);
    final result = <String, List<String>>{};
    try {
      final svc = ref.read(translationServiceProvider);
      final ai = ref.read(aiSettingsProvider);
      for (final code in langs) {
        final out = await runWithConcurrencyLimit<String, String>(
          paras,
          3,
          (p, _) async {
            try {
              return (await svc.translate(
                text: p,
                targetLang: code,
                sourceLang: story.langCode,
                aiSettings: ai,
              ))
                  .trim();
            } catch (_) {
              return '';
            }
          },
        );
        result[code] = out;
      }
      final updated = story.copyWith(translations: result);
      ref.read(storyLibraryProvider.notifier).update(updated);
      if (mounted && _result?.id == story.id) {
        setState(() => _result = updated);
      }
    } finally {
      if (mounted) setState(() => _storyTranslating = false);
    }
  }

  // ───────────── وارد کردنِ متن برای خوانش ─────────────
  List<String> _paras(SavedStory s) => s.text
      .split(RegExp(r'\n\s*\n'))
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();

  void _importForReading(String raw, {bool progressive = false}) {
    var sentences = _splitSentences(raw);
    if (sentences.isEmpty) {
      setState(() => _importError = 'متنی برای خوندن پیدا نشد');
      return;
    }
    var note = '';
    if (sentences.length > _kMaxImportSentences) {
      sentences = sentences.sublist(0, _kMaxImportSentences);
      note = 'توجه: چون متن زیاد بود، فقط بخشی از اون آماده‌ی خوانش شد';
    }
    final lang = _detectLang(
        raw, _activeLang(ref.read(languageSelectionProvider).targets));
    final paras = <String>[];
    for (var i = 0; i < sentences.length; i += _kSentencesPerParagraph) {
      final end = i + _kSentencesPerParagraph > sentences.length
          ? sentences.length
          : i + _kSentencesPerParagraph;
      paras.add(sentences.sublist(i, end).join(' '));
    }
    final story = SavedStory(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: sentences.first.split(RegExp(r'\s+')).take(6).join(' '),
      text: paras.join('\n\n'),
      langCode: lang,
      level: _detectCefr(raw),
      contentType: 'reading',
      words: const [],
      createdAt: DateTime.now(),
    );
    // در حالتِ تدریجی (OCRِ چند عکس) ترجمه‌های پاراگراف‌های بدونِ تغییر حفظ می‌شن
    var keep = 0;
    if (progressive && _reading != null) {
      final old = _paras(_reading!);
      while (keep < old.length && keep < paras.length && old[keep] == paras[keep]) {
        keep++;
      }
    }
    setState(() {
      _importError = note;
      _error = '';
      _storyLang = lang;
      _langTouched = true;
      _level = story.level;
      _result = null;
      _reading = story;
      _readSaved = false;
      if (progressive) {
        for (final l in _readTrans.values) {
          if (l.length > keep) l.removeRange(keep, l.length);
        }
      } else {
        _readTrans.clear();
        _visibleParas = _kParaPage;
      }
    });
    unawaited(_translateReading());
  }

  bool _readingNeedsMore(SavedStory s, List<String> langs, int upto) {
    for (final code in langs) {
      if ((_readTrans[code]?.length ?? 0) < upto) return true;
    }
    return false;
  }

  /// ترجمه‌ی تدریجی — فقط پاراگراف‌های نمایان‌شده (مثلِ PARAGRAPH_PAGE_SIZE در Hope)
  Future<void> _translateReading() async {
    final s = _reading;
    if (s == null || _readTranslating) return;
    final paras = _paras(s);
    final langs =
        _effectiveTransLangs().where((l) => l != s.langCode).toList();
    final upto = _visibleParas > paras.length ? paras.length : _visibleParas;
    if (langs.isEmpty || !_readingNeedsMore(s, langs, upto)) return;
    setState(() => _readTranslating = true);
    try {
      final svc = ref.read(translationServiceProvider);
      final ai = ref.read(aiSettingsProvider);
      for (final code in langs) {
        final list = _readTrans.putIfAbsent(code, () => <String>[]);
        final start = list.length;
        if (start >= upto) continue;
        final out = await runWithConcurrencyLimit<String, String>(
          paras.sublist(start, upto),
          3,
          (p, _) async {
            try {
              return (await svc.translate(
                text: p,
                targetLang: code,
                sourceLang: s.langCode,
                aiSettings: ai,
              ))
                  .trim();
            } catch (_) {
              return '';
            }
          },
        );
        if (!mounted || _reading?.id != s.id) return;
        // اگر در این فاصله لیست تغییر کرده (OCR تدریجی)، نتیجه کنار گذاشته می‌شه
        if (list.length == start) setState(() => list.addAll(out));
      }
    } finally {
      if (mounted) {
        setState(() => _readTranslating = false);
        final cur = _reading;
        if (cur != null) {
          final ps = _paras(cur);
          final ls =
              _effectiveTransLangs().where((l) => l != cur.langCode).toList();
          final up = _visibleParas > ps.length ? ps.length : _visibleParas;
          if (_readingNeedsMore(cur, ls, up)) unawaited(_translateReading());
        }
      }
    }
  }

  void _readingShowMore() {
    setState(() => _visibleParas += _kParaPage);
    unawaited(_translateReading());
  }

  void _readingSave() {
    final s = _reading;
    if (s == null) return;
    final langs = _effectiveTransLangs();
    ref.read(storyLibraryProvider.notifier).add(s.copyWith(translations: {
          for (final e in _readTrans.entries)
            if (langs.contains(e.key)) e.key: List<String>.from(e.value),
        }));
    setState(() => _readSaved = true);
  }

  void _readingClose() => setState(() {
        _reading = null;
        _readTrans.clear();
        _readSaved = false;
      });

  Widget _readingCard(AppThemeColorsExt c) {
    final s = _reading!;
    final paras = _paras(s);
    final shown = _visibleParas > paras.length ? paras.length : _visibleParas;
    final langs = _effectiveTransLangs();
    final trans = <String, List<String>>{
      for (final e in _readTrans.entries)
        if (langs.contains(e.key) && e.key != s.langCode) e.key: e.value,
    };
    return HopeCard(
      borderColor: c.teal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.title,
            textDirection: autoDir(s.title),
            style: TextStyle(
                color: c.ink, fontSize: 15, fontWeight: FontWeight.w800),
          ),
          Text(
            '${langFaName(s.langCode)} · ${s.level} · خوانش',
            style: TextStyle(color: c.inkSoft, fontSize: 11),
          ),
          const SizedBox(height: 8),
          _audioBar(s),
          _storyBody(c, paras.take(shown).join('\n\n'), trans, s.id),
          if (_readTranslating)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('در حال ترجمه...',
                  style: TextStyle(color: c.inkSoft, fontSize: 12)),
            ),
          if (shown < paras.length)
            Center(
              child: HopeTextAction(
                label: 'نمایش بیشتر ($shown از ${paras.length} پاراگراف)',
                color: c.teal,
                onTap: _readingShowMore,
              ),
            ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _readSaved
                  ? Text('در «کتابخانه‌ی من» ذخیره شد.',
                      style: TextStyle(color: c.teal, fontSize: 12))
                  : HopeTextAction(
                      label: 'ذخیره در کتابخانه‌ی من',
                      color: c.gold,
                      onTap: _readingSave,
                    ),
              HopeTextAction(label: 'بستن', color: c.rose, onTap: _readingClose),
            ],
          ),
        ],
      ),
    );
  }

  void _importPasted() {
    final raw = _pasteCtrl.text.trim();
    if (raw.isEmpty) return;
    setState(() => _importError = '');
    _importForReading(raw);
    _pasteCtrl.clear();
    setState(() => _showPaste = false);
  }


  // ───────────── PDF / عکس ─────────────

  String _ioError(Object e, String fallback) {
    if (e is UnsupportedError) {
      final m = e.message ?? '';
      if (m.startsWith('ocr-script')) {
        return 'خوندنِ متن از عکس برای این زبان روی گوشی پشتیبانی نمی‌شه '
            '(OCRِ گوشی فقط لاتین، چینی، ژاپنی، کره‌ای و دوناگری رو می‌خونه). '
            'متن رو کپی/پیست کن یا PDFِ متنی وارد کن.';
      }
      return 'این قابلیت روی این دستگاه پشتیبانی نمی‌شه.';
    }
    return fallback;
  }

  // ───────────── صوتِ آپلودی ─────────────
  List<String> _sentencesOf(String text) => [
        for (final p in text.split(RegExp(r'\n\s*\n')))
          if (p.trim().isNotEmpty) ..._splitSentences(p.trim()),
      ];

  StoryAudioController _ctrlFor(SavedStory s) {
    final sents = _sentencesOf(s.text);
    final ex = _audioCtrls[s.id];
    if (ex != null) {
      ex.updateSentences(sents);
      return ex;
    }
    final c = StoryAudioController(
      storyKey: s.id,
      sentences: sents,
      prefs: ref.read(sharedPrefsProvider),
    );
    _audioCtrls[s.id] = c;
    return c;
  }

  Widget _audioBar(SavedStory s) => StoryAudioBar(ctrl: _ctrlFor(s));

  String _readingLang() =>
      _activeLang(ref.read(languageSelectionProvider).targets);

  Future<void> _importPdfForReading() async {
    if (_pdfReadBusy) return;
    List<PickedFile> files;
    try {
      files = await pickFiles(accept: 'application/pdf');
    } catch (e) {
      setState(() => _importError = _ioError(e, 'انتخابِ فایل انجام نشد'));
      return;
    }
    if (files.isEmpty) return;
    final f = files.first;
    setState(() {
      _pdfReadBusy = true;
      _importError = '';
      _importProgress = '';
    });
    PdfDocHandle? doc;
    try {
      doc = await PdfDocHandle.open(f.bytes);
      final sentences = <String>[];
      var truncated = false;
      for (var i = 0; i < doc.pageCount; i++) {
        final t = await doc.pageText(i);
        sentences.addAll(_splitSentences(t));
        if (mounted) {
          setState(() => _importProgress = 'صفحه‌ی ${i + 1} از ${doc!.pageCount}...');
        }
        if (sentences.length > _kMaxImportSentences) {
          truncated = true;
          break;
        }
      }
      if (!mounted) return;
      if (sentences.isEmpty) {
        setState(() => _importError =
            'متنی از این PDF استخراج نشد — شاید این فایل اسکن/عکسه، نه متنِ واقعی');
        return;
      }
      _importForReading(sentences.join(' '));
      if (truncated) {
        setState(() => _importError =
            'توجه: چون فایل بزرگ بود، فقط بخشی از متنش خونده و آماده‌ی خوانش شد');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _importError = _ioError(e,
            'خوندنِ این PDF مشکل داشت — فایل ممکنه خراب یا رمزگذاری‌شده باشه، یا اینترنت قطع باشه'));
      }
    } finally {
      doc?.dispose();
      if (mounted) {
        setState(() {
          _pdfReadBusy = false;
          _importProgress = '';
        });
      }
    }
  }

  Future<void> _importImagesForReading() async {
    if (_imgReadBusy) return;
    List<PickedFile> files;
    try {
      files = await pickFiles(accept: 'image/*', multiple: true);
    } catch (e) {
      setState(() => _importError = _ioError(e, 'انتخابِ فایل انجام نشد'));
      return;
    }
    if (files.isEmpty) return;
    setState(() {
      _imgReadBusy = true;
      _importError = '';
    });
    final lang = _readingLang();
    final texts = <String>[];
    OcrSession? ocr;
    try {
      ocr = await OcrSession.open(lang);
      for (var i = 0; i < files.length; i++) {
        if (mounted) {
          setState(() => _importProgress =
              'عکسِ ${i + 1} از ${files.length} (بار اول ممکنه کمی طول بکشه)...');
        }
        final text = await ocr.recognize(files[i].bytes);
        if (text.isNotEmpty && mounted) {
          texts.add(text);
          // هر عکس همین‌که آماده شد نشون داده می‌شه (مثلِ Hope)
          _importForReading(texts.join(' '), progressive: texts.length > 1);
        }
      }
      if (!mounted) return;
      if (texts.isEmpty) {
        setState(() => _importError = 'متنی تو این عکس‌ها تشخیص داده نشد');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _importError = _ioError(e,
            'خوندنِ متن از این عکس‌ها مشکل داشت — اینترنتت رو چک کن و دوباره امتحان کن'));
      }
    } finally {
      await ocr?.close();
      if (mounted) {
        setState(() {
          _imgReadBusy = false;
          _importProgress = '';
        });
      }
    }
  }

  // ───── PDF با عکسِ اصلی + ترجمه‌ی همین‌جا ─────
  Future<void> _openPdfView() async {
    if (_pdfViewBusy) return;
    List<PickedFile> files;
    try {
      files = await pickFiles(accept: 'application/pdf');
    } catch (e) {
      setState(() => _importError = _ioError(e, 'انتخابِ فایل انجام نشد'));
      return;
    }
    if (files.isEmpty) return;
    final f = files.first;
    setState(() {
      _pdfViewBusy = true;
      _importError = '';
    });
    try {
      final doc = await PdfDocHandle.open(f.bytes);
      if (!mounted) {
        doc.dispose();
        return;
      }
      _closePdfView(notify: false);
      setState(() {
        _pdfDoc = doc;
        _pdfTitle = f.name;
        _pdfIndex = 0;
        _pdfShowOrig = false;
      });
      unawaited(_loadPdfPage(0));
    } catch (_) {
      if (mounted) {
        setState(() => _importError =
            'این PDF باز نشد — فایل ممکنه خراب یا رمزگذاری‌شده باشه، یا اینترنت قطع باشه');
      }
    } finally {
      if (mounted) setState(() => _pdfViewBusy = false);
    }
  }

  void _closePdfView({bool notify = true}) {
    _pdfDoc?.dispose();
    _pdfDoc = null;
    _pdfImages.clear();
    _pdfTexts.clear();
    _pdfTrans.clear();
    _pdfIndex = 0;
    if (notify && mounted) setState(() {});
  }

  Future<void> _loadPdfPage(int i) async {
    final doc = _pdfDoc;
    if (doc == null || i < 0 || i >= doc.pageCount) return;
    setState(() {
      _pdfIndex = i;
      _pdfPageBusy = true;
    });
    try {
      if (!_pdfImages.containsKey(i)) {
        _pdfImages[i] = await doc.renderPage(i);
        if (mounted && _pdfDoc == doc && _pdfIndex == i) setState(() {});
      }
      if (!_pdfTexts.containsKey(i)) {
        _pdfTexts[i] = await doc.pageText(i);
      }
      if (!_pdfTrans.containsKey(i)) {
        final text = _pdfTexts[i] ?? '';
        if (text.trim().isEmpty) {
          _pdfTrans[i] = '(این صفحه متنِ قابل‌خواندن نداره — احتمالاً فقط عکسه)';
        } else {
          final sentences = _splitSentences(text);
          final chunks = <String>[];
          for (var k = 0; k < sentences.length; k += _kSentencesPerParagraph) {
            final end = k + _kSentencesPerParagraph > sentences.length
                ? sentences.length
                : k + _kSentencesPerParagraph;
            chunks.add(sentences.sublist(k, end).join(' '));
          }
          final svc = ref.read(translationServiceProvider);
          final ai = ref.read(aiSettingsProvider);
          final native = ref.read(languageSelectionProvider).native;
          final out = await runWithConcurrencyLimit<String, String>(
            chunks,
            3,
            (ch, _) async {
              try {
                return (await svc.translate(
                  text: ch,
                  targetLang: native,
                  sourceLang: 'auto',
                  aiSettings: ai,
                ))
                    .trim();
              } catch (_) {
                return '';
              }
            },
          );
          _pdfTrans[i] = out.where((e) => e.isNotEmpty).join('\n\n');
        }
      }
    } catch (_) {
      _pdfTrans[i] ??= 'نمایش یا ترجمه‌ی این صفحه انجام نشد.';
    } finally {
      if (mounted && _pdfDoc == doc) setState(() => _pdfPageBusy = false);
    }
  }

  Future<void> _importLink() async {
    var raw = _linkCtrl.text.trim();
    if (raw.isEmpty || _linkBusy) return;
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(raw)) {
      raw = 'https://$raw';
    }
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty || !uri.host.contains('.')) {
      setState(() =>
          _importError = 'این لینک معتبر نیست — لطفاً آدرسِ کامل صفحه رو وارد کن');
      return;
    }
    if (RegExp(r'(^|\.)(youtube\.com|youtu\.be)$').hasMatch(uri.host)) {
      setState(() => _importError =
          'لینکِ یوتیوب پشتیبانی نمی‌شه — متنِ ویدیوها استخراج نمی‌شه.');
      return;
    }
    setState(() {
      _linkBusy = true;
      _importError = '';
    });
    try {
      final dio = Dio(BaseOptions(
        responseType: ResponseType.plain,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 25),
      ));
      var html = '';
      try {
        final r = await dio.get<String>(uri.toString());
        html = r.data ?? '';
      } catch (_) {
        // احتمالاً CORS — می‌ریم سراغ پراکسیِ بک‌اند
      }
      if (html.isEmpty) {
        final base = ref.read(aiSettingsProvider).baseUrl;
        final r = await dio.get<String>(
            '$base/api/fetch-url?url=${Uri.encodeComponent(uri.toString())}');
        html = r.data ?? '';
      }
      final body = _extractMainBodyText(html);
      if (body.isEmpty) {
        if (mounted) {
          setState(() => _importError =
              'متنی از این صفحه استخراج نشد — شاید محتوای سایت با جاوااسکریپت ساخته می‌شه');
        }
        return;
      }
      if (!mounted) return;
      _importForReading(body);
      _linkCtrl.clear();
      setState(() => _showLink = false);
    } catch (_) {
      if (mounted) {
        setState(() => _importError =
            'این لینک قابلِ خوندن نبود — یا سایت اجازه‌ی دسترسی نمی‌ده، یا آدرس اشتباهه. از کپی/پیستِ متن استفاده کن.');
      }
    } finally {
      if (mounted) setState(() => _linkBusy = false);
    }
  }

  Future<void> _confirmDelete(SavedStory s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text('این داستان برای همیشه پاک بشه؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('انصراف'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok == true) ref.read(storyLibraryProvider.notifier).remove(s.id);
  }

  // ───────────── UI ─────────────
  InputDecoration _fieldDeco(AppThemeColorsExt c, String hint) {
    OutlineInputBorder b(Color col) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: col),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: c.inkSoft.withOpacity(0.6), fontSize: 13),
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      enabledBorder: b(c.cardBorder),
      focusedBorder: b(c.teal),
      disabledBorder: b(c.cardBorder),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final sel = ref.watch(languageSelectionProvider);
    final stories = ref.watch(storyLibraryProvider);
    // برای بازسازیِ فهرستِ نتایجِ جستجو وقتی لغات ذخیره‌شده تغییر کنند
    ref.watch(savedWordsProvider);

    ref.listen<StoryDraft?>(storyDraftProvider, (prev, next) {
      if (next == null) return;
      Future.microtask(() {
        if (mounted) _consumeDraft(next);
      });
    });

    final lang = _activeLang(sel.targets);
    final options = <String>[...sel.targets];
    if (options.isEmpty) options.add('en');
    if (!options.contains(lang)) options.add(lang);

    return HopePanel(
      title: 'داستان‌ساز',
      titleSize: 16,
      children: [
        _modeSwitch(c, stories.length),
        if (_showLibrary)
          ..._libraryChildren(c, stories)
        else ...[
          _settingsCard(c, lang, options),
          _wordsCard(c, lang),
          _translationLangsCard(c),
          _generateButton(c, lang),
          if (_error.isNotEmpty)
            Text(_error, style: TextStyle(color: c.rose, fontSize: 13)),
          if (_result != null) _resultCard(c, _result!),
          ..._importSection(c),
          if (_reading != null) _readingCard(c),
        ],
      ],
    );
  }

  Widget _modeSwitch(AppThemeColorsExt c, int count) {
    Widget seg(bool isLib, String label, IconData icon) {
      final active = _showLibrary == isLib;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _showLibrary = isLib),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
            decoration: BoxDecoration(
              color: active ? c.ink : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 15, color: active ? c.paper : c.inkSoft),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: active ? c.paper : c.inkSoft,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.paperDark,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.cardBorder),
      ),
      child: Row(
        children: [
          seg(false, 'ساخت داستان', Icons.auto_fix_high),
          seg(true, 'کتابخانه‌ی من ($count)', Icons.local_library_outlined),
        ],
      ),
    );
  }

  Widget _settingsCard(
      AppThemeColorsExt c, String lang, List<String> options) {
    Widget label(String t, {double top = 10}) => Padding(
          padding: EdgeInsets.only(top: top, bottom: 6),
          child: Text(t, style: TextStyle(color: c.inkSoft, fontSize: 12)),
        );

    return HopeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('۱. زبان و سطح داستان',
              style: TextStyle(
                  color: c.ink, fontSize: 14.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          if (options.length > 1) ...[
            Text(
              'زبان داستان (از بین زبان‌های مقصدی که بالای صفحه انتخاب کردی)',
              style: TextStyle(color: c.inkSoft, fontSize: 12),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final code in options)
                  HopeChoiceChip(
                    label: langFaName(code),
                    active: lang == code,
                    activeBorder: c.gold,
                    activeFill: c.goldSoft,
                    activeText: c.ink,
                    fontSize: 13,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    onTap: () => setState(() {
                      _storyLang = code;
                      _langTouched = true;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 6),
          ] else
            Text(
              'زبان داستان: ${langFaName(lang)} (طبق زبان مقصدی که بالای صفحه انتخاب کردی)',
              style: TextStyle(color: c.inkSoft, fontSize: 12),
            ),
          label('سطح داستان', top: 4),
          LevelChips(
            selected: _level,
            includeAll: false,
            wrap: true,
            onSelect: (lv) => setState(() => _level = lv),
          ),
          label('نوع محتوا'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in _kContentTypes)
                HopeChoiceChip(
                  label: t.label,
                  active: _contentType == t.key,
                  activeBorder: c.rose,
                  activeFill: c.rose,
                  activeText: Colors.white,
                  onTap: () => setState(() => _contentType = t.key),
                ),
            ],
          ),
          label('طول داستان'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final l in _kLengths)
                HopeChoiceChip(
                  label: l.label,
                  active: _length == l.key,
                  activeBorder: c.gold,
                  activeFill: c.gold,
                  activeText: Colors.white,
                  onTap: () => setState(() => _length = l.key),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _wordsCard(AppThemeColorsExt c, String lang) {
    final matches = _matches(lang);
    return HopeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('۲. انتخاب لغت‌ها',
              style: TextStyle(
                  color: c.ink, fontSize: 14.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _custom,
                  enabled: !_translating,
                  style: TextStyle(color: c.ink, fontSize: 13),
                  onSubmitted: (_) => _addCustom(lang),
                  decoration: _fieldDeco(
                    c,
                    'یه لغت بنویس (به هر زبونی) — به ${langFaName(lang)} ترجمه و اضافه می‌شه...',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Opacity(
                opacity: _translating ? 0.6 : 1,
                child: Material(
                  color: c.ink,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: _translating ? null : () => _addCustom(lang),
                    child: SizedBox(
                      width: 42,
                      height: 40,
                      child: Center(
                        child: _translating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.add,
                                size: 18, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_note,
                  style: TextStyle(color: c.inkSoft, fontSize: 11)),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _query,
            onChanged: (_) => setState(() {}),
            style: TextStyle(color: c.ink, fontSize: 13),
            decoration: _fieldDeco(
              c,
              'یا از دیکشنری من، دیالوگ‌های روزمره، لغات، اصطلاحات عامیانه، لغات ذخیره‌شده جستجو کن...',
            ),
          ),
          if (matches.isNotEmpty) ...[
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 140),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in matches)
                      GestureDetector(
                        onTap: () => _toggleWord(m.word),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: _words.contains(m.word)
                                ? c.goldSoft
                                : (m.saved ? Colors.white : c.paper),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _words.contains(m.word)
                                  ? c.gold
                                  : (m.saved ? c.teal : c.cardBorder),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (m.saved) ...[
                                Icon(Icons.bookmark, size: 12, color: c.teal),
                                const SizedBox(width: 4),
                              ],
                              Text(m.word,
                                  textDirection: autoDir(m.word),
                                  style:
                                      TextStyle(color: c.ink, fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
          if (_words.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.cardBorder)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final w in _words)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: c.ink,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(w,
                                  textDirection: autoDir(w),
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 12)),
                              const SizedBox(width: 4),
                              GestureDetector(
                                onTap: () => _toggleWord(w),
                                child: const Icon(Icons.close,
                                    size: 13, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => setState(_words.clear),
                    child: Text(
                      'پاک کردن همه',
                      style: TextStyle(
                        color: c.rose,
                        fontSize: 11,
                        decoration: TextDecoration.underline,
                        decorationColor: c.rose,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }


  // ───────────── کارتِ زبان‌های ترجمه‌ی همزمان ─────────────
  Widget _translationLangsCard(AppThemeColorsExt c) {
    final selected = _effectiveTransLangs();
    void setAll(Set<String> v) {
      setState(() {
        _transTouched = true;
        _transLangs
          ..clear()
          ..addAll(v);
      });
      if (_reading != null) unawaited(_translateReading());
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.paperDark.withOpacity(0.35),
        border: Border.all(color: c.cardBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'داستان همزمان به چه زبان‌هایی ترجمه بشه؟ (می‌تونی چند تا انتخاب کنی)',
            style: TextStyle(color: c.inkSoft, fontSize: 12.5, height: 1.7),
          ),
          Row(
            children: [
              HopeTextAction(
                label: 'انتخاب همه',
                color: c.teal,
                onTap: () =>
                    setAll({for (final l in kSupportedLanguages) l.code}),
              ),
              const SizedBox(width: 14),
              HopeTextAction(
                label: 'پاک کردن همه',
                color: c.rose,
                onTap: () => setAll({}),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final l in kSupportedLanguages)
                HopeChoiceChip(
                  label: l.faLabel,
                  active: selected.contains(l.code),
                  activeBorder: c.gold,
                  activeFill: c.goldSoft,
                  activeText: c.ink,
                  fontSize: 13,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  onTap: () {
                    final next = {...selected};
                    if (!next.remove(l.code)) next.add(l.code);
                    setAll(next);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ───────────── وارد کردنِ لینک / متن برای خوانش ─────────────
  Widget _importButton(AppThemeColorsExt c,
      {required String emoji, required String label, required VoidCallback onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: c.cardBorder),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                    color: c.teal, fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _primaryBtn(AppThemeColorsExt c, String label, VoidCallback? onTap,
      {bool busy = false}) {
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Material(
        color: c.teal,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy) ...[
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }


  Widget _pdfViewer(AppThemeColorsExt c) {
    final doc = _pdfDoc!;
    final i = _pdfIndex;
    final img = _pdfImages[i];
    final trans = _pdfTrans[i];
    final orig = _pdfTexts[i] ?? '';
    final lang = _readingLang();
    return HopeCard(
      padding: const EdgeInsets.all(10),
      radius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$_pdfTitle — صفحه‌ی ${i + 1} از ${doc.pageCount}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                      color: c.ink, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              HopeTextAction(
                  label: 'بستن', color: c.rose, onTap: _closePdfView),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              constraints: const BoxConstraints(minHeight: 120),
              decoration:
                  BoxDecoration(border: Border.all(color: c.cardBorder)),
              child: img == null
                  ? const Padding(
                      padding: EdgeInsets.all(30),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : InteractiveViewer(
                      minScale: 1,
                      maxScale: 4,
                      child: Image.memory(img, fit: BoxFit.fitWidth),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: c.goldSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: trans == null
                ? Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text('در حال ترجمه‌ی این صفحه...',
                          style: TextStyle(color: c.inkSoft, fontSize: 12)),
                    ],
                  )
                : Text(
                    trans,
                    textDirection: autoDir(trans),
                    style: TextStyle(color: c.ink, fontSize: 13.5, height: 1.9),
                  ),
          ),
          if (orig.isNotEmpty) ...[
            HopeTextAction(
              label: _pdfShowOrig ? 'پنهان کردنِ متنِ اصلی' : 'نمایشِ متنِ اصلی',
              color: c.teal,
              onTap: () => setState(() => _pdfShowOrig = !_pdfShowOrig),
            ),
            if (_pdfShowOrig)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: c.paper,
                  border: Border.all(color: c.cardBorder),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  orig,
                  textDirection: dirFor(lang),
                  style: TextStyle(color: c.ink, fontSize: 13, height: 2),
                ),
              ),
          ],
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              HopeTextAction(
                label: '◀ صفحه‌ی قبل',
                color: c.teal,
                onTap: i == 0 || _pdfPageBusy ? null : () => _loadPdfPage(i - 1),
              ),
              HopeTextAction(
                label: 'صفحه‌ی بعد ▶',
                color: c.teal,
                onTap: i >= doc.pageCount - 1 || _pdfPageBusy
                    ? null
                    : () => _loadPdfPage(i + 1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _importSection(AppThemeColorsExt c) {
    final busyAny = _pdfReadBusy || _imgReadBusy || _pdfViewBusy;
    String lbl(bool busy, String idle) =>
        busy ? (_importProgress.isEmpty ? 'در حال پردازش...' : _importProgress) : idle;
    return [
      _importButton(
        c,
        emoji: '📖',
        label: lbl(_pdfReadBusy, 'به‌جاش یه PDF برای خوانش وارد کن'),
        onTap: busyAny ? () {} : _importPdfForReading,
      ),
      _importButton(
        c,
        emoji: '🖼️',
        label: lbl(_imgReadBusy, 'وارد کردنِ عکس برای ترجمه و خوانش'),
        onTap: busyAny ? () {} : _importImagesForReading,
      ),
      _importButton(
        c,
        emoji: '📑',
        label: _pdfViewBusy
            ? 'در حال باز کردنِ PDF...'
            : 'PDF رو با عکسِ اصلی + ترجمه همینجا نشون بده',
        onTap: busyAny ? () {} : _openPdfView,
      ),
      if (_pdfDoc != null) _pdfViewer(c),
      _importButton(
        c,
        emoji: '🔗',
        label: _showLink ? 'بستنِ لینک' : 'یا لینکِ یه صفحه رو وارد کن',
        onTap: () => setState(() => _showLink = !_showLink),
      ),
      if (_showLink)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _linkCtrl,
              textDirection: TextDirection.ltr,
              keyboardType: TextInputType.url,
              style: TextStyle(color: c.ink, fontSize: 13),
              decoration: _fieldDeco(c, 'https://example.com/article'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 4),
            Text(
              'متنِ اصلیِ صفحه خونده می‌شه و آماده‌ی خوانش و ترجمه می‌شه.',
              style: TextStyle(color: c.inkSoft, fontSize: 10.5),
            ),
            const SizedBox(height: 6),
            _primaryBtn(
              c,
              _linkBusy ? 'در حال گرفتنِ متن...' : 'بگیر و آماده‌ی خوانش کن',
              _linkCtrl.text.trim().isEmpty || _linkBusy ? null : _importLink,
              busy: _linkBusy,
            ),
          ],
        ),
      _importButton(
        c,
        emoji: '📋',
        label: _showPaste ? 'بستنِ کادرِ متن' : 'یا یه متن/داستان رو اینجا پیست کن',
        onTap: () => setState(() => _showPaste = !_showPaste),
      ),
      if (_showPaste)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _pasteCtrl,
              minLines: 5,
              maxLines: 10,
              textDirection: TextDirection.ltr,
              style: TextStyle(color: c.ink, fontSize: 13, height: 1.6),
              decoration: _fieldDeco(c, 'متنت رو اینجا پیست کن...'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 6),
            _primaryBtn(
              c,
              '📖 آماده‌ی خوانش کن',
              _pasteCtrl.text.trim().isEmpty ? null : _importPasted,
            ),
          ],
        ),
      if (_importError.isNotEmpty)
        Text(_importError, style: TextStyle(color: c.rose, fontSize: 12)),
      const SrtTranslatorTool(),
    ];
  }

  Widget _generateButton(AppThemeColorsExt c, String lang) {
    final disabled = _words.isEmpty || _generating;
    return Opacity(
      opacity: disabled ? 0.6 : 1,
      child: Material(
        color: c.gold,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: disabled ? null : () => _generate(lang),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_generating)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                else
                  const Icon(Icons.auto_awesome, size: 18, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  _generating ? 'در حال ساخت داستان...' : 'داستان بساز',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _resultCard(AppThemeColorsExt c, SavedStory s) {
    return HopeCard(
      borderColor: c.gold,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.title,
            textDirection: autoDir(s.title),
            style: TextStyle(
                color: c.ink, fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          _audioBar(s),
          _storyBody(c, s.text, s.translations, s.id),
          if (_storyTranslating)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('در حال ترجمه‌ی داستان...',
                  style: TextStyle(color: c.inkSoft, fontSize: 12)),
            ),
          const SizedBox(height: 8),
          Text('در «کتابخانه‌ی من» ذخیره شد.',
              style: TextStyle(color: c.teal, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _storyBody(AppThemeColorsExt c, String text,
      [Map<String, List<String>> translations = const {}, String? storyKey]) {
    final tp = ref.watch(textPrefsProvider);
    final ctrl = storyKey == null ? null : _audioCtrls[storyKey];
    if (ctrl == null) {
      return _storyBodyInner(c, tp, text, translations, null, storyKey);
    }
    // وقتی صدا وصل است، با هر تغییرِ خطِ فعال بدنه دوباره ساخته می‌شود (هایلایت + اسکرول)
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) => _storyBodyInner(
          c, tp, text, translations, ctrl.hasAudio ? ctrl : null, storyKey),
    );
  }

  Widget _storyBodyInner(AppThemeColorsExt c, TargetTextPrefs tp, String text,
      Map<String, List<String>> translations,
      StoryAudioController? audio, String? storyKey) {
    final paras = text
        .split(RegExp(r'\n\s*\n'))
        .where((p) => p.trim().isNotEmpty)
        .toList();
    // ✅ تنظیماتِ «اندازه و بولدِ متن»
    final boldText = tp.bold == TargetBoldMode.both || tp.bold == TargetBoldMode.text;
    final boldTr = tp.bold == TargetBoldMode.both || tp.bold == TargetBoldMode.translation;

    // ریسه‌های قبلیِ تپِ همین بدنه دور ریخته می‌شن (با هر ساختِ دوباره تازه ساخته می‌شن)
    final recKey = storyKey ?? '_';
    final recs = _tapRecs.putIfAbsent(recKey, () => <TapGestureRecognizer>[]);
    for (final r in recs) {
      r.dispose();
    }
    recs.clear();

    final keys = storyKey == null
        ? null
        : (_paraKeys[storyKey] = List.generate(paras.length, (_) => GlobalKey()));

    // پاراگرافِ شاملِ جمله‌ی فعال (برای اسکرولِ خودکار)
    int activeParaIdx = -1;
    var sentCounter = 0;
    final paraSents = <List<String>>[];
    for (var i = 0; i < paras.length; i++) {
      final ss = audio == null ? const <String>[] : _splitSentences(paras[i].trim());
      paraSents.add(ss);
      if (audio != null &&
          activeParaIdx < 0 &&
          audio.activeIndex < sentCounter + ss.length) {
        activeParaIdx = i;
      }
      sentCounter += ss.length;
    }
    if (audio != null && storyKey != null && activeParaIdx >= 0 &&
        keys != null &&
        _lastScrolled[storyKey] != audio.activeIndex) {
      final was = _lastScrolled[storyKey];
      _lastScrolled[storyKey] = audio.activeIndex;
      // فقط وقتی واقعاً در حالِ پخش/ناوبری هستیم (نه اولین ساخت)
      if (was != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = keys[activeParaIdx].currentContext;
          if (ctx != null && ctx.mounted) {
            Scrollable.ensureVisible(ctx,
                alignment: 0.25,
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOut);
          }
        });
      }
    }

    Widget paraText(int i) {
      final baseStyle = TextStyle(
        color: c.ink,
        fontSize: 14 * tp.scaleFactor,
        height: 1.9,
        fontWeight: boldText ? FontWeight.w700 : FontWeight.w400,
      );
      if (audio == null) {
        return Text(paras[i].trim(),
            textDirection: autoDir(paras[i]), style: baseStyle);
      }
      var before = 0;
      for (var k = 0; k < i; k++) {
        before += paraSents[k].length;
      }
      final spans = <InlineSpan>[];
      for (var k = 0; k < paraSents[i].length; k++) {
        final gi = before + k;
        final rec = TapGestureRecognizer()..onTap = () => audio.setActiveLine(gi);
        recs.add(rec);
        final on = gi == audio.activeIndex;
        spans.add(TextSpan(
          text: '${paraSents[i][k]}${k == paraSents[i].length - 1 ? '' : ' '}',
          recognizer: rec,
          style: on
              ? TextStyle(
                  backgroundColor: c.gold.withOpacity(0.28),
                  fontWeight: FontWeight.w700)
              : null,
        ));
      }
      return Text.rich(TextSpan(children: spans, style: baseStyle),
          textDirection: autoDir(paras[i]));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < paras.length; i++)
          Padding(
            key: keys?[i],
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                paraText(i),
                for (final e in translations.entries)
                  if (i < e.value.length && e.value[i].trim().isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: c.goldSoft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        e.value[i].trim(),
                        textDirection: dirFor(e.key),
                        style: TextStyle(
                          color: c.ink,
                          fontSize: 13 * tp.scaleFactor,
                          height: 1.8,
                          fontWeight: boldTr ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
              ],
            ),
          ),
      ],
    );
  }

  // ───────────── کتابخانه‌ی من ─────────────
  List<Widget> _libraryChildren(
      AppThemeColorsExt c, List<SavedStory> stories) {
    final q = _libSearch.text.trim().toLowerCase();
    final shown = stories.where((s) {
      if (_libLevel != 'all' && s.level != _libLevel) return false;
      if (q.isEmpty) return true;
      return s.title.toLowerCase().contains(q) ||
          s.text.toLowerCase().contains(q) ||
          s.words.any((w) => w.toLowerCase().contains(q));
    }).toList();

    return [
      if (stories.length > 1)
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: c.cardBorder),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Icon(Icons.search, size: 15, color: c.inkSoft),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _libSearch,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(color: c.ink, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'جستجو در کتابخانه...',
                    hintStyle: TextStyle(
                        color: c.inkSoft.withOpacity(0.6), fontSize: 13),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              if (_libSearch.text.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(_libSearch.clear),
                  child: Icon(Icons.close, size: 15, color: c.inkSoft),
                ),
            ],
          ),
        ),
      // سطح‌ها همیشه نشان داده می‌شوند (مثل LevelFilterRow در Hope)
      LevelChips(
        selected: _libLevel,
        onSelect: (lv) => setState(() => _libLevel = lv),
      ),
      if (stories.isEmpty)
        const HopeEmptyText('هنوز داستانی ذخیره نکردی.')
      else if (shown.isEmpty)
        const HopeEmptyText('چیزی پیدا نشد.')
      else
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final s in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _storyCard(c, s),
              ),
          ],
        ),
    ];
  }

  /// لینکِ ذخیره‌شده (اینستاگرام/یوتیوب/…) — خط اولِ متنِ داستان‌های لینکی.
  String? _linkOf(SavedStory s) {
    if (s.contentType != 'youtube') return null;
    for (final line in s.text.split('\n')) {
      final t = line.trim();
      if (RegExp(r'^https?://', caseSensitive: false).hasMatch(t)) return t;
    }
    return null;
  }

  /// نامِ برنامه‌ی مبدأ (خط دومِ متن: Instagram / YouTube / …).
  String _sourceOf(SavedStory s) {
    final ls = s.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    return ls.length > 1 && !RegExp(r'^https?://', caseSensitive: false).hasMatch(ls[1])
        ? ls[1]
        : _contentLabel(s.contentType);
  }

  Future<void> _openLink(String url) async {
    try {
      await NativeBridge.instance.openExternal(url: url);
    } catch (_) {}
  }

  Widget _storyCard(AppThemeColorsExt c, SavedStory s) {
    final link = _linkOf(s);
    final open = link == null && _openStoryId == s.id;
    final d = s.createdAt;
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${d.year}/${two(d.month)}/${two(d.day)}';
    return HopeCard(
      padding: const EdgeInsets.all(12),
      radius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: link != null
                ? () => _openLink(link)
                : () => setState(() => _openStoryId = open ? null : s.id),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.title,
                        textDirection: autoDir(s.title),
                        style: TextStyle(
                          color: c.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        link != null
                            ? '${_sourceOf(s)} · $date'
                            : '${langFaName(s.langCode)} · ${s.level} · '
                                '${_contentLabel(s.contentType)} · $date',
                        style: TextStyle(color: c.inkSoft, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => _confirmDelete(s),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 18, color: c.inkSoft),
                  ),
                ),
                Icon(
                  link != null
                      ? Icons.open_in_new
                      : (open ? Icons.keyboard_arrow_down : Icons.chevron_left),
                  size: 20,
                  color: c.inkSoft,
                ),
              ],
            ),
          ),
          if (open)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.cardBorder)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _audioBar(s),
                  _storyBody(c, s.text, s.translations, s.id),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
