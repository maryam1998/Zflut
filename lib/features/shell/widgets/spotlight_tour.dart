import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_prefs_provider.dart';
import '../../../core/storage/local_storage.dart' show sharedPrefsProvider;
import '../../../core/theme/app_theme_colors.dart';

// ═══════════════════════════════════════════════════════════════════
// تورِ معرفیِ برنامه (نورافکن + حلقه‌ی چشمک‌زن)
//
// بار اول که برنامه باز می‌شود، دکمه‌های واقعیِ صفحه (هدر، تب‌ها، پلیر…) یکی‌یکی
// روشن می‌شوند و کنارشان توضیح می‌آید. فقط یک‌بار نشان داده می‌شود؛ از
// تنظیمات ← «معرفی برنامه» دوباره قابل نمایش است.
//
// افزودنِ مرحله‌ی جدید:
//   ۱) دورِ ویجتِ هدف:  TourTarget(id: 'چیزی', child: ...)
//   ۲) یک _Step با همان id به _steps اضافه کن (متن‌ها: fa / en؛ بقیه‌ی زبان‌ها en).
// اگر هدفی روی صفحه نباشد (مثلاً اسکرول شده) آن مرحله خودکار رد می‌شود.
// ═══════════════════════════════════════════════════════════════════

const String _kTourSeenKey = 'zflut-tour-seen-v1';
const String _kImportTourSeenKey = 'zflut-tour-import-seen-v1';

final Map<String, _TourTargetState> _targets = {};

/// ویجتی که یک جای صفحه را برای تور «ثبت» می‌کند (بدون GlobalKey، پس با
/// انتقالِ صفحه‌ها تداخلی پیش نمی‌آید).
class TourTarget extends StatefulWidget {
  final String id;
  final Widget child;
  const TourTarget({super.key, required this.id, required this.child});

  @override
  State<TourTarget> createState() => _TourTargetState();
}

class _TourTargetState extends State<TourTarget> {
  @override
  void initState() {
    super.initState();
    _targets[widget.id] = this;
  }

  @override
  void dispose() {
    if (identical(_targets[widget.id], this)) _targets.remove(widget.id);
    super.dispose();
  }

  Rect? get _rect {
    try {
      if (!mounted) return null;
      final ro = context.findRenderObject();
      if (ro is! RenderBox || !ro.attached || !ro.hasSize) return null;
      return ro.localToGlobal(Offset.zero) & ro.size;
    } catch (_) {
      return null;
    }
  }

  /// هدف را (اگر داخلِ لیستِ اسکرول‌شونده است) فوراً به صفحه می‌آورد.
  void _reveal() {
    try {
      if (!mounted) return;
      Scrollable.ensureVisible(context,
          alignment: 0.4, duration: Duration.zero);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Step {
  final String id;
  final IconData icon;
  final Map<String, String> title;
  final Map<String, String> body;
  /// توضیحِ «لمس طولانی» (اختیاری) — جدا و پررنگ نشان داده می‌شود.
  final Map<String, String>? hold;
  const _Step(this.id, this.icon, this.title, this.body, [this.hold]);
}

const List<_Step> _steps = [
  _Step(
    'account',
    Icons.menu_rounded,
    {'en': 'Menu & settings', 'fa': 'منو و تنظیمات'},
    {
      'en': 'Open settings from here: themes, fonts, offline voices, your account and the help center.',
      'fa': 'از اینجا به تنظیمات می‌روی: تم و فونت، صداهای آفلاین، حساب کاربری و مرکز راهنما.',
    },
  ),
  _Step(
    'lang',
    Icons.translate_rounded,
    {'en': 'Pick your languages', 'fa': 'زبان‌هایت را انتخاب کن'},
    {
      'en': 'Choose your native language and one or more target languages. Every part of the app follows them.',
      'fa': 'زبان مادری و یک یا چند زبانِ مقصد را اینجا انتخاب کن. همه‌ی بخش‌های برنامه از همین انتخاب پیروی می‌کنند.',
    },
  ),
  _Step(
    'tabs',
    Icons.dashboard_rounded,
    {'en': 'The four main sections', 'fa': 'چهار بخشِ اصلی'},
    {
      'en': 'Talk (conversations), Story (build and read stories), Words (vocabulary) and Practice (review).',
      'fa': 'گفتگو، داستان (ساختن و خواندنِ داستان)، لغات و تمرین (مرور) — با یک لمس بین‌شان جابه‌جا شو.',
    },
  ),
  _Step(
    'dock',
    Icons.layers_rounded,
    {'en': 'Floating tools (Android)', 'fa': 'ابزارهای شناور (اندروید)'},
    {
      'en': 'They work on top of any other app, with no copy-paste: Magnifier (translate and hear any text), live translation of the audio playing on your phone (videos, podcasts, clips) and YouTube subtitles. Everything is processed locally on your own phone — your screen and audio are never recorded, sent or stored. Tap this edge tab to open it.',
      'fa': 'روی هر برنامه‌ی دیگری هم کار می‌کنند، بدون کپی‌کردن: ذره‌بین (ترجمه و تلفظِ هر متن)، ترجمه‌ی زنده‌ی صدایی که روی گوشی پخش می‌شود (ویدیو، پادکست، کلیپ) و زیرنویسِ یوتیوب. تشخیصِ متن و گفتار کاملاً روی خودِ گوشیِ شماست؛ تصویرِ صفحه و صدا ضبط، ارسال یا ذخیره نمی‌شود. این زبانه‌ی کنارِ صفحه را لمس کن تا باز شود.',
    },
  ),
  _Step(
    'play',
    Icons.play_arrow_rounded,
    {'en': 'Play / pause', 'fa': 'پخش و توقف'},
    {
      'en': 'Tap to read the page aloud, sentence by sentence.',
      'fa': 'با یک لمس، متنِ صفحه جمله‌به‌جمله خوانده می‌شود.',
    },
    {
      'en': 'Takes you exactly to the line and the tab that is being read.',
      'fa': 'شما را دقیقاً به همان خط و همان تبی می‌برد که در حال خواندنش است.',
    },
  ),
  _Step(
    'next',
    Icons.skip_next_rounded,
    {'en': 'Next / previous sentence', 'fa': 'جمله‌ی بعدی و قبلی'},
    {
      'en': 'Tap to move one sentence forward (the previous button moves one back).',
      'fa': 'با یک لمس یک جمله جلو می‌روی (دکمه‌ی قبلی: یک جمله عقب).',
    },
    {
      'en': 'Skips several seconds forward or back.',
      'fa': 'چند ثانیه جلو یا عقب می‌پرد.',
    },
  ),
  _Step(
    'repeat',
    Icons.repeat_rounded,
    {'en': 'Repeat', 'fa': 'تکرار'},
    {
      'en': 'Each tap changes the repeat mode.',
      'fa': 'با هر لمس، حالتِ تکرار عوض می‌شود.',
    },
    {
      'en': 'Type exactly how many times you want to repeat.',
      'fa': 'تعدادِ تکرارِ دلخواه را خودت وارد کن.',
    },
  ),
  _Step(
    'ab',
    Icons.linear_scale_rounded,
    {'en': 'Loop a section (A-B)', 'fa': 'تکرارِ یک قسمت (A-B)'},
    {
      'en': 'Mark where a section starts and ends, and the app loops just that part — great for hard sentences.',
      'fa': 'ابتدا و انتهای یک قسمت را علامت بزن تا فقط همان قسمت تکرار شود؛ مناسبِ جمله‌های سخت.',
    },
  ),
  _Step(
    'rec',
    Icons.mic_rounded,
    {'en': 'Practise your pronunciation', 'fa': 'تمرینِ تلفظ'},
    {
      'en': 'Record your own voice and compare it with the original (shadowing).',
      'fa': 'صدای خودت را ضبط کن و با تلفظِ اصلی مقایسه کن (روشِ شدوینگ).',
    },
  ),
  _Step(
    'speed',
    Icons.speed_rounded,
    {'en': 'Speech speed', 'fa': 'سرعتِ صدا'},
    {
      'en': 'Slow the voice down to catch every word, or speed it up when you are ready.',
      'fa': 'برای شنیدنِ تک‌تکِ کلمه‌ها صدا را کند کن، و وقتی آماده شدی تندترش کن.',
    },
  ),
  _Step(
    'top',
    Icons.vertical_align_top_rounded,
    {'en': 'Back to top', 'fa': 'رفتن به بالای صفحه'},
    {
      'en': 'In a long list or a long text, one tap takes you straight back to the top of the page.',
      'fa': 'وقتی در یک لیستِ بلند یا متنِ طولانی پایین رفته‌ای، با یک لمس مستقیم به بالای صفحه برمی‌گردی.',
    },
  ),
];

/// تورِ زیرتبِ «ایمپورت و خواندن» (داستان‌ساز) — بار اولِ ورود و با دکمه‌ی راهنمای همان بخش.
const List<_Step> _importSteps = [
  _Step(
    'imp_pdf',
    Icons.menu_book_rounded,
    {'en': 'Import a PDF to read', 'fa': 'ایمپورتِ PDF برای خواندن'},
    {
      'en': 'Pick a text PDF and the app turns it into a reading page, sentence by sentence. Tap any word or select a phrase to see its translation in any language you choose.',
      'fa': 'یک PDFِ متنی انتخاب کن تا برنامه آن را جمله‌به‌جمله برای خواندن آماده کند. روی هر لغت بزن یا یک عبارت را انتخاب کن تا ترجمه‌اش را به هر زبانی که می‌خواهی ببینی.',
    },
  ),
  _Step(
    'imp_img',
    Icons.image_rounded,
    {'en': 'Import photos', 'fa': 'ایمپورتِ عکس'},
    {
      'en': 'A page of a book, a sign, a screenshot… the app reads the text from the photo and you can translate it into any language.',
      'fa': 'صفحه‌ی یک کتاب، یک تابلو، اسکرین‌شات… برنامه متنِ داخلِ عکس را می‌خواند و می‌توانی آن را به هر زبانی ترجمه کنی.',
    },
  ),
  _Step(
    'imp_view',
    Icons.auto_stories_rounded,
    {'en': 'View a PDF with translation', 'fa': 'دیدنِ PDF با ترجمه'},
    {
      'en': 'Open a PDF with its original look (also scanned books). The translation is drawn on the page itself, and you can switch the target language any time.',
      'fa': 'یک PDF را با ظاهرِ اصلی‌اش باز کن (کتابِ اسکن‌شده هم). ترجمه روی خودِ صفحه نقش می‌بندد و هر وقت خواستی زبانِ مقصد را عوض می‌کنی.',
    },
  ),
  _Step(
    'imp_link',
    Icons.link_rounded,
    {'en': 'Import from a link', 'fa': 'ایمپورت از لینک'},
    {
      'en': 'Paste the address of an article or web page and its text is brought in, ready to read and translate.',
      'fa': 'آدرسِ یک مقاله یا صفحه‌ی وب را بگذار تا متنش وارد شود و برای خواندن و ترجمه آماده باشد.',
    },
  ),
  _Step(
    'imp_paste',
    Icons.content_paste_rounded,
    {'en': 'Paste any text', 'fa': 'متنِ دلخواه'},
    {
      'en': 'Copy any text from anywhere, paste it here, and read it with translations in any language.',
      'fa': 'هر متنی را از هر جا کپی کن، اینجا بگذار و با ترجمه به هر زبانی بخوانش.',
    },
  ),
  _Step(
    'imp_srt',
    Icons.subtitles_rounded,
    {'en': 'Translate subtitle files (SRT)', 'fa': 'ترجمه‌ی فایلِ زیرنویس (SRT)'},
    {
      'en': 'Load an .srt file, translate it into any language and save the new file. This one is free, with no limit — the other imports are free twice, then need Pro.',
      'fa': 'فایلِ .srt را بارگذاری کن، به هر زبانی ترجمه کن و فایلِ جدید را ذخیره کن. این بخش رایگان و بدونِ محدودیت است؛ بقیه‌ی ایمپورت‌ها دو بار رایگان‌اند و بعدش Pro می‌خواهند.',
    },
  ),
];

const Map<String, Map<String, String>> _ui = {
  'skip': {'en': 'Skip', 'fa': 'رد کردن'},
  'next': {'en': 'Next', 'fa': 'بعدی'},
  'done': {'en': 'Got it', 'fa': 'فهمیدم'},
  'replay': {'en': 'App tour', 'fa': 'معرفیِ برنامه'},
  'hold': {'en': 'Long-press', 'fa': 'لمس طولانی'},
};

class SpotlightTour extends ConsumerStatefulWidget {
  const SpotlightTour({super.key});

  static final ValueNotifier<int> _replayTick = ValueNotifier<int>(0);

  /// نمایشِ دوباره‌ی تور (از تنظیمات).
  static void replay() => _replayTick.value++;

  static final ValueNotifier<int> _importTick = ValueNotifier<int>(0);
  static bool _importForce = false;

  /// تورِ زیرتبِ «ایمپورت و خواندن». force=true (دکمه‌ی راهنما) → همیشه؛ وگرنه فقط بارِ اول.
  static void startImport({bool force = false}) {
    _importForce = force;
    _importTick.value++;
  }

  /// مرحله‌ی «ابزارهای شناور»: به داک (FeatureDock) می‌گوید باز شود.
  static final ValueNotifier<int> dockExpand = ValueNotifier<int>(0);

  @override
  ConsumerState<SpotlightTour> createState() => _SpotlightTourState();
}

class _SpotlightTourState extends ConsumerState<SpotlightTour>
    with TickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1500));
  late final AnimationController _move = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 380), value: 1);

  bool _active = false;
  String _group = 'main'; // 'main' | 'import'
  List<_Step> get _list => _group == 'import' ? _importSteps : _steps;
  int _i = -1;
  Rect? _prev;
  Rect? _last;
  Timer? _startTimer;
  Timer? _importTimer;

  @override
  void initState() {
    super.initState();
    var seen = true;
    try {
      seen = ref.read(sharedPrefsProvider).getBool(_kTourSeenKey) ?? false;
    } catch (_) {}
    if (!seen) {
      _startTimer = Timer(const Duration(milliseconds: 2200), _begin);
    }
    SpotlightTour._replayTick.addListener(_onReplay);
    SpotlightTour._importTick.addListener(_onImportTick);
  }

  @override
  void dispose() {
    _startTimer?.cancel();
    SpotlightTour._replayTick.removeListener(_onReplay);
    SpotlightTour._importTick.removeListener(_onImportTick);
    _importTimer?.cancel();
    _pulse.dispose();
    _move.dispose();
    super.dispose();
  }

  void _onReplay() {
    _startTimer?.cancel();
    _begin();
  }

  void _onImportTick() {
    if (_active) return;
    var seen = true;
    try {
      seen = ref.read(sharedPrefsProvider).getBool(_kImportTourSeenKey) ?? false;
    } catch (_) {}
    if (seen && !SpotlightTour._importForce) return;
    // کمی صبر تا دکمه‌های زیرتبِ ایمپورت روی صفحه بنشینند
    _importTimer?.cancel();
    _importTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted || _active) return;
      _begin(group: 'import');
      // اگر دکمه‌ها هنوز روی صفحه ننشسته بودند، یک بارِ دیگر (کمی دیرتر) امتحان کن
      if (!_active) {
        _importTimer = Timer(const Duration(milliseconds: 900), () {
          if (mounted && !_active) _begin(group: 'import');
        });
      }
    });
  }

  Rect? _usableRect(String id, Size size) {
    final r = _targets[id]?._rect;
    if (r == null) return null;
    final vis = r.intersect(Offset.zero & size);
    if (vis.width < 6 || vis.height < 6) return null;
    return vis;
  }

  void _begin({String group = 'main'}) {
    if (!mounted) return;
    _group = group;
    _prev = null;
    _last = null;
    _i = -1;
    setState(() => _active = true);
    _pulse.repeat();
    if (!_advance()) {
      // هیچ هدفی روی صفحه نبود (مثلاً هنوز بارگذاری نشده): بی‌سروصدا بسته می‌شود
      // و «دیده شد» ثبت نمی‌شود تا دفعه‌ی بعد دوباره امتحان شود.
      _pulse.stop();
      setState(() => _active = false);
    }
  }

  bool _advance() {
    final size = MediaQuery.of(context).size;
    for (var j = _i + 1; j < _list.length; j++) {
      if (_group == 'import') _targets[_list[j].id]?._reveal();
      final r = _usableRect(_list[j].id, size);
      if (r != null) {
        setState(() {
          _prev = _last;
          _i = j;
        });
        _move.forward(from: 0);
        if (_list[j].id == 'dock') SpotlightTour.dockExpand.value++;
        return true;
      }
    }
    return false;
  }

  void _finish() {
    try {
      ref.read(sharedPrefsProvider).setBool(
          _group == 'import' ? _kImportTourSeenKey : _kTourSeenKey, true);
    } catch (_) {}
    _pulse.stop();
    if (mounted) setState(() => _active = false);
  }

  void _next() {
    if (!_advance()) _finish();
  }

  @override
  Widget build(BuildContext context) {
    if (!_active || _i < 0) return const SizedBox.shrink();
    final c = context.appColors;
    final lang = ref.watch(appPrefsProvider).uiLang;
    String t(Map<String, String> m) => m[lang] ?? m['en']!;
    final rtl = lang == 'fa' || lang == 'ar';
    final step = _list[_i];
    final size = MediaQuery.of(context).size;
    final lastStep = !_hasLater(size);

    return Positioned.fill(
      child: Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: Material(
          type: MaterialType.transparency,
          child: AnimatedBuilder(
            animation: Listenable.merge([_pulse, _move]),
            builder: (context, _) {
              final cur = _usableRect(step.id, size) ??
                  _last ??
                  Rect.fromCenter(
                      center: size.center(Offset.zero), width: 60, height: 60);
              _last = cur;
              final k = Curves.easeOutCubic.transform(_move.value);
              final r = Rect.lerp(_prev ?? cur, cur, k)!;
              final hole = r.inflate(6);
              final below = hole.center.dy < size.height * 0.5;

              return Stack(
                children: [
                  // پرده‌ی تیره با سوراخ + حلقه‌ی چشمک‌زن (لمس‌ها را می‌گیرد)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {},
                      child: CustomPaint(
                        painter: _SpotPainter(
                            hole: hole, t: _pulse.value, color: c.gold),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    top: below ? math.max(hole.bottom + 16, 8.0) : null,
                    bottom:
                        below ? null : math.max(size.height - hole.top + 16, 8.0),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: _card(c, step, t, lastStep, key: ValueKey(_i)),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// آیا بعد از مرحله‌ی فعلی مرحله‌ی قابل‌نمایشی هست؟
  bool _hasLater(Size size) {
    for (var j = _i + 1; j < _list.length; j++) {
      // ایمپورت: هدفِ ثبت‌شده کافی است (در _advance به صفحه آورده می‌شود)
      if (_group == 'import'
          ? _targets[_list[j].id]?._rect != null
          : _usableRect(_list[j].id, size) != null) return true;
    }
    return false;
  }

  Widget _card(AppThemeColorsExt c, _Step step, String Function(Map<String, String>) t,
      bool lastStep,
      {Key? key}) {
    final shown = _list.indexOf(step) + 1;
    return Container(
      key: key,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: c.paper,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.cardBorder),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 16, offset: Offset(0, 6)),
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
                decoration:
                    BoxDecoration(color: c.goldSoft, shape: BoxShape.circle),
                child: Icon(step.icon, size: 22, color: c.gold),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t(step.title),
                  style: TextStyle(
                      color: c.ink, fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
              Text('$shown/${_list.length}',
                  style: TextStyle(color: c.inkSoft, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            t(step.body),
            style: TextStyle(color: c.ink, fontSize: 14, height: 1.65),
          ),
          if (step.hold != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: c.goldSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.touch_app_rounded, size: 18, color: c.gold),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${t(_ui['hold']!)}: ',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          TextSpan(text: t(step.hold!)),
                        ],
                      ),
                      style:
                          TextStyle(color: c.ink, fontSize: 13.5, height: 1.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton(
                onPressed: _finish,
                child: Text(t(_ui['skip']!),
                    style: TextStyle(color: c.inkSoft)),
              ),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: c.gold,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _next,
                child: Text(
                  t(_ui[lastStep ? 'done' : 'next']!),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SpotPainter extends CustomPainter {
  final Rect hole;
  final double t; // ۰..۱ (فازِ چشمک)
  final Color color;
  const _SpotPainter(
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

    // دو موجِ چشمک‌زن که از لبه‌ی هدف به بیرون پخش می‌شوند
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
    // حلقه‌ی ثابت دورِ هدف
    canvas.drawRRect(
      rr.inflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _SpotPainter old) =>
      old.hole != hole || old.t != t || old.color != color;
}

/// دکمه‌ی «معرفیِ برنامه» برای تنظیمات: شیت را می‌بندد و تور را از اول نشان می‌دهد.
class TourReplayButton extends ConsumerWidget {
  const TourReplayButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final lang = ref.watch(appPrefsProvider).uiLang;
    final label = _ui['replay']![lang] ?? _ui['replay']!['en']!;
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.ink,
        side: BorderSide(color: c.cardBorder),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: Icon(Icons.tips_and_updates_outlined, color: c.gold),
      label: Text(label),
      onPressed: () {
        Navigator.of(context).pop();
        Future<void>.delayed(
            const Duration(milliseconds: 450), SpotlightTour.replay);
      },
    );
  }
}
