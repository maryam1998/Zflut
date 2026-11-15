import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/native/native_bridge.dart';
import '../../../core/stats/listening_tracker.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../review_i18n.dart';

// ═══════════════════════════════════════════════════════════════════
// متن‌ها (۶ زبانِ برنامه) — بدونِ نیاز به تغییرِ فایل‌های ARB
// ═══════════════════════════════════════════════════════════════════
const Map<String, Map<String, String>> _kT = {
  'fa': {
    'wtotal': "مجموعِ هفته",
    'thisweek': "این هفته",
    'lastweek': "هفته‌ی گذشته",
    'weeksago': "{n} هفته پیش",
    'hs': 'س',
    'ms': 'د',
    'listen': 'گوش‌دادن',
    'review': 'مرور',
    'total': 'مجموعِ این هفته',
    'today': 'امروز',
    'avg': 'میانگین روزانه',
    'best': 'بهترین روز',
    'up': 'بیشتر از هفته‌ی قبل',
    'down': 'کمتر از هفته‌ی قبل',
    'yt': 'یوتیوب',
    'audio': 'فایل صوتی',
    'tts': 'پلیر برنامه',
    'empty': 'این هفته هنوز چیزی گوش نداده‌ای.\nیک ویدیوی یوتیوب یا فایل صوتی پخش کن 🎧',
    'access': 'برای ثبتِ ساعت‌های یوتیوب، «دسترسی به اعلان‌ها» را روشن کن.',
    'enable': 'فعال‌سازی',
    'h': 'ساعت',
    'm': 'دقیقه',
    'and': ' و ',
    'lt1': 'کمتر از ۱ دقیقه',
    'tap': 'روی هر ستون بزن تا جزئیاتِ آن روز را ببینی',
  },
  'en': {
    'wtotal': "Week total",
    'thisweek': "This week",
    'lastweek': "Last week",
    'weeksago': "{n} weeks ago",
    'hs': 'h',
    'ms': 'm',
    'listen': 'Listening',
    'review': 'Reviews',
    'total': 'This week',
    'today': 'Today',
    'avg': 'Daily average',
    'best': 'Best day',
    'up': 'more than last week',
    'down': 'less than last week',
    'yt': 'YouTube',
    'audio': 'Audio file',
    'tts': 'App player',
    'empty':
        "You haven't listened to anything this week yet.\nPlay a YouTube video or an audio file 🎧",
    'access': 'Turn on notification access to track YouTube listening time.',
    'enable': 'Enable',
    'h': 'h',
    'm': 'm',
    'and': ' ',
    'lt1': '<1m',
    'tap': 'Tap a bar to see that day',
  },
  'ar': {
    'wtotal': "إجمالي الأسبوع",
    'thisweek': "هذا الأسبوع",
    'lastweek': "الأسبوع الماضي",
    'weeksago': "قبل {n} أسابيع",
    'hs': 'س',
    'ms': 'د',
    'listen': 'الاستماع',
    'review': 'المراجعة',
    'total': 'إجمالي هذا الأسبوع',
    'today': 'اليوم',
    'avg': 'المتوسط اليومي',
    'best': 'أفضل يوم',
    'up': 'أكثر من الأسبوع الماضي',
    'down': 'أقل من الأسبوع الماضي',
    'yt': 'يوتيوب',
    'audio': 'ملف صوتي',
    'tts': 'مشغّل التطبيق',
    'empty': 'لم تستمع إلى أي شيء هذا الأسبوع بعد.\nشغّل فيديو يوتيوب أو ملفًا صوتيًا 🎧',
    'access': 'فعّل «الوصول إلى الإشعارات» لتسجيل وقت يوتيوب.',
    'enable': 'تفعيل',
    'h': 'س',
    'm': 'د',
    'and': ' ',
    'lt1': '<1د',
    'tap': 'اضغط على أي عمود لرؤية تفاصيل اليوم',
  },
  'de': {
    'wtotal': "Wochensumme",
    'thisweek': "Diese Woche",
    'lastweek': "Letzte Woche",
    'weeksago': "Vor {n} Wochen",
    'hs': 'h',
    'ms': 'm',
    'listen': 'Hören',
    'review': 'Wiederholen',
    'total': 'Diese Woche',
    'today': 'Heute',
    'avg': 'Ø pro Tag',
    'best': 'Bester Tag',
    'up': 'mehr als letzte Woche',
    'down': 'weniger als letzte Woche',
    'yt': 'YouTube',
    'audio': 'Audiodatei',
    'tts': 'App-Player',
    'empty':
        'Diese Woche hast du noch nichts gehört.\nSpiele ein YouTube-Video oder eine Audiodatei ab 🎧',
    'access':
        'Aktiviere den Benachrichtigungszugriff, um YouTube-Hörzeit zu erfassen.',
    'enable': 'Aktivieren',
    'h': 'Std',
    'm': 'Min',
    'and': ' ',
    'lt1': '<1 Min',
    'tap': 'Tippe auf einen Balken für Details',
  },
  'es': {
    'wtotal': "Total de la semana",
    'thisweek': "Esta semana",
    'lastweek': "Semana pasada",
    'weeksago': "Hace {n} semanas",
    'hs': 'h',
    'ms': 'm',
    'listen': 'Escucha',
    'review': 'Repaso',
    'total': 'Esta semana',
    'today': 'Hoy',
    'avg': 'Media diaria',
    'best': 'Mejor día',
    'up': 'más que la semana pasada',
    'down': 'menos que la semana pasada',
    'yt': 'YouTube',
    'audio': 'Archivo de audio',
    'tts': 'Reproductor',
    'empty':
        'Aún no has escuchado nada esta semana.\nReproduce un vídeo de YouTube o un audio 🎧',
    'access':
        'Activa el acceso a notificaciones para registrar el tiempo en YouTube.',
    'enable': 'Activar',
    'h': 'h',
    'm': 'min',
    'and': ' ',
    'lt1': '<1 min',
    'tap': 'Toca una barra para ver ese día',
  },
  'fr': {
    'wtotal': "Total de la semaine",
    'thisweek': "Cette semaine",
    'lastweek': "Semaine dernière",
    'weeksago': "Il y a {n} semaines",
    'hs': 'h',
    'ms': 'm',
    'listen': 'Écoute',
    'review': 'Révision',
    'total': 'Cette semaine',
    'today': "Aujourd'hui",
    'avg': 'Moyenne / jour',
    'best': 'Meilleur jour',
    'up': 'de plus que la semaine dernière',
    'down': 'de moins que la semaine dernière',
    'yt': 'YouTube',
    'audio': 'Fichier audio',
    'tts': "Lecteur de l'app",
    'empty':
        "Vous n'avez rien écouté cette semaine.\nLancez une vidéo YouTube ou un fichier audio 🎧",
    'access':
        "Activez l'accès aux notifications pour suivre le temps YouTube.",
    'enable': 'Activer',
    'h': 'h',
    'm': 'min',
    'and': ' ',
    'lt1': '<1 min',
    'tap': 'Touchez une barre pour voir ce jour',
  },
};

/// نامِ کاملِ روزهای هفته (دوشنبه … یکشنبه، هم‌ترتیبِ DateTime.weekday)
const Map<String, List<String>> _kDays = {
  'fa': ['دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنجشنبه', 'جمعه', 'شنبه', 'یکشنبه'],
  'en': ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'],
  'ar': ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'],
  'de': ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'],
  'es': ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'],
  'fr': ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'],
};

extension _ListenI18n on BuildContext {
  String lt(String k) {
    final lang = Localizations.localeOf(this).languageCode;
    return (_kT[lang] ?? _kT['en']!)[k] ?? _kT['en']![k] ?? k;
  }

  /// ثانیه → «۱ ساعت و ۲۵ دقیقه» / «1h 25m»
  String ldur(int sec) {
    if (sec <= 0) return '${rvNum(0)} ${lt('m')}'.trim();
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    if (h == 0 && m == 0) return lt('lt1');
    final isCompact = lt('and') == ' ' && lt('h').length <= 2;
    String part(int v, String u) => isCompact ? '${rvNum(v)}$u' : '${rvNum(v)} $u';
    if (h == 0) return part(m, lt('m'));
    if (m == 0) return part(h, lt('h'));
    return '${part(h, lt('h'))}${lt('and')}${part(m, lt('m'))}';
  }
}

// ═══════════════════════════════════════════════════════════════════
// سوئیچِ «گوش‌دادن | مرور» + محتوای هر کدام
// ═══════════════════════════════════════════════════════════════════
class WeeklyProgressSwitcher extends StatefulWidget {
  final ListenStats listen;

  /// نمودارِ قدیمیِ مرور (WeeklyChart) — دست‌نخورده
  final Widget reviewChart;

  const WeeklyProgressSwitcher({
    super.key,
    required this.listen,
    required this.reviewChart,
  });

  @override
  State<WeeklyProgressSwitcher> createState() => _WeeklyProgressSwitcherState();
}

class _WeeklyProgressSwitcherState extends State<WeeklyProgressSwitcher> {
  int _tab = 0; // 0 = گوش‌دادن، 1 = مرور

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    Widget seg(int i, String label, IconData icon) {
      final on = _tab == i;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _tab = i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: on ? c.gold : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: on ? Colors.white : c.inkSoft),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: on ? Colors.white : c.inkSoft,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: c.goldSoft.withOpacity(0.55),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            seg(0, context.lt('listen'), Icons.headphones_rounded),
            seg(1, context.lt('review'), Icons.style_rounded),
          ]),
        ),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _tab == 0
              ? ListenWeeklyView(key: const ValueKey('listen'), stats: widget.listen)
              : KeyedSubtree(
                  key: const ValueKey('review'), child: widget.reviewChart),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// نمودارِ هفتگیِ زمانِ گوش‌دادن
// ═══════════════════════════════════════════════════════════════════
class ListenWeeklyView extends StatefulWidget {
  final ListenStats stats;
  const ListenWeeklyView({super.key, required this.stats});

  @override
  State<ListenWeeklyView> createState() => _ListenWeeklyViewState();
}

class _ListenWeeklyViewState extends State<ListenWeeklyView>
    with WidgetsBindingObserver {
  int? _sel; // ایندکسِ ستونِ انتخاب‌شده؛ null = پیش‌فرض (امروز / بهترین روزِ هفته)
  int _off = 0; // ۰ = این هفته، -۱ = هفته‌ی قبل، …
  int? _src; // منبعِ فوکوس‌شده: 0=یوتیوب، 1=فایل صوتی، 2=پلیر برنامه
  bool _needAccess = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAccess();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _checkAccess();
  }

  Future<void> _checkAccess() async {
    if (!NativeBridge.instance.isSupported) return;
    try {
      final r = await NativeBridge.instance.ytCheckAccess();
      if (mounted) setState(() => _needAccess = r['granted'] != true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final dir = uiContentDirection(context);
    final isRtl = dir == TextDirection.rtl;
    final stats = widget.stats;
    final lang = Localizations.localeOf(context).languageCode;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // شروعِ هفته بر اساسِ زبانِ برنامه: فارسی/عربی = شنبه، بقیه = دوشنبه
    final startWd = (lang == 'fa' || lang == 'ar') ? DateTime.saturday : DateTime.monday;
    final back = (today.weekday - startWd + 7) % 7;
    final wkStart = DateTime(today.year, today.month, today.day - back + _off * 7);
    final dates = [
      for (var i = 0; i < 7; i++)
        DateTime(wkStart.year, wkStart.month, wkStart.day + i)
    ];
    final days = [for (final d in dates) stats.day(d)];
    // روزهای گذشته‌ی همین هفته (برای مقایسه و میانگینِ منصفانه)
    final elapsed = _off == 0 ? back + 1 : 7;
    final prevTotal = [
      for (var i = 0; i < elapsed; i++)
        stats.day(DateTime(wkStart.year, wkStart.month, wkStart.day - 7 + i)).total
    ].fold<int>(0, (a, b) => a + b);
    final total = days.fold<int>(0, (a, d) => a + d.total);
    final labels = context.rvWeekdayLetters;
    final avg = total ~/ elapsed;
    var bestIdx = 0;
    for (var i = 1; i < days.length; i++) {
      if (days[i].total > days[bestIdx].total) bestIdx = i;
    }
    final selIdx = _sel ?? (_off == 0 ? back : bestIdx);
    final sel = days[selIdx];
    final isToday = _off == 0 && selIdx == back;
    final maxSec = days.fold<int>(0, (a, d) => math.max(a, d.total));
    final weekLabel = _off == 0
        ? context.lt('thisweek')
        : _off == -1
            ? context.lt('lastweek')
            : context.lt('weeksago').replaceAll('{n}', context.rvNum(-_off));
    final canPrev = _off > -16; // داده فقط ~۱۲۰ روز نگه داشته می‌شود
    final canNext = _off < 0;
    void goWeek(int delta) => setState(() {
          _off = (_off + delta).clamp(-16, 0).toInt();
          _sel = null;
          _src = null;
        });
    Widget navBtn(IconData icon, bool on, VoidCallback f) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: on ? f : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Icon(icon,
                size: 24, color: on ? c.ink : c.inkSoft.withOpacity(0.35)),
          ),
        );

    final hasYt = days.any((d) => d.yt > 0);
    final hasAudio = days.any((d) => d.audio > 0);
    final hasTts = days.any((d) => d.tts > 0);

    final ytC = c.rose;
    final auC = c.teal;
    final ttC = c.gold;

    Widget accessHint() => Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            color: c.gold.withOpacity(0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.gold.withOpacity(0.4)),
          ),
          child: Row(children: [
            Icon(Icons.notifications_active_outlined, size: 18, color: c.gold),
            const SizedBox(width: 8),
            Expanded(
              child: Text(context.lt('access'),
                  style: TextStyle(color: c.ink, fontSize: 12, height: 1.6)),
            ),
            TextButton(
              onPressed: () async {
                try {
                  await NativeBridge.instance.ytRequestAccess();
                } catch (_) {}
              },
              child: Text(context.lt('enable'),
                  style: TextStyle(
                      color: c.gold, fontSize: 12, fontWeight: FontWeight.w800)),
            ),
          ]),
        );

    return Directionality(
      textDirection: dir,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── ناوبریِ هفته‌ها ──
          Row(
            children: [
              navBtn(isRtl ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
                  canPrev, () => goWeek(-1)),
              Expanded(
                child: Text(weekLabel,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: c.ink, fontSize: 13, fontWeight: FontWeight.w800)),
              ),
              navBtn(isRtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                  canNext, () => goWeek(1)),
            ],
          ),
          const SizedBox(height: 8),
          // ── خلاصه: مجموعِ هفته + مقایسه با هفته‌ی قبل ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.lt(_off == 0 ? 'total' : 'wtotal'),
                        style: TextStyle(color: c.inkSoft, fontSize: 12)),
                    const SizedBox(height: 2),
                    Text(context.ldur(total),
                        style: TextStyle(
                            color: c.ink,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            height: 1.2)),
                  ],
                ),
              ),
              if (total > 0 && prevTotal > 0) _DeltaChip(total: total, prev: prevTotal),
            ],
          ),
          const SizedBox(height: 14),

          // ── نمودار ──
          if (total == 0)
            _EmptyListen(text: context.lt('empty'))
          else ...[
            SizedBox(
              height: 168,
              child: LayoutBuilder(builder: (ctx, box) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) {
                    final w = box.maxWidth - _kGutter;
                    final x = isRtl
                        ? (box.maxWidth - _kGutter) - d.localPosition.dx
                        : d.localPosition.dx - _kGutter;
                    if (x < 0 || x > w) return;
                    final i = (x / (w / 7)).floor().clamp(0, 6).toInt();
                    // i=0 = اولین روزِ هفته (RTL: سمت راست)
                    // اگر روی یکی از رنگ‌های ستون زده شد، همان منبع فوکوس می‌شود
                    int? src;
                    final dd = days[i];
                    if (dd.total > 0) {
                      final (top, _) = _ListenBarsPainter._scale(maxSec);
                      const chartTop = 8.0;
                      final chartH = 168.0 - chartTop;
                      final bottom = chartTop + chartH - 1.4;
                      final h = math.max((dd.total / top) * chartH, 6.0);
                      final f = (bottom - d.localPosition.dy) / h;
                      if (f >= 0 && f <= 1) {
                        final yEnd = dd.yt / dd.total;
                        final aEnd = yEnd + dd.audio / dd.total;
                        if (f < yEnd && dd.yt > 0) {
                          src = 0;
                        } else if (f < aEnd && dd.audio > 0) {
                          src = 1;
                        } else if (dd.tts > 0) {
                          src = 2;
                        } else if (dd.audio > 0) {
                          src = 1;
                        } else {
                          src = 0;
                        }
                      }
                    }
                    setState(() {
                      _src = (src != null && src == _src && i == selIdx) ? null : src;
                      _sel = i;
                    });
                  },
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 650),
                    curve: Curves.easeOutCubic,
                    builder: (_, t, __) => CustomPaint(
                      size: Size(box.maxWidth, 168),
                      painter: _ListenBarsPainter(
                        days: days,
                        progress: t,
                        selected: selIdx,
                        focus: _src,
                        colors: (ytC, auC, ttC),
                        grid: c.cardBorder,
                        text: c.inkSoft,
                        ink: c.ink,
                        isRtl: isRtl,
                        axisLabel: (sec) => _axisLabel(context, sec),
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 6),
            Row(
                children: [
                  // جایِ محور (سمتِ شروع) برای هم‌ترازیِ برچسب‌ها با ستون‌ها
                  const SizedBox(width: _kGutter),
                  for (var i = 0; i < dates.length; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() {
                          _sel = i;
                          _src = null;
                        }),
                        child: Text(
                          labels[dates[i].weekday - 1],
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: i == selIdx ? c.ink : c.inkSoft,
                            fontSize: 12,
                            fontWeight:
                                i == selIdx ? FontWeight.w800 : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 14),

            // ── جزئیاتِ روزِ انتخاب‌شده ──
            _DayDetail(
              focus: _src,
              onFocus: (k) => setState(() => _src = _src == k ? null : k),
              title: isToday
                  ? context.lt('today')
                  : _fullDay(context, dates[selIdx]),
              day: sel,
              yt: (ytC, context.lt('yt')),
              audio: (auC, context.lt('audio')),
              tts: (ttC, context.lt('tts')),
              fmt: context.ldur,
            ),
            const SizedBox(height: 12),

            // ── سه آمارِ کوچک ──
            Row(children: [
              Expanded(
                  child: _Mini(
                      label: context.lt('today'),
                      value: context.ldur(stats.day(today).total))),
              const SizedBox(width: 8),
              Expanded(
                  child: _Mini(
                      label: context.lt('avg'), value: context.ldur(avg))),
              const SizedBox(width: 8),
              Expanded(
                  child: _Mini(
                      label: context.lt('best'),
                      value: context.ldur(days[bestIdx].total))),
            ]),
            const SizedBox(height: 12),

            // ── راهنمای رنگ‌ها ──
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                if (hasYt)
                  _Legend(
                      color: ytC,
                      label: context.lt('yt'),
                      active: _src == 0,
                      onTap: () => setState(() => _src = _src == 0 ? null : 0)),
                if (hasAudio)
                  _Legend(
                      color: auC,
                      label: context.lt('audio'),
                      active: _src == 1,
                      onTap: () => setState(() => _src = _src == 1 ? null : 1)),
                if (hasTts)
                  _Legend(
                      color: ttC,
                      label: context.lt('tts'),
                      active: _src == 2,
                      onTap: () => setState(() => _src = _src == 2 ? null : 2)),
              ],
            ),
          ],
          if (_needAccess) accessHint(),
        ],
      ),
    );
  }

  static String _fullDay(BuildContext ctx, DateTime d) {
    final lang = Localizations.localeOf(ctx).languageCode;
    final l = _kDays[lang] ?? _kDays['en']!;
    return l[d.weekday - 1];
  }

  static String _axisLabel(BuildContext ctx, int sec) {
    if (sec <= 0) return '';
    if (sec >= 3600 && sec % 3600 == 0) {
      return '${ctx.rvNum(sec ~/ 3600)}${ctx.lt('hs')}';
    }
    return '${ctx.rvNum(sec ~/ 60)}${ctx.lt('ms')}';
  }
}

const double _kGutter = 36;

// ───────────────────────────── اجزای کوچک ─────────────────────────────
class _DeltaChip extends StatelessWidget {
  final int total, prev;
  const _DeltaChip({required this.total, required this.prev});

  @override
  Widget build(BuildContext context) {
    final up = total >= prev;
    final pct = (((total - prev).abs() / prev) * 100).round();
    final col = up ? const Color(0xFF3F9B72) : context.appColors.rose;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: col.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
            size: 15, color: col),
        const SizedBox(width: 4),
        Text(
          '${context.rvNum(pct)}${Localizations.localeOf(context).languageCode == 'fa' ? '٪' : '%'} ${context.lt(up ? 'up' : 'down')}',
          style: TextStyle(color: col, fontSize: 11.5, fontWeight: FontWeight.w800),
        ),
      ]),
    );
  }
}

class _EmptyListen extends StatelessWidget {
  final String text;
  const _EmptyListen({required this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: c.goldSoft, shape: BoxShape.circle),
          child: Icon(Icons.headphones_rounded, size: 28, color: c.gold),
        ),
        const SizedBox(height: 10),
        Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.inkSoft, fontSize: 13, height: 1.7)),
      ]),
    );
  }
}

class _DayDetail extends StatelessWidget {
  final String title;
  final ListenDay day;
  final (Color, String) yt, audio, tts;
  final String Function(int) fmt;
  final int? focus;
  final void Function(int)? onFocus;
  const _DayDetail({
    this.focus,
    this.onFocus,
    required this.title,
    required this.day,
    required this.yt,
    required this.audio,
    required this.tts,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    Widget row((Color, String) s, int sec, int k) => sec <= 0
        ? const SizedBox.shrink()
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onFocus == null ? null : () => onFocus!(k),
            child: Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: focus == k ? s.$1.withOpacity(0.14) : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                    color: focus == k ? s.$1 : Colors.transparent, width: 1.2),
              ),
              child: Row(children: [
                Container(
                    width: 9,
                    height: 9,
                    decoration:
                        BoxDecoration(color: s.$1, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(s.$2,
                        style: TextStyle(color: c.inkSoft, fontSize: 12.5))),
                Text(fmt(sec),
                    style: TextStyle(
                        color: c.ink,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
          );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: c.paper,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
                child: Text(title,
                    style: TextStyle(
                        color: c.ink, fontSize: 13.5, fontWeight: FontWeight.w800))),
            Text(fmt(day.total),
                style: TextStyle(
                    color: c.ink, fontSize: 15, fontWeight: FontWeight.w800)),
          ]),
          row(yt, day.yt, 0),
          row(audio, day.audio, 1),
          row(tts, day.tts, 2),
          if (day.total == 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(context.lt('tap'),
                  style: TextStyle(color: c.inkSoft, fontSize: 11.5)),
            ),
        ],
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  final String label, value;
  const _Mini({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: c.goldSoft.withOpacity(0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: [
        Text(value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: c.ink, fontSize: 13, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: c.inkSoft, fontSize: 10.5)),
      ]),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  final bool active;
  final VoidCallback? onTap;
  const _Legend({
    required this.color,
    required this.label,
    this.active = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: active
                        ? context.appColors.ink
                        : context.appColors.inkSoft,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w400,
                    fontSize: 11.5)),
          ]),
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════
// Painter: ستون‌های انباشته (yt پایین، audio وسط، tts بالا) + خطوطِ راهنما
// ═══════════════════════════════════════════════════════════════════
class _ListenBarsPainter extends CustomPainter {
  final List<ListenDay> days; // قدیمی‌ترین اول
  final double progress;
  final int selected;
  final int? focus;
  final (Color, Color, Color) colors; // yt, audio, tts
  final Color grid, text, ink;
  final bool isRtl;
  final String Function(int sec) axisLabel;

  _ListenBarsPainter({
    required this.days,
    required this.progress,
    required this.selected,
    this.focus,
    required this.colors,
    required this.grid,
    required this.text,
    required this.ink,
    required this.isRtl,
    required this.axisLabel,
  });

  /// بالای محور: مضربِ «گردِ» بعدی (۵/۱۰/۱۵/۳۰ دقیقه، ۱/۲/۳… ساعت)
  static (int, int) _scale(int maxSec) {
    final m = math.max(maxSec, 60);
    const steps = [
      300, 600, 900, 1800, 3600, 7200, 10800, 14400, 21600, 28800 // ثانیه
    ];
    for (final s in steps) {
      // حداکثر ۴ خط
      if (m <= s * 3) {
        final top = ((m + s - 1) ~/ s) * s;
        return (top, s);
      }
    }
    final s = 28800;
    return (((m + s - 1) ~/ s) * s, s);
  }

  @override
  void paint(Canvas canvas, Size size) {
    const topPad = 8.0;
    final chartTop = topPad;
    final chartH = size.height - topPad;
    final plotW = size.width - _kGutter;
    // ناحیه‌ی رسم: RTL → محور سمتِ راست؛ LTR → محور سمتِ چپ
    final plotLeft = isRtl ? 0.0 : _kGutter;
    final slot = plotW / days.length;
    final barW = slot * 0.52;

    final maxSec = days.fold<int>(0, (a, d) => math.max(a, d.total));
    final (top, step) = _scale(maxSec);

    // خطوطِ راهنما + برچسبِ محور
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var v = 0; v <= top; v += step) {
      final y = chartTop + chartH - (v / top) * chartH;
      if (v == 0) {
        canvas.drawLine(Offset(plotLeft, y - 0.5),
            Offset(plotLeft + plotW, y - 0.5), gridPaint..strokeWidth = 1.4);
        gridPaint.strokeWidth = 1;
      } else {
        _dashed(canvas, Offset(plotLeft, y), Offset(plotLeft + plotW, y), gridPaint);
      }
      final label = axisLabel(v);
      if (label.isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
              text: label,
              style: TextStyle(color: text.withOpacity(0.85), fontSize: 10)),
          textDirection: TextDirection.ltr,
        )..layout();
        final x = isRtl ? plotW + 6 : (_kGutter - 6 - tp.width);
        tp.paint(canvas, Offset(x, y - tp.height / 2));
      }
    }

    // ستون‌ها
    for (var i = 0; i < days.length; i++) {
      final d = days[i];
      final cx = isRtl
          ? plotLeft + plotW - (i + 0.5) * slot
          : plotLeft + (i + 0.5) * slot;
      final isSel = i == selected;

      // زمینه‌ی ستونِ انتخاب‌شده
      if (isSel) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(cx - slot / 2 + 2, chartTop, slot - 4, chartH),
            const Radius.circular(10),
          ),
          Paint()..color = colors.$3.withOpacity(0.10),
        );
      }

      if (d.total <= 0) {
        // نقطه‌ی کوچک به‌جای ستونِ خالی
        canvas.drawCircle(Offset(cx, chartTop + chartH - 3), 2.2,
            Paint()..color = grid);
        continue;
      }

      final fullH = (d.total / top) * chartH * progress;
      final h = math.max(fullH, 6.0);
      final left = cx - barW / 2;
      final bottom = chartTop + chartH - 1.4;
      final barRect = RRect.fromRectAndCorners(
        Rect.fromLTWH(left, bottom - h, barW, h),
        topLeft: const Radius.circular(7),
        topRight: const Radius.circular(7),
        bottomLeft: const Radius.circular(2),
        bottomRight: const Radius.circular(2),
      );

      canvas.save();
      canvas.clipRRect(barRect);
      var y = bottom;
      void seg(int sec, Color col, int k) {
        if (sec <= 0) return;
        final sh = h * (sec / d.total);
        final op = focus == null
            ? (isSel ? 1.0 : 0.82)
            : (focus == k ? 1.0 : 0.2);
        canvas.drawRect(Rect.fromLTWH(left, y - sh, barW, sh),
            Paint()..color = col.withOpacity(op));
        y -= sh;
      }

      seg(d.yt, colors.$1, 0);
      seg(d.audio, colors.$2, 1);
      seg(d.tts, colors.$3, 2);
      canvas.restore();
    }
  }

  void _dashed(Canvas c, Offset a, Offset b, Paint p) {
    const dash = 4.0, gap = 4.0;
    var x = a.dx;
    while (x < b.dx) {
      c.drawLine(Offset(x, a.dy), Offset(math.min(x + dash, b.dx), a.dy), p);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_ListenBarsPainter o) =>
      o.progress != progress ||
      o.selected != selected ||
      o.focus != focus ||
      o.days != days ||
      o.isRtl != isRtl ||
      o.grid != grid;
}
