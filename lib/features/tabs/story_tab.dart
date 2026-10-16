import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/cefr_levels.dart';
import '../../core/constants/supported_languages.dart';
import '../../core/providers/ai_settings_provider.dart';
import '../../core/providers/conversation_provider.dart';
import '../../core/providers/language_selection_provider.dart';
import '../../core/providers/reader_providers.dart';
import '../../core/providers/story_library_provider.dart';
import '../../core/providers/translation_provider.dart';
import '../../core/theme/app_theme_colors.dart';
import '_hope_panel.dart';

// ═══════════════════════════════════════════════════════════════════
// تب «داستان‌ساز» — هم‌شکل StoryBuilder.jsx در Hope
// عنوان، سوئیچ دوقسمتی (ساخت داستان / کتابخانه‌ی من)، کارت تنظیمات
// (زبان و سطح، نوع محتوا، طول)، کارت انتخاب لغت، دکمه‌ی «بساز داستان».
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
  for (final c in _kContentTypes) {
    if (c.key == key) return c.label;
  }
  return 'عمومی';
}

String _stripThink(String t) => t
    .replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '')
    .replaceAll(RegExp(r'<think>[\s\S]*$', caseSensitive: false), '')
    .trim();

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
      ref.read(storyLibraryProvider.notifier).add(story);
      if (!mounted) return;
      setState(() => _result = story);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error =
          'ساخت داستان انجام نشد. اینترنتت رو چک کن و دوباره امتحان کن.');
    } finally {
      if (mounted) setState(() => _generating = false);
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
          _generateButton(c, lang),
          if (_error.isNotEmpty)
            Text(_error, style: TextStyle(color: c.rose, fontSize: 13)),
          if (_result != null) _resultCard(c, _result!),
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final lv in kCefrLevels)
                HopeChoiceChip(
                  label: lv,
                  active: _level == lv,
                  activeBorder: c.teal,
                  activeFill: c.teal,
                  activeText: Colors.white,
                  onTap: () => setState(() => _level = lv),
                ),
            ],
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
                  _generating ? 'در حال ساخت داستان...' : 'بساز داستان',
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
          _storyBody(c, s.text),
          const SizedBox(height: 8),
          Text('در «کتابخانه‌ی من» ذخیره شد.',
              style: TextStyle(color: c.teal, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _storyBody(AppThemeColorsExt c, String text) {
    final paras = text.split(RegExp(r'\n\s*\n')).where((p) => p.trim().isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final p in paras)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              p.trim(),
              textDirection: autoDir(p),
              style: TextStyle(color: c.ink, fontSize: 14, height: 1.9),
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
      SizedBox(
        height: 34,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: 1 + kCefrLevels.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final lv = i == 0 ? 'all' : kCefrLevels[i - 1];
            return Center(
              child: HopeChoiceChip(
                label: lv == 'all' ? 'همه سطوح' : lv,
                active: _libLevel == lv,
                activeBorder: c.teal,
                activeFill: c.teal,
                activeText: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                onTap: () => setState(() => _libLevel = lv),
              ),
            );
          },
        ),
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

  Widget _storyCard(AppThemeColorsExt c, SavedStory s) {
    final open = _openStoryId == s.id;
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
            onTap: () => setState(() => _openStoryId = open ? null : s.id),
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
                        '${langFaName(s.langCode)} · ${s.level} · '
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
                  open ? Icons.keyboard_arrow_down : Icons.chevron_left,
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
              child: _storyBody(c, s.text),
            ),
        ],
      ),
    );
  }
}
