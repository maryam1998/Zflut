import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_prefs_provider.dart';
import '../storage/local_storage.dart' show sharedPrefsProvider;
import '../theme/app_theme_colors.dart';

// ═══════════════════════════════════════════════════════════════════
// راهنمای «اولین استفاده» برای یک دکمه‌ی مشخص (نورافکن + کارتِ توضیح)
//
// اولین باری که کاربر روی دکمه می‌زند، همان دکمه روشن می‌شود و کارتِ توضیح
// می‌آید؛ بعد از «فهمیدم» کارِ دکمه ادامه پیدا می‌کند. فقط یک‌بار نشان داده
// می‌شود. متن‌ها به هر ۶ زبانِ برنامه (fa, en, es, de, fr, ar) هستند.
//
// استفاده:
//   final key = GlobalKey();                       // دورِ دکمه: KeyedSubtree(key: key, ...)
//   if (!await showFeatureCoach(context, ref,
//       id: CoachId.refreshTranslation, target: key)) return;
//   ... ادامه‌ی کارِ دکمه ...
// ═══════════════════════════════════════════════════════════════════

enum CoachId { refreshTranslation, generateStory }

class _Copy {
  final IconData icon;
  final Map<String, String> title;
  final Map<String, String> body;
  final Map<String, String> button;
  const _Copy(this.icon, this.title, this.body, this.button);
}

const Map<CoachId, _Copy> _copies = {
  CoachId.refreshTranslation: _Copy(
    Icons.refresh_rounded,
    {
      'en': 'Not happy with a translation?',
      'fa': 'ترجمه‌اش دقیق نیست؟',
      'es': '¿No te convence una traducción?',
      'de': 'Eine Übersetzung passt nicht?',
      'fr': 'Une traduction ne vous convient pas ?',
      'ar': 'هل الترجمة غير دقيقة؟',
    },
    {
      'en':
          'Tap this button and the AI translates this sentence again, more naturally. The better version replaces the old one and is remembered next time.',
      'fa':
          'این دکمه را بزن تا هوش مصنوعی همین جمله را دوباره و طبیعی‌تر ترجمه کند. نسخه‌ی بهتر جای قبلی می‌نشیند و دفعه‌ی بعد هم همان نمایش داده می‌شود.',
      'es':
          'Toca este botón y la IA volverá a traducir esta frase de forma más natural. La mejor versión sustituye a la anterior y se recuerda la próxima vez.',
      'de':
          'Tippe auf diese Schaltfläche, und die KI übersetzt diesen Satz noch einmal – natürlicher. Die bessere Version ersetzt die alte und wird für das nächste Mal gespeichert.',
      'fr':
          'Touchez ce bouton et l’IA retraduira cette phrase de façon plus naturelle. La meilleure version remplace l’ancienne et est mémorisée pour la prochaine fois.',
      'ar':
          'اضغط هذا الزر ليعيد الذكاء الاصطناعي ترجمة هذه الجملة بشكل أكثر طبيعية. تحلّ النسخة الأفضل محل القديمة وتُحفظ للمرة القادمة.',
    },
    {
      'en': 'Got it, try it',
      'fa': 'فهمیدم، امتحان کن',
      'es': 'Entendido, probar',
      'de': 'Verstanden, ausprobieren',
      'fr': 'Compris, essayer',
      'ar': 'فهمت، جرّب',
    },
  ),
  CoachId.generateStory: _Copy(
    Icons.auto_awesome,
    {
      'en': 'Your story, built from your words',
      'fa': 'داستانِ تو، از لغاتِ خودت',
      'es': 'Tu historia, hecha con tus palabras',
      'de': 'Deine Geschichte aus deinen Wörtern',
      'fr': 'Votre histoire, bâtie avec vos mots',
      'ar': 'قصتك من كلماتك',
    },
    {
      'en':
          'The AI writes a story that uses all the words you picked, at the level, language, type and length you chose. It takes a few seconds. The story is saved automatically in Saved, with translations added underneath.',
      'fa':
          'هوش مصنوعی داستانی می‌نویسد که همه‌ی لغاتِ انتخاب‌شده‌ات را با سطح، زبان، نوع و طولِ دلخواهت در خود دارد. چند ثانیه طول می‌کشد؛ داستان خودکار در بخشِ ذخیره‌شده‌ها ذخیره می‌شود و ترجمه‌ها زیرش اضافه می‌شود.',
      'es':
          'La IA escribe una historia que incluye todas las palabras que elegiste, con el nivel, idioma, tipo y longitud que has marcado. Tarda unos segundos. La historia se guarda sola en Guardadas y las traducciones aparecen debajo.',
      'de':
          'Die KI schreibt eine Geschichte, die alle gewählten Wörter enthält – in deinem Niveau, deiner Sprache, Art und Länge. Das dauert einige Sekunden. Die Geschichte wird automatisch unter „Gespeichert“ abgelegt, die Übersetzungen erscheinen darunter.',
      'fr':
          'L’IA écrit une histoire qui utilise tous les mots choisis, au niveau, dans la langue, le genre et la longueur que vous avez réglés. Cela prend quelques secondes. L’histoire est enregistrée automatiquement dans « Enregistrées » et les traductions s’affichent dessous.',
      'ar':
          'يكتب الذكاء الاصطناعي قصة تضم كل الكلمات التي اخترتها بالمستوى واللغة والنوع والطول الذي حددته. يستغرق ذلك بضع ثوانٍ؛ تُحفظ القصة تلقائيًا في «المحفوظات» وتظهر الترجمات تحتها.',
    },
    {
      'en': 'Got it, generate',
      'fa': 'فهمیدم، بساز',
      'es': 'Entendido, generar',
      'de': 'Verstanden, erstellen',
      'fr': 'Compris, générer',
      'ar': 'فهمت، أنشئ',
    },
  ),
};

String _prefKey(CoachId id) => 'zflut-coach-${id.name}-v1';

/// راهنمای اولین‌استفاده را (اگر قبلاً دیده نشده) نشان می‌دهد.
/// خروجی: true = کارِ دکمه ادامه پیدا کند (دیده‌شده/نشان‌دادنی نبود/«فهمیدم»)،
/// false = کاربر با دکمه‌ی برگشت بسته است و کار انجام نشود.
Future<bool> showFeatureCoach(
  BuildContext context,
  WidgetRef ref, {
  required CoachId id,
  required GlobalKey target,
}) async {
  final prefs = ref.read(sharedPrefsProvider);
  try {
    if (prefs.getBool(_prefKey(id)) ?? false) return true;
  } catch (_) {
    return true;
  }

  final ro = target.currentContext?.findRenderObject();
  if (ro is! RenderBox || !ro.attached || !ro.hasSize) return true;
  final size = MediaQuery.of(context).size;
  final rect = ro.localToGlobal(Offset.zero) & ro.size;
  final vis = rect.intersect(Offset.zero & size);
  if (vis.width < 6 || vis.height < 6) return true;

  final lang = ref.read(appPrefsProvider).uiLang;
  try {
    prefs.setBool(_prefKey(id), true);
  } catch (_) {}

  final ok = await showGeneralDialog<bool>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 220),
    transitionBuilder: (_, anim, __, child) =>
        FadeTransition(opacity: anim, child: child),
    pageBuilder: (ctx, _, __) => _CoachView(
      hole: vis,
      copy: _copies[id]!,
      lang: lang,
    ),
  );
  return ok ?? false;
}

class _CoachView extends StatefulWidget {
  final Rect hole;
  final _Copy copy;
  final String lang;
  const _CoachView(
      {required this.hole, required this.copy, required this.lang});

  @override
  State<_CoachView> createState() => _CoachViewState();
}

class _CoachViewState extends State<_CoachView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1500))
    ..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final lang = widget.lang;
    String t(Map<String, String> m) => m[lang] ?? m['en']!;
    final rtl = lang == 'fa' || lang == 'ar';
    final size = MediaQuery.of(context).size;
    final hole = widget.hole.inflate(6);
    final below = hole.center.dy < size.height * 0.5;

    return Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) => CustomPaint(
                    painter: _CoachPainter(
                        hole: hole, t: _pulse.value, color: c.gold),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              top: below ? math.max(hole.bottom + 16, 8.0) : null,
              bottom: below ? null : math.max(size.height - hole.top + 16, 8.0),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                    decoration: BoxDecoration(
                      color: c.paper,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: c.cardBorder),
                      boxShadow: const [
                        BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 16,
                            offset: Offset(0, 6)),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                  color: c.goldSoft, shape: BoxShape.circle),
                              child: Icon(widget.copy.icon,
                                  size: 22, color: c.gold),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                t(widget.copy.title),
                                style: TextStyle(
                                    color: c.ink,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t(widget.copy.body),
                          style: TextStyle(
                              color: c.ink, fontSize: 14, height: 1.65),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: c.gold,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () => Navigator.of(context).pop(true),
                            child: Text(
                              t(widget.copy.button),
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoachPainter extends CustomPainter {
  final Rect hole;
  final double t;
  final Color color;
  const _CoachPainter(
      {required this.hole, required this.t, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final aspect = hole.height == 0 ? 1.0 : hole.width / hole.height;
    final radius = (aspect > 0.8 && aspect < 1.25)
        ? hole.shortestSide / 2
        : math.min(hole.shortestSide / 2, 16.0);
    final rr = RRect.fromRectAndRadius(hole, Radius.circular(radius));

    final scrim = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(rr),
    );
    canvas.drawPath(scrim, Paint()..color = const Color(0xB8000000));

    for (var i = 0; i < 2; i++) {
      final ph = (t + i * 0.5) % 1.0;
      final a = ((1 - ph) * 0.85 * 255).round().clamp(0, 255);
      canvas.drawRRect(
        rr.inflate(2 + ph * 18),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = color.withAlpha(a),
      );
    }
    canvas.drawRRect(
      rr.inflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _CoachPainter old) =>
      old.hole != hole || old.t != t || old.color != color;
}
