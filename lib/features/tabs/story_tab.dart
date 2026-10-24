import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// intl هم یک کلاسِ TextDirection (با LTR/RTL) دارد که با TextDirection فلاتر تداخل می‌کند
// و باعث خطای «Member not found: 'ltr'» در بیلدِ وب می‌شد.
import 'package:intl/intl.dart' hide TextDirection;

import '../../app.dart';
import '../../core/router/back_handlers.dart';
import '../../l10n/app_localizations.dart';
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
    show runWithConcurrencyLimit, kLastAiError;
import '../../core/web/reading_io_stub.dart'
    if (dart.library.html) '../../core/web/reading_io_web.dart';
import 'package:flutter/gestures.dart';
import '../../core/audio/story_audio_controller.dart';
import '../../core/book/book_disk.dart';
import '../../core/book/page_translate_engine.dart';
import '../../core/story/long_text_prep.dart';
import '../../core/storage/local_storage.dart' show sharedPrefsProvider;
import '../../core/web/ocr_block.dart';
import '../story/book_translate_bar.dart';
import '../story/page_translate_render.dart';
import '../story/pdf_combined_image.dart';
import '../story/pdf_fullscreen_viewer.dart';
import '../story/pdf_page_nav.dart';
import '../story/pdf_save_tools.dart';
import '../story/pdf_zoom_image.dart';
import '../story/srt_translator_tool.dart';
import '../story/story_audio_bar.dart';
import '../story/story_reader_panel.dart';
import '_hope_panel.dart';
import 'saved_tab.dart';

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
      800),
  _Len('medium', 'متوسط', '2-3', 'medium length, roughly 5-8 sentences per paragraph',
      1400),
  _Len('long', 'بلند', '4-6', 'long, roughly 6-10 sentences per paragraph',
      2400),
];

String _enName(String code) {
  for (final l in kSupportedLanguages) {
    if (l.code == code) return l.enLabel;
  }
  return code;
}

String _contentLabel(AppLocalizations L, String key) {
  switch (key) {
    case 'reading': return L.story_content_reading;
    case 'news': return L.story_content_news;
    case 'psychology': return L.story_content_psychology;
    case 'children': return L.story_content_children;
    case 'funny': return L.story_content_funny;
    case 'mystery': return L.story_content_mystery;
    case 'crime': return L.story_content_crime;
    case 'scientific': return L.story_content_scientific;
    case 'conversational': return L.story_content_conversational;
    case 'philosophical': return L.story_content_philosophical;
    case 'metaphysical': return L.story_content_metaphysical;
    default: return L.story_content_general;
  }
}

String _lengthLabel(AppLocalizations L, String key) {
  switch (key) {
    case 'long': return L.story_length_long;
    case 'medium': return L.story_length_medium;
    default: return L.story_length_short;
  }
}

String _stripThink(String t) => t
    .replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '')
    .replaceAll(RegExp(r'<think>[\s\S]*$', caseSensitive: false), '')
    .trim();


// ───────────── کمکی‌های وارد کردنِ متن برای خوانش (پورتِ ساده‌ی Hope) ─────────────
const int _kSentencesPerParagraph = 5;
const int _kMaxImportSentences = 60000; // ≈ یک کتابِ بزرگ؛ پردازش در isolate انجام می‌شود
const int _kLongTextChars = 30000; // متن‌های بلندتر از این در isolate آماده می‌شوند
const int _kMaxWordsPerSentence = 40;

List<String> _splitSentences(String text) => splitSentencesText(text);

/// تشخیصِ سادته‌ی زبانِ متن از روی خطِ نوشتاری.
String _detectLang(String text, String fallback) =>
    detectTextLang(text, fallback);

/// حدسِ سطحِ CEFR از روی خودِ متن (همان فرمولِ detectTextCEFRLevel در Hope).
String _detectCefr(String text) => detectTextCefr(text);

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
  bool _showSaved = false;

  String _storyLang = 'en';
  bool _langTouched = false;
  String _level = 'B1';
  String _contentType = 'general';
  String _length = 'medium';

  final List<String> _words = [];
  final _custom = TextEditingController();
  final _query = TextEditingController();
  // زومِ مشترکِ عکسِ اصلی و ترجمه‌ی PDF
  final TransformationController _pdfZoom = TransformationController();
  final TransformationController _pdfZoomT = TransformationController(); // زومِ مستقلِ عکسِ ترجمه
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
  String _readNotes = '';

  bool _pdfReadBusy = false;
  bool _imgReadBusy = false;
  String _importProgress = '';

  // نمایشگرِ PDF با عکسِ اصلی + ترجمه (موتورِ ترجمه‌ی صفحه‌ها)
  bool _pdfViewBusy = false;
  PdfDocHandle? _pdfDoc;
  String _pdfTitle = '';
  String _pdfDocKey = '';
  int _pdfIndex = 0;
  bool _pdfPageBusy = false;
  bool _pdfShowOrig = false;
  // فقط چند صفحه‌ی اطرافِ صفحه‌ی فعلی در حافظه می‌مانند (بقیه حذف می‌شوند)
  final Map<int, Uint8List> _pdfImages = {};
  static const int _kPdfKeepImages = 6;
  final Map<int, String> _pdfTexts = {};
  final Map<int, String> _pdfTrans = {};
  String? _pdfViewLang; // زبانی که کاربر برای دیدنِ عکسِ ترجمه‌شده انتخاب کرده
  // حالتِ نمایشِ صفحه: both = اصلی بالا + ترجمه پایین، orig = فقط اصلی، trans = فقط ترجمه
  String _pdfMode = 'both';
  bool _pdfSaving = false;
  // موتورِ ترجمه‌ی صفحه‌ها: صف، کشِ دیسکی، تلاشِ دوباره، پیشرفتِ ماندگار
  PageTranslateEngine? _pdfEngine;
  int _pdfEngineToken = 0;
  OcrSession? _pdfOcr;
  Uint8List? _pdfCurTrans; // عکسِ ترجمه‌شده‌ی صفحه‌ی فعلی
  int _pdfCurTransFor = -1;
  final BookDisk _bookDisk = createBookDisk();
  // کشِ ساده برای کارهای سنگینِ بازسازی‌شونده در هر build
  String? _parasSrc;
  List<String> _parasCache = const [];
  String? _sentSrc;
  List<String> _sentCache = const [];
  final _linkCtrl = TextEditingController();
  final _pasteCtrl = TextEditingController();

  // صوتِ آپلودیِ هر داستان (کلید = id داستان) + همگام‌سازیِ هایلایت با متن
  final Map<String, StoryAudioController> _audioCtrls = {};
  final Map<String, List<TapGestureRecognizer>> _tapRecs = {};
  final Map<String, int> _lastScrolled = {};
  final Map<String, List<GlobalKey>> _paraKeys = {};

  String _libLevel = 'all';
  final _libSearch = TextEditingController();
  bool _libFavOnly = false;
  String? _openStoryId;
  // کتابِ بلندِ کتابخانه: تعدادِ پاراگرافِ نمایان (برای جلوگیری از ساختنِ کلِ متن یک‌جا)
  static const int _kLibParaPage = 20;
  final Map<String, int> _libVisible = {};

  @override
  void initState() {
    super.initState();
    BackHandlers.add(_handleBack);
    unawaited(cleanOcrTemp());
    final d = ref.read(storyDraftProvider);
    if (d != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _consumeDraft(d);
      });
    }
  }

  /// دکمه‌ی «بازگشت» گوشی: اول داستانِ بازشده/خوانده‌شده و زیرصفحه‌ی کتابخانه/ذخیره‌شده‌ها بسته می‌شوند.
  bool _handleBack() {
    if (!mounted) return false;
    if (_openStoryId != null) {
      setState(() => _openStoryId = null);
      return true;
    }
    if (_reading != null) {
      _readingClose();
      return true;
    }
    if (_showLibrary || _showSaved) {
      setState(() {
        _showLibrary = false;
        _showSaved = false;
      });
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    BackHandlers.remove(_handleBack);
    _custom.dispose();
    _pdfZoom.dispose();
    _pdfZoomT.dispose();
    _query.dispose();
    _libSearch.dispose();
    _linkCtrl.dispose();
    _pasteCtrl.dispose();
    _disposePdfEngine();
    final ocrToClose = _pdfOcr;
    _pdfOcr = null;
    if (ocrToClose != null) unawaited(ocrToClose.close());
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
      _showSaved = false;
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
            // زبان‌های غیرلاتین (فارسی/عربی/چینی/…) توکنِ بیشتری لازم دارند
            maxTokens: ((const {'fa', 'ar', 'ru', 'hi', 'zh', 'ja', 'ko'}
                            .contains(lang))
                        ? ln.tokens * 1.6
                        : ln.tokens.toDouble())
                    .round()
                    .clamp(300, 4096)
                    .toInt(),
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
          'ساخت داستان انجام نشد. اینترنتت رو چک کن و دوباره امتحان کن.'
          '${kLastAiError.isEmpty ? '' : '\n($kLastAiError)'}');
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
  List<String> _paras(SavedStory s) {
    // این تابع در هر build صدا زده می‌شود؛ برای متنِ بلند نتیجه کش می‌شود
    if (identical(s.text, _parasSrc)) return _parasCache;
    final out = s.text
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    _parasSrc = s.text;
    _parasCache = out;
    return out;
  }

  void _importForReading(String raw,
      {bool progressive = false, String preNote = ''}) {
    // متنِ بلند (مثلاً کتابِ ۴۰۰ صفحه‌ای) در isolateِ جدا آماده می‌شود تا UI قفل نشود
    if (!progressive && raw.length >= _kLongTextChars) {
      unawaited(_importLongForReading(raw, preNote: preNote));
      return;
    }
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
    _beginReading(story, note.isEmpty ? preNote : note,
        progressive: progressive);
  }

  /// نسخه‌ی ناهمگامِ متنِ بلند: شکستن به جمله/پاراگراف، تشخیصِ زبان و سطح
  /// همه در یک isolate انجام می‌شود؛ ترد اصلی فقط نتیجه را می‌گیرد.
  Future<void> _importLongForReading(String raw, {String preNote = ''}) async {
    final fallback = _activeLang(ref.read(languageSelectionProvider).targets);
    if (mounted) {
      setState(() {
        _importError = '';
        _importProgress = 'در حال آماده‌سازیِ متنِ بزرگ...';
      });
    }
    Map<String, Object?> r;
    try {
      r = await compute(prepareLongText, <String, Object?>{
        'raw': raw,
        'fallback': fallback,
        'maxSentences': _kMaxImportSentences,
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _importProgress = '';
          _importError =
              'آماده‌سازیِ این متن انجام نشد — حافظه‌ی گوشی کم بود؛ متنِ کوتاه‌تری امتحان کن';
        });
      }
      return;
    }
    if (!mounted) return;
    final paras = ((r['paras'] as List?) ?? const []).cast<String>();
    setState(() => _importProgress = '');
    if (paras.isEmpty) {
      setState(() => _importError = 'متنی برای خوندن پیدا نشد');
      return;
    }
    final story = SavedStory(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: (r['title'] ?? '').toString(),
      text: paras.join('\n\n'),
      langCode: (r['lang'] ?? fallback).toString(),
      level: (r['level'] ?? 'B1').toString(),
      contentType: 'reading',
      words: const [],
      createdAt: DateTime.now(),
    );
    _beginReading(
      story,
      r['truncated'] == true
          ? 'توجه: چون متن زیاد بود، فقط بخشی از اون آماده‌ی خوانش شد'
          : preNote,
      progressive: false,
    );
  }

  void _beginReading(SavedStory story, String note, {required bool progressive}) {
    final paras = _paras(story);
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
      _storyLang = story.langCode;
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
    ref.read(storyLibraryProvider.notifier).add(s.copyWith(
        notes: _readNotes,
        translations: {
          for (final e in _readTrans.entries)
            if (langs.contains(e.key)) e.key: List<String>.from(e.value),
        }));
    setState(() => _readSaved = true);
  }

  void _readingClose() => setState(() {
        _reading = null;
        _readTrans.clear();
        _readSaved = false;
        _readNotes = '';
      });

  Widget _readingCard(AppThemeColorsExt c) {
    final s = _reading!;
    final paras = _paras(s);
    final shown = _visibleParas > paras.length ? paras.length : _visibleParas;
    final langs =
        _effectiveTransLangs().where((l) => l != s.langCode).toList();
    final trans = <String, List<String>>{
      for (final e in _readTrans.entries)
        if (langs.contains(e.key)) e.key: e.value,
    };
    final bar = _audioBar(s);
    final ctrl = _audioCtrls[s.id];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StoryReaderPanel(
          key: ValueKey('rd-${s.id}'),
          storyId: s.id,
          title: s.title,
          text: paras.take(shown).join('\n\n'),
          fullText: s.text,
          langCode: s.langCode,
          targetLangs: langs,
          paraTranslations: trans,
          splitSentences: _splitSentences,
          audio: ctrl,
          audioBar: bar,
          saved: _readSaved,
          onSave: _readSaved ? null : _readingSave,
          onTextEdited: (t) => _importForReading(t),
          notes: _readNotes,
          onNotesChanged: (v) {
            _readNotes = v;
            if (_readSaved) _libNotes(s.id, v);
          },
          onParagraphRetranslated: (lang, idx, t) {
            final list = _readTrans[lang];
            if (list != null && idx < list.length) {
              setState(() => list[idx] = t);
            }
          },
        ),
        if (_readTranslating)
          Padding(
            padding: const EdgeInsets.only(top: 6),
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
        Align(
          alignment: Alignment.centerLeft,
          child: HopeTextAction(label: 'بستن', color: c.rose, onTap: _readingClose),
        ),
      ],
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
  List<String> _sentencesOf(String text) {
    if (identical(text, _sentSrc)) return _sentCache;
    final out = <String>[
      for (final p in text.split(RegExp(r'\n\s*\n')))
        if (p.trim().isNotEmpty) ..._splitSentences(p.trim()),
    ];
    _sentSrc = text;
    _sentCache = out;
    return out;
  }

  StoryAudioController _ctrlFor(SavedStory s) {
    final sents = _sentencesOf(s.text);
    final ex = _audioCtrls[s.id];
    if (ex != null) {
      ex.langCode = s.langCode;
      ex.updateSentences(sents);
      return ex;
    }
    final c = StoryAudioController(
      storyKey: s.id,
      sentences: sents,
      prefs: ref.read(sharedPrefsProvider),
      langCode: s.langCode,
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
      // متنِ هر صفحه از isolateِ جدا می‌آید؛ اینجا فقط جمع می‌کنیم (شکستن به جمله
      // بعداً یک‌جا و در isolate انجام می‌شود).
      final buf = StringBuffer();
      var truncated = false;
      final pc = doc.pageCount;
      for (var i = 0; i < pc; i++) {
        final t = await doc.pageText(i);
        if (!mounted) return;
        if (t.isNotEmpty) {
          buf.write(t);
          buf.write(' ');
        }
        if (i % 4 == 0 || i == pc - 1) {
          setState(() => _importProgress = 'صفحه‌ی ${i + 1} از $pc...');
        }
        if (buf.length > 6000000) {
          truncated = true;
          break;
        }
      }
      if (!mounted) return;
      final all = buf.toString();
      if (all.trim().isEmpty) {
        setState(() => _importError =
            'متنی از این PDF استخراج نشد — شاید این فایل اسکن/عکسه، نه متنِ واقعی');
        return;
      }
      _importForReading(
        all,
        preNote: truncated
            ? 'توجه: چون فایل بزرگ بود، فقط بخشی از متنش خونده و آماده‌ی خوانش شد'
            : '',
      );
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
  /// متنِ خامِ یک صفحه را به پاراگراف‌های چندجمله‌ای می‌شکند (مثلِ وارد کردنِ متن)
  String _chunkParas(String raw) {
    final sentences = _splitSentences(raw);
    if (sentences.isEmpty) return raw.trim();
    final chunks = <String>[];
    for (var k = 0; k < sentences.length; k += _kSentencesPerParagraph) {
      final end = k + _kSentencesPerParagraph > sentences.length
          ? sentences.length
          : k + _kSentencesPerParagraph;
      chunks.add(sentences.sublist(k, end).join(' '));
    }
    return chunks.join('\n\n');
  }

  /// شناسه‌ی پایدارِ فایل (اندازه + هشِ ۶۴KB اول و آخر) تا اگر همان PDF دوباره
  /// باز شد، ترجمه‌های قبلی از دیسک برگردند و ترجمه از اول شروع نشود.
  String _docKeyFor(PickedFile f) {
    final b = f.bytes;
    final n = b.length;
    var h = 0x811c9dc5;
    void feed(int from, int to) {
      for (var i = from; i < to; i++) {
        h ^= b[i];
        h = (h * 0x01000193) & 0xFFFFFFFF;
      }
    }

    feed(0, n < 65536 ? n : 65536);
    if (n > 131072) feed(n - 65536, n);
    return 'pdf_${n}_${h.toRadixString(36)}';
  }

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
      final key = _docKeyFor(f);
      setState(() {
        _pdfDoc = doc;
        _pdfTitle = f.name;
        _pdfDocKey = key;
        _pdfIndex = 0;
        _pdfShowOrig = false;
      });
      unawaited(_loadPdfPage(0));
      // ترجمه‌ی عکسی فقط برای صفحه‌ی فعلی و چند صفحه‌ی بعد شروع می‌شود.
      // ترجمه‌ی کلِ کتاب فقط با انتخابِ صریحِ کاربر (نوارِ ترجمه) انجام می‌شود.
      unawaited(_buildPdfEngine(activate: true));
      unawaited(_bookDisk.trim(maxBytes: 800 * 1024 * 1024, keepDoc: key));
    } catch (_) {
      if (mounted) {
        setState(() => _importError =
            'این PDF باز نشد — فایل ممکنه خراب یا رمزگذاری‌شده باشه، یا حافظه‌ی گوشی کم باشه');
      }
    } finally {
      if (mounted) setState(() => _pdfViewBusy = false);
    }
  }

  void _disposePdfEngine() {
    final e = _pdfEngine;
    if (e != null) {
      e.removeListener(_onPdfEngineChanged);
      e.dispose();
    }
    _pdfEngine = null;
    _pdfCurTrans = null;
    _pdfCurTransFor = -1;
  }

  void _closePdfView({bool notify = true}) {
    _pdfEngineToken++;
    _disposePdfEngine();
    final ocr = _pdfOcr;
    _pdfOcr = null;
    if (ocr != null) unawaited(ocr.close());
    _pdfDoc?.dispose();
    _pdfDoc = null;
    _pdfImages.clear();
    _pdfTexts.clear();
    _pdfTrans.clear();
    _pdfViewLang = null;
    _pdfDocKey = '';
    _pdfIndex = 0;
    if (notify && mounted) setState(() {});
  }

  String _pdfTransSigNow() =>
      'v3|${(_effectiveTransLangs().toList()..sort()).join(',')}|${_pdfViewLang ?? ''}';

  /// بعد از عوض‌شدنِ زبانِ ترجمه، موتورِ جدیدی با امضای جدید ساخته می‌شود
  /// (اگر قبلاً برای همین زبان ترجمه شده بود، صفحه‌ها از دیسک فوراً برمی‌گردند).
  void _restartPdfTransIfOpen() {
    if (_pdfDoc == null) return;
    Future.microtask(() {
      if (mounted && _pdfDoc != null) {
        unawaited(_buildPdfEngine(activate: true));
      }
    });
  }

  Future<void> _buildPdfEngine({bool activate = true}) async {
    final doc = _pdfDoc;
    if (doc == null) return;
    final token = ++_pdfEngineToken;
    _disposePdfEngine();
    final lang = _readingLang();
    final style = Theme.of(context).textTheme.bodyMedium;
    final eng = PageTranslateEngine(
      docKey: _pdfDocKey,
      sig: _pdfTransSigNow(),
      pageCount: doc.pageCount,
      disk: _bookDisk,
      worker: (i) => _translatePdfPage(doc, i, lang, style),
    );
    await eng.init();
    if (!mounted || _pdfDoc != doc || token != _pdfEngineToken) {
      eng.dispose();
      return;
    }
    eng.addListener(_onPdfEngineChanged);
    setState(() => _pdfEngine = eng);
    if (activate) eng.activate(page: _pdfIndex);
    unawaited(_refreshPdfTrans());
  }

  /// ترجمه‌ی کاملِ «یک» صفحه: رندر ← OCR ← ترجمه‌ی بلوک‌ها ← ساختنِ عکس.
  /// null = صفحه متنی ندارد. خطای PageTranslateFatal = توقفِ کلِ موتور.
  Future<Uint8List?> _translatePdfPage(
      PdfDocHandle doc, int i, String lang, TextStyle? style) async {
    if (!mounted || _pdfDoc != doc) throw StateError('closed');
    final ocr = _pdfOcr ??= await OcrSession.open(lang);
    final svc = ref.read(translationServiceProvider);
    final ai = ref.read(aiSettingsProvider);
    final base = await doc.renderPage(i, scale: 2.0);
    List<OcrBlock> blocks;
    try {
      blocks = await ocr.recognizeBlocks(base);
    } on UnsupportedError catch (e) {
      throw PageTranslateFatal(_ioError(e, 'OCR برای این زبان پشتیبانی نمی‌شه'));
    }
    if (blocks.isEmpty) return null; // فقط عکسه → همان عکسِ اصلی
    final pageLang = _detectLang(blocks.map((b) => b.text).join(' '), lang);
    final targets =
        _effectiveTransLangs().where((l) => l != pageLang).toList();
    if (targets.isEmpty) {
      throw const PageTranslateFatal(
          'زبانِ ترجمه با زبانِ متنِ صفحه یکیه — از تنظیماتِ ترجمه یه زبانِ دیگه انتخاب کن');
    }
    final target = (_pdfViewLang != null && targets.contains(_pdfViewLang))
        ? _pdfViewLang!
        : targets.first;
    final trs = await runWithConcurrencyLimit<OcrBlock, String>(
      blocks,
      3,
      (b, _) async {
        try {
          final t = (await svc.translate(
            text: b.text,
            targetLang: target,
            sourceLang: pageLang,
            aiSettings: ai,
          ))
              .trim();
          return t == b.text.trim() ? '' : t;
        } catch (_) {
          return '';
        }
      },
    );
    if (trs.every((t) => t.isEmpty)) {
      throw StateError('translate-failed'); // موتور تا ۳ بار دوباره تلاش می‌کند
    }
    return renderTranslatedPage(
      pageImage: base,
      blocks: blocks,
      translations: trs,
      rtl: const {'fa', 'ar', 'ur', 'he'}.contains(target),
      // جهتِ مبدأ و مقصد فرق دارد (مثلاً انگلیسی ← فارسی): ستون‌ها هم آینه می‌شوند
      mirror: const {'fa', 'ar', 'ur', 'he'}.contains(target) !=
          const {'fa', 'ar', 'ur', 'he'}.contains(pageLang),
      baseStyle: style,
    );
  }

  void _onPdfEngineChanged() {
    if (!mounted) return;
    final e = _pdfEngine;
    if (e == null) return;
    if (_pdfCurTransFor != _pdfIndex &&
        e.statusOf(_pdfIndex) == PageStatus.done) {
      unawaited(_refreshPdfTrans());
    }
  }

  /// عکسِ ترجمه‌شده‌ی صفحه‌ی فعلی را (از RAM یا دیسک) برای نمایش می‌آورد.
  Future<void> _refreshPdfTrans() async {
    final e = _pdfEngine;
    final idx = _pdfIndex;
    if (e == null) return;
    final img = await e.imageFor(idx);
    if (!mounted || _pdfEngine != e || _pdfIndex != idx) return;
    if (img == null && _pdfCurTrans == null) return;
    setState(() {
      _pdfCurTrans = img;
      _pdfCurTransFor = img == null ? -1 : idx;
    });
  }

  Future<void> _loadPdfPage(int i) async {
    final doc = _pdfDoc;
    if (doc == null || i < 0 || i >= doc.pageCount) return;
    setState(() {
      _pdfIndex = i;
      _pdfZoom.value = Matrix4.identity();
      _pdfZoomT.value = Matrix4.identity();
      _pdfPageBusy = true;
      _pdfCurTrans = null;
      _pdfCurTransFor = -1;
    });
    _pdfEngine?.focusOn(i);
    unawaited(_refreshPdfTrans());
    try {
      if (!_pdfImages.containsKey(i)) {
        _pdfImages[i] = await doc.renderPage(i);
        // حافظه: فقط چند صفحه‌ی نزدیک به صفحه‌ی فعلی نگه داشته می‌شود
        while (_pdfImages.length > _kPdfKeepImages) {
          var far = _pdfImages.keys.first;
          for (final k in _pdfImages.keys) {
            if ((k - i).abs() > (far - i).abs()) far = k;
          }
          if (far == i) break;
          _pdfImages.remove(far);
        }
        if (mounted && _pdfDoc == doc && _pdfIndex == i) setState(() {});
      }
      if (!_pdfTexts.containsKey(i)) {
        _pdfTexts[i] = await doc.pageText(i);
      }
    } catch (_) {
      _pdfTexts[i] ??= '';
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
        content: Text(context.l10n.story_delete_confirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.l10n.cancel_button),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.l10n.library_delete),
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

    // اگه کاربر زبانِ مادری رو عوض کرد (و زبانِ ترجمه رو دستی انتخاب نکرده)
    ref.listen(languageSelectionProvider, (prev, next) {
      if (prev != null && prev.native != next.native && !_transTouched) {
        _restartPdfTransIfOpen();
      }
    });
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
      contentDirection: uiContentDirection(context),
      title: context.l10n.story_builder_title,
      titleSize: 16,
      children: [
        _modeSwitch(c, stories.length),
        if (_showSaved)
          const SavedTab(embedded: true)
        else if (_showLibrary)
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
    // سه حالت: ساخت داستان | ذخیره‌شده‌ها (کتابخانه) | ذخیره برای داستان بعدی
    Widget seg(int mode, String label, IconData icon) {
      // 0 = ساخت داستان، 1 = ذخیره‌شده‌ها (کتابخانه)، 2 = ذخیره برای داستان بعدی
      final cur = _showLibrary ? 1 : (_showSaved ? 2 : 0);
      final active = cur == mode;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() {
            _showLibrary = mode == 1;
            _showSaved = mode == 2;
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 5),
            decoration: BoxDecoration(
              color: active ? c.gold : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: active ? c.gold : Colors.transparent,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 15, color: active ? c.headerTo : c.inkSoft),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: active ? c.headerTo : c.inkSoft,
                      fontSize: 12,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w600,
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
          seg(0, context.l10n.story_mode_create, Icons.auto_fix_high),
          seg(1, '${context.l10n.story_mode_saved_library} ($count)', Icons.local_library_outlined),
          seg(2, context.l10n.story_mode_saved_words, Icons.bookmark_outline),
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
          Text(context.l10n.story_lang_level_section,
              style: TextStyle(
                  color: c.ink, fontSize: 14.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          if (options.length > 1) ...[
            Text(
              context.l10n.story_lang_pick_hint,
              style: TextStyle(color: c.inkSoft, fontSize: 12),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final code in options)
                  HopeChoiceChip(
                    label: langDisplayName(context, code),
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
              context.l10n.story_lang_single_note(langDisplayName(context, lang)),
              style: TextStyle(color: c.inkSoft, fontSize: 12),
            ),
          label(context.l10n.story_level_label, top: 4),
          LevelChips(
            selected: _level,
            includeAll: false,
            wrap: true,
            onSelect: (lv) => setState(() => _level = lv),
          ),
          label(context.l10n.story_content_type_label),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in _kContentTypes)
                HopeChoiceChip(
                  label: _contentLabel(context.l10n, t.key),
                  active: _contentType == t.key,
                  activeBorder: c.rose,
                  activeFill: c.rose,
                  activeText: Colors.white,
                  onTap: () => setState(() => _contentType = t.key),
                ),
            ],
          ),
          label(context.l10n.story_length_label),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final l in _kLengths)
                HopeChoiceChip(
                  label: _lengthLabel(context.l10n, l.key),
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
          Text(context.l10n.story_words_section,
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
                    context.l10n.story_word_input_placeholder(langDisplayName(context, lang)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Opacity(
                opacity: _translating ? 0.6 : 1,
                child: Material(
                  color: c.gold,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: _translating ? null : () => _addCustom(lang),
                    child: SizedBox(
                      width: 42,
                      height: 40,
                      child: Center(
                        child: _translating
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: c.headerTo,
                                ),
                              )
                            : Icon(Icons.add, size: 18, color: c.headerTo),
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
              context.l10n.story_vocab_search_placeholder,
            ).copyWith(
              // ✕ سمتِ چپِ کادر
              prefixIcon: _query.text.isEmpty ||
                      Directionality.of(context) != TextDirection.ltr
                  ? null
                  : IconButton(
                      icon: Icon(Icons.close, size: 16, color: c.inkSoft),
                      onPressed: () => setState(_query.clear),
                    ),
              suffixIcon: _query.text.isEmpty ||
                      Directionality.of(context) == TextDirection.ltr
                  ? null
                  : IconButton(
                      icon: Icon(Icons.close, size: 16, color: c.inkSoft),
                      onPressed: () => setState(_query.clear),
                    ),
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
                            color: c.gold,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(w,
                                  textDirection: autoDir(w),
                                  style: TextStyle(
                                      color: c.headerTo, fontSize: 12)),
                              const SizedBox(width: 4),
                              GestureDetector(
                                onTap: () => _toggleWord(w),
                                child: Icon(Icons.close,
                                    size: 13, color: c.headerTo),
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
                      context.l10n.clear_all_words,
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
      _restartPdfTransIfOpen();
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
            context.l10n.story_translate_langs_question,
            style: TextStyle(color: c.inkSoft, fontSize: 12.5, height: 1.7),
          ),
          Row(
            children: [
              HopeTextAction(
                label: context.l10n.select_all,
                color: c.teal,
                onTap: () =>
                    setAll({for (final l in kSupportedLanguages) l.code}),
              ),
              const SizedBox(width: 14),
              HopeTextAction(
                label: context.l10n.clear_all_words,
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
                  label: langDisplayName(context, l.code),
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
        color: c.gold,
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
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: c.headerTo),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(label,
                    style: TextStyle(
                        color: c.headerTo,
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
    final tImg = _pdfCurTransFor == i ? _pdfCurTrans : null;
    final orig = _pdfTexts[i] ?? '';
    final lang = _readingLang();
    final viewPageLang = _detectLang(orig, lang);
    final viewTargets =
        _effectiveTransLangs().where((l) => l != viewPageLang).toList();
    return HopeCard(
      padding: const EdgeInsets.fromLTRB(3, 10, 3, 10), // کناره‌ی کم‌تر = صفحه‌ی بزرگ‌تر
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
          _pdfModeSelector(c),
          const SizedBox(height: 8),
          _pdfImagesBox(c, img, tImg, i),
          const SizedBox(height: 6),
          _pdfSaveRow(c, img, tImg, i),
          const SizedBox(height: 8),
          // دکمه‌های صفحه‌ی قبل/بعد درست زیرِ عکس (بدونِ نیاز به اسکرول)
          PdfPageNavBar(
            index: i,
            count: doc.pageCount,
            busy: _pdfPageBusy,
            onGo: (p) => _loadPdfPage(p),
          ),
          const SizedBox(height: 8),
          if (_pdfEngine != null)
            BookTranslateBar(
              key: ValueKey('bk-${identityHashCode(_pdfEngine)}'),
              engine: _pdfEngine!,
              currentPage: i,
              onJump: (p) => _loadPdfPage(p),
            ),
          const SizedBox(height: 6),
          if (viewTargets.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final l in viewTargets)
                    HopeChoiceChip(
                      label: langDisplayName(context, l),
                      active: (_pdfViewLang != null &&
                              viewTargets.contains(_pdfViewLang))
                          ? _pdfViewLang == l
                          : viewTargets.first == l,
                      activeBorder: c.gold,
                      activeFill: c.goldSoft,
                      activeText: c.ink,
                      fontSize: 12,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      onTap: () {
                        setState(() => _pdfViewLang = l);
                        _restartPdfTransIfOpen();
                      },
                    ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          if (!_pdfTexts.containsKey(i))
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text('در حال خواندنِ متنِ این صفحه...',
                      style: TextStyle(color: c.inkSoft, fontSize: 12)),
                ],
              ),
            )
          else if (orig.trim().isEmpty)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: c.goldSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'این صفحه متنِ قابل‌خواندن نداره — احتمالاً فقط عکسه. برای دیدنِ ترجمه روی خودِ عکس، دکمه‌ی «ترجمه‌ی عکسیِ صفحه‌ها» رو بزن.',
                style: TextStyle(color: c.inkSoft, fontSize: 12),
              ),
            )
          else
            Builder(builder: (_) {
              final pageLang = _detectLang(orig, lang);
              return StoryReaderPanel(
                key: ValueKey('pdf-${_pdfTitle.hashCode}-$i'),
                storyId: 'pdf${_pdfTitle.hashCode}-$i',
                title: 'متنِ صفحه‌ی ${i + 1}',
                text: _chunkParas(orig),
                langCode: pageLang,
                targetLangs: _effectiveTransLangs()
                    .where((l) => l != pageLang)
                    .toList(),
                splitSentences: _splitSentences,
              );
            }),
        ],
      ),
    );
  }

  // ───── ذخیره‌ی عکس / PDF ─────
  void _pdfSnack(String msg) {
    if (!mounted) return;
    final m = ScaffoldMessenger.maybeOf(context);
    m?.hideCurrentSnackBar();
    m?.showSnackBar(SnackBar(content: Text(msg)));
  }

  String get _pdfBaseName {
    var n = _pdfTitle.trim();
    if (n.toLowerCase().endsWith('.pdf')) n = n.substring(0, n.length - 4);
    n = n.replaceAll(RegExp(r'[\/:*?"<>|]'), '_');
    return n.isEmpty ? 'page' : n;
  }

  Widget _pdfSaveRow(
      AppThemeColorsExt c, Uint8List? img, Uint8List? tImg, int page) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // یک دکمه‌ی «ذخیره»: عکسِ اصلی + عکسِ ترجمه + متنِ زیرش (و ترجمه‌اش) با هم
        HopeTextAction(
          icon: Icons.bookmark_add_rounded,
          label: _pdfSaving ? 'در حال ذخیره…' : 'ذخیره',
          color: c.rose,
          onTap: _pdfSaving ? null : () => _savePdfPageAll(img, tImg, page),
        ),
        const SizedBox(width: 18),
        HopeTextAction(
          icon: Icons.picture_as_pdf_rounded,
          label: _pdfSaving ? 'در حال ساختنِ PDF…' : 'ذخیره‌ی PDF',
          color: c.gold,
          onTap: _pdfSaving ? null : _savePdfFile,
        ),
      ],
    );
  }

  /// «ذخیره»: عکسِ اصلیِ صفحه + عکسِ ترجمه‌شده + متنِ استخراج‌شده و ترجمه‌اش، همه در «یک» عکس؛
  /// و همان متن (با ترجمه) در کتابخانه‌ی داستان‌ساز.
  Future<void> _savePdfPageAll(
      Uint8List? img, Uint8List? tImg, int page) async {
    final doc = _pdfDoc;
    if (doc == null || _pdfSaving) return;
    setState(() => _pdfSaving = true);
    try {
      final base = img ?? await doc.renderPage(page, scale: 2.0);
      final trans = tImg ?? await _pdfEngine?.imageFor(page);
      var text = _pdfTexts[page];
      text ??= await doc.pageText(page);
      final lang = _readingLang();
      final pageLang = _detectLang(text, lang);
      final targets =
          _effectiveTransLangs().where((l) => l != pageLang).toList();
      final target = targets.isEmpty
          ? null
          : ((_pdfViewLang != null && targets.contains(_pdfViewLang))
              ? _pdfViewLang!
              : targets.first);
      const rtlLangs = {'fa', 'ar', 'ur', 'he'};
      final paras = _chunkParas(text)
          .split(RegExp(r'\n\s*\n'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      var trs = List<String>.filled(paras.length, '');
      if (target != null && paras.isNotEmpty) {
        final svc = ref.read(translationServiceProvider);
        final ai = ref.read(aiSettingsProvider);
        trs = await runWithConcurrencyLimit<String, String>(
          paras,
          3,
          (p, _) async {
            try {
              return (await svc.translate(
                text: p,
                targetLang: target,
                sourceLang: pageLang,
                aiSettings: ai,
              ))
                  .trim();
            } catch (_) {
              return '';
            }
          },
        );
      }
      if (!mounted || _pdfDoc != doc) return;
      final png = await buildCombinedPageImage(
        orig: base,
        trans: trans,
        paragraphs: paras,
        translations: trs,
        srcRtl: rtlLangs.contains(pageLang),
        dstRtl: target != null && rtlLangs.contains(target),
        baseStyle: Theme.of(context).textTheme.bodyMedium,
      );
      final ok = await saveBytesToDevice(
        fileName: '${_pdfBaseName}_p${page + 1}.png',
        bytes: png,
        ext: 'png',
      );
      if (ok) {
        await _saveTextAsStory(text,
            title: '$_pdfBaseName — صفحه‌ی ${page + 1}', translate: true);
        _pdfSnack('ذخیره شد ✓');
      }
    } catch (e) {
      _pdfSnack('ذخیره انجام نشد');
    } finally {
      if (mounted) setState(() => _pdfSaving = false);
    }
  }

  /// نمایشگرِ تمام‌صفحه (زومِ آزاد) با حالت‌های اصلی / ترجمه / متن
  void _openPdfFullscreen(String mode, int page) {
    showPdfFullscreen(
      context,
      orig: _pdfImages[page],
      trans: _pdfCurTransFor == page ? _pdfCurTrans : null,
      text: _pdfTexts[page] ?? '',
      title: '$_pdfTitle — صفحه‌ی ${page + 1}',
      initial: mode,
      onSaveText: () => _saveTextAsStory(_pdfTexts[page] ?? '',
          title: '$_pdfBaseName — صفحه‌ی ${page + 1}', translate: true),
    );
  }

  /// «ذخیره‌ی متن»: متنِ استخراج‌شده‌ی همین صفحه (یا همه‌ی صفحه‌ها) در کتابخانه‌ی داستان‌ساز ذخیره می‌شود.
  Future<void> _savePdfTextToStories(int page) async {
    final doc = _pdfDoc;
    if (doc == null) return;
    var scope = 'page';
    if (doc.pageCount > 1) {
      final r = await _askChoice('کدام متن ذخیره شود؟', {
        'page': 'فقط همین صفحه',
        'all': 'همه‌ی صفحه‌ها',
      });
      if (r == null) return;
      scope = r;
    }
    if (scope == 'page') {
      var t = _pdfTexts[page];
      t ??= await doc.pageText(page);
      final ok = await _saveTextAsStory(t,
          title: '$_pdfBaseName — صفحه‌ی ${page + 1}', translate: true);
      _pdfSnack(ok
          ? 'متنِ صفحه در داستان‌ساز ذخیره شد ✓'
          : 'این صفحه متنی برای ذخیره ندارد');
      return;
    }
    setState(() => _pdfSaving = true);
    try {
      final buf = StringBuffer();
      for (var p = 0; p < doc.pageCount; p++) {
        final t = _pdfTexts[p] ?? await doc.pageText(p);
        if (!mounted || _pdfDoc != doc) return;
        if (t.trim().isNotEmpty) {
          buf.write(t.trim());
          buf.write('\n\n');
        }
      }
      final ok = await _saveTextAsStory(buf.toString(), title: _pdfBaseName);
      _pdfSnack(ok
          ? 'متنِ همه‌ی صفحه‌ها در داستان‌ساز ذخیره شد ✓'
          : 'متنی برای ذخیره پیدا نشد');
    } catch (e) {
      _pdfSnack('ذخیره‌ی متن انجام نشد');
    } finally {
      if (mounted) setState(() => _pdfSaving = false);
    }
  }

  Future<bool> _saveTextAsStory(String raw,
      {required String title, bool translate = false}) async {
    if (raw.trim().isEmpty) return false;
    final lang = _detectLang(raw, _readingLang());
    final story = SavedStory(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      text: _chunkParas(raw),
      langCode: lang,
      level: _detectCefr(raw),
      contentType: 'reading',
      words: const [],
      createdAt: DateTime.now(),
    );
    ref.read(storyLibraryProvider.notifier).add(story);
    if (translate) unawaited(_translateStory(story));
    return true;
  }

  Future<String?> _askChoice(String title, Map<String, String> options) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title, style: const TextStyle(fontSize: 15)),
        children: [
          for (final e in options.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, e.key),
              child: Text(e.value, style: const TextStyle(fontSize: 14)),
            ),
        ],
      ),
    );
  }

  /// ذخیره‌ی عکسِ همین صفحه (اصلی یا ترجمه‌شده، بسته به حالتِ نمایش)
  Future<void> _savePdfPageImage(
      Uint8List? img, Uint8List? tImg, int page) async {
    String which;
    if (_pdfMode == 'orig') {
      which = 'orig';
    } else if (_pdfMode == 'trans') {
      which = 'trans';
    } else {
      final r = await _askChoice('کدام عکس ذخیره شود؟',
          {'orig': 'عکسِ اصلی', 'trans': 'عکسِ ترجمه‌شده'});
      if (r == null) return;
      which = r;
    }
    final bytes = which == 'trans' ? tImg : img;
    if (bytes == null) {
      _pdfSnack(which == 'trans'
          ? 'ترجمه‌ی این صفحه هنوز آماده نیست'
          : 'عکسِ این صفحه هنوز آماده نیست');
      return;
    }
    try {
      final ok = await saveBytesToDevice(
        fileName:
            '${_pdfBaseName}_p${page + 1}${which == 'trans' ? '_translated' : ''}.png',
        bytes: bytes,
        ext: 'png',
      );
      if (ok) _pdfSnack('عکس ذخیره شد ✓');
    } catch (e) {
      _pdfSnack('ذخیره‌ی عکس انجام نشد');
    }
  }

  /// ساختن و ذخیره‌ی PDF از همه‌ی صفحه‌ها (اصلی یا ترجمه‌شده)
  Future<void> _savePdfFile() async {
    final doc = _pdfDoc;
    if (doc == null || _pdfSaving) return;
    String which;
    if (_pdfMode == 'orig') {
      which = 'orig';
    } else if (_pdfMode == 'trans') {
      which = 'trans';
    } else {
      final r = await _askChoice('کدام PDF ذخیره شود؟',
          {'trans': 'PDFِ ترجمه‌شده', 'orig': 'PDFِ اصلی'});
      if (r == null) return;
      which = r;
    }
    setState(() => _pdfSaving = true);
    try {
      final imgs = <Uint8List>[];
      var missing = 0;
      for (var p = 0; p < doc.pageCount; p++) {
        Uint8List? b;
        if (which == 'trans') {
          b = await _pdfEngine?.imageFor(p);
          if (b == null) missing++;
        }
        b ??= await doc.renderPage(p, scale: 2.0);
        imgs.add(b);
        if (!mounted || _pdfDoc != doc) return;
      }
      final pdf = await imagesToPdf(imgs);
      final ok = await saveBytesToDevice(
        fileName: '$_pdfBaseName${which == 'trans' ? '_translated' : ''}.pdf',
        bytes: pdf,
        ext: 'pdf',
      );
      if (ok) {
        _pdfSnack(missing > 0
            ? 'PDF ذخیره شد ✓ ($missing صفحه هنوز ترجمه نشده بود و به‌صورتِ اصلی آمد)'
            : 'PDF ذخیره شد ✓');
      }
    } catch (e) {
      _pdfSnack('ساختن/ذخیره‌ی PDF انجام نشد');
    } finally {
      if (mounted) setState(() => _pdfSaving = false);
    }
  }

  /// انتخابِ حالتِ نمایشِ صفحه: هر دو (اصلی بالا، ترجمه پایین) · فقط ترجمه · فقط اصلی.
  Widget _pdfModeSelector(AppThemeColorsExt c) {
    Widget seg(String mode, IconData icon, String label, {bool? active, String? goTo}) {
      final on = active ?? (_pdfMode == mode);
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _pdfMode = goTo ?? mode),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              color: on ? c.teal : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: on ? Colors.white : c.teal),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: on ? Colors.white : c.ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w800)),
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
        color: c.goldSoft.withOpacity(0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.cardBorder),
      ),
      child: Row(
        children: [
          seg('both', Icons.view_agenda_outlined, 'اصلی + ترجمه'),
          // یک دکمه برای دو حالت: هر کلیک بین «دیدنِ ترجمه» و «دیدنِ اصلی» جابه‌جا می‌کند
          if (_pdfMode == 'trans')
            seg('trans', Icons.image_outlined, 'دیدنِ اصلی',
                active: true, goTo: 'orig')
          else
            seg('orig', Icons.translate_rounded, 'دیدنِ ترجمه',
                active: _pdfMode == 'orig', goTo: 'trans'),
        ],
      ),
    );
  }

  /// عکسِ اصلیِ صفحه و/یا عکسِ ترجمه‌شده؛ هر دو قابل زوم و چرخش جداگانه (دو انگشت / دوبار لمس).
  Widget _pdfImagesBox(
      AppThemeColorsExt c, Uint8List? img, Uint8List? tImg, int page) {
    Widget frame(Widget child) => ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            constraints: const BoxConstraints(minHeight: 120),
            decoration: BoxDecoration(border: Border.all(color: c.cardBorder)),
            child: child,
          ),
        );

    final orig = frame(img == null
        ? const Padding(
            padding: EdgeInsets.all(30),
            child: Center(child: CircularProgressIndicator()),
          )
        : ZoomablePageImage(
            bytes: img,
            label: 'اصلی',
            accent: c.gold,
            controller: _pdfZoom,
            onExpand: () => _openPdfFullscreen('orig', page)));

    Widget trans() {
      if (tImg != null) {
        return frame(
            ZoomablePageImage(
                bytes: tImg,
                label: 'ترجمه',
                accent: c.teal,
                controller: _pdfZoomT,
                onExpand: () => _openPdfFullscreen('trans', page)));
      }
      final e = _pdfEngine;
      final st = e?.statusOf(page);
      final String msg;
      if (e == null) {
        msg = 'برای دیدنِ ترجمه‌ی عکسی، ترجمه را با دکمه‌ی ▶ شروع کن.';
      } else if (st == PageStatus.working || (e.active && st == PageStatus.pending)) {
        msg = '⏳ ترجمه‌ی این صفحه در حال انجام است…';
      } else if (st == PageStatus.failed) {
        msg = 'ترجمه‌ی این صفحه انجام نشد — «تلاشِ دوباره» را بزن.';
      } else if (st == PageStatus.empty) {
        msg = 'این صفحه متنی برای ترجمه ندارد (همان عکسِ اصلی است).';
      } else {
        msg = 'ترجمه‌ی این صفحه هنوز آماده نیست — ▶ را بزن.';
      }
      return frame(Padding(
        padding: const EdgeInsets.all(22),
        child: Center(
          child: Text(msg,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.inkSoft, fontSize: 12.5, height: 1.6)),
        ),
      ));
    }

    switch (_pdfMode) {
      case 'orig':
        return orig;
      case 'trans':
        return trans();
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [orig, const SizedBox(height: 8), trans()],
        );
    }
  }

  List<Widget> _importSection(AppThemeColorsExt c) {
    final L = context.l10n;
    final busyAny = _pdfReadBusy || _imgReadBusy || _pdfViewBusy;
    String lbl(bool busy, String idle) =>
        busy ? (_importProgress.isEmpty ? L.story_busy_processing : _importProgress) : idle;
    return [
      _importButton(
        c,
        emoji: '📖',
        label: lbl(_pdfReadBusy, L.story_import_pdf),
        onTap: busyAny ? () {} : _importPdfForReading,
      ),
      _importButton(
        c,
        emoji: '🖼️',
        label: lbl(_imgReadBusy, L.story_import_images),
        onTap: busyAny ? () {} : _importImagesForReading,
      ),
      _importButton(
        c,
        emoji: '📑',
        label: _pdfViewBusy
            ? L.story_pdf_opening
            : L.story_pdf_view_btn,
        onTap: busyAny ? () {} : _openPdfView,
      ),
      if (_pdfDoc != null) _pdfViewer(c),
      _importButton(
        c,
        emoji: '🔗',
        label: _showLink ? L.story_link_close : L.story_link_open,
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
              L.story_link_note,
              style: TextStyle(color: c.inkSoft, fontSize: 10.5),
            ),
            const SizedBox(height: 6),
            _primaryBtn(
              c,
              _linkBusy ? L.story_link_fetching : L.story_link_fetch_btn,
              _linkCtrl.text.trim().isEmpty || _linkBusy ? null : _importLink,
              busy: _linkBusy,
            ),
          ],
        ),
      _importButton(
        c,
        emoji: '📋',
        label: _showPaste ? L.story_paste_close : L.story_paste_open,
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
              decoration: _fieldDeco(c, L.story_paste_hint),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 6),
            _primaryBtn(
              c,
              '📖 ${L.story_prepare_reading}',
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
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: c.headerTo),
                  )
                else
                  Icon(Icons.auto_awesome, size: 18, color: c.headerTo),
                const SizedBox(width: 8),
                Text(
                  _generating
                      ? context.l10n.story_generating_btn
                      : context.l10n.story_generate_btn,
                  style: TextStyle(
                    color: c.headerTo,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _libPanel(c, s),
        if (_storyTranslating)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('در حال ترجمه‌ی داستان...',
                style: TextStyle(color: c.inkSoft, fontSize: 12)),
          ),
      ],
    );
  }

  // ───────────── پنلِ داستانِ ذخیره‌شده (کتابخانه / نتیجه‌ی ساخت) ─────────────
  SavedStory? _libGet(String id) {
    for (final e in ref.read(storyLibraryProvider)) {
      if (e.id == id) return e;
    }
    return null;
  }

  void _libPut(SavedStory updated) {
    ref.read(storyLibraryProvider.notifier).update(updated);
    if (mounted && _result?.id == updated.id) {
      setState(() => _result = updated);
    }
  }

  void _libNotes(String id, String v) {
    final cur = _libGet(id);
    if (cur == null || cur.notes == v) return;
    _libPut(cur.copyWith(notes: v));
  }

  void _libEdit(String id, String t) {
    final cur = _libGet(id);
    if (cur == null) return;
    _libPut(cur.copyWith(
      text: t,
      langCode: _detectLang(t, cur.langCode),
      translations: const {},
    ));
  }

  void _libParaTr(String id, String lang, int idx, String t) {
    final cur = _libGet(id);
    if (cur == null) return;
    final map = <String, List<String>>{
      for (final e in cur.translations.entries)
        e.key: List<String>.from(e.value),
    };
    final list = map.putIfAbsent(lang, () => <String>[]);
    while (list.length <= idx) {
      list.add('');
    }
    list[idx] = t;
    _libPut(cur.copyWith(translations: map));
  }

  Widget _libPanel(AppThemeColorsExt c, SavedStory s) {
    final langs = (s.translations.isNotEmpty
            ? s.translations.keys.toList()
            : _effectiveTransLangs().toList())
        .where((l) => l != s.langCode)
        .toList();
    final bar = _audioBar(s);
    final ctrl = _audioCtrls[s.id];
    // کتاب‌های بلند صفحه‌صفحه نشان داده می‌شوند؛ ساختنِ هزاران پاراگراف یک‌جا UI را قفل می‌کرد
    final allParas = _paras(s);
    final bigBook = allParas.length > _kLibParaPage + 10;
    final shown = bigBook
        ? ((_libVisible[s.id] ?? _kLibParaPage) > allParas.length
            ? allParas.length
            : (_libVisible[s.id] ?? _kLibParaPage))
        : allParas.length;
    final panel = StoryReaderPanel(
      key: ValueKey('lib-${s.id}'),
      storyId: s.id,
      title: s.title,
      text: bigBook ? allParas.take(shown).join('\n\n') : s.text,
      fullText: s.text,
      langCode: s.langCode,
      targetLangs: langs,
      paraTranslations: s.translations,
      splitSentences: _splitSentences,
      audio: ctrl,
      audioBar: bar,
      saved: true,
      onSave: () {},
      onTextEdited: (t) => _libEdit(s.id, t),
      notes: s.notes,
      onNotesChanged: (v) => _libNotes(s.id, v),
      onParagraphRetranslated: (lang, idx, t) =>
          _libParaTr(s.id, lang, idx, t),
    );
    if (!bigBook || shown >= allParas.length) return panel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        panel,
        Center(
          child: HopeTextAction(
            label: 'نمایش بیشتر ($shown از ${allParas.length} پاراگراف)',
            color: c.teal,
            onTap: () => setState(
                () => _libVisible[s.id] = shown + _kLibParaPage),
          ),
        ),
      ],
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
      if (_libFavOnly && stories.length > 1 && !s.favorite) return false;
      if (_libLevel != 'all' && s.level != _libLevel) return false;
      if (q.isEmpty) return true;
      return s.title.toLowerCase().contains(q) ||
          s.text.toLowerCase().contains(q) ||
          s.words.any((w) => w.toLowerCase().contains(q));
    }).toList();

    return [
      if (stories.length > 1)
        Row(
          children: [
            Expanded(
              child: Container(
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
                        hintText: context.l10n.library_search_placeholder,
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
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: context.l10n.library_favorite_aria,
              child: InkWell(
                onTap: () => setState(() => _libFavOnly = !_libFavOnly),
                customBorder: const CircleBorder(),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _libFavOnly ? const Color(0x33F5C518) : Colors.white,
                    border: Border.all(
                        color: _libFavOnly ? const Color(0xFFF5C518) : c.cardBorder),
                  ),
                  child: Icon(
                    _libFavOnly ? Icons.star : Icons.star_border,
                    size: 20,
                    color: _libFavOnly ? const Color(0xFFF5C518) : c.inkSoft,
                  ),
                ),
              ),
            ),
          ],
        ),
      // سطح‌ها همیشه نشان داده می‌شوند (مثل LevelFilterRow در Hope)
      LevelChips(
        selected: _libLevel,
        onSelect: (lv) => setState(() => _libLevel = lv),
      ),
      if (stories.isEmpty)
        HopeEmptyText(context.l10n.library_empty)
      else if (shown.isEmpty)
        HopeEmptyText(context.l10n.reader_nothing_found)
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

  /// نامِ برنامه‌ی مبدأ — اول از روی دامنه‌ی لینک (یوتیوب → «YouTube»، نه نامِ کانال)،
  /// وگرنه خط دومِ متن.
  static String? _appFromUrl(String url) {
    var h = (Uri.tryParse(url)?.host ?? '').toLowerCase();
    h = h.replaceFirst(RegExp(r'^(www|m|vm|vt|mobile)\.'), '');
    if (h.isEmpty) return null;
    bool ends(String d) => h == d || h.endsWith('.$d');
    if (ends('instagram.com')) return 'Instagram';
    if (ends('tiktok.com')) return 'TikTok';
    if (ends('youtube.com') || h == 'youtu.be') return 'YouTube';
    if (h == 't.me' || ends('telegram.me') || ends('telegram.org')) return 'Telegram';
    if (ends('facebook.com') || h == 'fb.watch' || h == 'fb.me') return 'Facebook';
    if (h == 'x.com' || ends('twitter.com')) return 'X';
    if (ends('snapchat.com')) return 'Snapchat';
    if (ends('reddit.com') || h == 'redd.it') return 'Reddit';
    if (ends('vimeo.com')) return 'Vimeo';
    if (ends('twitch.tv')) return 'Twitch';
    if (ends('linkedin.com')) return 'LinkedIn';
    if (ends('pinterest.com') || h == 'pin.it') return 'Pinterest';
    if (ends('spotify.com')) return 'Spotify';
    return h;
  }

  String _sourceOf(SavedStory s) {
    final link = _linkOf(s);
    final byUrl = link == null ? null : _appFromUrl(link);
    if (byUrl != null) return byUrl;
    final ls = s.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    return ls.length > 1 && !RegExp(r'^https?://', caseSensitive: false).hasMatch(ls[1])
        ? ls[1]
        : _contentLabel(context.l10n, s.contentType);
  }

  /// تاریخ و ساعتِ ذخیره، بر اساس زبانِ رابط
  String _savedAtLabel(DateTime d) {
    final loc = Localizations.localeOf(context).toString();
    try {
      return DateFormat.yMMMd(loc).add_Hm().format(d);
    } catch (_) {
      String two(int n) => n.toString().padLeft(2, '0');
      return '${d.year}/${two(d.month)}/${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
    }
  }

  Future<void> _openLink(String url) async {
    try {
      await NativeBridge.instance.openExternal(url: url);
    } catch (_) {}
  }

  Widget _storyCard(AppThemeColorsExt c, SavedStory s) {
    final link = _linkOf(s);
    final open = link == null && _openStoryId == s.id;
    final dateTime = _savedAtLabel(s.createdAt);
    return HopeCard(
      padding: const EdgeInsets.all(12),
      radius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 📅 تاریخ و ساعتِ ذخیره (مثل Hope)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(Icons.event, size: 12, color: c.inkSoft),
                const SizedBox(width: 4),
                Text(
                  dateTime,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(color: c.inkSoft, fontSize: 10.5),
                ),
              ],
            ),
          ),
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
                            ? '${_sourceOf(s)} · ${langDisplayName(context, s.langCode)}'
                            : '${langDisplayName(context, s.langCode)} · ${s.level} · '
                                '${_contentLabel(context.l10n, s.contentType)}',
                        style: TextStyle(
                          color: link != null ? c.gold : c.inkSoft,
                          fontSize: 11,
                          fontWeight:
                              link != null ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () =>
                      ref.read(storyLibraryProvider.notifier).toggleFavorite(s.id),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      s.favorite ? Icons.star : Icons.star_border,
                      size: 20,
                      color: s.favorite
                          ? const Color(0xFFF5C518)
                          : c.inkSoft.withOpacity(0.6),
                    ),
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
                  _libPanel(c, s),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
