import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/category_icons.dart';
import '../constants/topic_icons.dart' show TopicVisual, badgeBgColor;
import '../theme/app_theme_colors.dart';
import '../usage/pro_i18n.dart';

/// 🗂️ شبکه‌ی دسته‌های تب‌های لغات (دیکشنری من / Vocab in use / Slang).
/// هم‌استایلِ کارت‌های تب مکالمه: ۳ ستون، آیکونِ گرد، نامِ دسته (حداکثر ۲ خط) و تعدادِ لغت.

/// «همه» برای هر لیست جدا: true = لیستِ کاملِ لغات (بدونِ دسته) باز است.
final categoryAllOpenProvider =
    StateProvider.family<bool, String>((ref, listId) => false);

class CategoryItem {
  /// کلیدِ دسته؛ null = کارتِ «همه»
  final String? key;
  final String label;
  final int total;

  /// تعدادِ لغاتِ بازِ کاربرِ رایگان (برای Pro = null)
  final int? free;
  const CategoryItem({
    required this.key,
    required this.label,
    required this.total,
    this.free,
  });
}

String _wordsUnit(BuildContext context) {
  switch (Localizations.localeOf(context).languageCode) {
    case 'fa':
      return 'لغت';
    case 'ar':
      return 'كلمة';
    case 'de':
      return 'Wörter';
    case 'es':
      return 'palabras';
    case 'fr':
      return 'mots';
    default:
      return 'words';
  }
}

String categoriesBackLabel(BuildContext context) {
  switch (Localizations.localeOf(context).languageCode) {
    case 'fa':
      return 'بازگشت به دسته‌ها';
    case 'ar':
      return 'العودة إلى الفئات';
    case 'de':
      return 'Zurück zu den Kategorien';
    case 'es':
      return 'Volver a las categorías';
    case 'fr':
      return 'Retour aux catégories';
    default:
      return 'Back to categories';
  }
}

class CategoryGrid extends StatelessWidget {
  /// 'daily' | 'slang' | 'vocab' — فقط برای انتخابِ آیکون
  final String list;
  final List<CategoryItem> items;
  final ValueChanged<String?> onTap;
  const CategoryGrid({
    super.key,
    required this.list,
    required this.items,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 90),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.72,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final it = items[i];
          return _CategoryCard(
            item: it,
            visual: it.key == null
                ? kAllCategoriesVisual
                : categoryVisual(list, it.key!),
            onTap: () => onTap(it.key),
          );
        },
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final CategoryItem item;
  final TopicVisual visual;
  final VoidCallback onTap;
  const _CategoryCard({
    required this.item,
    required this.visual,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final Color color = visual.color;
    final IconData icon = visual.icon;
    final free = item.free;
    final fullyLocked = free != null && free <= 0 && item.total > 0;
    final partial = free != null && free > 0 && free < item.total;

    Widget footer;
    if (fullyLocked) {
      footer = _pill(c, c.gold, Icons.lock, '${item.total}');
    } else if (partial) {
      footer = _pill(c, c.teal, Icons.lock_open,
          ProI18n.t(context, 'free_of', {'free': free!, 'n': item.total}));
    } else {
      footer = Text(
        '${item.total} ${_wordsUnit(context)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            color: c.inkSoft, fontSize: 11, fontWeight: FontWeight.w600),
      );
    }

    final BoxDecoration deco = fullyLocked
        ? BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [c.goldSoft.withOpacity(0.55), c.surface],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.gold.withOpacity(0.55), width: 1.1),
          )
        : BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.cardBorder, width: 1),
          );

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 14, 6, 8),
              decoration: deco,
              child: Column(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: fullyLocked
                          ? c.gold.withOpacity(0.14)
                          : badgeBgColor(color),
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon,
                        size: 24,
                        color: fullyLocked ? color.withOpacity(0.8) : color),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Text(
                        item.label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          height: 1.22,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(height: 20, child: Center(child: footer)),
                ],
              ),
            ),
          ),
          if (fullyLocked)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.gold,
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.lock, size: 12, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pill(dynamic c, Color color, IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: color, fontSize: 10.5, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

/// نوارِ «بازگشت به دسته‌ها» + نامِ دسته‌ی بازشده (بالای لیستِ لغات)
class CategoryBackBar extends StatelessWidget {
  final String list;
  final String? categoryKey;
  final String label;
  final VoidCallback onBack;
  const CategoryBackBar({
    super.key,
    required this.list,
    required this.categoryKey,
    required this.label,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final v = categoryKey == null
        ? kAllCategoriesVisual
        : categoryVisual(list, categoryKey!);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Row(
        children: [
          InkWell(
            onTap: onBack,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_back, size: 18, color: c.teal),
                  const SizedBox(width: 6),
                  Text(categoriesBackLabel(context),
                      style: TextStyle(
                          color: c.teal,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
          const Spacer(),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: badgeBgColor(v.color),
            ),
            alignment: Alignment.center,
            child: Icon(v.icon, size: 16, color: v.color),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: c.ink, fontSize: 13.5, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
