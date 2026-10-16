import 'package:flutter/material.dart';

import '../../../core/widgets/sync_item_card.dart';

// اجزای قدیمی از همین مسیر هم در دسترس می‌مانند
export '../../../core/widgets/sync_item_card.dart'
    show AiExamplesButton, NeuralPathButton;

// ═══════════════════════════════════════════════════════════════════
// WordCard — فقط یک پوسته‌ی نازک روی کارتِ مشترکِ برنامه (SyncItemCard).
// ظاهر، ترجمه، هایلایت و اسکرول همه در همان کارتِ مشترک‌اند و با
// تبِ مکالمات یکسان کار می‌کنند.
// ═══════════════════════════════════════════════════════════════════
class WordCard extends StatelessWidget {
  final String id;
  final String en;
  final String fa;
  final String level;
  final String pos;
  final List<String> langsToShow;
  final bool isPersonal;
  final Map<String, String> knownTranslations;

  /// ✕ برای لغات شخصی (فقط از تبِ دیکشنری من پنهان می‌کند).
  final VoidCallback? onRemove;

  const WordCard({
    super.key,
    required this.id,
    required this.en,
    required this.fa,
    required this.level,
    required this.pos,
    required this.langsToShow,
    this.isPersonal = false,
    this.knownTranslations = const <String, String>{},
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final known = <String, String>{...knownTranslations};
    if (fa.isNotEmpty && !known.containsKey('fa')) known['fa'] = fa;

    return SyncItemCard(
      id: id,
      en: en,
      level: level,
      pos: _posFa(pos),
      isPersonal: isPersonal,
      langsToShow: langsToShow,
      knownTranslations: known,
      compact: false,
      showActions: true,
      onRemove: onRemove,
    );
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
