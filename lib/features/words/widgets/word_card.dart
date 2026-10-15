import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/player_sync/sync_widgets.dart';
import '../../../core/providers/translation_provider.dart';
import '../../../core/theme/app_theme_colors.dart';

// ═══════════════════════════════════════════════════════════════════
// WordCard — کامپوننت مشترک برای همه‌ی تب‌های لغت‌محور
// ═══════════════════════════════════════════════════════════════════
class WordCard extends StatefulWidget {
  final String id;
  final String en;
  final String fa;
  final String level;
  final String pos;
  final List<String> langsToShow;
  final bool isPersonal;
  final Map<String, String> knownTranslations;

  const WordCard({
    super.key,
    required this.id,
    required this.en,
    required this.fa,
    required this.level,
    required this.pos,
    required this.langsToShow,
    this.isPersonal = false,
    this.knownTranslations = const {},
  });

  @override
  State<WordCard> createState() => _WordCardState();
}

class _WordCardState extends State<WordCard> {
  bool _isFavorite = false;
  bool _showAiExamples = false;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final levelColor = _levelColor(widget.level);

    // SyncAnchor: اسکرولِ خودکارِ پلیر دقیقاً وسطِ همین کارت می‌ایستد
    return SyncAnchor(
      code: 'en',
      id: widget.id,
      child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.cardBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: c.ink.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ═══ ردیف کلمه ═══
            Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                children: [
                  Flexible(
                    child: SyncText(
                      code: 'en',
                      id: widget.id,
                      text: widget.en,
                      style: TextStyle(
                        color: c.ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                      textDirection: TextDirection.ltr,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Level badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: levelColor.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      widget.level,
                      style: TextStyle(
                        color: levelColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // POS badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: c.paperDark,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _posFa(widget.pos),
                      style: TextStyle(
                        color: c.inkSoft,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  // Personal badge
                  if (widget.isPersonal) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFA34960).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFFA34960).withOpacity(0.4),
                          width: 0.8,
                        ),
                      ),
                      child: const Text(
                        'شخصی',
                        style: TextStyle(
                          color: Color(0xFFA34960),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  SyncSpeakButton(
                    code: 'en',
                    id: widget.id,
                    text: widget.en,
                    color: c.gold,
                    size: 20,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // ═══ ردیف‌های ترجمه ═══
            ...widget.langsToShow.map(
              (code) => TranslationRow(
                itemId: widget.id,
                en: widget.en,
                knownText: code == 'fa' ? widget.fa : widget.knownTranslations[code],
                langCode: code,
                isFavorite: _isFavorite,
                onToggleFavorite: () =>
                    setState(() => _isFavorite = !_isFavorite),
              ),
            ),

            const SizedBox(height: 6),

            // ═══ دکمه‌ی مثال AI — راست‌چین ═══
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

            const SizedBox(height: 4),

            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: IconButton(
                onPressed: () {},
                icon: Icon(Icons.close, size: 16, color: c.inkSoft),
                splashRadius: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }

  static Color _levelColor(String level) {
    switch (level) {
      case 'A1': return const Color(0xFF2E9E7B);
      case 'A2': return const Color(0xFF4C7A8A);
      case 'B1': return const Color(0xFF7A5FA8);
      case 'B2': return const Color(0xFFA34960);
      case 'C1': return const Color(0xFFD9752E);
      case 'C2': return const Color(0xFF9E3B3B);
      default:   return const Color(0xFF4B5551);
    }
  }

  static String _posFa(String pos) {
    const map = {
      'noun': 'اسم', 'verb': 'فعل', 'adjective': 'صفت', 'adverb': 'قید',
      'preposition': 'حرف اضافه', 'pronoun': 'ضمیر',
      'conjunction': 'حرف ربط', 'article': 'حرف تعریف',
      'interjection': 'شبه‌جمله', 'numeral': 'عدد',
      'auxiliary': 'فعل کمکی', 'other': 'سایر',
      'determiner': 'حرف تعیین‌کننده', 'exclamation': 'صوت',
      'idiom': 'اصطلاح', 'slang': 'اسلنگ',
    };
    return map[pos] ?? pos;
  }
}

// ═══════════════════════════════════════════════════════════════════
// TranslationRow — مشترک
// ═══════════════════════════════════════════════════════════════════
class TranslationRow extends ConsumerWidget {
  /// شناسه‌ی آیتم (لغت/خط) در متنِ کاملِ پلیر — برای هایلایت/اسکرول/پرش
  final String? itemId;
  final String en;
  final String? knownText;
  final String langCode;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;

  const TranslationRow({
    super.key,
    this.itemId,
    required this.en,
    this.knownText,
    required this.langCode,
    required this.isFavorite,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;

    // اگه ترجمه‌ی آماده داریم (فارسی)
    if (knownText != null && knownText!.isNotEmpty) {
      return _buildRow(context, ref, c, knownText!);
    }

    final async = ref.watch(
      translationProvider(
          (text: en, to: langCode, from: 'en', verify: false)),
    );

    return async.when(
      loading: () =>
          _buildRow(context, ref, c, 'در حال ترجمه...', loading: true),
      error: (_, __) => _buildRow(context, ref, c, '—', loading: true),
      data: (text) {
        if (text.isEmpty) {
          return _buildRow(context, ref, c, '—', loading: true);
        }
        return _buildRow(context, ref, c, text);
      },
    );
  }

  Widget _buildRow(BuildContext context, WidgetRef ref, dynamic c, String text,
      {bool loading = false}) {
    final sid = itemId ?? '';
    // ترجمه آماده شد → به سیستمِ مشترکِ پلیر خبر بده تا «خواندنِ پیوسته‌ی
    // ترجمه‌ها» (متنِ کاملِ همین زبان) ساخته شود — مثل onResolveTranslation.
    if (!loading && itemId != null) {
      syncReportTranslation(context, ref, langCode, sid, text);
    }
    return SyncAnchor(
      code: langCode,
      id: sid,
      child: Directionality(
      textDirection: TextDirection.ltr,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: c.paperDark,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: c.cardBorder, width: 0.6),
              ),
              child: Text(
                langCode.toUpperCase(),
                style: TextStyle(
                  color: c.gold,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SyncText(
                code: langCode,
                id: sid,
                text: text,
                style: TextStyle(
                  color: loading ? c.inkSoft : const Color(0xFF0F5C34),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.left,
              ),
            ),
            _IconBtn(
              icon: Icons.refresh,
              color: c.inkSoft,
              onTap: () {},
              size: 16,
            ),
            SyncSpeakButton(
              code: langCode,
              id: sid,
              text: text,
              color: c.gold,
              size: 16,
              padding: const EdgeInsets.all(6),
            ),
            _IconBtn(
              icon: isFavorite ? Icons.star : Icons.star_border,
              color: isFavorite
                  ? const Color(0xFFF5C518)
                  : c.inkSoft.withOpacity(0.4),
              onTap: onToggleFavorite,
              size: 18,
            ),
            NeuralPathButton(onTap: () {}),
          ],
        ),
      ),
    ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final double size;

  const _IconBtn({
    required this.icon,
    required this.color,
    required this.onTap,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(icon, size: size, color: color),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
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

// ═══════════════════════════════════════════════════════════════════
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
