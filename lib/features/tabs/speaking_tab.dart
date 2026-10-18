import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../core/constants/supported_languages.dart';
import '../../core/models/grammar_note.dart';
import '../../core/providers/ai_settings_provider.dart';
import '../../core/providers/language_selection_provider.dart';
import '../../core/providers/reader_providers.dart';
import '../../core/providers/translation_provider.dart';
import '../../core/storage/local_storage.dart';
import '../../core/theme/app_theme_colors.dart';
import '_hope_panel.dart';

// ═══════════════════════════════════════════════════════════════════
// تب «تمرین مکالمه» — هم‌شکل SpeakingPractice.jsx در Hope
// عنوان + توضیح، انتخاب زبانِ تمرین، کادرِ چت (با پیامِ خوش‌آمدِ Jimmy)،
// نوارِ ورودیِ سبزآبی. گفتگو فقط روی همین گوشی ذخیره می‌شود.
// ═══════════════════════════════════════════════════════════════════

const String _kChatKey = 'zflut-speaking-chat-v1';
const String _kLangKey = 'zflut-speaking-lang-v1';
const Color _kMistake = Color(0xFFC81E1E);
const Color _kCorrection = Color(0xFF166534);

class _Correction {
  final String original;
  final String corrected;
  final int oStart;
  final int oEnd;
  final int cStart;
  final int cEnd;

  const _Correction({
    required this.original,
    required this.corrected,
    required this.oStart,
    required this.oEnd,
    required this.cStart,
    required this.cEnd,
  });

  Map<String, dynamic> toJson() => {
        'original': original,
        'corrected': corrected,
        'oStart': oStart,
        'oEnd': oEnd,
        'cStart': cStart,
        'cEnd': cEnd,
      };

  factory _Correction.fromJson(Map<String, dynamic> j) => _Correction(
        original: (j['original'] ?? '').toString(),
        corrected: (j['corrected'] ?? '').toString(),
        oStart: (j['oStart'] as num?)?.toInt() ?? 0,
        oEnd: (j['oEnd'] as num?)?.toInt() ?? 0,
        cStart: (j['cStart'] as num?)?.toInt() ?? 0,
        cEnd: (j['cEnd'] as num?)?.toInt() ?? 0,
      );
}

class _Msg {
  final String role; // 'user' | 'ai'
  final String text;
  final List<_Correction> corrections;
  final bool savedToGrammar;

  const _Msg({
    required this.role,
    required this.text,
    this.corrections = const [],
    this.savedToGrammar = false,
  });

  _Msg copyWith({bool? savedToGrammar}) => _Msg(
        role: role,
        text: text,
        corrections: corrections,
        savedToGrammar: savedToGrammar ?? this.savedToGrammar,
      );

  Map<String, dynamic> toJson() => {
        'role': role,
        'text': text,
        'corrections': corrections.map((c) => c.toJson()).toList(),
        'savedToGrammar': savedToGrammar,
      };

  factory _Msg.fromJson(Map<String, dynamic> j) => _Msg(
        role: (j['role'] ?? 'ai').toString(),
        text: (j['text'] ?? '').toString(),
        corrections: [
          for (final e in (j['corrections'] as List? ?? const []))
            if (e is Map) _Correction.fromJson(Map<String, dynamic>.from(e)),
        ],
        savedToGrammar: j['savedToGrammar'] == true,
      );
}

class _Reply {
  final String text;
  final List<_Correction> corrections;
  const _Reply(this.text, this.corrections);
}

String _enName(String code) {
  for (final l in kSupportedLanguages) {
    if (l.code == code) return l.enLabel;
  }
  return code;
}

String _normalizeAiText(String t) => t
    .replaceAll('**', '')
    .replaceAll('*', '')
    .replaceAll(RegExp('[\u2018\u2019]'), "'")
    .replaceAll(RegExp('[\u201C\u201D]'), '"');

String _stripThink(String t) => t
    .replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '')
    .replaceAll(RegExp(r'<think>[\s\S]*$', caseSensitive: false), '')
    .trim();

/// خطوطِ «FIX: X => Y» بالای پاسخ را استخراج می‌کند و متنِ نمایشی را با
/// آفستِ دقیقِ اشتباه/پیشنهاد می‌سازد (پورتِ extractCorrections وب).
_Reply _extractCorrections(String reply) {
  final normalized = _normalizeAiText(reply);
  final lines = normalized.split('\n');
  final fixRe = RegExp(r'^FIX:\s*(.+?)\s*=>\s*(.+)$', caseSensitive: false);
  final raw = <List<String>>[];
  var i = 0;
  while (i < lines.length) {
    final m = fixRe.firstMatch(lines[i].trim());
    if (m == null) break;
    raw.add([m.group(1)!.trim(), m.group(2)!.trim()]);
    i++;
  }
  final body = lines.sublist(i).join('\n').replaceFirst(RegExp(r'^\s+'), '');
  if (raw.isEmpty) return _Reply(normalized, const []);

  var built = '';
  final out = <_Correction>[];
  for (var idx = 0; idx < raw.length; idx++) {
    final prefix = '${idx + 1}. Instead of "';
    const mid = '", you should say "';
    final oStart = built.length + prefix.length;
    final oEnd = oStart + raw[idx][0].length;
    final cStart = oEnd + mid.length;
    final cEnd = cStart + raw[idx][1].length;
    built += '$prefix${raw[idx][0]}$mid${raw[idx][1]}".\n';
    out.add(_Correction(
      original: raw[idx][0],
      corrected: raw[idx][1],
      oStart: oStart,
      oEnd: oEnd,
      cStart: cStart,
      cEnd: cEnd,
    ));
  }
  return _Reply('$built\n$body', out);
}

class _Seg {
  final String text;
  final int type; // 0 plain, 1 mistake, 2 correction
  const _Seg(this.text, this.type);
}

List<_Seg> _segments(String text, List<_Correction> corrections) {
  if (text.isEmpty || corrections.isEmpty) return [_Seg(text, 0)];
  final ranges = <List<int>>[]; // start, end, type
  for (final c in corrections) {
    if (c.oEnd > c.oStart) ranges.add([c.oStart, c.oEnd, 1]);
    if (c.cEnd > c.cStart) ranges.add([c.cStart, c.cEnd, 2]);
  }
  if (ranges.isEmpty) return [_Seg(text, 0)];
  ranges.sort((a, b) => a[0].compareTo(b[0]));
  final segs = <_Seg>[];
  var cursor = 0;
  for (final r in ranges) {
    if (r[0] < cursor || r[1] > text.length) continue;
    if (r[0] > cursor) segs.add(_Seg(text.substring(cursor, r[0]), 0));
    segs.add(_Seg(text.substring(r[0], r[1]), r[2]));
    cursor = r[1];
  }
  if (cursor < text.length) segs.add(_Seg(text.substring(cursor), 0));
  return segs;
}

String _compactCoach(String text) {
  final kept = text
      .split('\n')
      .where((l) => !RegExp(r'^\s*\d+\.\s*Instead of\s').hasMatch(l))
      .join(' ')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();
  final s = kept.isEmpty ? text : kept;
  return s.length > 400 ? s.substring(0, 400) : s;
}

String _historyText(List<_Msg> history) {
  final from = math.max(0, history.length - 4);
  return history.sublist(from).map((m) {
    if (m.role == 'ai') return 'Coach: ${_compactCoach(m.text)}';
    final t = m.text.length > 300 ? m.text.substring(0, 300) : m.text;
    return 'Learner: $t';
  }).join('\n');
}

/// متنِ ترجمه را بدونِ ایموجیِ ابتدایی برمی‌گرداند (مثلاً «✅ Saved» → «Saved»).
String _plain(String t) =>
    t.replaceFirst(RegExp(r'^[^\p{L}\p{N}]+', unicode: true), '');

class SpeakingTab extends ConsumerStatefulWidget {
  const SpeakingTab({super.key});

  @override
  ConsumerState<SpeakingTab> createState() => _SpeakingTabState();
}

class _SpeakingTabState extends ConsumerState<SpeakingTab> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  List<_Msg> _messages = [];
  bool _loading = false;
  String _error = '';
  String _chatLang = 'en';
  List<_Correction> _corrections = [];
  bool _correctionsSaved = false;
  String? _failedText;
  List<_Msg>? _failedHistory;

  @override
  void initState() {
    super.initState();
    final sel = ref.read(languageSelectionProvider);
    final options = sel.targets.isNotEmpty ? sel.targets : const ['en'];
    // زبانِ تمرینِ انتخاب‌شده‌ی قبلی حفظ می‌شود (با جابجایی بین تب‌ها ریست نشود)
    final saved =
        (ref.read(localStorageProvider).readJson(_kLangKey)['lang'] ?? '')
            .toString();
    _chatLang = options.contains(saved) ? saved : options.first;
    _messages = _load();
    // اگر فقط پیامِ خوش‌آمد هست، با زبانِ فعلی بازسازی شود
    if (_messages.isEmpty ||
        (_messages.length == 1 && _messages.first.role == 'ai')) {
      _messages = [_welcome(_chatLang)];
      _persist();
    }
  }

  void _setChatLang(String v) {
    setState(() {
      _chatLang = v;
      if (_messages.length <= 1) _messages = [_welcome(v)];
    });
    unawaited(ref.read(localStorageProvider).writeJson(_kLangKey, {'lang': v}));
    _persist();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ───────────── ذخیره/بازیابی ─────────────
  List<_Msg> _load() {
    final raw = ref.read(localStorageProvider).readJson(_kChatKey)['items'];
    if (raw is! List) return [];
    final out = <_Msg>[];
    for (final e in raw) {
      if (e is Map) {
        try {
          out.add(_Msg.fromJson(Map<String, dynamic>.from(e)));
        } catch (_) {}
      }
    }
    return out;
  }

  void _persist() {
    unawaited(ref.read(localStorageProvider).writeJson(
        _kChatKey, {'items': _messages.map((m) => m.toJson()).toList()}));
  }

  _Msg _welcome(String lang) => _Msg(
        role: 'ai',
        text: "Hey there! I'm Jimmy, your conversation coach. Let's practice "
            '${_enName(lang)} together.\n\n'
            "I'll help you with grammar, vocabulary, and natural expressions. "
            "Feel free to write anything you'd like to talk about!\n\n"
            "By the way, what's your name? Or tell me something about yourself.",
      );

  String _activeLang() {
    final sel = ref.read(languageSelectionProvider);
    final options = sel.targets.isEmpty ? ['en'] : sel.targets;
    return options.contains(_chatLang) ? _chatLang : options.first;
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  // ───────────── AI ─────────────
  Future<String> _callAi(String prompt, int maxTokens) async {
    final svc = ref.read(translationServiceProvider);
    final ai = ref.read(aiSettingsProvider);
    final r = await svc.callAI(
      prompt: prompt,
      maxTokens: maxTokens,
      retries: 1,
      settings: ai,
    );
    final cleaned = _stripThink(r);
    if (cleaned.isEmpty) throw Exception('empty');
    return cleaned;
  }

  Future<_Reply> _askTeacher({
    required String sentence,
    required String lang,
    required String native,
    required List<_Msg> history,
    required bool writtenInNative,
  }) async {
    final langLabel = _enName(lang);
    final nativeLabel = _enName(native);
    final prompt = '''
You are Jimmy, a friendly patient $langLabel coach. Learner's native language: $nativeLabel.
They just wrote${writtenInNative ? ' (in $nativeLabel, not $langLabel)' : ''}: "$sentence"

Rules:
- If they wrote in $langLabel with mistakes, list each one on its own line at the very top, using EXACTLY this tag — keep the word FIX and the => symbol in English even though everything else you write is in $langLabel, do NOT translate this tag:
FIX: <what they wrote> => <the correct version>
(one FIX line per mistake, using their exact wording for "what they wrote")
- If they wrote in $nativeLabel instead of $langLabel (not a mistake, just the wrong language), use ONE such line: FIX: <what they wrote in $nativeLabel> => <$langLabel equivalent>
- After the FIX line(s) — or immediately if there were no mistakes — leave a blank line, then continue the chat: reply ENTIRELY in $langLabel, plain text only (no markdown/asterisks), naturally and briefly — react, ask a follow-up, like a real conversation, not a report. Do NOT explain the mistakes yourself in prose; the FIX lines above are enough.

Recent conversation:
${_historyText(history)}

Now respond to: "$sentence"
''';
    final result = await _callAi(prompt, 550);
    return _extractCorrections(result);
  }

  Future<String> _askContinuation({
    required String translated,
    required String lang,
    required String native,
    required List<_Msg> history,
  }) async {
    final langLabel = _enName(lang);
    final prompt =
        'You are Jimmy, a friendly $langLabel conversation partner. The learner '
        '(native language: ${_enName(native)}) just said, in $langLabel: "$translated"\n\n'
        'Reply ENTIRELY in $langLabel, briefly and naturally (1-3 short sentences) — '
        'react to what they said and/or ask a short follow-up question, like a real '
        'chat message. Plain text only, no markdown, no numbered lists.\n\n'
        'Recent conversation:\n${_historyText(history)}\n';
    final result = await _callAi(prompt, 180);
    return _normalizeAiText(result);
  }

  Future<_Reply> _coachReply(
      String text, List<_Msg> history, String lang) async {
    final native = ref.read(languageSelectionProvider).native;
    final writtenInNative = (native == 'fa' || native == 'ar') &&
        native != lang &&
        lang != 'fa' &&
        lang != 'ar' &&
        isMostlyArabicScript(text);

    if (writtenInNative) {
      // فارسی نوشته → فقط ترجمه است؛ اول ترجمه‌ی رایگان (بدون توکنِ AI)
      var translated = '';
      try {
        translated = (await ref.read(translationServiceProvider).translate(
                  text: text,
                  targetLang: lang,
                  sourceLang: native,
                  aiSettings: ref.read(aiSettingsProvider),
                ))
            .trim();
      } catch (_) {
        translated = '';
      }
      if (translated.isEmpty || translated == text) {
        return _askTeacher(
          sentence: text,
          lang: lang,
          native: native,
          history: history,
          writtenInNative: true,
        );
      }
      final continuation = await _askContinuation(
        translated: translated,
        lang: lang,
        native: native,
        history: history,
      );
      const prefix = '1. Instead of "';
      const mid = '", you should say "';
      final oStart = prefix.length;
      final oEnd = oStart + text.length;
      final cStart = oEnd + mid.length;
      final cEnd = cStart + translated.length;
      return _Reply(
        '$prefix$text$mid$translated".\n\n$continuation',
        [
          _Correction(
            original: text,
            corrected: translated,
            oStart: oStart,
            oEnd: oEnd,
            cStart: cStart,
            cEnd: cEnd,
          ),
        ],
      );
    }

    return _askTeacher(
      sentence: text,
      lang: lang,
      native: native,
      history: history,
      writtenInNative: false,
    );
  }

  Future<void> _ask(String text, List<_Msg> history) async {
    final lang = _activeLang();
    setState(() {
      _error = '';
      _corrections = [];
      _correctionsSaved = false;
      _messages = [...history, _Msg(role: 'user', text: text)];
      _loading = true;
    });
    _persist();
    _scrollDown();
    try {
      final r = await _coachReply(text, history, lang);
      if (!mounted) return;
      setState(() {
        if (r.corrections.isNotEmpty) _corrections = r.corrections;
        _messages = [
          ..._messages,
          _Msg(role: 'ai', text: r.text, corrections: r.corrections),
        ];
        _failedText = null;
        _failedHistory = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failedText = text;
        _failedHistory = history;
        _error = context.l10n.speaking_ai_no_response;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    _persist();
    _scrollDown();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _loading) return;
    _input.clear();
    await _ask(text, _messages);
  }

  void _retry() {
    final t = _failedText;
    final h = _failedHistory;
    if (t == null || h == null || _loading) return;
    unawaited(_ask(t, h));
  }

  void _clearChat() {
    setState(() {
      _messages = [_welcome(_activeLang())];
      _corrections = [];
      _correctionsSaved = false;
      _error = '';
      _failedText = null;
      _failedHistory = null;
    });
    _persist();
  }

  void _saveToGrammar(List<_Correction> list) {
    if (list.isEmpty) return;
    final md = [
      for (var i = 0; i < list.length; i++)
        '**${i + 1}. ${_plain(context.l10n.speaking_mistake)}** ${list[i].original}\n\n'
            '**${_plain(context.l10n.speaking_suggestion)}** ${list[i].corrected}',
    ].join('\n\n---\n\n');
    ref.read(grammarNotesProvider.notifier).addNote(GrammarNote(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          word: '',
          sentence: '',
          markdown: md,
          langCode: _activeLang(),
          savedAt: DateTime.now(),
        ));
  }

  // ───────────── UI ─────────────
  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final sel = ref.watch(languageSelectionProvider);
    final options = sel.targets.isEmpty ? ['en'] : sel.targets;
    final lang = options.contains(_chatLang) ? _chatLang : options.first;

    return HopePanel(
      contentDirection: uiContentDirection(context),
      title: _plain(context.l10n.speaking_title),
      intro: context.l10n.speaking_intro,
      children: [
        // ── زبان تمرین + پاک کردن گفتگو ──
        Row(
          children: [
            Text(context.l10n.speaking_practice_language,
                style: TextStyle(color: c.inkSoft, fontSize: 12)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.cardBorder),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: lang,
                  isDense: true,
                  style: TextStyle(color: c.ink, fontSize: 13),
                  dropdownColor: Colors.white,
                  items: [
                    for (final code in options)
                      DropdownMenuItem(
                        value: code,
                        child: Text(langDisplayName(context, code)),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) _setChatLang(v);
                  },
                ),
              ),
            ),
            const Spacer(),
            if (_messages.isNotEmpty)
              HopeTextAction(
                icon: Icons.delete_outline,
                label: context.l10n.speaking_clear_chat,
                color: c.rose,
                onTap: _clearChat,
              ),
          ],
        ),

        // ── کادر تصحیحات ──
        if (_corrections.isNotEmpty) _correctionsBox(c),

        // ── منطقه‌ی چت ──
        _chatArea(c),

        // ── نوار ورودی ──
        _inputBar(c),
      ],
    );
  }

  Widget _correctionsBox(AppThemeColorsExt c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.goldSoft,
        border: Border.all(color: c.gold),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.edit_outlined, size: 15, color: c.ink),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _plain(context.l10n.speaking_corrections_title),
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              HopeTextAction(
                label: _correctionsSaved
                    ? _plain(context.l10n.speaking_saved)
                    : _plain(context.l10n.speaking_save_to_grammar),
                color: _correctionsSaved ? c.inkSoft : c.teal,
                fontSize: 11,
                onTap: _correctionsSaved
                    ? null
                    : () {
                        _saveToGrammar(_corrections);
                        setState(() => _correctionsSaved = true);
                      },
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < _corrections.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text.rich(
                TextSpan(
                  style: TextStyle(color: c.ink, fontSize: 13, height: 1.7),
                  children: [
                    TextSpan(
                      text: '${i + 1}. ${_plain(context.l10n.speaking_mistake)} ',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    TextSpan(
                      text: _corrections[i].original,
                      style: const TextStyle(
                        color: _kMistake,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                        decorationColor: _kMistake,
                      ),
                    ),
                    const TextSpan(text: '\n'),
                    TextSpan(
                      text: '${_plain(context.l10n.speaking_suggestion)} ',
                      style: const TextStyle(
                        color: _kCorrection,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(
                      text: _corrections[i].corrected,
                      style: const TextStyle(
                        color: _kCorrection,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chatArea(AppThemeColorsExt c) {
    return Container(
      constraints: const BoxConstraints(minHeight: 200, maxHeight: 420),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: c.cardBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, bc) {
          final maxW = bc.maxWidth * 0.88;
          return ListView(
            controller: _scroll,
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            children: [
              for (var i = 0; i < _messages.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _messageRow(i, _messages[i], maxW, c),
                ),
              if (_loading)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: c.gold,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(context.l10n.speaking_checking,
                          style: TextStyle(color: c.inkSoft, fontSize: 13)),
                    ],
                  ),
                ),
              if (_error.isNotEmpty)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_error,
                          style: TextStyle(color: c.rose, fontSize: 12)),
                      if (_failedText != null) ...[
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: _loading ? null : _retry,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: c.rose,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.refresh,
                                    size: 13, color: Colors.white),
                                const SizedBox(width: 4),
                                Text(
                                  context.l10n.speaking_try_again,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _messageRow(int idx, _Msg m, double maxW, AppThemeColorsExt c) {
    final isUser = m.role == 'user';
    final dir = autoDir(m.text);

    final Widget content;
    if (isUser) {
      content = Text(
        m.text,
        textDirection: dir,
        style: TextStyle(color: c.ink, fontSize: 13, height: 1.7),
      );
    } else {
      content = Text.rich(
        TextSpan(
          style: TextStyle(color: c.ink, fontSize: 13, height: 1.7),
          children: [
            for (final s in _segments(m.text, m.corrections))
              TextSpan(
                text: s.text,
                style: s.type == 1
                    ? const TextStyle(
                        color: _kMistake,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                        decorationColor: _kMistake,
                      )
                    : s.type == 2
                        ? const TextStyle(
                            color: _kCorrection,
                            fontWeight: FontWeight.w700,
                          )
                        : null,
              ),
          ],
        ),
        textDirection: dir,
      );
    }

    return Align(
      alignment: isUser
          ? AlignmentDirectional.centerStart
          : AlignmentDirectional.centerEnd,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isUser ? c.paper : c.goldSoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.cardBorder),
              ),
              child: content,
            ),
            if (!isUser && m.corrections.isNotEmpty)
              HopeTextAction(
                label: m.savedToGrammar
                    ? _plain(context.l10n.speaking_saved)
                    : _plain(context.l10n.speaking_save_to_grammar),
                color: m.savedToGrammar ? c.inkSoft : c.teal,
                fontSize: 11,
                onTap: m.savedToGrammar
                    ? null
                    : () {
                        _saveToGrammar(m.corrections);
                        setState(() {
                          _messages = [
                            for (var i = 0; i < _messages.length; i++)
                              i == idx
                                  ? _messages[i].copyWith(savedToGrammar: true)
                                  : _messages[i],
                          ];
                        });
                        _persist();
                      },
              ),
          ],
        ),
      ),
    );
  }

  Widget _inputBar(AppThemeColorsExt c) {
    final canSend = !_loading && _input.text.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: c.teal, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Opacity(
            opacity: canSend ? 1 : 0.5,
            child: Material(
              color: c.teal,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: canSend ? _send : null,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  child: Icon(Icons.send_rounded, size: 17, color: Colors.white),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 5,
              onChanged: (_) => setState(() {}),
              style: TextStyle(color: c.ink, fontSize: 13, height: 1.6),
              decoration: InputDecoration(
                hintText: context.l10n.speaking_input_placeholder,
                hintStyle: TextStyle(
                  color: c.inkSoft.withOpacity(0.6),
                  fontSize: 13,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
