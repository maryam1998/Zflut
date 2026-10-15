import 'package:flutter/gestures.dart'; // برای TapGestureRecognizer
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/level_colors.dart';
import '../constants/supported_languages.dart';
import '../player_sync/sync_widgets.dart';
import '../providers/ai_settings_provider.dart';
import '../providers/language_selection_provider.dart';
import '../providers/translation_provider.dart';
import '../theme/app_theme_colors.dart';
import '../translate/translation_service.dart';
import '../../features/reader/widgets/selection_popup.dart';

// ═══════════════════════════════════════════════════════════════════
// SyncItemCard — «کارتِ مشترک» برای همه‌ی تب‌ها
// ═══════════════════════════════════════════════════════════════════
class SyncItemCard extends ConsumerStatefulWidget {   // ✅ تغییر از StatefulWidget
  final String id;
  final String en;
  final String level;
  final String? pos;
  final bool isPersonal;
  final List<String> langsToShow;
  final Map<String, String> knownTranslations;
  final bool compact;
  final bool showActions;

  const SyncItemCard({
    super.key,
    required this.id,
    required this.en,
    required this.level,
    required this.langsToShow,
    this.pos,
    this.isPersonal = false,
    this.knownTranslations = const <String, String>{},
    this.compact = false,
    this.showActions = false,
  });

  @override
  ConsumerState<SyncItemCard> createState() => _SyncItemCardState();  // ✅ ConsumerState
}

class _SyncItemCardState extends ConsumerState<SyncItemCard> {   // ✅ ConsumerState
  bool _isFavorite = false;
  bool _showAiExamples = false;

  // ═══════════════════════════════════════════════════════════════════
  // تابع نمایش کادر پاپ‌آپ
  // ═══════════════════════════════════════════════════════════════════
  void _showPopup(
    BuildContext context,
    String word,
    String sentence,
    Offset globalPosition,
  ) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    final sel = ref.read(languageSelectionProvider);

    entry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // برای بستن کادر با کلیک بیرون
          Positioned.fill(
            child: GestureDetector(
              onTap: () => entry.remove(),
              behavior: HitTestBehavior.translucent,
            ),
          ),
          SelectionPopup(
            word: word,
            sentence: sentence,
            sourceLang: 'en',
            nativeLang: sel.native,
            targetLangs: sel.targets,
            position: globalPosition,
            onDismiss: () => entry.remove(),
          ),
        ],
      ),
    );

    overlay.insert(entry);
  }

  // ═══════════════════════════════════════════════════════════════════
  // ساخت متن با قابلیت کلیک روی تک‌کلمه‌ها
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildClickableText(
    String text,
    TextStyle style,
    String langCode,
    String sentence,
  ) {
    final words = text.split(RegExp(r'(\s+)'));
    final spans = <TextSpan>[];

    for (final word in words) {
      if (word.trim().isEmpty) {
        spans.add(TextSpan(text: word, style: style));
      } else {
        final recognizer = TapGestureRecognizer()
          ..onTapDown = (details) {
            _showPopup(context, word, sentence, details.globalPosition);
          };
        spans.add(
          TextSpan(text: word, recognizer: recognizer, style: style),
        );
      }
    }

    return Text.rich(TextSpan(children: spans));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final compact = widget.compact;
    final pos = widget.pos;

    return SyncAnchor(
      code: 'en',
      id: widget.id,
      child: Container(
        margin: EdgeInsets.only(bottom: compact ? 6 : 10),
        padding: compact
            ? const EdgeInsets.fromLTRB(10, 8, 10, 8)
            : const EdgeInsets.fromLTRB(14, 12, 14, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(compact ? 10 : 14),
          border: Border.all(color: c.cardBorder, width: compact ? 0.6 : 1),
          boxShadow: compact
              ? null
              : [
                  BoxShadow(
                    color: c.ink.withOpacity(0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ═══ ردیف اصلی: [سطح] متن … [نوع] [🔊] ═══
            Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                children: [
                  _Badge(
                    text: widget.level,
                    fg: levelColor(widget.level),
                    bg: levelBgColor(widget.level),
                    size: compact ? 10 : 11,
                  ),
                  const SizedBox(width: 8),

                  // ✅ متن اصلی کلیک‌پذیر + انتخاب محدوده
                  Expanded(
                    child: SelectionArea(
                      child: _buildClickableText(
                        widget.en,
                        TextStyle(
                          color: c.ink,
                          fontSize: compact ? 15 : 19,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                        'en',
                        widget.en,
                      ),
                    ),
                  ),

                  if (pos != null && pos.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    _Badge(text: pos, fg: c.inkSoft, bg: c.paperDark, size: 10),
                  ],
                  if (widget.isPersonal) ...[
                    const SizedBox(width: 6),
                    const _Badge(
                      text: 'شخصی',
                      fg: Color(0xFFA34960),
                      bg: Color(0x1FA34960),
                      size: 10,
                    ),
                  ],
                  SyncSpeakButton(
                    code: 'en',
                    id: widget.id,
                    text: widget.en,
                    color: c.gold,
                    size: 20,
                    padding: const EdgeInsets.all(4),
                  ),
                ],
              ),
            ),

            if (widget.langsToShow.isNotEmpty)
              SizedBox(height: compact ? 2 : 6),

            // ═══ ردیف‌های ترجمه ═══
            for (final code in widget.langsToShow)
              SyncTranslationRow(
                key: ValueKey('${widget.id}::$code'),
                itemId: widget.id,
                en: widget.en,
                langCode: code,
                knownText: widget.knownTranslations[code] ?? '',
                compact: compact,
                showActions: widget.showActions,
                isFavorite: _isFavorite,
                onToggleFavorite: () =>
                    setState(() => _isFavorite = !_isFavorite),
              ),

            if (widget.showActions) ...[
              const SizedBox(height: 6),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: AiExamplesButton(
                  onTap: () =>
                      setState(() => _showAiExamples = !_showAiExamples),
                  expanded: _showAiExamples,
                ),
              ),
              if (_showAiExamples) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: c.paperDark.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: c.cardBorder),
                  ),
                  child: Text(
                    'در حال ساخت مثال...',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.inkSoft, fontSize: 12),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// SyncTranslationRow — ردیفِ ترجمه‌ی برنامه
// ═══════════════════════════════════════════════════════════════════
class SyncTranslationRow extends ConsumerStatefulWidget {
  final String itemId;
  final String en;
  final String langCode;
  final String knownText;
  final bool compact;
  final bool showActions;
  final bool isFavorite;
  final VoidCallback? onToggleFavorite;

  const SyncTranslationRow({
    super.key,
    required this.itemId,
    required this.en,
    required this.langCode,
    this.knownText = '',
    this.compact = false,
    this.showActions = false,
    this.isFavorite = false,
    this.onToggleFavorite,
  });

  @override
  ConsumerState<SyncTranslationRow> createState() =>
      _SyncTranslationRowState();
}

class _SyncTranslationRowState extends ConsumerState<SyncTranslationRow> {
  static const int _maxAttempts = 2;

  String? _text;
  bool _failed = false;
  bool _retrying = false;
  bool _retryFailed = false;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant SyncTranslationRow old) {
    super.didUpdateWidget(old);
    if (old.en != widget.en ||
        old.langCode != widget.langCode ||
        old.knownText != widget.knownText) {
      _text = null;
      _failed = false;
      _retryFailed = false;
      _retrying = false;
      _resolve();
    }
  }

  @override
  void dispose() {
    _gen++;
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════
  // کادر پاپ‌آپ برای ترجمه
  // ═══════════════════════════════════════════════════════════════════
  void _showPopup(
    BuildContext context,
    String word,
    String sentence,
    Offset globalPosition,
  ) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    final sel = ref.read(languageSelectionProvider);

    entry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => entry.remove(),
              behavior: HitTestBehavior.translucent,
            ),
          ),
          SelectionPopup(
            word: word,
            sentence: sentence,
            sourceLang: widget.langCode,
            nativeLang: sel.native,
            targetLangs: sel.targets,
            position: globalPosition,
            onDismiss: () => entry.remove(),
          ),
        ],
      ),
    );

    overlay.insert(entry);
  }

  Widget _buildClickableText(
    String text,
    TextStyle style,
    String langCode,
    String sentence,
  ) {
    final words = text.split(RegExp(r'(\s+)'));
    final spans = <TextSpan>[];

    for (final word in words) {
      if (word.trim().isEmpty) {
        spans.add(TextSpan(text: word, style: style));
      } else {
        final recognizer = TapGestureRecognizer()
          ..onTapDown = (details) {
            _showPopup(context, word, sentence, details.globalPosition);
          };
        spans.add(
          TextSpan(text: word, recognizer: recognizer, style: style),
        );
      }
    }

    return Text.rich(TextSpan(children: spans));
  }

  bool _usable(String t) {
    final s = t.trim();
    if (s.isEmpty) return false;
    return !looksLikelyMistranslated(widget.en, s, widget.langCode,
        sourceLang: 'en');
  }

  void _resolve() {
    final gen = ++_gen;

    if (widget.knownText.isNotEmpty) {
      _text = widget.knownText;
      return;
    }

    final service = ref.read(translationServiceProvider);
    final hit = service.peekCached(widget.en, 'en', widget.langCode);
    if (hit != null && _usable(hit)) {
      _text = hit;
      return;
    }

    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted || gen != _gen) return;
      _fetch(gen, 0);
    });
  }

  Future<void> _fetch(int gen, int attempt) async {
    final service = ref.read(translationServiceProvider);
    final ai = ref.read(aiSettingsProvider);
    final en = widget.en;
    final code = widget.langCode;

    String? result;
    try {
      result = await service.translate(
        text: en,
        targetLang: code,
        sourceLang: 'en',
        aiSettings: ai,
      );
    } catch (_) {
      result = null;
    }
    if (!mounted || gen != _gen) return;

    final r = result;
    if (r != null && _usable(r)) {
      setState(() {
        _text = r.trim();
        _failed = false;
      });
      return;
    }

    if (attempt + 1 < _maxAttempts) {
      await Future.delayed(Duration(milliseconds: 1500 * (attempt + 1)));
      if (!mounted || gen != _gen) return;
      await _fetch(gen, attempt + 1);
      return;
    }

    setState(() => _failed = true);
  }

  Future<void> _retry() async {
    if (_retrying) return;
    final service = ref.read(translationServiceProvider);
    final ai = ref.read(aiSettingsProvider);
    final en = widget.en;
    final code = widget.langCode;
    final gen = ++_gen;

    setState(() {
      _retrying = true;
      _retryFailed = false;
    });

    String? result;
    try {
      result = await service.translateViaAI(en, code, 'en', ai);
    } catch (_) {
      result = null;
    }
    if (result == null || !_usable(result)) {
      try {
        result = await service.translate(
          text: en,
          targetLang: code,
          sourceLang: 'en',
          aiSettings: ai,
          forceVerify: true,
        );
      } catch (_) {
        result = null;
      }
    }
    if (!mounted || gen != _gen) return;

    final r = result;
    if (r != null && _usable(r)) {
      await service.cachePut(en, 'en', code, r.trim());
      if (!mounted || gen != _gen) return;
      setState(() {
        _text = r.trim();
        _failed = false;
        _retrying = false;
      });
    } else {
      setState(() {
        _retrying = false;
        if (_text == null) {
          _failed = true;
        } else {
          _retryFailed = true;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final text = _text;
    final loading = text == null && !_failed;
    final rtl = dirFor(widget.langCode) == TextDirection.rtl;

    if (text != null) {
      syncReportTranslation(context, ref, widget.langCode, widget.itemId, text);
    }

    final canRetry = widget.knownText.isEmpty && !loading;

    return SyncAnchor(
      code: widget.langCode,
      id: widget.itemId,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Padding(
          padding: EdgeInsets.only(top: widget.compact ? 4 : 3),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
              const SizedBox(width: 10),

              // ✅ متن ترجمه کلیک‌پذیر + انتخاب محدوده
              Expanded(
                child: text != null
                    ? SelectionArea(
                        child: Align(
                          alignment: rtl
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: _buildClickableText(
                            text,
                            TextStyle(
                              color: const Color(0xFF0F5C34),
                              fontSize: widget.compact ? 13 : 14,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                            widget.langCode,
                            widget.en,
                          ),
                        ),
                      )
                    : Text(
                        _failed ? 'ترجمه نشد — دوباره بزن' : 'در حال ترجمه...',
                        style: TextStyle(
                          color: _failed ? c.rose : c.inkSoft,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),

              if (_retryFailed)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    'جواب بهتری نیامد',
                    style: TextStyle(color: c.rose, fontSize: 10),
                  ),
                ),
              if (canRetry)
                _IconBtn(
                  onTap: _retrying ? null : _retry,
                  size: 16,
                  color: c.inkSoft.withOpacity(0.7),
                  child: _retrying
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 1.6, color: c.inkSoft),
                        )
                      : null,
                  icon: Icons.refresh,
                ),
              if (text != null)
                SyncSpeakButton(
                  code: widget.langCode,
                  id: widget.itemId,
                  text: text,
                  color: c.gold,
                  size: widget.compact ? 17 : 16,
                  padding: const EdgeInsets.all(5),
                ),
              if (widget.showActions && text != null) ...[
                _IconBtn(
                  icon: widget.isFavorite ? Icons.star : Icons.star_border,
                  color: widget.isFavorite
                      ? const Color(0xFFF5C518)
                      : c.inkSoft.withOpacity(0.4),
                  onTap: widget.onToggleFavorite,
                  size: 18,
                ),
                NeuralPathButton(onTap: () {}),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// اجزای کوچکِ مشترک
// ═══════════════════════════════════════════════════════════════════
class _Badge extends StatelessWidget {
  final String text;
  final Color fg;
  final Color bg;
  final double size;

  const _Badge({
    required this.text,
    required this.fg,
    required this.bg,
    this.size = 11,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fg,
          fontSize: size,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final double size;
  final Widget? child;

  const _IconBtn({
    required this.icon,
    required this.color,
    required this.onTap,
    this.size = 18,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: child ?? Icon(icon, size: size, color: color),
        ),
      ),
    );
  }
}

class NeuralPathButton extends StatelessWidget {
  final VoidCallback onTap;
  const NeuralPathButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'مسیر عصبی',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                const Color(0xFF8B7CF6).withOpacity(0.18),
                const Color(0xFF6366F1).withOpacity(0.10),
              ],
            ),
            border: Border.all(
              color: const Color(0xFF8B7CF6).withOpacity(0.35),
              width: 0.8,
            ),
          ),
          child: const Icon(
            Icons.hub_outlined,
            size: 14,
            color: Color(0xFF6366F1),
          ),
        ),
      ),
    );
  }
}

class AiExamplesButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool expanded;

  const AiExamplesButton({
    super.key,
    required this.onTap,
    required this.expanded,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: c.gold.withOpacity(0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.gold.withOpacity(0.35), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 13, color: c.gold),
            const SizedBox(width: 5),
            Text(
              expanded ? 'بستن مثال‌ها' : 'مثال (با هوش مصنوعی)',
              style: TextStyle(
                color: c.gold,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
