import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/ai_settings_provider.dart';
import '../providers/language_selection_provider.dart';
import '../providers/translation_provider.dart';

/// زبان‌هایی که ترجمه‌ی یک لغت باید به آن‌ها نشان داده شود:
/// زبان مادری + زبان‌های مقصدِ انتخابی، بدون تکرار، و بدون خودِ زبانِ لغت
/// (چون خودِ لغت همان زبان را نشان می‌دهد؛ مثلاً مادری = مقصد = آلمانی → یک‌بار).
List<String> wordTranslationLangs({
  required String native,
  required List<String> targets,
  required String wordLang,
}) {
  final out = <String>[];
  for (final c in [native, ...targets]) {
    final t = c.trim().toLowerCase();
    if (t.isEmpty || t == wordLang.toLowerCase() || out.contains(t)) continue;
    out.add(t);
  }
  return out;
}

final Map<String, String> _trCache = {};

TextDirection _dirOf(String s) =>
    RegExp(r'[\u0590-\u08FF]').hasMatch(s) ? TextDirection.rtl : TextDirection.ltr;

/// ترجمه‌ی یک لغت به همه‌ی زبان‌های مادری+مقصدِ انتخابی.
/// تا رسیدن ترجمه‌ها، معنیِ ذخیره‌شده ([fallback]) نشان داده می‌شود.
class WordTranslations extends ConsumerStatefulWidget {
  final String word;
  final String langCode;
  final String fallback;
  final TextStyle style;
  final bool centered;

  /// برچسب کوچک کدِ زبان (EN / FA ...) کنار هر ترجمه — فقط وقتی بیش از یک زبان باشد.
  final bool showLabels;

  const WordTranslations({
    super.key,
    required this.word,
    required this.langCode,
    required this.fallback,
    required this.style,
    this.centered = false,
    this.showLabels = true,
  });

  @override
  ConsumerState<WordTranslations> createState() => _WordTranslationsState();
}

class _WordTranslationsState extends ConsumerState<WordTranslations> {
  Map<String, String> _res = {};
  String _sig = '';
  int _gen = 0;

  Future<void> _load(List<String> langs) async {
    final gen = ++_gen;
    final svc = ref.read(translationServiceProvider);
    final ai = ref.read(aiSettingsProvider);
    final out = <String, String>{};
    for (final l in langs) {
      final key = '${widget.langCode}|$l|${widget.word}';
      var t = _trCache[key];
      if (t == null) {
        try {
          t = (await svc.translate(
            text: widget.word,
            targetLang: l,
            sourceLang: widget.langCode,
            aiSettings: ai,
          ))
              .trim();
        } catch (_) {
          t = '';
        }
        if (t.isNotEmpty) _trCache[key] = t;
      }
      if (t.isNotEmpty && t.toLowerCase() != widget.word.trim().toLowerCase()) {
        out[l] = t;
      }
      if (!mounted || gen != _gen) return;
    }
    if (!mounted || gen != _gen) return;
    setState(() => _res = out);
  }

  @override
  Widget build(BuildContext context) {
    final sel = ref.watch(languageSelectionProvider);
    final langs = wordTranslationLangs(
      native: sel.native,
      targets: sel.targets,
      wordLang: widget.langCode,
    );
    final sig = '${widget.word}|${widget.langCode}|${langs.join(',')}';
    if (sig != _sig) {
      _sig = sig;
      _res = {};
      if (langs.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && sig == _sig) _load(langs);
        });
      }
    }

    final fb = widget.fallback.trim();
    if (_res.isEmpty) {
      if (fb.isEmpty) return const SizedBox.shrink();
      return Text(fb,
          textAlign: widget.centered ? TextAlign.center : TextAlign.start,
          textDirection: _dirOf(fb),
          style: widget.style);
    }

    final labels = widget.showLabels && _res.length > 1;
    final lines = <Widget>[];
    for (final l in langs) {
      final t = _res[l];
      if (t == null) continue;
      final txt = Text(t,
          textAlign: widget.centered ? TextAlign.center : TextAlign.start,
          textDirection: _dirOf(t),
          style: widget.style);
      lines.add(labels
          ? Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(l.toUpperCase(),
                    style: widget.style.copyWith(
                        fontSize: (widget.style.fontSize ?? 12) * 0.6,
                        fontWeight: FontWeight.w700,
                        color: widget.style.color?.withOpacity(0.6))),
                const SizedBox(width: 6),
                Flexible(child: txt),
              ],
            )
          : txt);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          widget.centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: lines,
    );
  }
}
