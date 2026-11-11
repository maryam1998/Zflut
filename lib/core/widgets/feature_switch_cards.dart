// 📁 مسیر: lib/core/widgets/feature_switch_cards.dart
//
// کارت‌های آیکون‌دارِ حرفه‌ای برای زیرتب‌های «داستان‌ساز» و «مکالمه‌ی AI».
// هر کارت: آیکونِ گرادیانی + عنوان + یک جمله‌ی کوتاه که ارزشِ قابلیت را نشان می‌دهد.
// ویجتِ مستقل است و هیچ منطقِ دیگری را تغییر نمی‌دهد.

import 'package:flutter/material.dart';

import '../theme/app_theme_colors.dart';

class FeatureCardItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final int? count; // نشانِ تعداد (مثلاً تعداد داستان‌های ذخیره‌شده)
  final bool ai;
  const FeatureCardItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.count,
    this.ai = false,
  });
}

class FeatureSwitchCards extends StatelessWidget {
  final List<FeatureCardItem> items;
  final int selected;
  final ValueChanged<int> onSelect;
  final int columns;

  const FeatureSwitchCards({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelect,
    this.columns = 2,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += columns) {
      final cells = <Widget>[];
      for (var j = 0; j < columns; j++) {
        final idx = i + j;
        if (j > 0) cells.add(const SizedBox(width: 10));
        cells.add(Expanded(
          child: idx < items.length
              ? _FeatureCard(
                  item: items[idx],
                  active: idx == selected,
                  onTap: () => onSelect(idx),
                )
              : const SizedBox.shrink(),
        ));
      }
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 10));
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: cells,
        ),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}

class _FeatureCard extends StatelessWidget {
  final FeatureCardItem item;
  final bool active;
  final VoidCallback onTap;
  const _FeatureCard(
      {required this.item, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final Color gold = c.gold;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: active ? c.goldSoft : c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: active ? gold : c.cardBorder,
          width: active ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: active
                ? gold.withOpacity(0.35)
                : Colors.black.withOpacity(0.05),
            blurRadius: active ? 12 : 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: active
                              ? [gold, gold.withOpacity(0.72)]
                              : [
                                  gold.withOpacity(0.20),
                                  gold.withOpacity(0.08),
                                ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(item.icon,
                          size: 23, color: active ? c.headerTo : gold),
                    ),
                    if (item.count != null)
                      PositionedDirectional(
                        top: -6,
                        end: -10,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 18),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: c.rose,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            '${item.count}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        item.title,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (item.ai) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [Color(0xFF8B7CF6), Color(0xFF6366F1)]),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Text('AI',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.4)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  item.subtitle,
                  maxLines: 3,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.inkSoft,
                    fontSize: 10.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// جمله‌های ارزش‌محورِ زیر هر کارت (۶ زبانِ اپ).
class FeatureCardTexts {
  static const Map<String, Map<String, String>> _t = {
    'story_create': {
      'fa': 'داستانِ اختصاصی با لغاتِ خودت، هم‌سطحِ تو',
      'en': 'A custom story built from your words, at your level',
      'es': 'Un cuento a medida con tus palabras y tu nivel',
      'de': 'Eine eigene Geschichte aus deinen Wörtern, auf deinem Niveau',
      'fr': 'Une histoire sur mesure avec tes mots, à ton niveau',
      'ar': 'قصة مخصّصة من كلماتك وبمستواك',
    },
    'story_import': {
      'fa': 'هر متن، کتاب یا PDF را با ترجمه بخوان',
      'en': 'Read any text, book or PDF with translation',
      'es': 'Lee cualquier texto, libro o PDF con traducción',
      'de': 'Lies jeden Text, jedes Buch oder PDF mit Übersetzung',
      'fr': 'Lis tout texte, livre ou PDF avec traduction',
      'ar': 'اقرأ أي نص أو كتاب أو PDF مع الترجمة',
    },
    'story_library': {
      'fa': 'همه‌ی داستان‌ها و کتاب‌هایت، همیشه در دسترس',
      'en': 'All your stories and books, always at hand',
      'es': 'Todos tus cuentos y libros, siempre a mano',
      'de': 'Alle deine Geschichten und Bücher, immer griffbereit',
      'fr': 'Toutes tes histoires et livres, toujours à portée',
      'ar': 'كل قصصك وكتبك في متناول يدك دائمًا',
    },
    'story_saved': {
      'fa': 'لغاتِ ذخیره‌شده برای داستانِ بعدی',
      'en': 'Saved words queued for your next story',
      'es': 'Palabras guardadas para tu próximo cuento',
      'de': 'Gespeicherte Wörter für deine nächste Geschichte',
      'fr': 'Mots enregistrés pour ta prochaine histoire',
      'ar': 'كلمات محفوظة لقصتك القادمة',
    },
    'talk_chat': {
      'fa': 'گفتگو با Jimmy؛ اصلاحِ فوریِ اشتباه‌ها و توضیح',
      'en': 'Chat with Jimmy: instant corrections & explanations',
      'es': 'Habla con Jimmy: correcciones y explicaciones al instante',
      'de': 'Chatte mit Jimmy: sofortige Korrekturen & Erklärungen',
      'fr': 'Discute avec Jimmy : corrections et explications instantanées',
      'ar': 'تحدّث مع Jimmy: تصحيح وشرح فوري للأخطاء',
    },
    'talk_history': {
      'fa': 'مکالمه‌های ذخیره‌شده؛ ادامه بده و مرور کن',
      'en': 'Saved chats: continue and review any time',
      'es': 'Chats guardados: continúa y repasa cuando quieras',
      'de': 'Gespeicherte Chats: jederzeit fortsetzen und wiederholen',
      'fr': 'Chats enregistrés : reprends et révise à tout moment',
      'ar': 'محادثات محفوظة: تابعها وراجعها في أي وقت',
    },
  };

  static String of(BuildContext context, String key) {
    final lang = Localizations.localeOf(context).languageCode;
    final m = _t[key]!;
    return m[lang] ?? m['en']!;
  }
}
