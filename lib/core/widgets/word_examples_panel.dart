import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/word_examples.dart';
import '../constants/supported_languages.dart';
import '../providers/ai_settings_provider.dart';
import '../providers/translation_provider.dart';
import '../providers/speech_provider.dart';
import '../theme/app_theme_colors.dart';

// ═══════════════════════════════════════════════════════════════════
// پنلِ «مثال (با هوش مصنوعی)» — پورتِ WordExamples در Hope
// • با باز شدن، اگر مثالی نیست خودکار اولین مثال ساخته می‌شود (بدون انتظارِ اضافه)
// • مثال‌ها روی گوشی کش می‌شوند؛ «مثالِ جدید» با لیستِ قبلی تکراری نمی‌سازد
// • هر مثال: 🔊، 🔁 (جایگزینیِ همان مثال)، و ترجمه به زبان‌های انتخابی
// ═══════════════════════════════════════════════════════════════════
class WordExamplesPanel extends ConsumerStatefulWidget {
  final String word;
  final String langCode;
  final String meaningNative;
  final String nativeCode;
  final List<String> targetLangs;

  const WordExamplesPanel({
    super.key,
    required this.word,
    required this.langCode,
    required this.meaningNative,
    required this.nativeCode,
    required this.targetLangs,
  });

  @override
  ConsumerState<WordExamplesPanel> createState() => _WordExamplesPanelState();
}

class _WordExamplesPanelState extends ConsumerState<WordExamplesPanel> {
  List<WordExample> _examples = [];
  bool _generating = false;
  String? _refreshingId;
  String _err = '';

  String get _nativeLabel {
    for (final l in kSupportedLanguages) {
      if (l.code == widget.nativeCode) return l.enLabel;
    }
    return widget.nativeCode;
  }

  @override
  void initState() {
    super.initState();
    _examples = ref
        .read(wordExamplesStoreProvider)
        .load(widget.word, widget.langCode);
    if (_examples.isEmpty) _generate();
  }

  Future<void> _generate() async {
    if (_generating) return;
    setState(() {
      _generating = true;
      _err = '';
    });
    try {
      final text = await generateWordExample(
        svc: ref.read(translationServiceProvider),
        settings: ref.read(aiSettingsProvider),
        word: widget.word,
        langCode: widget.langCode,
        meaningNative: widget.meaningNative,
        nativeLabel: _nativeLabel,
        existing: _examples.map((e) => e.text).toList(),
      );
      final list = await ref
          .read(wordExamplesStoreProvider)
          .add(widget.word, widget.langCode, text);
      if (!mounted) return;
      setState(() => _examples = list);
    } catch (_) {
      if (!mounted) return;
      setState(() => _err = 'مثال ساخته نشد — دوباره امتحان کن.');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _refresh(String id) async {
    if (_refreshingId != null) return;
    setState(() {
      _refreshingId = id;
      _err = '';
    });
    try {
      final text = await generateWordExample(
        svc: ref.read(translationServiceProvider),
        settings: ref.read(aiSettingsProvider),
        word: widget.word,
        langCode: widget.langCode,
        meaningNative: widget.meaningNative,
        nativeLabel: _nativeLabel,
        existing:
            _examples.where((e) => e.id != id).map((e) => e.text).toList(),
      );
      final list = await ref
          .read(wordExamplesStoreProvider)
          .replace(widget.word, widget.langCode, id, text);
      if (!mounted) return;
      setState(() => _examples = list);
    } catch (_) {
      if (!mounted) return;
      setState(() => _err = 'مثال ساخته نشد — دوباره امتحان کن.');
    } finally {
      if (mounted) setState(() => _refreshingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final targets =
        widget.targetLangs.where((l) => l != widget.langCode).toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: InkWell(
              onTap: _generating ? null : _generate,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: c.goldSoft),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_generating)
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.6, color: c.gold),
                      )
                    else
                      Icon(Icons.auto_awesome, size: 12, color: c.gold),
                    const SizedBox(width: 4),
                    Text(
                      _generating
                          ? 'در حال ساخت مثال...'
                          : (_examples.isEmpty ? 'یه مثال بساز' : 'یه مثال دیگه'),
                      style: TextStyle(
                          color: c.gold,
                          fontSize: 11,
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_err.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_err, style: TextStyle(color: c.rose, fontSize: 11)),
            ),
          for (final ex in _examples)
            _ExampleRow(
              key: ValueKey(ex.id + ex.text),
              word: widget.word,
              langCode: widget.langCode,
              example: ex,
              targets: targets,
              refreshing: _refreshingId == ex.id,
              onRefresh: () => _refresh(ex.id),
            ),
        ],
      ),
    );
  }
}

class _ExampleRow extends ConsumerWidget {
  final String word;
  final String langCode;
  final WordExample example;
  final List<String> targets;
  final bool refreshing;
  final VoidCallback onRefresh;

  const _ExampleRow({
    super.key,
    required this.word,
    required this.langCode,
    required this.example,
    required this.targets,
    required this.refreshing,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: c.paperDark.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.cardBorder),
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    example.text,
                    style: TextStyle(
                        color: c.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        height: 1.45),
                  ),
                ),
                InkResponse(
                  onTap: () => ref
                      .read(speechControllerProvider.notifier)
                      .toggle(example.text, langCode),
                  radius: 18,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text('🔊',
                        style: const TextStyle(fontSize: 18, height: 1.1)),
                  ),
                ),
                InkResponse(
                  onTap: refreshing ? null : onRefresh,
                  radius: 16,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: refreshing
                        ? SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.6, color: c.teal))
                        : Icon(Icons.refresh,
                            size: 15, color: c.teal.withOpacity(0.8)),
                  ),
                ),
              ],
            ),
            for (final t in targets)
              _ExampleTranslation(
                key: ValueKey('${example.id}::${example.text.hashCode}::$t'),
                word: word,
                langCode: langCode,
                example: example,
                target: t,
              ),
          ],
        ),
      ),
    );
  }
}

class _ExampleTranslation extends ConsumerStatefulWidget {
  final String word;
  final String langCode;
  final WordExample example;
  final String target;

  const _ExampleTranslation({
    super.key,
    required this.word,
    required this.langCode,
    required this.example,
    required this.target,
  });

  @override
  ConsumerState<_ExampleTranslation> createState() =>
      _ExampleTranslationState();
}

class _ExampleTranslationState extends ConsumerState<_ExampleTranslation> {
  String _text = '';
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _text = widget.example.translations[widget.target] ?? '';
    if (_text.isEmpty) _load();
  }

  Future<void> _load() async {
    try {
      final t = await ref.read(translationServiceProvider).translate(
            text: widget.example.text,
            targetLang: widget.target,
            sourceLang: widget.langCode,
            aiSettings: ref.read(aiSettingsProvider),
            forceVerify: true,
          );
      if (!mounted) return;
      if (t.trim().isEmpty || t.trim() == widget.example.text.trim()) {
        setState(() => _failed = true);
        return;
      }
      setState(() => _text = t.trim());
      await ref.read(wordExamplesStoreProvider).setTranslation(
          widget.word, widget.langCode, widget.example.id, widget.target, t);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    String abbr = widget.target.toUpperCase();
    bool rtl = widget.target == 'fa' || widget.target == 'ar';
    for (final l in kSupportedLanguages) {
      if (l.code == widget.target) {
        abbr = l.abbr;
        rtl = l.dir == TextDirection.rtl;
      }
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              border: Border.all(color: c.goldSoft),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(abbr,
                style: TextStyle(
                    color: c.gold, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _text.isEmpty
                ? Text(_failed ? '—' : 'در حال ترجمه...',
                    style: TextStyle(color: c.inkSoft, fontSize: 11))
                : Directionality(
                    textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                    child: Text(_text,
                        style: TextStyle(
                            color: c.teal,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            height: 1.45)),
                  ),
          ),
        ],
      ),
    );
  }
}
