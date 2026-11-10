import '../../app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/word_examples.dart';
import '../constants/supported_languages.dart';
import '../providers/ai_settings_provider.dart';
import '../providers/translation_provider.dart';
import '../providers/example_favorites_provider.dart';
import '../providers/speech_provider.dart';
import '../../features/reader/widgets/neural_path_dialog.dart';
import '../player_sync/examples_registry.dart';
import '../player_sync/player_track.dart' show PlayerTrack;
import '../player_sync/sync_widgets.dart' show SyncAnchor, syncSpeakAdhoc;
import '../tts/speech_state.dart';
import 'selection_card.dart' show SelectableSyncText;
import 'sync_item_card.dart' show NeuralPathButton;
import '../theme/app_theme_colors.dart';

// ═══════════════════════════════════════════════════════════════════
// پنلِ «مثال (با هوش مصنوعی)» — پورتِ WordExamples در Hope
// • با باز شدن، اگر مثالی نیست خودکار اولین مثال ساخته می‌شود (بدون انتظارِ اضافه)
// • مثال‌ها روی گوشی کش می‌شوند؛ «مثالِ جدید» با لیستِ قبلی تکراری نمی‌سازد
// • هر مثال: 🔊، 🔁 (جایگزینیِ همان مثال)، و ترجمه به زبان‌های انتخابی
// ═══════════════════════════════════════════════════════════════════
/// یک عضو از زنجیره‌ی خوانش: مثال یا ترجمه‌ی یک مثال
typedef _ChainItem = ({String code, String text, String id});

class WordExamplesPanel extends ConsumerStatefulWidget {
  final String word;
  final String langCode;
  final String meaningNative;
  final String nativeCode;
  final List<String> targetLangs;

  /// عرضِ ستونِ کناریِ کارت: کنارِ هر جعبه‌ی مثال یک ⭐ (علاقه‌مندیِ همان مثال)
  /// دقیقاً زیرِ ⭐ِ لغتِ بالای کارت قرار می‌گیرد.
  final double gutter;

  const WordExamplesPanel({
    super.key,
    required this.word,
    required this.langCode,
    required this.meaningNative,
    required this.nativeCode,
    required this.targetLangs,
    this.gutter = 0,
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
    if (_examples.isEmpty) {
      _generate();
    } else {
      // ⚡ صدای اولین مثال از قبل ساخته شود تا تپ روی 🔊 بدون تأخیر باشد
      ref
          .read(speechControllerProvider.notifier)
          .warmUp(_examples.first.text, widget.langCode);
    }
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
      ref.read(speechControllerProvider.notifier).warmUp(text, widget.langCode);
    } catch (_) {
      if (!mounted) return;
      setState(() => _err = context.l10n.word_examples_failed);
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
      ref.read(speechControllerProvider.notifier).warmUp(text, widget.langCode);
    } catch (_) {
      if (!mounted) return;
      setState(() => _err = context.l10n.word_examples_failed);
    } finally {
      if (mounted) setState(() => _refreshingId = null);
    }
  }

  /// 🔗 ترتیبِ خوانشِ خودکار: مثال ۱ ← ترجمه‌ی هر زبان ← مثال ۲ ← ترجمه‌ها ← …
  /// ترجمه‌ها از حافظه‌ی مثال‌ها خوانده می‌شوند (همان متنی که روی صفحه است)؛
  /// ترجمه‌ای که هنوز آماده نشده در زنجیره نیست.
  List<_ChainItem> _chainItems() {
    Map<String, Map<String, String>> stored = {};
    try {
      stored = {
        for (final e
            in ref.read(wordExamplesStoreProvider).load(widget.word, widget.langCode))
          e.id: e.translations,
      };
    } catch (_) {}
    final targets =
        widget.targetLangs.where((l) => l != widget.langCode).toList();
    final out = <_ChainItem>[];
    for (final e in _examples) {
      if (e.text.trim().isEmpty) continue;
      out.add((
        code: widget.langCode,
        text: e.text,
        id: 'ai-ex-${widget.langCode}-${e.text.hashCode}',
      ));
      final trs = stored[e.id] ?? e.translations;
      for (final t in targets) {
        final tr = trs[t];
        if (tr == null || tr.trim().isEmpty || tr.trim() == e.text.trim()) {
          continue;
        }
        out.add((code: t, text: tr, id: 'ai-ex-tr-$t-${tr.hashCode}'));
      }
    }
    return out;
  }

  @override
  void dispose() {
    ExamplesRegistry.remove(widget.langCode, widget.word);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final targets =
        widget.targetLangs.where((l) => l != widget.langCode).toList();

    // پلیرِ لیست از اینجا می‌فهمد این لغت مثالِ بازِ روی صفحه دارد
    ExamplesRegistry.set(
        widget.langCode, widget.word, [for (final e in _examples) e.text]);
    // پلیرِ لیست از اینجا می‌فهمد زنجیره‌ی (مثال ← ترجمه‌ها ← مثالِ بعدی) کجا تمام می‌شود
    ExamplesRegistry.setChain(widget.langCode, widget.word, () => [
          for (final it in _chainItems()) PlayerTrack.keyFor(it.code, it.text)
        ]);

    // ▶️ پایانِ طبیعیِ پخشِ یک مثال ← ترجمه‌هایش (به ترتیبِ زبان‌ها) ← مثالِ بعدی ← ترجمه‌هایش …
    // (توقفِ دستی کلید را پاک می‌کند، پس زنجیره ادامه پیدا نمی‌کند).
    ref.listen<SpeechState>(speechControllerProvider, (prev, next) {
      // پس‌زمینه: صفِ پلیر خودش ترتیبِ مثال‌ها و ترجمه‌هایشان را می‌خواند
      if (ExamplesRegistry.bgDriving) return;
      if (prev == null ||
          prev.status != SpeechStatus.playing ||
          next.status != SpeechStatus.idle ||
          next.key == null ||
          next.key != prev.key) {
        return;
      }
      final items = _chainItems();
      final i = items.indexWhere(
          (it) => PlayerTrack.keyFor(it.code, it.text) == next.key);
      if (i < 0 || i + 1 >= items.length) return;
      // خطای صدا (مثلاً نبودنِ صدای یک زبان) فقط برای «ترجمه‌ها» زنجیره را قطع نمی‌کند
      if (next.error != null && items[i].code == widget.langCode) return;
      final n = items[i + 1];
      syncSpeakAdhoc(ref, n.code, n.id, n.text);
    });

    final g = widget.gutter;

    // ⭐ِ هر مثال: ستونِ کناری، هم‌راستا با ⭐ِ لغت
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Spacer(),
                InkWell(
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
                              ? context.l10n.word_examples_generating
                              : (_examples.isEmpty
                                  ? context.l10n.word_examples_btn_generate
                                  : context.l10n.word_examples_btn_another),
                          style: TextStyle(
                              color: c.gold,
                              fontSize: 11,
                              fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
                if (g > 0) SizedBox(width: g),
              ],
            ),
          ),
          if (_err.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: 4, right: g),
              child: Text(_err, style: TextStyle(color: c.rose, fontSize: 11)),
            ),
          for (var i = 0; i < _examples.length; i++)
            Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _ExampleRow(
                      key: ValueKey(_examples[i].id + _examples[i].text),
                      word: widget.word,
                      langCode: widget.langCode,
                      example: _examples[i],
                      targets: targets,
                      refreshing: _refreshingId == _examples[i].id,
                      onRefresh: () => _refresh(_examples[i].id),
                    ),
                  ),
                  if (g > 0)
                    SizedBox(
                      width: g,
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: _ExampleStar(
                            word: widget.word,
                            langCode: widget.langCode,
                            example: _examples[i],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// ⭐ِ مثال (ستونِ کناریِ جعبه‌ی مثال) — کلِ مثال با ترجمه‌هایش به علاقه‌مندی‌ها می‌رود.
class _ExampleStar extends ConsumerWidget {
  final String word;
  final String langCode;
  final WordExample example;

  const _ExampleStar({
    required this.word,
    required this.langCode,
    required this.example,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final key = '$langCode::${example.text.trim()}';
    final fav = ref.watch(
        exampleFavoritesProvider.select((l) => l.any((f) => f.key == key)));
    return Directionality(
      textDirection: TextDirection.ltr,
      child: InkResponse(
        onTap: () {
          // ترجمه‌هایی که تا الان گرفته شده‌اند، از حافظه‌ی مثال‌ها
          final stored = ref
              .read(wordExamplesStoreProvider)
              .load(word, langCode)
              .where((e) => e.id == example.id);
          final tr = stored.isNotEmpty ? stored.first.translations : example.translations;
          ref.read(exampleFavoritesProvider.notifier).toggle(
                example.text,
                langCode,
                word,
                translations: tr,
              );
        },
        radius: 16,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(fav ? Icons.star : Icons.star_border,
              size: 20,
              color: fav
                  ? const Color(0xFFF5C518)
                  : c.inkSoft.withOpacity(0.4)),
        ),
      ),
    );
  }
}

/// ردیفِ دکمه‌ها — از راست به چپ: 🔊 ← 🧬 ← رفرش (مثل ردیف‌های ترجمه)
class _ExActions extends ConsumerWidget {
  final String text;
  final String lang;
  final String baseText;
  final String syncId;
  final bool refreshing;
  final VoidCallback? onRefresh;

  const _ExActions({
    required this.text,
    required this.lang,
    required this.baseText,
    required this.syncId,
    required this.refreshing,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkResponse(
            onTap: refreshing ? null : onRefresh,
            radius: 16,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: refreshing
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.6, color: c.inkSoft))
                  : Icon(Icons.refresh,
                      size: 16, color: c.inkSoft.withOpacity(0.7)),
            ),
          ),
          NeuralPathButton(
            onTap: () => showNeuralPath(
              context,
              word: text,
              langCode: lang,
              baseText: baseText,
            ),
          ),
          InkResponse(
            onTap: () => syncSpeakAdhoc(ref, lang, syncId, text),
            radius: 16,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.volume_up_outlined, size: 18, color: c.gold),
            ),
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
    final exId = 'ai-ex-$langCode-${example.text.hashCode}';
    return SyncAnchor(
      code: langCode,
      id: exId,
      child: Container(
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    // لمسِ لغت یا انتخابِ محدوده → کارتِ پاپ‌آپ (ذخیره برای داستان بعدی، گرامر، …)
                    child: SelectableSyncText(
                      code: langCode,
                      id: exId,
                      text: example.text,
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                          color: c.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          height: 1.45),
                    ),
                  ),
                ),
                _ExActions(
                  text: example.text,
                  lang: langCode,
                  baseText: example.text,
                  syncId: exId,
                  refreshing: refreshing,
                  onRefresh: onRefresh,
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
    ));
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
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _text = widget.example.translations[widget.target] ?? '';
    if (_text.isEmpty) _load();
  }

  /// ترجمه‌ی تأییدشده را ذخیره و نمایش می‌دهد.
  Future<void> _apply(String t) async {
    if (!mounted) return;
    setState(() {
      _text = t;
      _failed = false;
    });
    await ref.read(wordExamplesStoreProvider).setTranslation(
        widget.word, widget.langCode, widget.example.id, widget.target, t);
    ref.read(exampleFavoritesProvider.notifier).setTranslation(
        widget.example.text, widget.langCode, widget.target, t);
    if (mounted) {
      ref.read(speechControllerProvider.notifier).warmUp(t, widget.target);
    }
  }

  /// ⚡ دو مرحله‌ای: اول ترجمه‌ی سریع (ML Kit/کش/مترجم رایگان) فوراً نشان داده می‌شود؛
  /// بعد در پس‌زمینه با ناظر AI بررسی می‌شود و اگر اصلاحی بود، جایگزین می‌شود.
  /// (قبلاً تا پایانِ بررسیِ AI هیچ ترجمه‌ای نشان داده نمی‌شد.)
  Future<void> _load() async {
    final svc = ref.read(translationServiceProvider);
    final ai = ref.read(aiSettingsProvider);
    final src = widget.example.text.trim();
    bool bad(String t) => t.trim().isEmpty || t.trim() == src;
    try {
      // مرحله ۱: سریع
      var fast = '';
      try {
        fast = await svc.translate(
          text: widget.example.text,
          targetLang: widget.target,
          sourceLang: widget.langCode,
          aiSettings: ai,
        );
      } catch (_) {}
      if (!mounted) return;
      if (!bad(fast)) await _apply(fast.trim());

      // مرحله ۲: بررسیِ AI در پس‌زمینه (کش را دور می‌زند تا واقعاً بررسی شود)
      var verified = '';
      try {
        verified = await svc
            .translateNetwork(
              text: widget.example.text,
              targetLang: widget.target,
              sourceLang: widget.langCode,
              aiSettings: ai,
              forceVerify: true,
            )
            .timeout(const Duration(seconds: 25));
      } catch (_) {}
      if (!mounted || _refreshing) return;   // کاربر وسطِ کار رفرش زده؛ نتیجه‌ی او مقدم است
      if (!bad(verified)) {
        if (verified.trim() != _text) await _apply(verified.trim());
      } else if (_text.isEmpty) {
        setState(() => _failed = true);
      }
    } catch (_) {
      if (mounted && _text.isEmpty) setState(() => _failed = true);
    }
  }

  /// رفرش: ترجمه‌ی دوباره بدون کش (مترجم‌های رایگان + ناظر AI).
  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _failed = false;
    });
    try {
      final t = await ref.read(translationServiceProvider).retranslate(
            text: widget.example.text,
            targetLang: widget.target,
            sourceLang: widget.langCode,
            aiSettings: ref.read(aiSettingsProvider),
            previous: _text,
          );
      if (!mounted) return;
      final v = t.trim();
      if (v.isEmpty || v == widget.example.text.trim()) {
        setState(() => _failed = _text.isEmpty);
        return;
      }
      setState(() => _text = v);
      await ref.read(wordExamplesStoreProvider).setTranslation(
          widget.word, widget.langCode, widget.example.id, widget.target, v);
      ref.read(exampleFavoritesProvider.notifier).setTranslation(
          widget.example.text, widget.langCode, widget.target, v);
    } catch (_) {
      if (mounted && _text.isEmpty) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _refreshing = false);
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
    final trId = 'ai-ex-tr-${widget.target}-${_text.hashCode}';
    return SyncAnchor(
      code: widget.target,
      id: trId,
      child: Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6),
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
            child: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: _text.isEmpty
                  ? Text(_failed ? '—' : context.l10n.grammar_translating,
                      style: TextStyle(color: c.inkSoft, fontSize: 11))
                  : Directionality(
                      textDirection:
                          rtl ? TextDirection.rtl : TextDirection.ltr,
                      child: SelectableSyncText(
                          code: widget.target,
                          id: trId,
                          text: _text,
                          textDirection:
                              rtl ? TextDirection.rtl : TextDirection.ltr,
                          style: TextStyle(
                              color: c.teal,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              height: 1.45)),
                    ),
            ),
          ),
          _ExActions(
            text: _text,
            lang: widget.target,
            baseText: widget.example.text,
            syncId: trId,
            refreshing: _refreshing,
            onRefresh: _refresh,
          ),
        ],
      ),
    ));
  }
}
