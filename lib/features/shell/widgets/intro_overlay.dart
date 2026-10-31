import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_prefs_provider.dart';
import '../../../core/storage/local_storage.dart' show sharedPrefsProvider;
import '../../../core/theme/app_theme_colors.dart';

const String _kIntroSeenKey = 'zflut-intro-seen-v1';

class _IntroPage {
  final IconData icon;
  final Map<String, String> title;
  final Map<String, String> body;
  const _IntroPage(this.icon, this.title, this.body);
}

const List<_IntroPage> _pages = [
  _IntroPage(
    Icons.translate_rounded,
    {
      'en': 'Pick your languages',
      'fa': 'زبان‌هایت را انتخاب کن',
      'es': 'Elige tus idiomas',
      'de': 'Wähle deine Sprachen',
      'fr': 'Choisis tes langues',
      'ar': 'اختر لغاتك',
    },
    {
      'en': 'Set your native language and one or more target languages at the top. Everything in the app follows them.',
      'fa': 'در بالای صفحه زبان مادری و یک یا چند زبان مقصد را انتخاب کن. همه‌ی بخش‌های برنامه از همین انتخاب پیروی می‌کنند.',
      'es': 'Elige tu idioma nativo y uno o más idiomas de destino arriba. Toda la app los sigue.',
      'de': 'Wähle oben deine Muttersprache und eine oder mehrere Zielsprachen. Die ganze App richtet sich danach.',
      'fr': 'Choisis ta langue maternelle et une ou plusieurs langues cibles en haut. Toute l’appli les suit.',
      'ar': 'اختر لغتك الأم ولغة هدف أو أكثر في الأعلى. يتبع التطبيق كله اختيارك.',
    },
  ),
  _IntroPage(
    Icons.touch_app_rounded,
    {
      'en': 'Tap any word',
      'fa': 'روی هر کلمه بزن',
      'es': 'Toca cualquier palabra',
      'de': 'Tippe auf ein Wort',
      'fr': 'Touche un mot',
      'ar': 'المس أي كلمة',
    },
    {
      'en': 'Tap a word or sentence to see its translation, hear it, and save it for your next story or for review.',
      'fa': 'روی کلمه یا جمله بزن تا ترجمه‌اش را ببینی، تلفظش را بشنوی و آن را برای داستان بعدی یا مرور ذخیره کنی.',
      'es': 'Toca una palabra o frase para ver su traducción, escucharla y guardarla para tu próxima historia o repaso.',
      'de': 'Tippe auf ein Wort oder einen Satz, um die Übersetzung zu sehen, es zu hören und für die nächste Geschichte oder Wiederholung zu speichern.',
      'fr': 'Touche un mot ou une phrase pour voir sa traduction, l’écouter et l’enregistrer pour ta prochaine histoire ou ta révision.',
      'ar': 'المس كلمة أو جملة لترى ترجمتها وتسمعها وتحفظها لقصتك القادمة أو للمراجعة.',
    },
  ),
  _IntroPage(
    Icons.auto_stories_rounded,
    {
      'en': 'Build your own story',
      'fa': 'داستان خودت را بساز',
      'es': 'Crea tu propia historia',
      'de': 'Erstelle deine Geschichte',
      'fr': 'Crée ta propre histoire',
      'ar': 'أنشئ قصتك الخاصة',
    },
    {
      'en': 'In Story, choose a level and topic, add the words you want to practise, and get a story with translations and audio.',
      'fa': 'در بخش داستان، سطح و موضوع را انتخاب کن، لغت‌های دلخواهت را اضافه کن و داستانی با ترجمه و صدا بگیر.',
      'es': 'En Historia, elige nivel y tema, añade las palabras que quieras practicar y recibe una historia con traducciones y audio.',
      'de': 'Wähle unter Geschichte Niveau und Thema, füge Wörter zum Üben hinzu und erhalte eine Geschichte mit Übersetzungen und Audio.',
      'fr': 'Dans Histoire, choisis un niveau et un thème, ajoute les mots à pratiquer et obtiens une histoire avec traductions et audio.',
      'ar': 'في القصة، اختر المستوى والموضوع وأضف الكلمات التي تريد التدرّب عليها لتحصل على قصة مع ترجمات وصوت.',
    },
  ),
  _IntroPage(
    Icons.check_circle_outline_rounded,
    {
      'en': 'Review and remember',
      'fa': 'مرور کن و به خاطر بسپار',
      'es': 'Repasa y recuerda',
      'de': 'Wiederholen und merken',
      'fr': 'Révise et retiens',
      'ar': 'راجع وتذكّر',
    },
    {
      'en': 'Saved words come back in Practice at the right time (Leitner box), so they stick.',
      'fa': 'لغت‌های ذخیره‌شده در بخش تمرین، در زمان مناسب (جعبه‌ی لایتنر) دوباره نشان داده می‌شوند تا ماندگار شوند.',
      'es': 'Las palabras guardadas vuelven en Práctica en el momento justo (caja de Leitner) para que se queden.',
      'de': 'Gespeicherte Wörter kommen im Training zur richtigen Zeit zurück (Leitner-Box), damit sie hängen bleiben.',
      'fr': 'Les mots enregistrés reviennent dans Pratique au bon moment (boîte de Leitner) pour bien rester.',
      'ar': 'تعود الكلمات المحفوظة في التمرين في الوقت المناسب (صندوق لايتنر) لتثبت في الذاكرة.',
    },
  ),
];

const Map<String, Map<String, String>> _ui = {
  'skip': {
    'en': 'Skip', 'fa': 'رد کردن', 'es': 'Omitir', 'de': 'Überspringen',
    'fr': 'Passer', 'ar': 'تخطي',
  },
  'next': {
    'en': 'Next', 'fa': 'بعدی', 'es': 'Siguiente', 'de': 'Weiter',
    'fr': 'Suivant', 'ar': 'التالي',
  },
  'start': {
    'en': 'Get started', 'fa': 'شروع', 'es': 'Empezar', 'de': 'Los geht’s',
    'fr': 'Commencer', 'ar': 'ابدأ',
  },
};

/// معرفیِ کوتاهِ بار اول (۴ کارت) با دکمه‌ی «رد کردن» در همه‌ی کارت‌ها.
/// فقط یک‌بار نشان داده می‌شود؛ بعد از رد کردن یا پایان، دیگر ظاهر نمی‌شود.
class IntroOverlay extends ConsumerStatefulWidget {
  const IntroOverlay({super.key});

  static final ValueNotifier<int> _replayTick = ValueNotifier<int>(0);

  /// «نمایش دوباره» (از مرکز راهنما).
  static void replay() => _replayTick.value++;

  /// برای «نمایش دوباره» از تنظیمات.
  static void reset(WidgetRef ref) {
    try {
      ref.read(sharedPrefsProvider).remove(_kIntroSeenKey);
    } catch (_) {}
  }

  @override
  ConsumerState<IntroOverlay> createState() => _IntroOverlayState();
}

class _IntroOverlayState extends ConsumerState<IntroOverlay> {
  late bool _visible;
  final PageController _ctrl = PageController();
  int _page = 0;

  @override
  void initState() {
    super.initState();
    var seen = true;
    try {
      seen = ref.read(sharedPrefsProvider).getBool(_kIntroSeenKey) ?? false;
    } catch (_) {}
    _visible = !seen;
    IntroOverlay._replayTick.addListener(_onReplay);
  }

  void _onReplay() {
    if (!mounted) return;
    setState(() {
      _visible = true;
      _page = 0;
    });
    if (_ctrl.hasClients) _ctrl.jumpToPage(0);
  }

  @override
  void dispose() {
    IntroOverlay._replayTick.removeListener(_onReplay);
    _ctrl.dispose();
    super.dispose();
  }

  void _finish() {
    try {
      ref.read(sharedPrefsProvider).setBool(_kIntroSeenKey, true);
    } catch (_) {}
    if (mounted) setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final c = context.appColors;
    final lang = ref.watch(appPrefsProvider).uiLang;
    String t(Map<String, String> m) => m[lang] ?? m['en']!;
    final rtl = lang == 'fa' || lang == 'ar';
    final last = _page == _pages.length - 1;

    return Positioned.fill(
      child: Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: Material(
          color: Colors.black54,
          child: SafeArea(
            child: Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                constraints: const BoxConstraints(maxWidth: 420),
                decoration: BoxDecoration(
                  color: c.paper,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: c.cardBorder),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton(
                        onPressed: _finish,
                        child: Text(t(_ui['skip']!),
                            style: TextStyle(color: c.inkSoft)),
                      ),
                    ),
                    SizedBox(
                      height: 250,
                      child: PageView.builder(
                        controller: _ctrl,
                        itemCount: _pages.length,
                        onPageChanged: (i) => setState(() => _page = i),
                        itemBuilder: (_, i) {
                          final p = _pages[i];
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 76,
                                height: 76,
                                decoration: BoxDecoration(
                                  color: c.goldSoft,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(p.icon, size: 38, color: c.gold),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                t(p.title),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: c.ink,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                t(p.body),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: c.inkSoft,
                                  fontSize: 14.5,
                                  height: 1.6,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < _pages.length; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: i == _page ? 18 : 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: i == _page ? c.gold : c.cardBorder,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: c.gold,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: () {
                          if (last) {
                            _finish();
                          } else {
                            _ctrl.nextPage(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOut,
                            );
                          }
                        },
                        child: Text(
                          t(_ui[last ? 'start' : 'next']!),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
