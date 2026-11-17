import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/topic_titles.dart' show topicTitle;
import '../../../core/native/native_bridge.dart';
import '../../../core/neural/neural_dates.dart' show gregorianToJalali, kPersianMonths;
import '../../../core/player_sync/playback_origin.dart';
import '../../../core/providers/story_library_provider.dart'
    show storyLibraryProvider;
import '../../../core/stats/listening_tracker.dart';
import '../../../core/storage/local_storage.dart' show sharedPrefsProvider;
import '../../../core/theme/app_theme_colors.dart';
import '../review_i18n.dart';

// ═══════════════════════════════════════════════════════════════════
// متن‌ها (۶ زبانِ برنامه) — بدونِ نیاز به تغییرِ فایل‌های ARB
// ═══════════════════════════════════════════════════════════════════
const Map<String, Map<String, String>> _kT = {
  'fa': {
    'vweek': "هفته",
    'vmonth': "ماه",
    'activedays': "روزِ فعال",
    'mtotal': "مجموعِ ماه",
    'goal': "هدف روزانه",
    'streakd': "{n} روز پشت‌سرهم",
    'streakn': "امروز گوش بده تا زنجیره شروع شود",
    'goalto': "{t} تا هدف",
    'goaldone': "هدف امروز انجام شد 🎉",
    'goalpick': "هدف روزانه‌ی گوش‌دادن",
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
    'tts': 'پلیر برنامه (تبِ نامشخص)',
    'scn': 'سناریو',
    'items': 'مورد',
    'holdhint': 'روی هر رنگِ ستون نگه دار (لمسِ طولانی) تا به همان تب و همان خط‌هایی که خواندی بروی؛ محدوده‌ی خوانده‌شده چند ثانیه رنگی می‌شود و محو می‌شود.',
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
    'vweek': "Week",
    'vmonth': "Month",
    'activedays': "active days",
    'mtotal': "Month total",
    'goal': "Daily goal",
    'streakd': "{n} days in a row",
    'streakn': "Listen today to start a streak",
    'goalto': "{t} to goal",
    'goaldone': "Today's goal reached 🎉",
    'goalpick': "Daily listening goal",
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
    'tts': 'App player (unknown tab)',
    'scn': 'Scenario',
    'items': 'items',
    'holdhint': 'Long-press a colour in a bar to jump to the exact tab and lines you read; the range is highlighted for a few seconds, then fades.',
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
    'vweek': "أسبوع",
    'vmonth': "شهر",
    'activedays': "أيام نشطة",
    'mtotal': "إجمالي الشهر",
    'goal': "الهدف اليومي",
    'streakd': "{n} أيام متتالية",
    'streakn': "استمع اليوم لتبدأ السلسلة",
    'goalto': "{t} للوصول إلى الهدف",
    'goaldone': "تم تحقيق هدف اليوم 🎉",
    'goalpick': "هدف الاستماع اليومي",
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
    'scn': 'السيناريو',
    'items': 'عناصر',
    'holdhint': 'اضغط مطولًا على أي لون في العمود للانتقال إلى التبويب والأسطر التي قرأتها؛ يُظهَر النطاق بضع ثوانٍ ثم يتلاشى.',
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
    'vweek': "Woche",
    'vmonth': "Monat",
    'activedays': "aktive Tage",
    'mtotal': "Monatssumme",
    'goal': "Tagesziel",
    'streakd': "{n} Tage in Folge",
    'streakn': "Hör heute zu, um eine Serie zu starten",
    'goalto': "Noch {t} bis zum Ziel",
    'goaldone': "Tagesziel erreicht 🎉",
    'goalpick': "Tägliches Hörziel",
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
    'vweek': "Semana",
    'vmonth': "Mes",
    'activedays': "días activos",
    'mtotal': "Total del mes",
    'goal': "Meta diaria",
    'streakd': "{n} días seguidos",
    'streakn': "Escucha hoy para empezar una racha",
    'goalto': "{t} para la meta",
    'goaldone': "Meta de hoy cumplida 🎉",
    'goalpick': "Meta diaria de escucha",
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
    'vweek': "Semaine",
    'vmonth': "Mois",
    'activedays': "jours actifs",
    'mtotal': "Total du mois",
    'goal': "Objectif du jour",
    'streakd': "{n} jours de suite",
    'streakn': "Écoutez aujourd'hui pour lancer une série",
    'goalto': "{t} avant l'objectif",
    'goaldone': "Objectif du jour atteint 🎉",
    'goalpick': "Objectif d'écoute quotidien",
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

/// نامِ زیرتب‌ها (مسیرِ تب → برچسب)
const Map<String, Map<String, String>> _kRoute = {
  'fa': {
    '/words': 'دیکشنری من',
    '/vocab-in-use': 'Vocab in use',
    '/slang': 'Slang',
    '/favorites': 'علاقه‌مندی‌ها',
    '/conversations': 'مکالمه',
    '/story': 'داستان',
  },
  'en': {
    '/words': 'My dictionary',
    '/vocab-in-use': 'Vocab in use',
    '/slang': 'Slang',
    '/favorites': 'Favorites',
    '/conversations': 'Conversation',
    '/story': 'Story',
  },
  'ar': {
    '/words': 'قاموسي',
    '/vocab-in-use': 'Vocab in use',
    '/slang': 'Slang',
    '/favorites': 'المفضلة',
    '/conversations': 'المحادثة',
    '/story': 'القصة',
  },
  'de': {
    '/words': 'Mein Wörterbuch',
    '/vocab-in-use': 'Vocab in use',
    '/slang': 'Slang',
    '/favorites': 'Favoriten',
    '/conversations': 'Gespräch',
    '/story': 'Geschichte',
  },
  'es': {
    '/words': 'Mi diccionario',
    '/vocab-in-use': 'Vocab in use',
    '/slang': 'Slang',
    '/favorites': 'Favoritos',
    '/conversations': 'Conversación',
    '/story': 'Historia',
  },
  'fr': {
    '/words': 'Mon dictionnaire',
    '/vocab-in-use': 'Vocab in use',
    '/slang': 'Slang',
    '/favorites': 'Favoris',
    '/conversations': 'Conversation',
    '/story': 'Histoire',
  },
};

/// نامِ ماه‌های میلادی (برای زبان‌هایی که ماهِ شمسی ندارند)
const Map<String, List<String>> _kMonthsG = {
  'en': ['January','February','March','April','May','June','July','August','September','October','November','December'],
  'ar': ['يناير','فبراير','مارس','أبريل','مايو','يونيو','يوليو','أغسطس','سبتمبر','أكتوبر','نوفمبر','ديسمبر'],
  'de': ['Januar','Februar','März','April','Mai','Juni','Juli','August','September','Oktober','November','Dezember'],
  'es': ['enero','febrero','marzo','abril','mayo','junio','julio','agosto','septiembre','octubre','noviembre','diciembre'],
  'fr': ['janvier','février','mars','avril','mai','juin','juillet','août','septembre','octobre','novembre','décembre'],
};

/// ماهِ نمایش‌داده‌شده: اولین روز، تعداد روز، عنوان و نامِ ماه
class _MonthInfo {
  final DateTime first;
  final int days;
  final String title;
  final String monthName;
  const _MonthInfo(this.first, this.days, this.title, this.monthName);
}

DateTime _addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

/// [off] = ۰ ماهِ جاری، -۱ ماهِ قبل … ؛ فارسی ← ماهِ شمسی، بقیه ← میلادی
_MonthInfo _monthAt(int off, String lang, DateTime today, String Function(Object) fmtNum) {
  if (lang == 'fa') {
    var jt = gregorianToJalali(today.year, today.month, today.day);
    var first = _addDays(today, -(jt[2] - 1));
    for (var i = 0; i < -off; i++) {
      final last = _addDays(first, -1);
      final jl = gregorianToJalali(last.year, last.month, last.day);
      first = _addDays(last, -(jl[2] - 1));
    }
    final jf = gregorianToJalali(first.year, first.month, first.day);
    var count = 1;
    var cur = first;
    while (count < 32) {
      final nxt = _addDays(cur, 1);
      if (gregorianToJalali(nxt.year, nxt.month, nxt.day)[1] != jf[1]) break;
      count++;
      cur = nxt;
    }
    final name = kPersianMonths[jf[1] - 1];
    return _MonthInfo(first, count, '$name ${fmtNum(jf[0])}', name);
  }
  final first = DateTime(today.year, today.month + off, 1);
  final days = DateTime(first.year, first.month + 1, 0).day;
  final names = _kMonthsG[lang] ?? _kMonthsG['en']!;
  final name = names[first.month - 1];
  return _MonthInfo(first, days, '$name ${first.year}', name);
}

/// ترتیبِ ثابتِ تب‌ها در ستون (پایین → بالا) و در راهنمای رنگ
const List<String> _kRouteOrder = [
  '/words',
  '/vocab-in-use',
  '/slang',
  '/favorites',
  '/conversations',
  '/story',
];

/// قطعه‌های رنگیِ یک روز: [(شناسه، ثانیه)]؛ شناسه = 'yt' | 'audio' | مسیرِ تب | 'tts'
/// ('tts' = پلیرِ برنامه که تبش معلوم نیست، مثلاً دیتای قدیمی یا 🔊 کارتِ انتخاب)
List<(String, int)> _segsOf(ListenDay d) {
  final out = <(String, int)>[];
  if (d.yt > 0) out.add(('yt', d.yt));
  if (d.audio > 0) out.add(('audio', d.audio));
  var used = 0;
  final routes = [
    ..._kRouteOrder.where(d.tabs.containsKey),
    ...d.tabs.keys.where((k) => !_kRouteOrder.contains(k)),
  ];
  for (final r in routes) {
    final v = d.tabs[r] ?? 0;
    if (v > 0) {
      out.add((r, v));
      used += v;
    }
  }
  final rest = d.tts - used;
  if (rest > 0) out.add(('tts', rest));
  return out;
}

extension _ListenI18n on BuildContext {
  /// رنگِ هر منبع/زیرتب
  Color lsrcColor(String id) {
    final c = appColors;
    switch (id) {
      case 'yt':
        return c.rose;
      case 'audio':
        return c.teal;
      case '/words':
        return c.gold;
      case '/slang':
        return const Color(0xFF8E5BB5);
      case '/vocab-in-use':
        return const Color(0xFF3F7FBF);
      case '/favorites':
        return const Color(0xFFD9774A);
      case '/conversations':
        return const Color(0xFF3F9B72);
      case '/story':
        return const Color(0xFF6B5B95);
      case 'tts':
        return const Color(0xFF8A8A8A);
      default:
        return const Color(0xFF8D6E4E);
    }
  }

  String lsrcLabel(String id) {
    if (id == 'yt') return lt('yt');
    if (id == 'audio') return lt('audio');
    if (id == 'tts') return lt('tts');
    final lang = Localizations.localeOf(this).languageCode;
    return (_kRoute[lang] ?? _kRoute['en']!)[id] ?? _kRoute['en']![id] ?? id;
  }

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
  int _goalMin = 15; // هدفِ روزانه (دقیقه)
  bool _month = false; // نمای ماهانه (فارسی: ماهِ شمسی)
  int _moff = 0; // ۰ = ماهِ جاری
  int? _msel; // روزِ انتخاب‌شده در ماه (۰-پایه)
  String? _src; // منبعِ فوکوس‌شده ('yt' | 'audio' | مسیرِ تب | 'tts')
  bool _needAccess = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAccess();
    try {
      final c = ProviderScope.containerOf(context, listen: false);
      final g = c.read(sharedPrefsProvider).getInt(_kGoalKey);
      if (g != null && g > 0) _goalMin = g;
    } catch (_) {}
  }

  static const String _kGoalKey = 'zflut-listen-goal-min';

  void _pickGoal() {
    final c = context.appColors;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.paper,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(context.lt('goalpick'),
                style: TextStyle(
                    color: c.ink, fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final m in const [10, 15, 20, 30, 45, 60, 90])
                GestureDetector(
                  onTap: () {
                    setState(() => _goalMin = m);
                    try {
                      ProviderScope.containerOf(context, listen: false)
                          .read(sharedPrefsProvider)
                          .setInt(_kGoalKey, m);
                    } catch (_) {}
                    Navigator.of(ctx).pop();
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    decoration: BoxDecoration(
                      color: m == _goalMin ? c.gold : c.goldSoft.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(context.ldur(m * 60),
                        style: TextStyle(
                            color: m == _goalMin ? Colors.white : c.ink,
                            fontWeight: FontWeight.w800,
                            fontSize: 13)),
                  ),
                ),
            ]),
          ]),
        ),
      ),
    );
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

  Widget _modeToggle(BuildContext context) {
    final c = context.appColors;
    Widget chip(bool month, String label) {
      final on = _month == month;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() {
            _month = month;
            _src = null;
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: on ? c.paper : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: on ? c.gold : Colors.transparent),
            ),
            alignment: Alignment.center,
            child: Text(label,
                style: TextStyle(
                    color: on ? c.ink : c.inkSoft,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.goldSoft.withOpacity(0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        chip(false, context.lt('vweek')),
        chip(true, context.lt('vmonth')),
      ]),
    );
  }

  /// 🗓 نمای ماهانه: نقشه‌ی حرارتیِ روزها (فارسی ← ماهِ شمسی) + جزئیاتِ روزِ انتخابی
  List<Widget> _monthChildren(BuildContext context, ListenStats stats,
      bool isRtl, String lang, DateTime today, int startWd) {
    final c = context.appColors;
    final m = _monthAt(_moff, lang, today, context.rvNum);
    final cutoff = _addDays(today, -119);
    final canPrev = !_addDays(m.first, -1).isBefore(cutoff);
    final canNext = _moff < 0;
    final dates = [for (var i = 0; i < m.days; i++) _addDays(m.first, i)];
    final days = [for (final d in dates) stats.day(d)];
    final segs = [for (final d in days) _segsOf(d)];
    final lead = (m.first.weekday - startWd + 7) % 7;
    final total = days.fold<int>(0, (a, d) => a + d.total);
    final elapsed = _moff == 0
        ? dates.where((d) => !d.isAfter(today)).length.clamp(1, 31).toInt()
        : m.days;
    final active = days.where((d) => d.total >= 60).length;
    var bestIdx = 0;
    for (var i = 1; i < days.length; i++) {
      if (days[i].total > days[bestIdx].total) bestIdx = i;
    }
    final todayIdx = dates.indexWhere((d) => d == today);
    final selIdx = (_msel != null && _msel! < m.days)
        ? _msel!
        : (todayIdx >= 0 ? todayIdx : bestIdx);
    final maxSec = days.fold<int>(0, (a, d) => math.max(a, d.total));
    final labels = context.rvWeekdayLetters;

    Widget navBtn(IconData icon, bool on, VoidCallback f) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: on ? f : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Icon(icon,
                size: 24, color: on ? c.ink : c.inkSoft.withOpacity(0.35)),
          ),
        );

    Widget cell(int? i) {
      if (i == null) return const Expanded(child: SizedBox(height: 40));
      final d = dates[i];
      final sec = days[i].total;
      final future = d.isAfter(today);
      final ratio = maxSec <= 0 ? 0.0 : (sec / maxSec).clamp(0.0, 1.0).toDouble();
      final fill = sec <= 0
          ? c.goldSoft.withOpacity(future ? 0.12 : 0.30)
          : c.gold.withOpacity(0.25 + 0.75 * ratio);
      final dark = sec > 0 && ratio > 0.55;
      final isSel = i == selIdx;
      final isTod = d == today;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() {
            _msel = i;
            _src = null;
          }),
          child: Container(
            height: 40,
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: isSel ? c.ink : (isTod ? c.gold : Colors.transparent),
                width: isSel ? 1.8 : 1.4,
              ),
            ),
            alignment: Alignment.center,
            child: Text(context.rvNum(i + 1),
                style: TextStyle(
                    color: dark ? Colors.white : (future ? c.inkSoft.withOpacity(0.5) : c.ink),
                    fontSize: 12,
                    fontWeight: isTod || isSel ? FontWeight.w800 : FontWeight.w500)),
          ),
        ),
      );
    }

    final rows = <Widget>[];
    final cells = <int?>[
      for (var i = 0; i < lead; i++) null,
      for (var i = 0; i < m.days; i++) i,
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    for (var r = 0; r < cells.length ~/ 7; r++) {
      rows.add(Row(children: [for (var k = 0; k < 7; k++) cell(cells[r * 7 + k])]));
    }

    final selDate = dates[selIdx];
    return [
      Row(children: [
        navBtn(isRtl ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
            canPrev, () => setState(() {
                  _moff--;
                  _msel = null;
                  _src = null;
                })),
        Expanded(
          child: Text(m.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: c.ink, fontSize: 14, fontWeight: FontWeight.w800)),
        ),
        navBtn(isRtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
            canNext, () => setState(() {
                  _moff++;
                  _msel = null;
                  _src = null;
                })),
      ]),
      const SizedBox(height: 8),
      Text(context.lt('mtotal'),
          style: TextStyle(color: c.inkSoft, fontSize: 12)),
      const SizedBox(height: 2),
      Text(context.ldur(total),
          style: TextStyle(
              color: c.ink, fontSize: 24, fontWeight: FontWeight.w800, height: 1.2)),
      const SizedBox(height: 12),
      Row(children: [
        for (var k = 0; k < 7; k++)
          Expanded(
            child: Text(labels[((startWd - 1 + k) % 7)],
                textAlign: TextAlign.center,
                style: TextStyle(color: c.inkSoft, fontSize: 11.5)),
          ),
      ]),
      const SizedBox(height: 4),
      ...rows,
      const SizedBox(height: 14),
      _DayDetail(
        focus: _src,
        isRtl: isRtl,
        segs: segs[selIdx],
        onFocus: (k) => setState(() => _src = _src == k ? null : k),
        onOpen: (r) => _openRoute(r, days[selIdx].last[r]),
        onOpenRead: (r, cx) => _openRoute(r, null, ctx: cx),
        title: selDate == today
            ? context.lt('today')
            : '${_fullDay(context, selDate)} ${context.rvNum(selIdx + 1)} ${m.monthName}',
        day: days[selIdx],
        fmt: context.ldur,
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
            child: _Mini(
                label: context.lt('avg'), value: context.ldur(total ~/ elapsed))),
        const SizedBox(width: 8),
        Expanded(
            child: _Mini(
                label: context.lt('best'),
                value: context.ldur(days[bestIdx].total))),
        const SizedBox(width: 8),
        Expanded(
            child: _Mini(
                label: context.lt('activedays'),
                value: context.rvNum(active))),
      ]),
    ];
  }

  /// 📍 رفتن به همان تب و همان جمله‌ای که آخرین بار گوش دادی.
  void _openRoute(String route, ListenPoint? p, {ReadCtx? ctx}) {
    try {
      final container = ProviderScope.containerOf(context, listen: false);
      final router = GoRouter.of(context);
      if (ctx != null) {
        // 📖 همان موضوع/سناریو/داستان + اسکرول به اولین جمله‌ی خوانده‌شده + هایلایتِ کلِ محدوده
        p = ListenPoint(ctx.ids.isEmpty ? null : ctx.ids.first, ctx.extra);
        showReadHighlight(container, ctx.ids,
            startAfter: const Duration(milliseconds: 1000));
      }
      if (p != null) {
        final origin = PlaybackOrigin(route, '', p.extra);
        container.read(tabRestoreProvider.notifier).state = origin;
        final id = p.id;
        if (id != null) container.read(revealItemProvider.notifier).state = id;
        // اگر تبی درخواست را برنداشت، بعداً اشتباهی اعمال نشود
        Future.delayed(const Duration(seconds: 4), () {
          try {
            if (identical(container.read(tabRestoreProvider), origin)) {
              container.read(tabRestoreProvider.notifier).state = null;
            }
            if (id != null && container.read(revealItemProvider) == id) {
              container.read(revealItemProvider.notifier).state = null;
            }
          } catch (_) {}
        });
      }
      router.go(route);
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
    // 🔥 زنجیره‌ی گوش‌دادن: روزهای پشت‌سرهم با حداقل ۱ دقیقه (اگر امروز هنوز نشنیده‌ای از دیروز می‌شمارد)
    var streak = 0;
    var sd = today;
    if (stats.day(sd).total < 60) sd = DateTime(sd.year, sd.month, sd.day - 1);
    while (streak < 120 && stats.day(sd).total >= 60) {
      streak++;
      sd = DateTime(sd.year, sd.month, sd.day - 1);
    }
    final todaySec = stats.day(today).total;
    final goalSec = _goalMin * 60;
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

    final segs = [for (final d in days) _segsOf(d)];
    // منبع‌های این هفته به ترتیبِ ثابت (برای راهنمای رنگ)
    final srcIds = <String>[
      for (final id in ['yt', 'audio', ..._kRouteOrder, 'tts'])
        if (segs.any((l) => l.any((e) => e.$1 == id))) id,
      for (final l in segs)
        for (final e in l)
          if (!['yt', 'audio', 'tts', ..._kRouteOrder].contains(e.$1)) e.$1,
    ].toSet().toList();

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

    if (_month) {
      return Directionality(
        textDirection: dir,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _modeToggle(context),
            const SizedBox(height: 12),
            ..._monthChildren(context, stats, isRtl, lang, today, startWd),
            if (_needAccess) accessHint(),
          ],
        ),
      );
    }

    return Directionality(
      textDirection: dir,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _modeToggle(context),
          const SizedBox(height: 12),
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

          if (_off == 0) ...[
            _GoalCard(
              streak: streak,
              todaySec: todaySec,
              goalSec: goalSec,
              onTap: _pickGoal,
            ),
            const SizedBox(height: 14),
          ],

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
                    // روی یکی از رنگ‌های ستون زده شد؟ زیرتب ← مستقیم به همان تب و جمله؛
                    // یوتیوب/فایل صوتی ← فقط هایلایت
                    String? hit;
                    final dd = days[i];
                    if (dd.total > 0 && segs[i].isNotEmpty) {
                      final (top, _) = _ListenBarsPainter._scale(maxSec);
                      const chartTop = 8.0;
                      final chartH = 168.0 - chartTop;
                      final bottom = chartTop + chartH - 1.4;
                      final h = math.max((dd.total / top) * chartH, 6.0);
                      final f = (bottom - d.localPosition.dy) / h;
                      if (f >= 0 && f <= 1) {
                        var acc = 0.0;
                        for (final e in segs[i]) {
                          acc += e.$2 / dd.total;
                          if (f < acc) {
                            hit = e.$1;
                            break;
                          }
                        }
                        hit ??= segs[i].last.$1;
                      }
                    }
                    final tapped = hit;
                    if (tapped != null && tapped.startsWith('/')) {
                      setState(() {
                        _sel = i;
                        _src = tapped;
                      });
                      _openRoute(tapped, dd.last[tapped]);
                      return;
                    }
                    setState(() {
                      _src = (tapped != null && tapped == _src && i == selIdx)
                          ? null
                          : tapped;
                      _sel = i;
                    });
                  },
                  // 📖 لمسِ طولانیِ یک رنگِ ستون: رفتن به همان تب و همان خط‌های خوانده‌شده
                  onLongPressStart: (d) {
                    final w = box.maxWidth - _kGutter;
                    final x = isRtl
                        ? (box.maxWidth - _kGutter) - d.localPosition.dx
                        : d.localPosition.dx - _kGutter;
                    if (x < 0 || x > w) return;
                    final i = (x / (w / 7)).floor().clamp(0, 6).toInt();
                    final dd = days[i];
                    if (dd.total <= 0 || segs[i].isEmpty) return;
                    final (top, _) = _ListenBarsPainter._scale(maxSec);
                    const chartTop = 8.0;
                    final chartH = 168.0 - chartTop;
                    final bottom = chartTop + chartH - 1.4;
                    final h = math.max((dd.total / top) * chartH, 6.0);
                    final f = (bottom - d.localPosition.dy) / h;
                    if (f < 0 || f > 1) return;
                    String? hit;
                    var acc = 0.0;
                    for (final e in segs[i]) {
                      acc += e.$2 / dd.total;
                      if (f < acc) {
                        hit = e.$1;
                        break;
                      }
                    }
                    hit ??= segs[i].last.$1;
                    if (!hit.startsWith('/')) return;
                    final route = hit;
                    setState(() {
                      _sel = i;
                      _src = route;
                    });
                    final ctxs = dd.reads[route];
                    if (ctxs != null && ctxs.isNotEmpty) {
                      _openRoute(route, null, ctx: ctxs.last);
                    } else {
                      _openRoute(route, dd.last[route]);
                    }
                  },
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 650),
                    curve: Curves.easeOutCubic,
                    builder: (_, t, __) => CustomPaint(
                      size: Size(box.maxWidth, 168),
                      painter: _ListenBarsPainter(
                        days: days,
                        segs: segs,
                        colorOf: context.lsrcColor,
                        progress: t,
                        selected: selIdx,
                        focus: _src,
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
              isRtl: isRtl,
              segs: segs[selIdx],
              onFocus: (k) => setState(() => _src = _src == k ? null : k),
              onOpen: (r) => _openRoute(r, sel.last[r]),
              onOpenRead: (r, cx) => _openRoute(r, null, ctx: cx),
              title: isToday
                  ? context.lt('today')
                  : _fullDay(context, dates[selIdx]),
              day: sel,
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
                for (final id in srcIds)
                  _Legend(
                      color: context.lsrcColor(id),
                      label: context.lsrcLabel(id),
                      active: _src == id,
                      onTap: () => setState(() => _src = _src == id ? null : id)),
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
class _GoalCard extends StatelessWidget {
  final int streak, todaySec, goalSec;
  final VoidCallback onTap;
  const _GoalCard({
    required this.streak,
    required this.todaySec,
    required this.goalSec,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final done = todaySec >= goalSec;
    final p = (todaySec / goalSec).clamp(0.0, 1.0).toDouble();
    final col = done ? const Color(0xFF3F9B72) : c.gold;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: c.goldSoft.withOpacity(0.45),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Text(streak > 0 ? '🔥' : '🎧', style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  streak > 0
                      ? context.lt('streakd').replaceAll('{n}', context.rvNum(streak))
                      : context.lt('streakn'),
                  style: TextStyle(
                      color: c.ink, fontSize: 13.5, fontWeight: FontWeight.w800),
                ),
              ),
              Icon(Icons.flag_rounded, size: 15, color: c.inkSoft),
              const SizedBox(width: 3),
              Text(context.ldur(goalSec),
                  style: TextStyle(color: c.inkSoft, fontSize: 11.5)),
            ]),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: p,
                minHeight: 9,
                backgroundColor: c.paperDark,
                valueColor: AlwaysStoppedAnimation<Color>(col),
              ),
            ),
            const SizedBox(height: 7),
            Row(children: [
              Expanded(
                child: Text(
                  done
                      ? context.lt('goaldone')
                      : context.lt('goalto').replaceAll('{t}', context.ldur(goalSec - todaySec)),
                  style: TextStyle(
                      color: done ? col : c.inkSoft,
                      fontSize: 12,
                      fontWeight: done ? FontWeight.w800 : FontWeight.w500),
                ),
              ),
              Text(context.ldur(todaySec),
                  style: TextStyle(
                      color: c.ink, fontSize: 12, fontWeight: FontWeight.w800)),
            ]),
          ],
        ),
      ),
    );
  }
}

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

/// نامِ خوانا برای «چه چیزی خوانده شد»: موضوع/سناریوی مکالمه، عنوانِ داستان، یا نامِ تب.
String _ctxLabel(BuildContext context, String route, ReadCtx cx) {
  final lang = Localizations.localeOf(context).languageCode;
  try {
    if (route == '/conversations') {
      final t = cx.extra['topic'];
      final sc = cx.extra['scenario'];
      final parts = <String>[
        if (t is String && t.isNotEmpty) topicTitle(t, lang),
        if (sc is num) '${context.lt('scn')} ${context.rvNum(sc.toInt() + 1)}',
      ];
      if (parts.isNotEmpty) return parts.join(' · ');
    } else if (route == '/story') {
      final sid = cx.extra['storyId'];
      if (sid is String) {
        final list = ProviderScope.containerOf(context, listen: false)
            .read(storyLibraryProvider);
        for (final st in list) {
          if (st.id == sid) return st.title;
        }
      }
    }
  } catch (_) {}
  return context.lsrcLabel(route);
}

class _DayDetail extends StatelessWidget {
  final String title;
  final ListenDay day;
  final List<(String, int)> segs;
  final String Function(int) fmt;
  final String? focus;
  final bool isRtl;
  final void Function(String)? onFocus;
  final void Function(String)? onOpen;
  final void Function(String, ReadCtx)? onOpenRead;
  const _DayDetail({
    this.focus,
    this.onFocus,
    this.onOpen,
    this.onOpenRead,
    this.isRtl = true,
    required this.segs,
    required this.title,
    required this.day,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    Widget row(String id, int sec) {
      final col = context.lsrcColor(id);
      final isTab = id.startsWith('/');
      // رفتن به تب فقط وقتی «آخرین جای» ثبت شده باشد
      final canOpen = isTab && day.last.containsKey(id);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (canOpen) {
            onOpen?.call(id);
          } else {
            onFocus?.call(id);
          }
        },
        child: Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: focus == id ? col.withOpacity(0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
                color: focus == id ? col : Colors.transparent, width: 1.2),
          ),
          child: Row(children: [
            Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(
                child: Text(context.lsrcLabel(id),
                    style: TextStyle(color: c.inkSoft, fontSize: 12.5))),
            Text(fmt(sec),
                style: TextStyle(
                    color: c.ink, fontSize: 12.5, fontWeight: FontWeight.w700)),
            if (canOpen) ...[
              const SizedBox(width: 4),
              Icon(isRtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                  size: 18, color: col),
            ],
          ]),
        ),
      );
    }

    // 📖 زیرِ هر تب: چه موضوع/سناریو/داستانی و چند مورد خوانده شد (لمس = رفتن + هایلایت)
    List<Widget> ctxRows(String id) {
      final list = day.reads[id];
      if (list == null || list.isEmpty) return const <Widget>[];
      final col = context.lsrcColor(id);
      return [
        for (final cx in list.reversed)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onOpenRead?.call(id, cx),
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 17, top: 5),
              child: Row(children: [
                Icon(Icons.subdirectory_arrow_right_rounded,
                    size: 14, color: c.inkSoft),
                const SizedBox(width: 4),
                Expanded(
                    child: Text(_ctxLabel(context, id, cx),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.inkSoft, fontSize: 11.5))),
                const SizedBox(width: 6),
                Text('${context.rvNum(cx.ids.length)} ${context.lt('items')}',
                    style: TextStyle(
                        color: c.ink,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700)),
                Icon(
                    isRtl
                        ? Icons.chevron_left_rounded
                        : Icons.chevron_right_rounded,
                    size: 16,
                    color: col),
              ]),
            ),
          ),
      ];
    }

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
          for (final e in segs) ...[
            row(e.$1, e.$2),
            ...ctxRows(e.$1),
          ],
          if (day.reads.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(context.lt('holdhint'),
                  style: TextStyle(color: c.inkSoft, fontSize: 11)),
            ),
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
  final List<ListenDay> days; // اولین روزِ هفته اول
  final List<List<(String, int)>> segs;
  final Color Function(String) colorOf;
  final double progress;
  final int selected;
  final String? focus;
  final Color grid, text, ink;
  final bool isRtl;
  final String Function(int sec) axisLabel;

  _ListenBarsPainter({
    required this.days,
    required this.segs,
    required this.colorOf,
    required this.progress,
    required this.selected,
    this.focus,
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
          Paint()..color = grid.withOpacity(0.45),
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
      for (final e in segs[i]) {
        final sh = h * (e.$2 / d.total);
        final op = focus == null
            ? (isSel ? 1.0 : 0.82)
            : (focus == e.$1 ? 1.0 : 0.2);
        canvas.drawRect(Rect.fromLTWH(left, y - sh, barW, sh),
            Paint()..color = colorOf(e.$1).withOpacity(op));
        y -= sh;
      }
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
      o.segs != segs ||
      o.isRtl != isRtl ||
      o.grid != grid;
}
