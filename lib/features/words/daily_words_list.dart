import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/cefr_levels.dart';
import '../../core/models/daily_word.dart';
import '../../core/providers/conversation_provider.dart';
import '../../core/providers/language_selection_provider.dart';
import '../../core/providers/translation_provider.dart';
import '../../core/providers/words_filter_provider.dart';
import '../../core/theme/app_theme_colors.dart';

class DailyWordsList extends ConsumerWidget {
  const DailyWordsList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final words = ref.watch(filteredDailyWordsProvider);
    final all = ref.watch(allDailyWordsProvider);
    final sel = ref.watch(languageSelectionProvider);
    final filter = ref.watch(wordsFilterProvider);
    final notifier = ref.read(wordsFilterProvider.notifier);

    // زبان‌های نمایش (مادری + مقصدها بدون en)
    final langsToShow = <String>[
      if (sel.native != 'en') sel.native,
      ...sel.targets.where((t) => t != 'en'),
    ];

    return Column(
      children: [
        // ═══ فیلتر سطح + جستجو ═══
        Container(
          color: c.paper,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: 1 + kCefrLevels.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 7),
                  itemBuilder: (_, i) {
                    final lvl = i == 0 ? 'all' : kCefrLevels[i - 1];
                    final active = filter.level == lvl;
                    final label = lvl == 'all' ? 'همه سطوح' : lvl;
                    return GestureDetector(
                      onTap: () => notifier.setLevel(lvl),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: EdgeInsets.symmetric(
                          horizontal: lvl == 'all' ? 16 : 14,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: active ? c.headerFrom : Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: active ? c.headerFrom : c.cardBorder,
                            width: 1.1,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          label,
                          style: TextStyle(
                            color: active ? c.headerText : c.inkSoft,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              // Sort row
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: c.paperDark.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: c.cardBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.sort, size: 14, color: c.inkSoft),
                      const SizedBox(width: 6),
                      Text('مرتب‌سازی: پیش‌فرض',
                          style: TextStyle(
                              color: c.ink,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(width: 3),
                      Icon(Icons.keyboard_arrow_down, size: 14, color: c.inkSoft),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Search
              Container(
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.cardBorder, width: 1),
                ),
                child: TextField(
                  onChanged: notifier.setQuery,
                  textAlign: TextAlign.right,
                  style: TextStyle(color: c.ink, fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText: 'جستجوی لغت...',
                    hintStyle: TextStyle(
                        color: c.inkSoft.withOpacity(0.55), fontSize: 13.5),
                    prefixIcon: Icon(Icons.search, color: c.inkSoft, size: 19),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
            ],
          ),
        ),

        // ═══ لیست لغات ═══
        Expanded(
          child: words.isEmpty
              ? _EmptyState(c: c, hasData: all.isNotEmpty)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                  itemCount: words.length,
                  itemBuilder: (_, i) => _WordCard(
                    word: words[i],
                    langsToShow: langsToShow,
                  ),
                ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
class _EmptyState extends StatelessWidget {
  final dynamic c;
  final bool hasData;
  const _EmptyState({required this.c, required this.hasData});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.gold.withOpacity(0.10),
                border: Border.all(color: c.gold.withOpacity(0.3), width: 1.5),
              ),
              child: Icon(Icons.search_off, size: 32, color: c.gold),
            ),
            const SizedBox(height: 18),
            Text(
              hasData ? 'چیزی پیدا نشد' : 'داده‌ای بارگذاری نشد',
              style: TextStyle(
                color: c.ink,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              hasData
                  ? 'فیلتر سطح یا جستجو را تغییر بده.'
                  : 'فایل daily_words.json را چک کن.',
              style: TextStyle(color: c.inkSoft, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// کارت لغت — مطابق وب اپ
// ═══════════════════════════════════════════════════════════════════
class _WordCard extends StatefulWidget {
  final DailyWord word;
  final List<String> langsToShow;
  const _WordCard({required this.word, required this.langsToShow});

  @override
  State<_WordCard> createState() => _WordCardState();
}

class _WordCardState extends State<_WordCard> {
  bool _isFavorite = false;
  bool _showAiExamples = false;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final word = widget.word;
    final levelColor = _levelColor(word.level);

    return Container(
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
            // ═══ ردیف کلمه: [word] [B2] [شخصی] ... 🔊  ═══
            // چون اپ RTL است، Row معکوس میشه. پس کلمه رو در سمت چپ می‌خوایم.
            // با directionality LTR این ردیف رو چپ‌چین می‌کنیم.
            Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                children: [
                  // Word (LTR - natural for Latin)
                  Flexible(
                    child: Text(
                      word.en,
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
                      word.level,
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
                      _posFa(word.pos),
                      style: TextStyle(
                        color: c.inkSoft,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Speak icon (right side)
                  _IconButton(
                    icon: Icons.volume_up_outlined,
                    color: c.gold,
                    onTap: () {},
                    tooltip: 'پخش تلفظ',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // ═══ ردیف‌های ترجمه ═══
            ...widget.langsToShow.map(
              (code) => _TranslationRow(
                en: word.en,
                knownFa: word.fa,
                langCode: code,
                isFavorite: _isFavorite,
                onToggleFavorite: () =>
                    setState(() => _isFavorite = !_isFavorite),
              ),
            ),

            const SizedBox(height: 6),

            // ═══ مثال (با هوش مصنوعی) — دکمه‌ی راست‌چین ═══
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: _AiExamplesButton(
                onTap: () =>
                    setState(() => _showAiExamples = !_showAiExamples),
                expanded: _showAiExamples,
              ),
            ),

            // ═══ محتوای مثال AI (اگه باز بود) ═══
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

            // ═══ دکمه حذف (گوشه) ═══
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
// ردیف ترجمه — چپ‌چین با آیکون‌ها روی راست
// [FR]  saisi              🔄 🔊 ⭐ 🧬
// ═══════════════════════════════════════════════════════════════════
class _TranslationRow extends ConsumerWidget {
  final String en;
  final String knownFa;
  final String langCode;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;

  const _TranslationRow({
    required this.en,
    required this.knownFa,
    required this.langCode,
    required this.isFavorite,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;

    // فارسی — از دیتای JSON (بدون درخواست شبکه)
    if (langCode == 'fa' && knownFa.isNotEmpty) {
      return _row(context, c, knownFa);
    }

    final async = ref.watch(
      translationProvider(
          (text: en, to: langCode, from: 'en', verify: false)),
    );

    return async.when(
      loading: () => _row(context, c, 'در حال ترجمه...', loading: true),
      error: (_, __) => _row(context, c, '—', loading: true),
      data: (text) {
        if (text.isEmpty) return _row(context, c, '—', loading: true);
        return _row(context, c, text);
      },
    );
  }

  Widget _row(BuildContext context, dynamic c, String text,
      {bool loading = false}) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            // Language badge
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

            // Translated text (LTR container, but text content flows naturally)
            Expanded(
              child: Text(
                text,
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

            // Refresh
            _IconButton(
              icon: Icons.refresh,
              color: c.inkSoft,
              onTap: () {},
              size: 16,
              tooltip: 'ترجمه دوباره',
            ),
            // Speak
            _IconButton(
              icon: Icons.volume_up_outlined,
              color: c.gold,
              onTap: () {},
              size: 16,
              tooltip: 'پخش',
            ),
            // Favorite
            _IconButton(
              icon: isFavorite ? Icons.star : Icons.star_border,
              color: isFavorite
                  ? const Color(0xFFF5C518)
                  : c.inkSoft.withOpacity(0.4),
              onTap: onToggleFavorite,
              size: 18,
              tooltip: isFavorite ? 'حذف از علاقه‌مندی' : 'افزودن به علاقه‌مندی',
            ),
            // Neural path (🧬 → Icons.hub)
            _NeuralPathButton(
              onTap: () {},
              color: c.teal,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// دکمه‌ی آیکونی سبک برای ردیف
// ═══════════════════════════════════════════════════════════════════
class _IconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final double size;
  final String? tooltip;

  const _IconButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.size = 18,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final btn = Padding(
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
    return tooltip != null ? Tooltip(message: tooltip!, child: btn) : btn;
  }
}

// ═══════════════════════════════════════════════════════════════════
// دکمه‌ی مسیر عصبی — به‌جای 🧬 از Icons.hub استفاده می‌کنم
// (شبکه‌ی گره‌ای، شبیه نورون؛ واضح‌تر از DNA)
// ═══════════════════════════════════════════════════════════════════
class _NeuralPathButton extends StatelessWidget {
  final VoidCallback onTap;
  final Color color;

  const _NeuralPathButton({required this.onTap, required this.color});

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
// دکمه‌ی «مثال (با هوش مصنوعی)» — گوشه‌ی راست
// ═══════════════════════════════════════════════════════════════════
class _AiExamplesButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool expanded;

  const _AiExamplesButton({required this.onTap, required this.expanded});

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
          border: Border.all(
            color: c.gold.withOpacity(0.35),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 13, color: c.gold),
            const SizedBox(width: 5),
            Text(
              expanded
                  ? 'بستن مثال‌ها'
                  : 'مثال (با هوش مصنوعی)',
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
