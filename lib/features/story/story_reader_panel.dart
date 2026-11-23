import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../core/audio/story_audio_controller.dart';
import '../../core/constants/supported_languages.dart' show dirFor;
import '../../core/models/text_prefs.dart';
import '../../core/player_sync/playback_origin.dart'
    show revealActiveTickProvider;
import '../../core/player_sync/player_track.dart' show SyncItem, TrackMode;
import '../../core/player_sync/sync_widgets.dart'
    show SyncAnchor, SyncPlayScope, SyncSpeakButton, syncReportTranslation;
import '../../core/providers/ai_settings_provider.dart';
import '../../core/providers/language_selection_provider.dart';
import '../../core/tts/dialogue_voices.dart';
import '../../core/providers/reader_providers.dart' show savedWordsProvider;
import '../../core/providers/story_user_audio_provider.dart';
import '../../core/providers/text_prefs_provider.dart';
import '../../core/providers/translation_provider.dart';
import '../../core/storage/local_storage.dart' show sharedPrefsProvider;
import '../../core/theme/app_theme_colors.dart';
import '../../core/translate/known_translations.dart';
import '../../core/translate/shared_translations.dart';
import '../../core/translate/translation_service.dart'
    show TranslationService;
import '../../core/widgets/selection_card.dart'
    show SelectableRun, SelectableSyncText;
import '../../core/widgets/sync_item_card.dart' show NeuralPathButton;
import '../reader/widgets/neural_path_dialog.dart' show showNeuralPath;
import '../tabs/_hope_panel.dart'
    show HopeChoiceChip, autoDir, uiContentDirection;
import 'story_i18n.dart';
import 'story_voice_practice.dart';
import 'word_equivalents.dart';
import 'word_highlight.dart';

// ═══════════════════════════════════════════════════════════════════
// پنل خواندنِ داستان — هم‌شکل StoryReaderPanel.jsx در Hope
//   • بالا: عنوان + ✏️ ویرایشِ متن + 🔖 ذخیره در کتابخانه
//   • جستجو داخلِ متنِ داستان (هر زبانی)
//   • نمایشِ ترجمه: هیچ / پاراگراف‌به‌پاراگراف / جمله‌به‌جمله
//   • برای هر جمله (یا پاراگراف) و هر ترجمه: 🧬 🔊 و ↻
//   • پایین: یادداشت‌های من
// ═══════════════════════════════════════════════════════════════════

const String _kModeKey = 'zflut-story-trans-mode';
const Color _kTrColor = Color(0xFF0F5C34);

class _P {
  final String text;
  final List<String> sents;
  final int firstGi;
  const _P(this.text, this.sents, this.firstGi);
}

class _ParaUpdate {
  final String lang;
  final int pi;
  final String text;
  const _ParaUpdate(this.lang, this.pi, this.text);
}

class _Job {
  final String lang;
  final String src;
  final String key;
  const _Job(this.lang, this.src, this.key);
}

class _Hit {
  final int pi;
  final int gi;
  final String text;
  const _Hit(this.pi, this.gi, this.text);
}

class StoryReaderPanel extends ConsumerStatefulWidget {
  /// شناسه‌ی یکتا (برای کلیدِ دکمه‌های 🔊)
  final String storyId;
  final String title;

  /// متنِ نمایشی؛ پاراگراف‌ها با خطِ خالی جدا می‌شوند
  final String text;

  /// متنِ کاملِ داستان برای ویرایش (اگر null باشد همان [text])
  final String? fullText;
  final String langCode;

  /// زبان‌های ترجمه (بدونِ زبانِ خودِ متن)
  final List<String> targetLangs;

  /// ترجمه‌های آماده‌ی هر پاراگراف (کد زبان → لیست) — فقط برای پُر کردنِ اولیه
  final Map<String, List<String>> paraTranslations;
  final List<String> Function(String) splitSentences;

  final StoryAudioController? audio;
  final Widget? audioBar;

  /// دکمه‌ی 🔖: null = نمایش داده نمی‌شود
  final VoidCallback? onSave;
  final bool saved;

  /// دکمه‌ی ✏️: null = نمایش داده نمی‌شود
  final ValueChanged<String>? onTextEdited;

  /// یادداشت‌ها: null = بخشِ یادداشت نمایش داده نمی‌شود
  final ValueChanged<String>? onNotesChanged;
  final String notes;

  /// وقتی کاربر ↻ روی یک پاراگراف می‌زند
  final void Function(String lang, int paraIdx, String text)?
      onParagraphRetranslated;

  /// کشیدنِ برچسبِ زبانِ یک ترجمه روی ترجمه‌ی دیگر → جابه‌جایی (from به جای to)
  final void Function(String from, String to)? onReorderLangs;

  /// لغت‌هایی که هنگامِ ساختِ داستان انتخاب شده‌اند؛ داخلِ متن بولد می‌شوند (توسطِ خودِ اپ)
  final List<String> highlightWords;

  /// 🎭 داستانِ مکالمه‌ای: گوینده‌ی اول = صدای مرد، گوینده‌ی دوم = صدای زن
  /// (هم برای متنِ اصلی و هم برای ترجمه‌ها، مثلِ تبِ «مکالمه»)
  final bool dialogue;

  /// 🎙️ دکمه‌ی «حالتِ تمرین» (ویدیو کالِ AI) نشان داده شود؟ (داستان‌ساز و داستان‌های ذخیره‌شده)
  final bool enablePractice;

  /// سطحِ داستان و انتخابِ سطحِ بعدی بعد از «چند درصد فهمیدی؟» (اختیاری)
  final String level;
  final ValueChanged<String>? onLevelUp;

  const StoryReaderPanel({
    super.key,
    required this.storyId,
    required this.title,
    required this.text,
    required this.langCode,
    required this.targetLangs,
    required this.splitSentences,
    this.fullText,
    this.paraTranslations = const {},
    this.audio,
    this.audioBar,
    this.onSave,
    this.saved = false,
    this.onTextEdited,
    this.onNotesChanged,
    this.notes = '',
    this.onParagraphRetranslated,
    this.onReorderLangs,
    this.highlightWords = const [],
    this.dialogue = false,
    this.enablePractice = false,
    this.level = 'B1',
    this.onLevelUp,
  });

  @override
  ConsumerState<StoryReaderPanel> createState() => _StoryReaderPanelState();
}

class _StoryReaderPanelState extends ConsumerState<StoryReaderPanel> {
  /// 0 = هیچ، 1 = پاراگراف‌به‌پاراگراف، 2 = جمله‌به‌جمله
  int _mode = 2;

  final _searchCtrl = TextEditingController();
  final _editCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _editing = false;
  Timer? _notesTimer;
  Timer? _flashTimer;
  int _flashGi = -1;
  int? _lastActive;
  String _sig = '';

  // ثبتِ متنِ داستان در پلیرِ همگام (هایلایت + اسکرولِ خودکارِ 🔊 و پلیرِ پایین)
  Object _scopeRev = Object();
  String _scopeSig = '';

  final Map<String, String> _tr = {};
  final Set<String> _inflight = {};
  final Set<String> _failed = {};
  final Set<String> _retrying = {};
  final Map<int, GlobalKey> _pk = {};

  // ⚡ نمایشِ تدریجیِ پاراگراف‌ها: داستان با چند پاراگرافِ اول باز می‌شود و بقیه
  // دسته‌دسته (هر ~۸۰ms) اضافه می‌شوند تا باز شدنِ داستان‌های بلند قفل نکند.
  static const int _kFirstParas = 6;
  static const int _kGrowParas = 8;
  int _shownParas = _kFirstParas;
  int _totalParas = 0;
  Timer? _growTimer;

  void _scheduleGrow() {
    if (_growTimer != null || _shownParas >= _totalParas) return;
    _growTimer = Timer(const Duration(milliseconds: 80), () {
      _growTimer = null;
      if (!mounted || _shownParas >= _totalParas) return;
      setState(() => _shownParas += _kGrowParas);
    });
  }

  /// اسکرول به پاراگراف؛ اگر هنوز ساخته نشده، اول تا آنجا نشان داده می‌شود.
  void _scrollToPara(int pi, double alignment) {
    void go() {
      final ctx = _pk[pi]?.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(ctx,
            alignment: alignment,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut);
      }
    }

    if (pi >= _shownParas && mounted) {
      setState(() => _shownParas = pi + 4);
      WidgetsBinding.instance.addPostFrameCallback((_) => go());
    } else {
      go();
    }
  }

  static String _k(String lang, String src) => '$lang\u0001$src';

  // ───────────── بولدِ معادلِ لغت‌های انتخابی داخلِ ترجمه‌ها (توسط خودِ اپ، نه AI) ─────────────
  // لغت‌های بولدِ متنِ داستان (highlightWords) را داخلِ ترجمه‌ی هر زبان هم پیدا و بولد می‌کند.
  // معادل‌ها به ترتیبِ سرعت: ۱) دیکشنریِ اپ و لغاتِ ذخیره‌شده (آفلاین، فوری)
  // ۲) ترجمه‌ی تک‌لغت (کش‌دار) ۳) ترجمه‌ی لغت «داخلِ همان جمله» — دو مرحله‌ی آخر فقط وقتی لازم است
  // که معادلِ مرحله‌های قبل داخلِ ترجمه پیدا نشده باشد و پس‌زمینه و پشتِ‌هم اجرا می‌شوند.
  final Map<String, List<String>> _eqWord = {}; // 'from>to|word' ← معادل‌ها
  final Map<String, List<String>> _eqCtx = {}; // 'to␁src␁word' ← معادلِ داخلِ جمله
  final Set<String> _eqTried = {};
  final Set<String> _eqQueued = {};
  final List<Future<void> Function()> _eqQueue = [];
  bool _eqPumping = false;
  int _eqVer = 0;
  int _eqMemoVer = -1;
  final Map<String, List<SelectableRun>?> _eqMemo = {};

  static const TextStyle _eqBold = TextStyle(fontWeight: FontWeight.w900);

  // ⚡ نتیجه‌های بولدِ معادل پشت‌سرهم می‌آیند؛ به‌جای یک setState برای هر کدام (که کلِ پنل را
  // دوباره می‌ساخت و اسکرول را هنگ می‌کرد)، همه با هم و حداکثر هر ~۲ ثانیه یک‌بار اعمال می‌شوند.
  Timer? _eqFlushTimer;
  void _eqMarkDirty() {
    _eqVer++;
    if (_eqFlushTimer != null) return;
    _eqFlushTimer = Timer(const Duration(milliseconds: 2000), () {
      _eqFlushTimer = null;
      if (mounted) setState(() {});
    });
  }

  List<String> _eqCandidates(String w, String lang, String src) {
    final lw = w.toLowerCase().trim();
    final out = <String>[];
    final k = KnownTranslations.get(w, widget.langCode, lang);
    if (k != null && k.trim().isNotEmpty) out.add(k);
    try {
      for (final sw in ref.read(savedWordsProvider)) {
        if (sw.langCode != widget.langCode) continue;
        if (sw.word.toLowerCase().trim() != lw) continue;
        final tr = sw.translations[lang];
        if (tr != null && tr.trim().isNotEmpty) out.add(tr);
      }
    } catch (_) {}
    out.addAll(_eqWord['${widget.langCode}>$lang|$lw'] ?? const <String>[]);
    out.addAll(_eqCtx['$lang\u0001$src\u0001$lw'] ?? const <String>[]);
    return out;
  }

  /// تکه‌های ترجمه با معادلِ لغت‌های انتخابی بولد؛ null = چیزی برای بولد نیست.
  List<SelectableRun>? _eqRuns(String lang, String src, String t) {
    // ⛔ بولدِ خودکارِ معادلِ لغت‌ها داخلِ ترجمه برداشته شد (بدونِ ترجمه‌ی پس‌زمینه)
    return null;
    // ignore: dead_code
    if (widget.highlightWords.isEmpty || t.isEmpty) return null;
    if (_eqMemoVer != _eqVer) {
      _eqMemo.clear();
      _eqMemoVer = _eqVer;
    }
    final mk =
        '$lang\u0001$src\u0001${t.hashCode}\u0001${Object.hashAll(widget.highlightWords)}';
    if (_eqMemo.containsKey(mk)) return _eqMemo[mk];
    final byWord = <String, List<String>>{};
    for (final w in widget.highlightWords) {
      if (sourceForms(src, w, widget.langCode).isEmpty) continue; // این لغت در این جمله نیست
      byWord[w] = _eqCandidates(w, lang, src);
    }
    if (byWord.isEmpty) {
      _eqMemo[mk] = null;
      return null;
    }
    final res = equivalentRuns(
        text: t, lang: lang, equivByWord: byWord, boldStyle: _eqBold);
    final missing = [
      for (final w in byWord.keys)
        if (!res.matched.contains(w)) w,
    ];
    if (missing.isNotEmpty) _eqSchedule(lang, src, missing);
    _eqMemo[mk] = res.runs;
    return res.runs;
  }

  void _eqSchedule(String lang, String src, List<String> missing) {
    final job = '$lang\u0001$src\u0001${missing.join('\u0002')}';
    if (!_eqQueued.add(job)) return;
    _eqQueue.add(() => _eqRun(lang, src, missing));
    if (_eqPumping) return;
    _eqPumping = true;
    Future<void>(() async {
      try {
        // ⏳ بولدِ معادلِ لغت‌ها کارِ پس‌زمینه است: بعد از باز شدنِ داستان شروع شود تا UI قفل نشود
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        while (mounted && _eqQueue.isNotEmpty) {
          final f = _eqQueue.removeAt(0);
          try {
            await f();
          } catch (_) {}
          // به UI فرصتِ نفس‌کشیدن بده
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
      } finally {
        _eqPumping = false;
      }
    });
  }

  bool _eqMatchedNow(String lang, String src, String w) {
    final t = _tr[_k(lang, src)];
    if (t == null || t.isEmpty) return true; // ترجمه‌ای نیست/عوض شده؛ کاری نمی‌ماند
    final r = equivalentRuns(
      text: t,
      lang: lang,
      equivByWord: {w: _eqCandidates(w, lang, src)},
      boldStyle: _eqBold,
    );
    return r.matched.contains(w);
  }

  /// جمله‌ای از [src] که [form] در آن است (برای ترجمه‌ی لغت داخلِ جمله؛ نه کلِ پاراگراف).
  String? _eqSentenceWith(String src, String form) {
    final lf = form.toLowerCase();
    List<String> ss;
    try {
      ss = widget.splitSentences(src);
    } catch (_) {
      ss = const [];
    }
    if (ss.isEmpty) ss = [src];
    for (final x in ss) {
      if (x.toLowerCase().contains(lf)) return x;
    }
    return src.length <= 300 ? src : null;
  }

  Future<void> _eqRun(String lang, String src, List<String> missing) async {
    final svc = ref.read(translationServiceProvider);
    // بولدِ معادلِ لغت فقط با مترجم‌های رایگان/ML Kit/کش؛ AI صدا زده نمی‌شود
    const ai = null;
    for (final w in missing) {
      if (!mounted) return;
      if (_eqMatchedNow(lang, src, w)) continue;
      final lw = w.toLowerCase().trim();

      // مرحله‌ی ۲: ترجمه‌ی تک‌لغت (در کشِ ترجمه می‌ماند و برای همه‌ی جمله‌ها مشترک است)
      final wk = '${widget.langCode}>$lang|$lw';
      if (_eqTried.add('w|$wk')) {
        var r = '';
        try {
          r = (await svc.translate(
            text: w,
            targetLang: lang,
            sourceLang: widget.langCode,
            aiSettings: ai,
          ))
              .trim();
        } catch (_) {}
        if (!mounted) return;
        if (r.isNotEmpty && r.toLowerCase() != lw) {
          _eqWord[wk] = [r];
          _eqMarkDirty();
        }
        if (_eqMatchedNow(lang, src, w)) continue;
      }

      // مرحله‌ی ۳: معادلِ لغت «داخلِ همین جمله» (ترجمه با نشانگرِ ⟦ ⟧ و برداشتنِ همان تکه)
      final ck = '$lang\u0001$src\u0001$lw';
      if (_eqTried.add('c|$ck')) {
        final forms = sourceForms(src, w, widget.langCode);
        if (forms.isEmpty) continue;
        final sent = _eqSentenceWith(src, forms.first);
        if (sent == null) continue;
        String? r;
        try {
          r = await svc.translateWordInContext(
            sentenceText: sent,
            word: forms.first,
            sourceLang: widget.langCode,
            targetLang: lang,
            aiSettings: ai,
          );
        } catch (_) {}
        if (!mounted) return;
        if (r != null && r.trim().isNotEmpty) {
          _eqCtx[ck] = [r!];
          _eqMarkDirty();
        }
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _pc = ProviderScope.containerOf(context, listen: false);
    WidgetsBinding.instance.addPostFrameCallback((_) => _registerAudio());
    try {
      final v = ref.read(sharedPrefsProvider).getInt(_kModeKey);
      if (v != null && v >= 0 && v <= 2) _mode = v;
    } catch (_) {}
    _notesCtrl.text = widget.notes;
    _seed();
    _sig = _signature();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensure());
    _dvEnsure();
  }

  // ───────────── 🎭 دو صدا برای داستانِ مکالمه‌ای ─────────────
  DialogueVoices? _dv;

  void _dvEnsure() {
    if (!widget.dialogue || _dv != null) return;
    _dv = DialogueVoices(
      ref: ref,
      mainLang: () => widget.langCode,
      isMounted: () => mounted,
    )..start();
  }

  String _spkSig = '';
  List<bool> _spkMaleBySent = const []; // اندیسِ جمله ← true = مرد (گوینده‌ی اول)
  List<int> _spkParaFirstGi = const []; // اندیسِ پاراگراف ← اندیسِ اولین جمله‌اش

  static final RegExp _spkLabel = RegExp(
      r"^\s*(?:\*\*)?(\p{L}[\p{L}\p{N}'’\-]*(?:\s\p{L}[\p{L}\p{N}'’\-]*){0,2})(?:\*\*)?\s*[:：]\s*\S",
      unicode: true);
  static final RegExp _spkOpenQuote = RegExp('^\\s*[“"«„]');

  /// گوینده‌ی هر «جمله»:
  ///  • اگر متن «نام: جمله» برچسب دارد (۲ تا ۳ نامِ متفاوت) بر اساسِ نام؛
  ///  • وگرنه نوبتِ گفتگو با هر پاراگراف، هر خطِ جدید (حتی بدونِ خطِ خالی)، یا هر جمله‌ای که با
  ///    گیومه‌ی بازشو شروع شود عوض می‌شود و گوینده‌ها به‌نوبت می‌آیند (۱ مرد، ۲ زن، ۳ مرد، …).
  void _spkEnsure() {
    final sig = '${widget.text.hashCode}';
    if (sig == _spkSig) return;
    final paras = _structure();

    // نوبت‌های هر جمله (شماره‌ی نوبت از ۰) + برچسب‌ها
    final turnOf = <int>[];
    final labelOfSent = <String?>[];
    final names = <String>[];
    var labeledLines = 0;
    var totalLines = 0;
    var turn = -1;
    for (final p in paras) {
      turn++; // هر پاراگراف = نوبتِ تازه
      var cursor = 0;
      var first = true;
      for (final sent in p.sents) {
        final at = p.text.indexOf(sent.trim(), cursor);
        var newTurn = false;
        if (!first) {
          if (at > cursor && p.text.substring(cursor, at).contains('\n')) {
            newTurn = true;
          } else if (_spkOpenQuote.hasMatch(sent)) {
            newTurn = true;
          }
        }
        if (newTurn) turn++;
        String? label;
        if (first || newTurn) {
          totalLines++;
          final m = _spkLabel.firstMatch(sent);
          label = m?.group(1)?.toLowerCase();
          if (label != null) {
            labeledLines++;
            if (!names.contains(label)) names.add(label);
          }
        }
        turnOf.add(turn);
        labelOfSent.add(label);
        if (at >= 0) cursor = at + sent.trim().length;
        first = false;
      }
    }

    final useLabels = totalLines >= 2 &&
        labeledLines >= 2 &&
        labeledLines * 10 >= totalLines * 6 &&
        names.length >= 2 &&
        names.length <= 3;

    final male = <bool>[];
    var prevTurn = -1;
    var cur = true;
    for (var i = 0; i < turnOf.length; i++) {
      if (useLabels) {
        final n = labelOfSent[i];
        if (n != null) cur = names.indexOf(n).isEven;
      } else if (turnOf[i] != prevTurn) {
        cur = turnOf[i].isEven;
      }
      prevTurn = turnOf[i];
      male.add(cur);
    }
    _spkSig = sig;
    _spkMaleBySent = male;
    _spkParaFirstGi = [for (final p in paras) p.firstGi];
  }

  /// شناسه‌ی آیتم ('<id>-s<gi>' یا '<id>-p<pi>') ← صدای مرد/زن برای همان زبان
  String? _dialogueVoice(String itemId, String lang) {
    if (!widget.dialogue) return null;
    _dvEnsure();
    final dv = _dv;
    if (dv == null) return null;
    final m = RegExp(r'-([sp])(\d+)$').firstMatch(itemId);
    if (m == null) return null;
    _spkEnsure();
    final n = int.tryParse(m.group(2)!) ?? -1;
    final gi = m.group(1) == 'p'
        ? (n >= 0 && n < _spkParaFirstGi.length ? _spkParaFirstGi[n] : -1)
        : n;
    if (gi < 0 || gi >= _spkMaleBySent.length) return null;
    return dv.voiceFor(male: _spkMaleBySent[gi], lang: lang);
  }

  // ثبتِ صوتِ آپلودیِ این داستان در پلیرِ اصلیِ پایین (معادلِ onUserAudioStateChange در Hope)
  late final ProviderContainer _pc;

  void _registerAudio() {
    if (!mounted) return;
    final a = widget.audio;
    if (a == null) return;
    if (!identical(_pc.read(storyUserAudioProvider), a)) {
      _pc.read(storyPlaybackModeProvider.notifier).state = 'tts';
      _pc.read(storyUserAudioProvider.notifier).state = a;
    }
  }

  @override
  void didUpdateWidget(covariant StoryReaderPanel old) {
    super.didUpdateWidget(old);
    if (!identical(old.audio, widget.audio)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _registerAudio());
    }
    final s = _signature();
    if (s != _sig) {
      _sig = s;
      _seed();
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensure());
    }
    if (old.notes != widget.notes && widget.notes != _notesCtrl.text) {
      _notesCtrl.text = widget.notes;
    }
  }

  @override
  void dispose() {
    _eqFlushTimer?.cancel();
    _dv?.dispose();
    _dv = null;
    final a = widget.audio;
    final pc = _pc;
    Future.microtask(() {
      try {
        if (a != null && identical(pc.read(storyUserAudioProvider), a)) {
          pc.read(storyUserAudioProvider.notifier).state = null;
          pc.read(storyPlaybackModeProvider.notifier).state = 'tts';
        }
      } catch (_) {}
    });
    _notesTimer?.cancel();
    _flashTimer?.cancel();
    _searchCtrl.dispose();
    _editCtrl.dispose();
    _growTimer?.cancel();
    _notesCtrl.dispose();
    super.dispose();
  }

  String _signature() {
    var n = 0;
    for (final e in widget.paraTranslations.entries) {
      for (final v in e.value) {
        n += v.length + 1;
      }
    }
    return '${widget.text.hashCode}|${widget.langCode}|'
        '${widget.targetLangs.join(',')}|$n';
  }

  // ───────────── ساختارِ متن ─────────────
  List<_P> _structure() {
    final out = <_P>[];
    var gi = 0;
    for (final raw in widget.text.split(RegExp(r'\n\s*\n'))) {
      final p = raw.trim();
      if (p.isEmpty) continue;
      var ss = widget.splitSentences(p);
      if (ss.isEmpty) ss = [p];
      out.add(_P(p, ss, gi));
      gi += ss.length;
    }
    return out;
  }

  List<String> get _langs =>
      widget.targetLangs.where((l) => l != widget.langCode).toList();

  // ───────────── ترجمه ─────────────
  /// ترجمه‌های آماده‌ی پاراگراف را (و اگر تعدادِ جمله‌ها برابر بود، جمله‌به‌جمله) در کش می‌گذارد
  void _seed() {
    final paras = _structure();
    for (final lang in _langs) {
      final list = widget.paraTranslations[lang];
      if (list == null) continue;
      for (var i = 0; i < paras.length && i < list.length; i++) {
        final t = list[i].trim();
        if (t.isEmpty) continue;
        // ترجمه‌ی قدیمیِ ناموفق (همان متن مبدأ) ترجمه حساب نمی‌شود → دوباره ترجمه می‌شود
        if (t.toLowerCase() == paras[i].text.trim().toLowerCase()) continue;
        _tr.putIfAbsent(_k(lang, paras[i].text), () => t);
        final ts = widget.splitSentences(t);
        if (paras[i].sents.length > 1 && ts.length == paras[i].sents.length) {
          for (var k = 0; k < ts.length; k++) {
            _tr.putIfAbsent(_k(lang, paras[i].sents[k]), () => ts[k]);
          }
        }
      }
    }
  }

  void _ensure() {
    if (!mounted || _mode == 0) return;
    final langs = _langs;
    if (langs.isEmpty) return;
    final units = <String>[
      for (final p in _structure()) ...(_mode == 1 ? [p.text] : p.sents),
    ];
    final jobs = <_Job>[];
    final svc = ref.read(translationServiceProvider);
    var fromCache = false;
    for (final lang in langs) {
      for (final src in units) {
        final key = _k(lang, src);
        if (_tr.containsKey(key) ||
            _inflight.contains(key) ||
            _failed.contains(key)) {
          continue;
        }
        // ترجمه‌ی درستِ ذخیره‌شده روی گوشی (مثلاً از ↻ در حالتِ جمله‌به‌جمله) → فوری، بدونِ فلیکر
        final hit = svc.peekCached(src, widget.langCode, lang)?.trim() ?? '';
        if (hit.isNotEmpty && hit != src.trim()) {
          _tr[key] = hit;
          fromCache = true;
          continue;
        }
        _inflight.add(key);
        jobs.add(_Job(lang, src, key));
      }
    }
    if (fromCache) setState(() {});
    if (jobs.isNotEmpty) unawaited(_run(jobs));
  }

  /// کشِ مشترکِ همه‌ی کاربرها (ترجمه‌های اصلاح‌شده): یک درخواستِ گروهی برای هر زبان.
  /// مواردِ پیداشده همین‌جا پُر و روی گوشی ذخیره می‌شوند؛ بقیه برای ترجمه‌ی عادی برمی‌گردند.
  Future<List<_Job>> _applyShared(
      TranslationService svc, String baseUrl, List<_Job> jobs) async {
    final byLang = <String, List<_Job>>{};
    for (final j in jobs) {
      byLang.putIfAbsent(j.lang, () => []).add(j);
    }
    final left = <_Job>[];
    for (final e in byLang.entries) {
      final found = await SharedTranslations.fetchMany(
          baseUrl, widget.langCode, e.key, [for (final j in e.value) j.src]);
      if (!mounted) return const [];
      final hits = <_Job, String>{};
      for (final j in e.value) {
        final r = found[j.src];
        if (r != null && r.isNotEmpty) {
          hits[j] = r;
        } else {
          left.add(j);
        }
      }
      if (hits.isEmpty) continue;
      for (final h in hits.entries) {
        unawaited(svc.cachePut(h.key.src, widget.langCode, e.key, h.value));
      }
      setState(() {
        for (final h in hits.entries) {
          _inflight.remove(h.key.key);
          _failed.remove(h.key.key);
          _tr[h.key.key] = h.value;
          _linkUnits(e.key, h.key.src, h.value, overwrite: false);
        }
      });
    }
    return left;
  }

  Future<void> _run(List<_Job> allJobs) async {
    final svc = ref.read(translationServiceProvider);
    final ai = ref.read(aiSettingsProvider);
    var jobs = allJobs;
    try {
      jobs = await _applyShared(svc, ai.baseUrl, allJobs);
    } catch (_) {
      jobs = allJobs;
    }
    if (!mounted) return;

    // نتیجه‌ها دسته‌ای و حداکثر هر ۲۵۰ms یک‌بار اعمال می‌شوند (به‌جای یک setState برای هر جمله)
    final buf = <MapEntry<_Job, String>>[];
    Timer? flushT;
    void flush() {
      flushT?.cancel();
      flushT = null;
      if (buf.isEmpty) return;
      final items = List<MapEntry<_Job, String>>.of(buf);
      buf.clear();
      if (!mounted) return;
      setState(() {
        for (final e in items) {
          final j = e.key;
          final r = e.value;
          _inflight.remove(j.key);
          if (r.isEmpty || r == j.src.trim()) {
            _failed.add(j.key);
          } else {
            _tr[j.key] = r;
            _linkUnits(j.lang, j.src, r, overwrite: false);
          }
        }
      });
    }

    var next = 0;
    Future<void> worker() async {
      while (mounted) {
        final i = next++;
        if (i >= jobs.length) return;
        final j = jobs[i];
        var r = '';
        try {
          // 🚫 باز کردنِ داستان هیچ‌وقت AI صدا نمی‌زند (کش ← ML Kit ← مترجم‌های رایگان).
          // بازبینی/ترجمه‌ی AI فقط با دکمه‌ی ↻ (خودِ کاربر) انجام می‌شود.
          r = (await svc.translate(
            text: j.src,
            targetLang: j.lang,
            sourceLang: widget.langCode,
          ))
              .trim();
        } catch (_) {}
        if (!mounted) return;
        buf.add(MapEntry(j, r));
        flushT ??= Timer(const Duration(milliseconds: 250), flush);
      }
    }

    try {
      await Future.wait([worker(), worker(), worker()]);
    } finally {
      flush();
      flushT?.cancel();
    }
  }

  static const Set<String> _noSpaceLangs = {'zh', 'ja'};

  /// اتصالِ ترجمه‌ی جمله‌ها و پاراگراف‌ها به هم (باید داخلِ setState صدا زده شود):
  ///  • اگر [src] یک جمله است و همه‌ی جمله‌های آن پاراگراف ترجمه دارند → ترجمه‌ی پاراگراف
  ///    از کنارِ هم گذاشتنِ ترجمه‌ی جمله‌ها ساخته می‌شود (و روی گوشی کش می‌شود)
  ///  • اگر [src] یک پاراگراف است و تعدادِ جمله‌های ترجمه با مبدأ برابر است → ترجمه‌ی
  ///    هر جمله از روی آن پر می‌شود (و کش می‌شود)
  /// [overwrite] = true (↻ کاربر): جایگزینِ ترجمه‌ی قبلیِ حالتِ دیگر؛ false: فقط جای خالی را پر می‌کند.
  /// خروجی: پاراگراف‌هایی که (فقط در حالتِ overwrite) تغییر کرده‌اند تا در داستان ذخیره شوند.
  List<_ParaUpdate> _linkUnits(String lang, String src, String tr,
      {required bool overwrite}) {
    final updates = <_ParaUpdate>[];
    final svc = ref.read(translationServiceProvider);
    final paras = _structure();
    for (var pi = 0; pi < paras.length; pi++) {
      final p = paras[pi];
      if (p.sents.length < 2) continue;

      if (p.sents.contains(src)) {
        // جمله → پاراگراف
        final parts = <String>[];
        var complete = true;
        for (final s in p.sents) {
          final t = _tr[_k(lang, s)]?.trim() ?? '';
          if (t.isEmpty) {
            complete = false;
            break;
          }
          parts.add(t);
        }
        if (!complete) continue;
        final pk = _k(lang, p.text);
        if (!overwrite && _tr.containsKey(pk)) continue;
        final joined = parts.join(_noSpaceLangs.contains(lang) ? '' : ' ');
        _tr[pk] = joined;
        _failed.remove(pk);
        unawaited(svc.cachePut(p.text, widget.langCode, lang, joined));
        if (overwrite) updates.add(_ParaUpdate(lang, pi, joined));
      } else if (p.text == src) {
        // پاراگراف → جمله‌ها (فقط اگر تعدادِ جمله‌ها برابر باشد)
        final ts = widget.splitSentences(tr);
        if (ts.length != p.sents.length) continue;
        for (var k = 0; k < ts.length; k++) {
          final sk = _k(lang, p.sents[k]);
          final t = ts[k].trim();
          if (t.isEmpty) continue;
          if (!overwrite && _tr.containsKey(sk)) continue;
          _tr[sk] = t;
          _failed.remove(sk);
          unawaited(svc.cachePut(p.sents[k], widget.langCode, lang, t));
        }
      }
    }
    return updates;
  }

  Future<void> _retry(String lang, String src, {int? paraIdx}) async {
    final key = _k(lang, src);
    if (_retrying.contains(key)) return;
    setState(() => _retrying.add(key));
    try {
      final r = (await ref.read(translationServiceProvider).retranslate(
                text: src,
                targetLang: lang,
                sourceLang: widget.langCode,
                aiSettings: ref.read(aiSettingsProvider),
              ))
          .trim();
      if (!mounted) return;
      if (r.isNotEmpty && r != src.trim()) {
        var linked = const <_ParaUpdate>[];
        setState(() {
          _tr[key] = r;
          _failed.remove(key);
          // ↻ در یک حالت = اصلاحِ دستیِ کاربر → در حالتِ دیگر هم همین ترجمه جایگزین می‌شود
          linked = _linkUnits(lang, src, r, overwrite: true);
        });
        if (paraIdx != null) {
          widget.onParagraphRetranslated?.call(lang, paraIdx, r);
        }
        // پاراگرافِ ساخته‌شده از جمله‌ها هم در داستان ذخیره می‌شود
        for (final u in linked) {
          if (u.pi == paraIdx && u.lang == lang) continue;
          widget.onParagraphRetranslated?.call(u.lang, u.pi, u.text);
        }
        // 🔒 ↻ فقط روی گوشیِ خودِ کاربر قفل می‌شود (خودِ retranslate این کار را می‌کند)؛
        // به سرور فقط اگر AI تأیید کرده باشد و آن هم فقط به‌عنوان پیشنهاد (داخلِ سرویس).
      } else if (!_tr.containsKey(key)) {
        setState(() => _failed.add(key));
      }
    } catch (_) {
      if (mounted && !_tr.containsKey(key)) setState(() => _failed.add(key));
    } finally {
      if (mounted) setState(() => _retrying.remove(key));
    }
  }

  void _setMode(int m) {
    if (m == _mode) return;
    setState(() => _mode = m);
    try {
      ref.read(sharedPrefsProvider).setInt(_kModeKey, m);
    } catch (_) {}
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensure());
  }

  // ───────────── ویرایش / یادداشت / جستجو ─────────────
  void _toggleEdit() {
    setState(() {
      if (_editing) {
        _editing = false;
      } else {
        _editCtrl.text = widget.fullText ?? widget.text;
        _editing = true;
      }
    });
  }

  void _applyEdit() {
    final t = _editCtrl.text.trim();
    if (t.isEmpty) return;
    setState(() => _editing = false);
    widget.onTextEdited?.call(t);
  }

  void _onNotes(String v) {
    _notesTimer?.cancel();
    _notesTimer = Timer(const Duration(milliseconds: 600), () {
      widget.onNotesChanged?.call(v);
    });
  }

  List<_Hit> _hits(List<_P> paras) {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final out = <_Hit>[];
    for (var pi = 0; pi < paras.length; pi++) {
      final p = paras[pi];
      for (var si = 0; si < p.sents.length; si++) {
        final s = p.sents[si];
        var hit = s.toLowerCase().contains(q);
        if (!hit) {
          for (final lang in _langs) {
            final t = _tr[_k(lang, s)];
            if (t != null && t.toLowerCase().contains(q)) {
              hit = true;
              break;
            }
          }
        }
        if (hit) out.add(_Hit(pi, p.firstGi + si, s));
        if (out.length >= 30) return out;
      }
    }
    return out;
  }

  void _jumpTo(_Hit h) {
    FocusScope.of(context).unfocus();
    setState(() => _flashGi = h.gi);
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _flashGi = -1);
    });
    _scrollToPara(h.pi, 0.2);
  }

  /// آیتم‌های پلیر: جمله‌به‌جمله (حالتِ ۲) یا پاراگراف‌به‌پاراگراف (حالتِ ۰ و ۱)
  /// — همان شناسه‌هایی که ردیف‌ها برای هایلایت/اسکرول استفاده می‌کنند.
  List<SyncItem> _syncItems() {
    final out = <SyncItem>[];
    final paras = _structure();
    for (var pi = 0; pi < paras.length; pi++) {
      final p = paras[pi];
      if (_mode == 2) {
        for (var si = 0; si < p.sents.length; si++) {
          out.add(SyncItem('${widget.storyId}-s${p.firstGi + si}', p.sents[si]));
        }
      } else {
        out.add(SyncItem('${widget.storyId}-p$pi', p.text));
      }
    }
    return out;
  }

  void _revealAudioLine() {
    final a = widget.audio;
    if (!mounted || a == null || !a.hasAudio) return;
    final paras = _structure();
    for (var i = 0; i < paras.length; i++) {
      if (a.activeIndex < paras[i].firstGi + paras[i].sents.length) {
        _scrollToPara(i, 0.25);
        return;
      }
    }
  }

  // ───────────── ساخت ─────────────
  @override
  Widget build(BuildContext context) {
    final audio = widget.audio;
    // ref.watch فقط همین‌جا (داخلِ build) — نه داخلِ builderِ فرزند
    final tp = ref.watch(textPrefsProvider);
    // 🎭 هدرِ زبان عوض شد → صدای مرد/زنِ زبان‌های تازه دوباره پیدا شود
    if (widget.dialogue) {
      ref.listen(languageSelectionProvider,
          (_, __) => unawaited(_dv?.load() ?? Future<void>.value()));
    }
    // لمسِ طولانیِ دکمه‌ی پخش (صدای اپلودی): به پاراگرافِ در حال خواندن برو
    ref.listen<int>(revealActiveTickProvider, (prev, next) {
      if (prev != next) _revealAudioLine();
    });
    if (audio == null) return _card(context, tp, null);
    // با هر تغییرِ خطِ فعالِ صدا، هایلایت و اسکرول به‌روز می‌شود
    return ListenableBuilder(
      listenable: audio,
      builder: (ctx, _) => _card(ctx, tp, audio.hasAudio ? audio : null),
    );
  }

  Widget _card(
      BuildContext context, TargetTextPrefs tp, StoryAudioController? audio) {
    final c = context.appColors;
    final paras = _structure();
    final hits = _hits(paras);
    final q = _searchCtrl.text.trim();

    // اسکرولِ خودکار به پاراگرافِ جمله‌ی فعالِ صدا
    if (audio != null && _lastActive != audio.activeIndex) {
      final was = _lastActive;
      _lastActive = audio.activeIndex;
      if (was != null) {
        var pi = -1;
        for (var i = 0; i < paras.length; i++) {
          if (audio.activeIndex < paras[i].firstGi + paras[i].sents.length) {
            pi = i;
            break;
          }
        }
        if (pi >= 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _scrollToPara(pi, 0.25);
          });
        }
      }
    }

    final hasEdit = widget.onTextEdited != null;
    final hasSave = widget.onSave != null || widget.saved;

    final sig = '${widget.storyId}|${widget.text.hashCode}|$_mode|'
        '${widget.langCode}|$_editing';
    if (sig != _scopeSig) {
      _scopeSig = sig;
      _scopeRev = Object();
    }

    return SyncPlayScope(
      revision: _scopeRev,
      originExtra: {
        'storyId': widget.storyId,
        'paras': widget.text.split('\n\n').length,
      },
      mode: TrackMode.lines,
      mainCode: widget.langCode,
      voiceForItem: widget.dialogue
          ? (id) => _dialogueVoice(id, widget.langCode)
          : null,
      voiceForTrans: widget.dialogue ? _dialogueVoice : null,
      itemsBuilder: () => _editing ? const <SyncItem>[] : _syncItems(),
      child: Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: c.cardBorder),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── سرتیتر: عنوان | ✏️ | 🔖 ──
            // (این پنل همیشه RTL است؛ پس اولین فرزند = راست‌ترین)
            Row(
              children: [
                if (hasEdit)
                  _HeadIcon(
                    icon: _editing ? Icons.close : Icons.edit_outlined,
                    color: _editing ? c.rose : c.teal,
                    tooltip: _editing
                        ? context.l10n.reader_cancel_editing
                        : context.l10n.reader_edit_text,
                    onTap: _toggleEdit,
                  ),
                if (hasSave)
                  _HeadIcon(
                    icon: widget.saved ? Icons.bookmark_added : Icons.bookmark_border,
                    color: widget.saved ? c.teal : c.gold,
                    tooltip:
                        widget.saved
                            ? context.l10n.grammar_saved
                            : context.l10n.reader_save_story,
                    onTap: widget.saved ? null : widget.onSave,
                  ),
                if (hasEdit || hasSave) const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textDirection: autoDir(widget.title),
                    style: TextStyle(
                        color: c.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (!_editing) ...[
              // ── جستجو ──
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: c.cardBorder),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: (_) => setState(() {}),
                        style: TextStyle(color: c.ink, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: context.l10n.reader_search_placeholder,
                          hintStyle: TextStyle(
                              color: c.inkSoft.withOpacity(0.6), fontSize: 13),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                    if (q.isNotEmpty)
                      GestureDetector(
                        onTap: () => setState(_searchCtrl.clear),
                        child: Icon(Icons.close, size: 16, color: c.inkSoft),
                      )
                    else
                      Icon(Icons.search, size: 18, color: c.inkSoft),
                  ],
                ),
              ),
              if (q.isNotEmpty) ...[
                const SizedBox(height: 6),
                if (hits.isEmpty)
                  Text(context.l10n.reader_nothing_found,
                      style: TextStyle(color: c.inkSoft, fontSize: 12))
                else ...[
                  Text(context.l10n.reader_n_results('${hits.length}'),
                      style: TextStyle(color: c.inkSoft, fontSize: 11)),
                  for (final h in hits)
                    GestureDetector(
                      onTap: () => _jumpTo(h),
                      child: Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: c.paper,
                          border: Border.all(color: c.cardBorder),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          h.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: autoDir(h.text),
                          style: TextStyle(color: c.ink, fontSize: 12),
                        ),
                      ),
                    ),
                ],
              ],
              const SizedBox(height: 12),

              // ── نمایشِ ترجمه ──
              // زبانِ رابطِ چپ‌به‌راست (انگلیسی/آلمانی/…) ← عنوان و دکمه‌ها چپ‌چین؛ فارسی/عربی ← راست‌چین.
              // سه دکمه همیشه در «یک» ردیف (اگر جا نشد کوچک می‌شوند).
              Builder(builder: (ctx) {
                final dir = uiContentDirection(ctx);
                final left = dir == TextDirection.ltr;
                return Directionality(
                  textDirection: dir,
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ctx.l10n.reader_translation_display,
                        textDirection: dir,
                        style: TextStyle(color: c.inkSoft, fontSize: 13)),
                    const SizedBox(height: 6),
                    Directionality(
                      textDirection: dir,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment:
                            left ? Alignment.centerLeft : Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final m in [
                              [2, stTr(ctx, 'modeSentence')],
                              [1, stTr(ctx, 'modeParagraph')],
                              [0, stTr(ctx, 'modeNone')],
                            ]) ...[
                              HopeChoiceChip(
                                label: m[1] as String,
                                active: _mode == m[0],
                                activeBorder: c.teal,
                                activeFill: c.teal,
                                activeText: Colors.white,
                                onTap: () => _setMode(m[0] as int),
                              ),
                              if (m[0] != 0) const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                  ),
                );
              }),
              if (widget.enablePractice) ...[
                const SizedBox(height: 12),
                StoryVoicePractice(
                  key: ValueKey('practice-${widget.storyId}'),
                  storyId: widget.storyId,
                  title: widget.title,
                  text: widget.text,
                  langCode: widget.langCode,
                  level: widget.level,
                  dialogue: widget.dialogue,
                  splitSentences: widget.splitSentences,
                  onLevelUp: widget.onLevelUp,
                ),
              ],
              if (widget.audioBar != null) ...[
                const SizedBox(height: 12),
                widget.audioBar!,
              ],
              const SizedBox(height: 12),
              ..._body(c, tp, paras, audio),
            ] else
              _editBox(c),

            if (widget.onNotesChanged != null && !_editing) ..._notes(c),
          ],
        ),
      ),
    ),
    );
  }

  Widget _editBox(AppThemeColorsExt c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.l10n.reader_edit_hint,
          style: TextStyle(color: c.inkSoft, fontSize: 12),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _editCtrl,
          minLines: 8,
          maxLines: 16,
          textDirection: autoDir(_editCtrl.text),
          style: TextStyle(color: c.ink, fontSize: 13, height: 1.7),
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: c.cardBorder),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: _applyEdit,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.gold,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(context.l10n.reader_apply_edit,
                      style: TextStyle(
                          color: c.headerTo,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _toggleEdit,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                decoration: BoxDecoration(
                  border: Border.all(color: c.cardBorder),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(context.l10n.cancel_button,
                    style: TextStyle(color: c.ink, fontSize: 13)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _notes(AppThemeColorsExt c) => [
        const SizedBox(height: 14),
        Divider(color: c.cardBorder, height: 1),
        const SizedBox(height: 12),
        Text(context.l10n.reader_notes_title,
            style: TextStyle(
                color: c.ink, fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        TextField(
          controller: _notesCtrl,
          onChanged: _onNotes,
          minLines: 4,
          maxLines: 12,
          textDirection: autoDir(_notesCtrl.text),
          style: TextStyle(color: c.ink, fontSize: 13, height: 1.7),
          decoration: InputDecoration(
            hintText: context.l10n.reader_notes_placeholder,
            hintStyle:
                TextStyle(color: c.inkSoft.withOpacity(0.6), fontSize: 13),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: c.cardBorder),
            ),
          ),
        ),
      ];

  // ───────────── بدنه ─────────────
  List<Widget> _body(
      AppThemeColorsExt c, TargetTextPrefs tp, List<_P> paras, StoryAudioController? audio) {
    final boldText =
        tp.bold == TargetBoldMode.both || tp.bold == TargetBoldMode.text;
    final out = <Widget>[];
    _totalParas = paras.length;
    final limit = paras.length < _shownParas ? paras.length : _shownParas;
    for (var pi = 0; pi < limit; pi++) {
      final p = paras[pi];
      final key = _pk.putIfAbsent(pi, () => GlobalKey());
      final rows = <Widget>[];

      if (_mode == 2) {
        for (var si = 0; si < p.sents.length; si++) {
          final gi = p.firstGi + si;
          rows.add(_unit(
            c, tp,
            src: p.sents[si],
            id: '${widget.storyId}-s$gi',
            active: (audio != null && audio.activeIndex == gi) ||
                _flashGi == gi,
            seekTo: gi,
            audio: audio,
            boldText: boldText,
            showTr: true,
            paraIdx: null,
          ));
        }
      } else {
        final last = p.firstGi + p.sents.length;
        final act = (audio != null &&
                audio.activeIndex >= p.firstGi &&
                audio.activeIndex < last) ||
            (_flashGi >= p.firstGi && _flashGi < last);
        rows.add(_unit(
          c, tp,
          src: p.text,
          id: '${widget.storyId}-p$pi',
          active: act,
          seekTo: p.firstGi,
          audio: audio,
          boldText: boldText,
          showTr: _mode == 1,
          paraIdx: pi,
        ));
      }

      // ⚡ هر پاراگراف لایه‌ی جدا دارد؛ هایلایت/انیمیشنِ یک خط کلِ داستان را دوباره نمی‌کشد
      out.add(RepaintBoundary(
        child: Padding(
          key: key,
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rows,
          ),
        ),
      ));
    }
    if (limit < paras.length) {
      _scheduleGrow();
      out.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ));
    }
    return out;
  }

  /// فاصله‌های تکراری/ناخواسته‌ی متنِ PDF (چند فاصله‌ی پشت‌سرهم، فاصله‌ی NBSP، فاصله‌ی ته/اول خط)
  /// را یکی می‌کند تا justify فاصله‌ی اضافه بین کلمه‌ها نسازد. فقط برای نمایش.
  static String _tidy(String t) => t
      .replaceAll(RegExp(r'[ \t\u00A0\u2000-\u200A\u202F]+'), ' ')
      .replaceAll(RegExp(r' *\n *'), '\n')
      .trim();

  /// یک جمله (یا پاراگراف) + ترجمه‌هایش
  Widget _unit(
    AppThemeColorsExt c,
    TargetTextPrefs tp, {
    required String src,
    required String id,
    required bool active,
    required int seekTo,
    required StoryAudioController? audio,
    required bool boldText,
    required bool showTr,
    required int? paraIdx,
  }) {
    final dir = autoDir(src);
    final rtl = dir == TextDirection.rtl;
    return SyncAnchor(
      code: widget.langCode,
      id: id,
      child: Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: active ? c.gold.withOpacity(0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            textDirection: TextDirection.ltr,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SizedBox(
                  width: double.infinity,
                  child: SelectableSyncText(
                    code: widget.langCode,
                    id: id,
                    text: _tidy(src),
                    sentence: _tidy(src),
                    // ⛔ بولدِ خودکارِ لغت‌های داستان برداشته شد
                    runs: null,
                    style: TextStyle(
                      color: c.ink,
                      fontSize: 15 * tp.scaleFactor,
                      height: 1.9,
                      fontWeight: boldText ? FontWeight.w700 : FontWeight.w400,
                    ),
                    textDirection: dir,
                    textAlign: TextAlign.justify,
                  ),
                ),
              ),
              if (audio != null)
                InkWell(
                  onTap: () => audio.setActiveLine(seekTo),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.my_location, size: 16, color: c.teal),
                  ),
                ),
              NeuralPathButton(
                onTap: () => showNeuralPath(
                  context,
                  word: src,
                  langCode: widget.langCode,
                ),
              ),
              SyncSpeakButton(
                code: widget.langCode,
                id: id,
                text: src,
                color: c.gold,
                size: 20,
                padding: const EdgeInsets.all(4),
              ),
            ],
          ),
          if (showTr)
            for (final lang in _langs) _trRow(c, tp, lang, src, id, paraIdx),
        ],
      ),
    ),
    );
  }

  Widget _trRow(
      AppThemeColorsExt c, TargetTextPrefs tp, String lang, String src, String id, int? paraIdx) {
    final key = _k(lang, src);
    final t = _tr[key];
    final eqRuns = t == null ? null : _eqRuns(lang, src, t);
    final failed = _failed.contains(key);
    final busy = _retrying.contains(key);
    final dir = dirFor(lang);
    final rtl = dir == TextDirection.rtl;
    final boldTr =
        tp.bold == TargetBoldMode.both || tp.bold == TargetBoldMode.translation;

    Widget tagBox({bool lifted = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: c.paperDark,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: c.cardBorder, width: 0.6),
            boxShadow: lifted
                ? [BoxShadow(color: Colors.black26, blurRadius: 6)]
                : null,
          ),
          child: Text(
            lang.toUpperCase(),
            style: TextStyle(
              color: c.gold,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
        );

    final tag = widget.onReorderLangs == null
        ? Padding(padding: const EdgeInsets.only(top: 3), child: tagBox())
        : LongPressDraggable<String>(
            data: lang,
            feedback: Material(
              color: Colors.transparent,
              child: tagBox(lifted: true),
            ),
            childWhenDragging: Opacity(
              opacity: 0.3,
              child: Padding(
                  padding: const EdgeInsets.only(top: 3), child: tagBox()),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 3, 6, 6),
              child: tagBox(),
            ),
          );

    // Builder: contextِ زیرِ SyncPlayScope لازم است (گزارشِ ترجمه به پلیر)
    return Builder(builder: (bctx) {
      if (t != null) syncReportTranslation(bctx, ref, lang, id, t);
      final row = SyncAnchor(
        code: lang,
        id: id,
        child: Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        textDirection: TextDirection.ltr,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Row(
              textDirection: dir,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                tag,
                const SizedBox(width: 10),
                Expanded(
                  child: t != null
                      ? SizedBox(
                          width: double.infinity,
                          child: SelectableSyncText(
                            code: lang,
                            id: id,
                            text: t,
                            sentence: t,
                            runs: eqRuns,
                            style: TextStyle(
                              color: _kTrColor,
                              fontSize: 15 * tp.scaleFactor,
                              height: 1.7,
                              fontWeight:
                                  boldTr ? FontWeight.w600 : FontWeight.w400,
                            ),
                            textDirection: dir,
                            textAlign: TextAlign.justify,
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            failed
                                ? context.l10n.reader_not_translated_retry
                                : context.l10n.grammar_translating,
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                              color: failed ? c.rose : c.inkSoft,
                              fontSize: 12,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
          // از راست به چپ: 🔊 ← 🧬 ← رفرش
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: InkWell(
              onTap: busy ? null : () => _retry(lang, src, paraIdx: paraIdx),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: busy
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.6, color: c.inkSoft),
                      )
                    : Icon(Icons.refresh,
                        size: 16, color: c.inkSoft.withOpacity(0.7)),
              ),
            ),
          ),
          if (t != null)
            NeuralPathButton(
              onTap: () => showNeuralPath(
                context,
                word: t,
                langCode: lang,
                baseText: src,
              ),
            ),
          if (t != null)
            SyncSpeakButton(
              code: lang,
              id: id,
              text: t,
              color: c.gold,
              size: 16,
              padding: const EdgeInsets.all(5),
            ),
        ],
      ),
        ),
      );
      if (widget.onReorderLangs == null) return row;
      return DragTarget<String>(
        onWillAcceptWithDetails: (d) => d.data != lang,
        onAcceptWithDetails: (d) => widget.onReorderLangs!(d.data, lang),
        builder: (context, cand, _) => DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: cand.isNotEmpty ? c.gold : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: row,
        ),
      );
    });
  }
}

class _HeadIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onTap;
  const _HeadIcon({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }
}
