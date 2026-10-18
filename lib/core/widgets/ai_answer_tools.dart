import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/ai_gateway.dart';
import '../constants/supported_languages.dart';
import '../models/language_selection.dart';
import '../providers/ai_settings_provider.dart';
import '../providers/language_selection_provider.dart';
import '../providers/speech_provider.dart';
import '../providers/translation_provider.dart';
import '../theme/app_theme_colors.dart';
import '../translate/translation_service.dart' show englishLangName;
import '../../features/reader/widgets/neural_path_dialog.dart';
import 'sync_item_card.dart' show NeuralPathButton;

/// زبان‌هایی که زیر یک جوابِ AI دکمه‌ی ترجمه می‌گیرند:
/// زبانِ مبدأ (مادریِ کاربر) + زبان‌های مقصدِ او، بدونِ تکرار، و بدونِ
/// خودِ زبانِ جواب (جواب به همان زبان است و ترجمه‌اش لازم نیست).
List<String> answerTranslationLangs(LanguageSelection sel, String source) {
  final out = <String>[];
  for (final t in [sel.native, ...sel.targets]) {
    if (t.isNotEmpty && t != source && !out.contains(t)) out.add(t);
  }
  return out;
}

/// نوارِ زیرِ کادرِ جوابِ هوش مصنوعی — هم‌شکلِ کارتِ لغت:
///   [FA] [ES] [DE] …                      🧬 🔊   ← 🔊 سمتِ راست
/// با زدنِ هر زبان (مبدأ و تارگت‌های کاربر)، جواب به همان زبان ترجمه و در یک
/// ردیفِ ترجمه نشان داده می‌شود: [زبان] متن … 🔁 🧬 🔊
/// دوباره زدن، ترجمه را می‌بندد.
class AiAnswerTools extends ConsumerStatefulWidget {
  /// متنِ جواب
  final String text;

  /// زبانِ متنِ جواب؛ null = زبانِ مادریِ کاربر
  final String? sourceLang;

  const AiAnswerTools({super.key, required this.text, this.sourceLang});

  @override
  ConsumerState<AiAnswerTools> createState() => _AiAnswerToolsState();
}

class _AiAnswerToolsState extends ConsumerState<AiAnswerTools> {
  final List<String> _open = [];
  final Map<String, String> _results = {};
  final Set<String> _loading = {};
  final Set<String> _failed = {};

  @override
  void didUpdateWidget(covariant AiAnswerTools old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      // جواب عوض شد (مثلاً رفرش) → ترجمه‌های قبلی معتبر نیستند
      _open.clear();
      _results.clear();
      _loading.clear();
      _failed.clear();
    }
  }

  static String _plain(String t) => t
      .replaceAll(RegExp(r'\*\*|__|`'), '')
      .replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*[-*•]\s+', multiLine: true), '')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  String get _source =>
      widget.sourceLang ?? ref.read(languageSelectionProvider).native;

  void _speak(String text, String lang) {
    final t = _plain(text);
    if (t.isEmpty) return;
    ref.read(speechControllerProvider.notifier).toggle(t, lang);
  }

  Future<void> _translate(String lang, {bool force = false}) async {
    if (_loading.contains(lang)) return;
    if (!force && _results.containsKey(lang)) return;
    setState(() {
      _loading.add(lang);
      _failed.remove(lang);
    });
    final src = _plain(widget.text);
    final original = widget.text;
    try {
      final label = englishLangName(lang);
      final text = await aiGenerate(
        svc: ref.read(translationServiceProvider),
        settings: ref.read(aiSettingsProvider),
        prompt: 'Translate the following text into $label. Keep the meaning, '
            'tone, line breaks and list structure. Output ONLY the translation '
            '— no notes, no original text, no quotes.\n\nText:\n$src',
        maxTokens: (src.length ~/ 1.5 + 200).clamp(300, 1800).toInt(),
        retries: 1,
        timeoutMs: 45000,
      );
      if (!mounted || original != widget.text) return;
      final clean = _plain(text);
      if (clean.isEmpty) throw Exception('empty');
      setState(() => _results[lang] = clean);
    } catch (_) {
      if (!mounted || original != widget.text) return;
      setState(() => _failed.add(lang));
    } finally {
      if (mounted && original == widget.text) {
        setState(() => _loading.remove(lang));
      }
    }
  }

  void _toggleLang(String lang) {
    if (_open.contains(lang)) {
      setState(() => _open.remove(lang));
      return;
    }
    setState(() => _open.add(lang));
    _translate(lang);
  }

  SupportedLanguage? _info(String code) {
    for (final l in kSupportedLanguages) {
      if (l.code == code) return l;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final sel = ref.watch(languageSelectionProvider);
    final source = _source;
    final langs = answerTranslationLangs(sel, source);
    if (widget.text.trim().isEmpty || langs.isEmpty) {
      return const SizedBox.shrink();
    }

    // داخلِ کادرِ جواب: خطِ‌چین ← 🌐 + چیپ‌های زبان ← جعبه‌ی ترجمه‌ی زبانِ انتخابی
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 10),
            child: CustomPaint(
              size: const Size(double.infinity, 1),
              painter: _DashedLinePainter(c.inkSoft.withOpacity(0.35)),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(Icons.language, size: 22, color: c.inkSoft),
              for (final l in langs)
                _Pill(
                  active: _open.contains(l),
                  onTap: () => _toggleLang(l),
                  label: _info(l)?.enLabel ?? l.toUpperCase(),
                ),
            ],
          ),
          for (final l in _open) _resultRow(c, l),
        ],
      ),
    );
  }

  /// جعبه‌ی ترجمه‌ی سفید زیرِ چیپ‌ها؛ 🔁 🧬 🔊 کنارِ متن (🔊 سمتِ راست)
  Widget _resultRow(AppThemeColorsExt c, String lang) {
    final text = _results[lang];
    final loading = _loading.contains(lang);
    final failed = _failed.contains(lang);
    final rtl = dirFor(lang) == TextDirection.rtl;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.cardBorder, width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: loading
                  ? Text('در حال ترجمه...',
                      style: TextStyle(color: c.inkSoft, fontSize: 13))
                  : failed || text == null
                      ? Text('ترجمه نشد — دوباره بزن',
                          style: TextStyle(color: c.rose, fontSize: 13))
                      : Directionality(
                          textDirection:
                              rtl ? TextDirection.rtl : TextDirection.ltr,
                          child: SelectableText(
                            text,
                            style: TextStyle(
                                color: c.ink, fontSize: 14, height: 1.6),
                          ),
                        ),
            ),
          ),
          if (!loading && (text != null || failed))
            InkResponse(
              onTap: () => _translate(lang, force: true),
              radius: 16,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.refresh,
                    size: 16,
                    color: failed ? c.rose : c.inkSoft.withOpacity(0.7)),
              ),
            ),
          if (text != null && !loading) ...[
            NeuralPathButton(
              onTap: () => showNeuralPath(
                context,
                word: text,
                langCode: lang,
                baseText: _plain(widget.text),
              ),
            ),
            InkResponse(
              onTap: () => _speak(text, lang),
              radius: 16,
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Icon(Icons.volume_up_outlined, size: 18, color: c.gold),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 🧬 و 🔊 که داخلِ کادرِ جوابِ AI، بالا سمتِ راست می‌نشینند (🔊 در لبه‌ی راست).
class AiBubbleActions extends ConsumerWidget {
  final String text;
  final String? sourceLang;
  const AiBubbleActions({super.key, required this.text, this.sourceLang});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final lang = sourceLang ?? ref.read(languageSelectionProvider).native;
    final plain = _AiAnswerToolsState._plain(text);
    if (plain.isEmpty) return const SizedBox.shrink();
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          NeuralPathButton(
            onTap: () => showNeuralPath(context,
                word: plain, langCode: lang, baseText: plain),
          ),
          InkResponse(
            onTap: () =>
                ref.read(speechControllerProvider.notifier).toggle(plain, lang),
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

/// چیپ‌ِ زبان — سفید و گرد؛ انتخاب‌شده: سبزِ تیره با متنِ سفید
class _Pill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool active;
  const _Pill({required this.label, required this.onTap, this.active = false});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? c.teal : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? c.teal : c.cardBorder),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : c.ink.withOpacity(0.85),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  final Color color;
  const _DashedLinePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + 4, 0), paint);
      x += 7;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter old) => old.color != color;
}
