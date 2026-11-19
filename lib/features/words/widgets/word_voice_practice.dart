import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/word_examples.dart' show wordExamplesStoreProvider;
import '../../../core/constants/supported_languages.dart';
import '../../../core/models/daily_word.dart';
import '../../../core/providers/ai_settings_provider.dart';
import '../../../core/providers/language_selection_provider.dart';
import '../../../core/providers/speech_provider.dart' show speechControllerProvider;
import '../../../core/providers/translation_provider.dart';
import '../../../core/storage/local_storage.dart';
import '../../../core/theme/app_theme_colors.dart';
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

class WordVoicePractice extends ConsumerStatefulWidget {
  /// لغاتِ بازه‌ی نمایش‌داده‌شده
  final List<DailyWord> words;
  const WordVoicePractice({super.key, required this.words});

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

  @override
  void initState() {
    super.initState();
    _persona = PersonaStore.builtIns.first;
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
      r = decodeHtmlEntities((await ref
              .read(translationServiceProvider)
              .translate(
                text: w.en,
                targetLang: to,
                sourceLang: w.lang,
                aiSettings: ref.read(aiSettingsProvider),
              ))
          .trim());
    } catch (_) {}
    if (r.toLowerCase() == w.en.trim().toLowerCase()) r = '';
    r = r.isEmpty ? '' : _firstMeaning(r);
    if (r.isNotEmpty) _trCache[key] = r;
    return r;
  }

  Future<List<_P>> _plan(int i) {
    if (i < 0 || i >= _ws.length) return Future.value(const <_P>[]);
    return _plans[i] ??= _buildPlan(i);
  }

  Future<List<_P>> _buildPlan(int i) async {
    final w = _ws[i];
    final word = w.en.trim();
    if (word.isEmpty) return const <_P>[];
    final langs = [for (final l in _langs) if (l != w.lang) l];
    final trs = await Future.wait([for (final l in langs) _translate(w, l)]);
    final out = <_P>[];
    for (var k = 0; k < langs.length; k++) {
      final t = trs[k].trim();
      if (t.isEmpty) continue;
      out.add(_P(out.isEmpty ? word : '', w.lang, t, langs[k]));
      _langOf[t] = langs[k];
    }
    if (out.isEmpty) return const <_P>[]; // ترجمه‌ای نیامد → این لغت رد می‌شود
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
      _mode = true;
      _nonce++;
    });
  }

  void _reset() {
    _wi = 0;
    _pi = 0;
    _lastTurn = null;
    _plans.clear();
    _langOf.clear();
  }

  void _end() {
    if (_mode && mounted) setState(() => _mode = false);
  }

  void _redial() {
    if (!mounted) return;
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
    return p.lead;
  }

  Future<CallTurn?> _reply(String text, bool retry) async {
    if (retry && _lastTurn != null) return _lastTurn;
    await _peek();
    _pi++;
    final nx = await _peek();
    _prefetch();
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
    return p.target;
  }

  String _listenLang(String target) =>
      _langOf[target] ?? (_ws.isNotEmpty ? _ws.first.lang : 'en');

  // ───────────── UI ─────────────
  Widget _button(AppThemeColorsExt c) {
    final fa = _fa;
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: c.gold,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      onPressed: widget.words.isEmpty ? null : _start,
      icon: const Icon(Icons.videocam_rounded, size: 20),
      label: Text(
        fa ? 'تمرین صوتی لغات' : 'Voice practice',
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.words.isEmpty && !_mode) return const SizedBox.shrink();
    final c = context.appColors;
    final lang = _ws.isNotEmpty ? _ws.first.lang : 'en';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: _mode
          ? SpeakingCallPanel(
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
            )
          : _button(c),
    );
  }
}
