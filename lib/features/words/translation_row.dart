import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/supported_languages.dart';
import '../../core/providers/ai_settings_provider.dart';
import '../../core/providers/translation_provider.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../core/translate/translation_service.dart';

/// یک ردیف ترجمه‌ی یک متن به یک زبان — معادلِ WordTargetTranslation وب:
///  • اگر ترجمه از قبل معلوم است ([knownText]، مثلاً فارسیِ دیتا) همان را نشان می‌دهد
///  • وگرنه از کش/زنجیره‌ی ترجمه (TranslationService.translate) می‌گیرد
///  • دکمه‌ی «ترجمه‌ی دوباره»: اول مستقیم AI، بعد زنجیره با forceVerify
class TranslationRow extends ConsumerStatefulWidget {
  final String text;
  final String langCode;
  final String sourceLang;
  final String knownText;
  final bool forceVerify;

  const TranslationRow({
    super.key,
    required this.text,
    required this.langCode,
    this.sourceLang = 'en',
    this.knownText = '',
    this.forceVerify = false,
  });

  @override
  ConsumerState<TranslationRow> createState() => _TranslationRowState();
}

class _TranslationRowState extends ConsumerState<TranslationRow> {
  String? _text;
  bool _retrying = false;
  bool _retryFailed = false;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TranslationRow old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text ||
        old.langCode != widget.langCode ||
        old.sourceLang != widget.sourceLang ||
        old.knownText != widget.knownText) {
      _text = null;
      _retryFailed = false;
      _load();
    }
  }

  @override
  void dispose() {
    _gen++;
    super.dispose();
  }

  void _load() {
    final gen = ++_gen;
    if (widget.knownText.isNotEmpty) {
      _text = widget.knownText;
      return;
    }
    final service = ref.read(translationServiceProvider);
    final ai = ref.read(aiSettingsProvider);
    service
        .translate(
          text: widget.text,
          targetLang: widget.langCode,
          sourceLang: widget.sourceLang,
          aiSettings: ai,
          forceVerify: widget.forceVerify,
        )
        .then((t) {
      if (!mounted || gen != _gen || t.isEmpty) return;
      setState(() => _text = t);
    }).catchError((_) {});
  }

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() {
      _retrying = true;
      _retryFailed = false;
    });
    final service = ref.read(translationServiceProvider);
    final ai = ref.read(aiSettingsProvider);
    try {
      String? result;
      try {
        result = await service.translateViaAI(
            widget.text, widget.langCode, widget.sourceLang, ai);
      } catch (_) {
        result = null;
      }
      result ??= await service.translate(
        text: widget.text,
        targetLang: widget.langCode,
        sourceLang: widget.sourceLang,
        aiSettings: ai,
        forceVerify: true,
      );
      if (result.trim().isNotEmpty &&
          !looksLikelyMistranslated(widget.text, result, widget.langCode,
              sourceLang: widget.sourceLang)) {
        await service.cachePut(
            widget.text, widget.sourceLang, widget.langCode, result);
        if (mounted) setState(() => _text = result);
      } else if (mounted) {
        setState(() => _retryFailed = true);
      }
    } catch (_) {
      if (mounted) setState(() => _retryFailed = true);
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final loading = _text == null;
    final showRetry = !loading && widget.knownText.isEmpty;

    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
              color: c.paperDark,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: c.cardBorder, width: 0.6),
            ),
            child: Text(
              widget.langCode.toUpperCase(),
              style: TextStyle(
                color: c.gold,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.4,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              loading ? 'در حال ترجمه...' : _text!,
              textDirection: loading ? null : dirFor(widget.langCode),
              style: TextStyle(
                color: loading ? c.inkSoft : const Color(0xFF0F5C34),
                fontSize: loading ? 12 : 13,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
          if (showRetry)
            GestureDetector(
              onTap: _retrying ? null : _retry,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 1, 2, 1),
                child: _retrying
                    ? SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.6, color: c.inkSoft),
                      )
                    : Icon(Icons.refresh,
                        size: 15, color: c.inkSoft.withOpacity(0.6)),
              ),
            ),
          if (_retryFailed)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                'هنوز جواب درست نگرفتیم',
                style: TextStyle(color: c.rose, fontSize: 10),
              ),
            ),
        ],
      ),
    );
  }
}
