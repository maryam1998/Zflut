import 'package:flutter/widgets.dart';

// ═══════════════════════════════════════════════════════════════════
// 🌍 متن‌های کارت‌ها/بنرهای «قفل Pro» به ۶ زبانِ اپ (en, fa, ar, de, es, fr)
//
// مستقل از فایل‌های ARB است (مثل review_i18n.dart / topic_titles.dart)، پس نیازی به
// gen-l10n ندارد. زبانِ ناشناخته ← انگلیسی. جای‌نگه‌دارها: {n} {free} {total} …
// برای زبان جدید فقط یک Map به [_all] اضافه کن.
// ═══════════════════════════════════════════════════════════════════

class ProI18n {
  ProI18n._();

  static const Map<String, String> _en = {
    'words_locked_title': '{n} more words locked',
    'in_scope': 'in “{scope}”',
    'words_progress': 'You can read {free} of {total} words',
    'locked_by_level': 'Locked by level',
    'locked_by_topic': 'Locked by topic',
    'words_cta': 'Unlock all words with Pro',
    'search_note':
        'Search only covers the free words. Go Pro to search all {total} words.',
    'search_empty_title': 'No free results for “{q}”',
    'perk_words': 'All {total} words in this section',
    'perk_levels': 'Every level, A1 to C2',
    'perk_search': 'Search the full library',
    'lines_unit': 'lines',
    'free_of': '{free} of {n}',
    'conv_banner_title': '{locked} dialogue lines in {topics} topics are locked',
    'conv_banner_title_short': '{locked} more lines locked',
    'conv_progress': 'You can read {free} of {total} lines',
    'conv_cta': 'Unlock all conversations with Pro',
    'conv_card_title': '{n} more lines locked',
    'conv_cta_levels': 'Unlock every level with Pro',
  };

  static const Map<String, String> _fa = {
    'words_locked_title': '{n} لغتِ دیگر قفل است',
    'in_scope': 'در «{scope}»',
    'words_progress': 'شما {free} از {total} لغت را می‌توانید بخوانید',
    'locked_by_level': 'قفل‌شده به‌تفکیکِ سطح',
    'locked_by_topic': 'قفل‌شده به‌تفکیکِ موضوع',
    'words_cta': 'باز کردنِ همه‌ی لغات با Pro',
    'search_note':
        'جستجو فقط روی لغاتِ رایگان کار می‌کند. با Pro در همه‌ی {total} لغت جستجو کنید.',
    'search_empty_title': 'نتیجه‌ی رایگانی برای «{q}» پیدا نشد',
    'perk_words': 'همه‌ی {total} لغتِ این بخش',
    'perk_levels': 'همه‌ی سطح‌ها، از A1 تا C2',
    'perk_search': 'جستجو در کلِ کتابخانه',
    'lines_unit': 'جمله',
    'free_of': '{free} از {n}',
    'conv_banner_title': '{locked} جمله‌ی مکالمه در {topics} موضوع قفل است',
    'conv_banner_title_short': '{locked} جمله‌ی دیگر قفل است',
    'conv_progress': 'شما {free} از {total} جمله را می‌توانید بخوانید',
    'conv_cta': 'باز کردنِ همه‌ی مکالمه‌ها با Pro',
    'conv_card_title': '{n} جمله‌ی دیگر قفل است',
    'conv_cta_levels': 'باز کردنِ همه‌ی سطح‌ها با Pro',
  };

  static const Map<String, String> _ar = {
    'words_locked_title': '{n} كلمة أخرى مقفلة',
    'in_scope': 'في «{scope}»',
    'words_progress': 'يمكنك قراءة {free} من أصل {total} كلمة',
    'locked_by_level': 'مقفلة حسب المستوى',
    'locked_by_topic': 'مقفلة حسب الموضوع',
    'words_cta': 'افتح جميع الكلمات مع Pro',
    'search_note':
        'البحث يشمل الكلمات المجانية فقط. مع Pro تبحث في جميع الكلمات ({total}).',
    'search_empty_title': 'لا توجد نتائج مجانية لـ «{q}»',
    'perk_words': 'جميع كلمات هذا القسم ({total})',
    'perk_levels': 'كل المستويات، من A1 إلى C2',
    'perk_search': 'البحث في المكتبة كاملة',
    'lines_unit': 'جملة',
    'free_of': '{free} من {n}',
    'conv_banner_title': '{locked} جملة حوار في {topics} موضوعًا مقفلة',
    'conv_banner_title_short': '{locked} جملة أخرى مقفلة',
    'conv_progress': 'يمكنك قراءة {free} من أصل {total} جملة',
    'conv_cta': 'افتح جميع المحادثات مع Pro',
    'conv_card_title': '{n} جملة أخرى مقفلة',
    'conv_cta_levels': 'افتح كل المستويات مع Pro',
  };

  static const Map<String, String> _de = {
    'words_locked_title': '{n} weitere Wörter gesperrt',
    'in_scope': 'in „{scope}“',
    'words_progress': 'Du kannst {free} von {total} Wörtern lesen',
    'locked_by_level': 'Nach Niveau gesperrt',
    'locked_by_topic': 'Nach Thema gesperrt',
    'words_cta': 'Alle Wörter mit Pro freischalten',
    'search_note':
        'Die Suche umfasst nur die kostenlosen Wörter. Mit Pro durchsuchst du alle {total} Wörter.',
    'search_empty_title': 'Keine kostenlosen Treffer für „{q}“',
    'perk_words': 'Alle {total} Wörter in diesem Bereich',
    'perk_levels': 'Alle Niveaus, von A1 bis C2',
    'perk_search': 'Die gesamte Bibliothek durchsuchen',
    'lines_unit': 'Sätze',
    'free_of': '{free} von {n}',
    'conv_banner_title': '{locked} Dialogsätze in {topics} Themen sind gesperrt',
    'conv_banner_title_short': '{locked} weitere Sätze gesperrt',
    'conv_progress': 'Du kannst {free} von {total} Sätzen lesen',
    'conv_cta': 'Alle Gespräche mit Pro freischalten',
    'conv_card_title': '{n} weitere Sätze gesperrt',
    'conv_cta_levels': 'Alle Niveaus mit Pro freischalten',
  };

  static const Map<String, String> _es = {
    'words_locked_title': '{n} palabras más bloqueadas',
    'in_scope': 'en «{scope}»',
    'words_progress': 'Puedes leer {free} de {total} palabras',
    'locked_by_level': 'Bloqueado por nivel',
    'locked_by_topic': 'Bloqueado por tema',
    'words_cta': 'Desbloquea todas las palabras con Pro',
    'search_note':
        'La búsqueda solo incluye las palabras gratuitas. Con Pro buscas en las {total} palabras.',
    'search_empty_title': 'Sin resultados gratuitos para «{q}»',
    'perk_words': 'Las {total} palabras de esta sección',
    'perk_levels': 'Todos los niveles, de A1 a C2',
    'perk_search': 'Busca en toda la biblioteca',
    'lines_unit': 'frases',
    'free_of': '{free} de {n}',
    'conv_banner_title':
        '{locked} frases de diálogo en {topics} temas están bloqueadas',
    'conv_banner_title_short': '{locked} frases más bloqueadas',
    'conv_progress': 'Puedes leer {free} de {total} frases',
    'conv_cta': 'Desbloquea todas las conversaciones con Pro',
    'conv_card_title': '{n} frases más bloqueadas',
    'conv_cta_levels': 'Desbloquea todos los niveles con Pro',
  };

  static const Map<String, String> _fr = {
    'words_locked_title': '{n} mots de plus verrouillés',
    'in_scope': 'dans « {scope} »',
    'words_progress': 'Vous pouvez lire {free} mots sur {total}',
    'locked_by_level': 'Verrouillé par niveau',
    'locked_by_topic': 'Verrouillé par thème',
    'words_cta': 'Débloquez tous les mots avec Pro',
    'search_note':
        'La recherche ne couvre que les mots gratuits. Avec Pro, cherchez dans les {total} mots.',
    'search_empty_title': 'Aucun résultat gratuit pour « {q} »',
    'perk_words': 'Les {total} mots de cette section',
    'perk_levels': 'Tous les niveaux, de A1 à C2',
    'perk_search': 'Recherchez dans toute la bibliothèque',
    'lines_unit': 'phrases',
    'free_of': '{free} sur {n}',
    'conv_banner_title':
        '{locked} phrases de dialogue dans {topics} thèmes sont verrouillées',
    'conv_banner_title_short': '{locked} phrases de plus verrouillées',
    'conv_progress': 'Vous pouvez lire {free} phrases sur {total}',
    'conv_cta': 'Débloquez toutes les conversations avec Pro',
    'conv_card_title': '{n} phrases de plus verrouillées',
    'conv_cta_levels': 'Débloquez tous les niveaux avec Pro',
  };

  static const Map<String, Map<String, String>> _all = {
    'en': _en,
    'fa': _fa,
    'ar': _ar,
    'de': _de,
    'es': _es,
    'fr': _fr,
  };

  /// متنِ [key] به زبانِ رابط؛ [args] جای‌نگه‌دارهای {name} را پر می‌کند.
  static String t(BuildContext context, String key,
      [Map<String, Object> args = const <String, Object>{}]) {
    final lang = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
    var s = (_all[lang] ?? _en)[key] ?? _en[key] ?? key;
    for (final e in args.entries) {
      s = s.replaceAll('{${e.key}}', '${e.value}');
    }
    return s;
  }
}
