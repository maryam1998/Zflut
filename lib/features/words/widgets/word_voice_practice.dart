import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/word_examples.dart' show wordExamplesStoreProvider;
import '../../../core/constants/supported_languages.dart';
import '../../../core/models/daily_word.dart';
import '../../../core/practice/practice_follow.dart';
import '../../../core/providers/ai_settings_provider.dart';
import '../../../core/providers/language_selection_provider.dart';
import '../../../core/providers/speech_provider.dart' show speechControllerProvider;
import '../../../core/providers/translation_provider.dart';
import '../../../core/storage/local_storage.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/translate/in_text_translation.dart';
import '../../../core/utils/html_entities.dart';
import '../../tabs/speaking_call.dart';

// ═══════════════════════════════════════════════════════════════════
// 🎙️ «تمرین صوتی لغات» (تب‌های لغات / Vocabulary in Use / Slang)
//
// همان ویدیو کالِ AI (SpeakingCallPanel) که برای «تمرین این مکالمه» هست، ولی برای لغات:
//   1. AI لغت را می‌گوید (مثلاً "Apple").
//   2. راهنما خودکار معنیِ لغت را به اولین زبانِ انتخابی نشان می‌دهد؛ کاربر می‌گوید.
//   3. STT (گوشی، بدونِ AI) با سخت‌گیریِ کم چک می‌کند. غلط بود → همان معنی با TTS خوانده می‌شود.
//   4. زبانِ بعدی (کاربر می‌تواند چند زبان را همزمان انتخاب کند).
//   5. اگر لغت مثالِ ذخیره‌شده دارد: AI می‌گوید "Say example" و کاربر جمله را می‌خواند.
//   6. لغتِ بعدی …
// فقط لغاتِ بازه‌ی نمایش‌داده‌شده (مثلاً «لغت از ۱ تا ۶۰») تمرین می‌شوند.
// ═══════════════════════════════════════════════════════════════════

const String _kLangsKey = 'zflut-word-voice-langs-v1';

class _P {
  final String lead; // آنچه AI قبل از این نوبت می‌گوید (می‌تواند خالی باشد)
  final String leadLang;
  final String target; // آنچه کاربر باید بگوید
  final String lang; // زبانِ target
  const _P(this.lead, this.leadLang, this.target, this.lang);
}

/// پلِ بینِ دکمه‌ی ردیفِ «Mark range read / Clear range» و پنلِ تمرین.
class WordVoiceController {
  final ValueNotifier<int> startTick = ValueNotifier<int>(0);
  final ValueNotifier<bool> active = ValueNotifier<bool>(false);
  void start() => startTick.value++;
  void dispose() {
    startTick.dispose();
    active.dispose();
  }
}

/// دکمه‌ی «تمرین» کنارِ Mark range read / Clear range.
class WordVoiceButton extends StatelessWidget {
  final WordVoiceController controller;
  const WordVoiceButton({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final fa = Localizations.localeOf(context).languageCode == 'fa';
    return ValueListenableBuilder<bool>(
      valueListenable: controller.active,
      builder: (_, on, __) => Tooltip(
        message: fa ? 'تمرین مکالمه با AI' : 'Practice conversation with AI',
        child: FilledButton.icon(
          onPressed: on ? null : controller.start,
          style: FilledButton.styleFrom(
            backgroundColor: c.gold,
            foregroundColor: Colors.white,
            disabledBackgroundColor: c.goldSoft,
            disabledForegroundColor: c.gold,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          ),
          icon: const Icon(Icons.videocam_rounded, size: 17),
          label: Text(
            fa ? 'تمرین' : 'Practice',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}

class WordVoicePractice extends ConsumerStatefulWidget {
  /// لغاتِ بازه‌ی نمایش‌داده‌شده
  final List<DailyWord> words;
  final WordVoiceController? controller;
  const WordVoicePractice({super.key, required this.words, this.controller});

  @override
  ConsumerState<WordVoicePractice> createState() => _WordVoicePracticeState();
}

class _WordVoicePracticeState extends ConsumerState<WordVoicePractice> {
  bool _mode = false;
  int _nonce = 0;
  late AiPersona _persona;

  // نشستِ تمرین
  List<DailyWord> _ws = const [];
  List<String> _langs = const [];
  bool _withExample = true;
  int _wi = 0;
  int _pi = 0;
  CallTurn? _lastTurn;
  final Map<int, Future<List<_P>>> _plans = {};
  final Map<String, String> _langOf = {};
  final Map<String, String> _trCache = {};

  bool get _fa => Localizations.localeOf(context).languageCode == 'fa';

  int _hintWi = -1;
  int _hintPi = 0;

  /// دکمه‌ی CC در پنلِ تماس (پیش‌فرض خاموش)
  bool _cc = false;

  void _onCc(bool v) {
    _cc = v;
    if (v) {
      _hlWord();
    } else {
      _follow.clear();
    }
  }

  // 🎥 ویدیو کال بالای صفحه سنجاق می‌شود + لغتِ در حالِ تمرین در لیستِ پایین هایلایت/اسکرول می‌شود
  late final ProviderContainer _pc;
  late final PracticeFollow _follow;

  /// لغتِ فعلیِ تمرین را در لیستِ لغات هایلایت می‌کند و به آن اسکرول می‌کند.
  void _hlWord() {
    // لغت فقط وقتی CC روشن است در لیست هایلایت می‌شود (CC خاموش = لغت دیده نشود)
    if (!_cc) return;
    if (_wi < 0 || _wi >= _ws.length) return;
    final w = _ws[_wi];
    _follow.show([w.sid], codes: [w.lang, 'en'], lazy: true);
  }

  @override
  void initState() {
    super.initState();
    _persona = PersonaStore.builtIns.first;
    _pc = ProviderScope.containerOf(context, listen: false);
    _follow = PracticeFollow(_pc);
    widget.controller?.startTick.addListener(_onStartTick);
  }

  @override
  void didUpdateWidget(covariant WordVoicePractice old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?.startTick.removeListener(_onStartTick);
      widget.controller?.startTick.addListener(_onStartTick);
    }
  }

  @override
  void dispose() {
    widget.controller?.startTick.removeListener(_onStartTick);
    _follow.clear();
    super.dispose();
  }

  void _onStartTick() {
    if (!_mode && mounted) unawaited(_start());
  }

  void _setMode(bool v) {
    _mode = v;
    widget.controller?.active.value = v;
  }

  /// آواتار را همین‌جا (بدونِ رفتن به تبِ Live chat) عوض می‌کند.
  Future<void> _pickPersona() async {
    final ls = ref.read(localStorageProvider);
    final picked = await showPersonaSheet(context, ls, _persona.id);
    if (!mounted) return;
    final p = PersonaStore.byId(ls, picked ?? _persona.id);
    PersonaStore.setActive(ls, p.id);
    if (p.id == _persona.id && !_mode) {
      setState(() => _persona = p);
      return;
    }
    setState(() {
      _persona = p;
      if (_mode) {
        // تماس با آواتارِ جدید از همان جمله‌ای که تمرین می‌شد ادامه می‌یابد
        if (_hintWi >= 0) {
          _wi = _hintWi;
          _pi = _hintPi;
        }
        _lastTurn = null;
        _cc = false; // پنلِ جدید با CC خاموش شروع می‌شود
        _follow.clear();
        _nonce++;
      }
    });
  }

  String _enName(String code) {
    for (final l in kSupportedLanguages) {
      if (l.code == code) return l.enLabel;
    }
    return code;
  }

  // ───────────── انتخابِ زبان‌ها ─────────────
  List<String> _savedLangs() {
    try {
      final raw = ref.read(localStorageProvider).readJson(_kLangsKey)['langs'];
      if (raw is List) {
        return [for (final e in raw) e.toString()];
      }
    } catch (_) {}
    return const [];
  }

  Future<({List<String> langs, bool example})?> _pickLangs() {
    final c = context.appColors;
    final fa = _fa;
    final sel = ref.read(languageSelectionProvider);
    final anyNonEn = widget.words.any((w) => w.lang != 'en');
    final codes = <String>[];
    for (final x in [sel.native, ...sel.targets]) {
      if (x.isNotEmpty && !codes.contains(x) && (x != 'en' || anyNonEn)) {
        codes.add(x);
      }
    }
    for (final l in kSupportedLanguages) {
      if (!codes.contains(l.code) && (l.code != 'en' || anyNonEn)) {
        codes.add(l.code);
      }
    }
    final saved = _savedLangs().where(codes.contains).toList();
    final chosen = <String>{
      if (saved.isNotEmpty)
        ...saved
      else if (sel.native.isNotEmpty && codes.contains(sel.native))
        sel.native
      else if (codes.isNotEmpty)
        codes.first,
    };
    var example = _withExample;
    return showModalBottomSheet<({List<String> langs, bool example})>(
      context: context,
      backgroundColor: c.paper,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    children: [
                      PersonaChangeChip(
                        persona: _persona,
                        onTap: () async {
                          await _pickPersona();
                          setS(() {});
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        fa
                            ? 'معنیِ لغت را به کدام زبان‌ها بگویی؟'
                            : 'Say the meaning in which languages?',
                        style: TextStyle(
                            color: c.ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        fa
                            ? 'می‌توانی چند زبان را با هم انتخاب کنی؛ برای هر لغت به‌ترتیب همه را می‌گویی.'
                            : 'Pick one or more languages; you say each word\'s meaning in all of them, in order.',
                        style: TextStyle(color: c.inkSoft, fontSize: 12.5),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding:
                            const EdgeInsetsDirectional.fromSTEB(14, 4, 6, 4),
                        decoration: BoxDecoration(
                          color: example ? c.goldSoft : c.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: example ? c.gold : c.cardBorder),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                fa
                                    ? 'جمله‌ی مثال (اگر لغت مثال دارد)'
                                    : 'Example sentence (if the word has one)',
                                style: TextStyle(
                                    color: c.ink,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                            Switch(
                              value: example,
                              activeColor: c.gold,
                              onChanged: (v) => setS(() => example = v),
                            ),
                          ],
                        ),
                      ),
                      for (final code in codes)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Material(
                            color: chosen.contains(code)
                                ? c.goldSoft
                                : c.surface,
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => setS(() {
                                if (!chosen.add(code)) chosen.remove(code);
                              }),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: chosen.contains(code)
                                          ? c.gold
                                          : c.cardBorder),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        langDisplayName(ctx, code),
                                        style: TextStyle(
                                            color: c.ink,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                    Icon(
                                      chosen.contains(code)
                                          ? Icons.check_circle_rounded
                                          : Icons.circle_outlined,
                                      size: 22,
                                      color: chosen.contains(code)
                                          ? c.gold
                                          : c.inkSoft,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: c.gold,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: chosen.isEmpty
                          ? null
                          : () => Navigator.of(ctx).pop((
                                // ترتیبِ انتخاب = ترتیبِ فهرست
                                langs: [
                                  for (final x in codes)
                                    if (chosen.contains(x)) x
                                ],
                                example: example,
                              )),
                      icon: const Icon(Icons.videocam_rounded, size: 20),
                      label: Text(
                        fa ? 'شروع تمرین' : 'Start practice',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ───────────── ترجمه و ساختنِ نوبت‌های هر لغت ─────────────
  String _firstMeaning(String s) {
    final parts = s
        .split(RegExp(r'[،؛;,/\n|]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return parts.isEmpty ? s.trim() : parts.first;
  }

  Future<String> _translate(DailyWord w, String to) async {
    // 🔗 ترجمه‌ی ذخیره‌شده/اصلاح‌شده‌ی داخلِ کارتِ لغت (↻) اولویت دارد
    final saved = ref
        .read(translationServiceProvider)
        .peekCached(w.en, w.lang, to)
        ?.trim();
    if (saved != null && saved.isNotEmpty &&
        saved.toLowerCase() != w.en.trim().toLowerCase()) {
      return _firstMeaning(decodeHtmlEntities(saved));
    }
    final known = (w.translations[to] ?? '').trim();
    if (known.isNotEmpty) return _firstMeaning(known);
    if (to == 'fa' && w.lang == 'en' && w.fa.trim().isNotEmpty) {
      return _firstMeaning(w.fa);
    }
    final key = '${w.lang}|$to|${w.en}';
    final hit = _trCache[key];
    if (hit != null) return hit;
    var r = '';
    try {
      r = (await inTextTranslate(
        svc: ref.read(translationServiceProvider),
        ai: ref.read(aiSettingsProvider),
        text: w.en,
        from: w.lang,
        to: to,
      ))
          .trim();
    } catch (_) {}
    if (r.toLowerCase() == w.en.trim().toLowerCase()) r = '';
    r = r.isEmpty ? '' : _firstMeaning(r);
    if (r.isNotEmpty) _trCache[key] = r;
    return r;
  }

  /// برای مقایسه‌ی «ترجمه همان لغت است؟»: حروف/عددها، بدونِ حساسیت به بزرگی/کوچکی،
  /// اعراب، نیم‌فاصله و علائم.
  static String _same(String s) => s
      .toLowerCase()
      .replaceAll('ي', 'ی')
      .replaceAll('ك', 'ک')
      .replaceAll(RegExp('[\u064B-\u065F\u0670\u200C\u200D]'), '')
      .replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

  /// هم‌زبان بودن (بدونِ حساسیت به بزرگی/کوچکی و پسوندِ منطقه‌ای مثل en-US)
  static bool _sameLang(String a, String b) {
    String base(String x) =>
        x.toLowerCase().replaceAll('_', '-').split('-').first.trim();
    return base(a) == base(b);
  }

  Future<List<_P>> _plan(int i) {
    if (i < 0 || i >= _ws.length) return Future.value(const <_P>[]);
    return _plans[i] ??= _buildPlan(i);
  }

  Future<List<_P>> _buildPlan(int i) async {
    final w = _ws[i];
    final word = w.en.trim();
    if (word.isEmpty) return const <_P>[];
    // زبانِ مقصد = زبانِ خودِ لغت → نه ترجمه می‌شود نه STT چک می‌شود؛ مستقیم می‌رود سراغ زبانِ بعدی
    final langs = [for (final l in _langs) if (!_sameLang(l, w.lang)) l];
    final skippedSameLang = langs.length != _langs.length;
    final trs = await Future.wait([for (final l in langs) _translate(w, l)]);
    final out = <_P>[];
    var sawSame = skippedSameLang;
    final wordKey = _same(word);
    for (var k = 0; k < langs.length; k++) {
      final t = trs[k].trim();
      if (t.isEmpty) continue;
      // ترجمه با خودِ لغت یکی است (مثلاً نامِ خاص/وام‌واژه) → تلفظش چک نمی‌شود
      if (wordKey.isNotEmpty && _same(t) == wordKey) {
        sawSame = true;
        continue;
      }
      out.add(_P(out.isEmpty ? word : '', w.lang, t, langs[k]));
      _langOf[t] = langs[k];
    }
    // ترجمه‌ای نیامد → این لغت رد می‌شود (مگر اینکه ترجمه‌ها هم‌شکلِ لغت بوده باشند؛
    // آن‌وقت فقط جمله‌ی مثال تمرین می‌شود)
    if (out.isEmpty && !sawSame) return const <_P>[];
    if (_withExample) {
      try {
        final ex = ref
            .read(wordExamplesStoreProvider)
            .load(word, w.lang)
            .map((e) => e.text.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        if (ex.isNotEmpty) {
          out.add(_P('Say example.', 'en', ex.first, w.lang));
          _langOf[ex.first] = w.lang;
        }
      } catch (_) {}
    }
    return out;
  }

  /// نوبتِ فعلی (لغاتِ بدونِ ترجمه رد می‌شوند). null = تمام شد.
  Future<_P?> _peek() async {
    while (_wi < _ws.length) {
      final plan = await _plan(_wi);
      if (_pi < plan.length) return plan[_pi];
      _wi++;
      _pi = 0;
    }
    return null;
  }

  void _prefetch() {
    for (var d = 1; d <= 2; d++) {
      unawaited(_plan(_wi + d));
    }
  }

  // ───────────── شروع / پایان ─────────────
  Future<void> _start() async {
    final ws = [
      for (final w in widget.words)
        if (w.en.trim().isNotEmpty) w
    ];
    if (ws.isEmpty) return;
    _persona = PersonaStore.active(ref.read(localStorageProvider));
    final pick = await _pickLangs();
    if (pick == null || !mounted) return;
    try {
      unawaited(ref.read(localStorageProvider).writeJson(
          _kLangsKey, {'langs': pick.langs}));
    } catch (_) {}
    try {
      unawaited(ref.read(speechControllerProvider.notifier).stop());
    } catch (_) {}
    setState(() {
      _ws = ws;
      _langs = pick.langs;
      _withExample = pick.example;
      _reset();
      _setMode(true);
      _nonce++;
    });
  }

  void _reset() {
    _cc = false; // پنلِ جدید با CC خاموش شروع می‌شود
    _wi = 0;
    _pi = 0;
    _hintWi = -1;
    _lastTurn = null;
    _plans.clear();
    _langOf.clear();
  }

  void _end() {
    _follow.clear();
    if (_mode && mounted) setState(() => _setMode(false));
  }

  void _redial() {
    if (!mounted) return;
    _follow.clear();
    setState(() {
      _reset();
      _nonce++;
    });
  }

  // ───────────── کال‌بک‌های پنلِ تماس ─────────────
  String get _doneMsg => 'Great job! That was the last word.';

  Future<String?> _greeting() async {
    final p = await _peek();
    _prefetch();
    if (p == null) {
      return 'Sorry, I could not get the translations. Check your connection and call again.';
    }
    _hlWord();
    return p.lead;
  }

  Future<CallTurn?> _reply(String text, bool retry) async {
    if (retry && _lastTurn != null) return _lastTurn;
    await _peek();
    _pi++;
    final nx = await _peek();
    _prefetch();
    if (nx != null) _hlWord();
    final t = nx == null
        ? CallTurn(_doneMsg, <CallFix>[], lang: 'en')
        : CallTurn(nx.lead, <CallFix>[], lang: nx.leadLang);
    _lastTurn = t;
    return t;
  }

  /// 💡 راهنما: معنی (یا جمله‌ی مثال) برای نوبتِ فعلی.
  Future<String?> _hint() async {
    final p = await _peek();
    if (p == null) return null;
    _langOf[p.target] = p.lang;
    _hlWord();
    _hintWi = _wi;
    _hintPi = _pi;
    return p.target;
  }

  String _listenLang(String target) =>
      _langOf[target] ?? (_ws.isNotEmpty ? _ws.first.lang : 'en');

  // ───────────── UI ─────────────
  Widget _panel() {
    final lang = _ws.isNotEmpty ? _ws.first.lang : 'en';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PersonaChangeChip(persona: _persona, onTap: _pickPersona),
        const SizedBox(height: 8),
        SpeakingCallPanel(
          key: ValueKey('word-practice-$_nonce'),
          persona: _persona,
          langCode: lang,
          langName: _enName(lang),
          onConnected: _greeting,
          onUserSaid: _reply,
          onEnd: _end,
          onHint: _hint,
          onRedial: _redial,
          autoHint: true,
          listenLang: _listenLang,
          onCcChanged: _onCc,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // 🎥 ویدیو کال سنجاق نیست؛ کامل بالای لیستِ لغات (داخلِ اسکرول) می‌آید
    if (!_mode) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: KeepAliveCall(child: _panel()),
    );
  }
}
