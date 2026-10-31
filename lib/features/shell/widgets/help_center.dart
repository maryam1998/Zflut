import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_prefs_provider.dart';
import '../../../core/theme/app_theme_colors.dart';
import 'intro_overlay.dart';

// ═══════════════════════════════════════════════════════════════════
// مرکز راهنما — دسته‌بندی + جستجو. متن‌ها فارسی/انگلیسی‌اند؛
// برای بقیه‌ی زبان‌ها انگلیسی نشان داده می‌شود. برای افزودن مطلب:
// یک _Article به _articles اضافه کن (cat = کلیدِ یکی از _cats).
// ═══════════════════════════════════════════════════════════════════

class _Cat {
  final String key;
  final IconData icon;
  final Map<String, String> label;
  const _Cat(this.key, this.icon, this.label);
}

class _Article {
  final String cat;
  final Map<String, String> title;
  final Map<String, String> body;
  final String keywords; // کلیدواژه‌های اضافه برای جستجو (هر دو زبان)
  const _Article(this.cat, this.title, this.body, [this.keywords = '']);
}

const List<_Cat> _cats = [
  _Cat('start', Icons.rocket_launch_rounded,
      {'en': 'Getting started', 'fa': 'شروع کار'}),
  _Cat('story', Icons.auto_stories_rounded,
      {'en': 'Story builder', 'fa': 'داستان‌ساز'}),
  _Cat('words', Icons.bookmark_rounded,
      {'en': 'Words & review', 'fa': 'لغات و مرور'}),
  _Cat('audio', Icons.volume_up_rounded,
      {'en': 'Voice & audio', 'fa': 'صدا و تلفظ'}),
  _Cat('lang', Icons.translate_rounded,
      {'en': 'Languages & translation', 'fa': 'زبان‌ها و ترجمه'}),
  _Cat('fix', Icons.build_rounded,
      {'en': 'Troubleshooting', 'fa': 'حل مشکل'}),
];

const List<_Article> _articles = [
  // ── شروع کار ──
  _Article(
    'start',
    {'en': 'How the app is organized', 'fa': 'برنامه چطور چیده شده؟'},
    {
      'en': 'The main tabs are Talk (conversations), Words (daily words and vocabulary), Story (build and read stories) and Practice (favorites and review). Your language choices at the top apply to all of them.',
      'fa': 'تب‌های اصلی: گفتگو (Talk)، لغات (Words)، داستان (Story) و تمرین (Practice) که شامل علاقه‌مندی‌ها و مرور است. زبان‌هایی که بالای صفحه انتخاب می‌کنی روی همه‌ی تب‌ها اثر دارد.',
    },
    'tabs talk words story practice home تب صفحه اصلی',
  ),
  _Article(
    'start',
    {'en': 'Tap a word to translate it', 'fa': 'ترجمه‌ی کلمه با یک لمس'},
    {
      'en': 'Tap any word or sentence to open its card: translation, listen, and buttons to save it for your next story or add a grammar note.',
      'fa': 'روی هر کلمه یا جمله بزن تا کارتش باز شود: ترجمه، گوش‌دادن، و دکمه‌هایی برای ذخیره برای داستان بعدی یا افزودن یادداشت گرامر.',
    },
    'translate selection card save bookmark ترجمه ذخیره کارت',
  ),
  _Article(
    'start',
    {'en': 'Replay the intro', 'fa': 'نمایش دوباره‌ی معرفی'},
    {
      'en': 'Use the “Show intro again” button at the bottom of this page to replay the short welcome tour.',
      'fa': 'از دکمه‌ی «نمایش دوباره‌ی معرفی» پایین همین صفحه می‌توانی تور کوتاه خوش‌آمدگویی را دوباره ببینی.',
    },
    'intro tour welcome معرفی راهنما',
  ),

  // ── داستان‌ساز ──
  _Article(
    'story',
    {'en': 'Create a story step by step', 'fa': 'ساخت داستان مرحله‌به‌مرحله'},
    {
      'en': '1) Choose a level (A1–C2), content type and length.\n2) Add words: type any word in any language (it is translated to the story language) or search the built-in lists.\n3) Pick which languages the story should be translated into.\n4) Generate. You can listen to it and read the translations under each paragraph.',
      'fa': '۱) سطح (A1 تا C2)، نوع محتوا و طول داستان را انتخاب کن.\n۲) لغت اضافه کن: هر کلمه‌ای را به هر زبانی بنویس (به زبان داستان ترجمه می‌شود) یا در لیست‌های آماده جستجو کن.\n۳) زبان‌هایی را که داستان باید به آن‌ها ترجمه شود انتخاب کن.\n۴) بساز. می‌توانی داستان را گوش بدهی و زیر هر بند ترجمه‌ها را بخوانی.',
    },
    'create generate level A1 B1 C2 length short long ساخت سطح طول کوتاه بلند',
  ),
  _Article(
    'story',
    {'en': 'Saved for next story', 'fa': 'لغات ذخیره‌شده برای داستان بعدی'},
    {
      'en': 'Words you bookmark with “Save for next story” collect in the Saved tab of the Story builder. Tap words to select them, then press “Add to Story Builder”. Translations are shown in your native and target languages.',
      'fa': 'لغاتی که با «ذخیره برای داستان بعدی» نشان می‌کنی در زیرتب ذخیره‌شده‌ها جمع می‌شوند. روی لغت‌ها بزن تا انتخاب شوند و بعد «افزودن به داستان‌ساز» را بزن. ترجمه‌ها به زبان مادری و زبان‌های مقصدت نمایش داده می‌شود.',
    },
    'saved bookmark add select ذخیره افزودن انتخاب',
  ),
  _Article(
    'story',
    {'en': 'My typed word was not translated', 'fa': 'کلمه‌ای که نوشتم ترجمه نشد'},
    {
      'en': 'Make sure the story language is selected and you are online. Very informal sentences can fail on the first try — remove the word and add it again, or rephrase it slightly.',
      'fa': 'مطمئن شو زبان داستان انتخاب شده و به اینترنت وصلی. جمله‌های خیلی محاوره‌ای ممکن است بار اول ترجمه نشوند؛ لغت را حذف و دوباره اضافه کن یا کمی بازنویسی‌اش کن.',
    },
    'translation failed colloquial informal محاوره ترجمه نشد',
  ),

  // ── لغات و مرور ──
  _Article(
    'words',
    {'en': 'How review (Leitner) works', 'fa': 'مرور لایتنر چطور کار می‌کند؟'},
    {
      'en': 'Words you add to review live in boxes 1–5. Each time you recall a word correctly it moves up and comes back after a longer gap (1, 3, 7, 14, then 30 days). If you forget, it returns sooner. Open Practice › Review to start.',
      'fa': 'لغاتی که به مرور اضافه می‌کنی در جعبه‌های ۱ تا ۵ قرار می‌گیرند. هر بار درست یادت بیاید یک جعبه بالا می‌رود و با فاصله‌ی بیشتری برمی‌گردد (۱، ۳، ۷، ۱۴ و بعد ۳۰ روز). اگر فراموش کنی زودتر برمی‌گردد. برای شروع: تمرین › مرور.',
    },
    'leitner box review spaced repetition flashcard جعبه مرور فلش‌کارت',
  ),
  _Article(
    'words',
    {'en': 'Favorites', 'fa': 'علاقه‌مندی‌ها'},
    {
      'en': 'Mark words or phrases with the heart to find them later in Practice › Favorites.',
      'fa': 'با زدن قلب روی لغت یا عبارت، می‌توانی بعداً آن را در تمرین › علاقه‌مندی‌ها پیدا کنی.',
    },
    'favorite heart like قلب',
  ),
  _Article(
    'words',
    {'en': 'Which languages show on review cards', 'fa': 'ترجمه‌ی کارت مرور به چه زبانی است؟'},
    {
      'en': 'The back of a review card shows translations in your native language plus your target languages. A language is shown only once, and the word’s own language is skipped.',
      'fa': 'پشت کارت مرور، ترجمه‌ها به زبان مادری و زبان‌های مقصد نمایش داده می‌شود. هر زبان فقط یک‌بار می‌آید و زبان خودِ لغت تکرار نمی‌شود.',
    },
    'review card translation native target کارت ترجمه مادری مقصد',
  ),

  // ── صدا ──
  _Article(
    'audio',
    {'en': 'App voice vs Phone’s voice', 'fa': 'صدای برنامه یا صدای گوشی؟'},
    {
      'en': 'Settings › Reading voice. “App voice” is higher quality and needs a one-time download per language; “Phone’s voice” uses the voice installed on your device. When App voice is on, tapping 🔊 on a language that is not installed starts its download automatically (the phone voice is used until it finishes).',
      'fa': 'تنظیمات › صدای خوانش. «صدای برنامه» کیفیت بهتری دارد و برای هر زبان یک‌بار دانلود می‌شود؛ «صدای گوشی» از صدای نصب‌شده روی دستگاهت استفاده می‌کند. وقتی صدای برنامه فعال است، با زدن 🔊 روی زبانی که نصب نیست، دانلودش خودکار شروع می‌شود (تا آماده شدن با صدای گوشی خوانده می‌شود).',
    },
    'tts voice download offline piper صدا دانلود آفلاین',
  ),
  _Article(
    'audio',
    {'en': 'Player controls', 'fa': 'دکمه‌های پلیر'},
    {
      'en': 'The bottom player lets you change speed, jump ±10 seconds, loop a section (A-B), repeat, change volume and record your own voice to compare pronunciation.',
      'fa': 'پلیر پایین صفحه: تغییر سرعت، پرش ۱۰ ثانیه به جلو/عقب، تکرار بخش (A-B)، تکرار، تنظیم صدا، و ضبط صدای خودت برای مقایسه‌ی تلفظ.',
    },
    'player speed loop a-b record mic سرعت تکرار ضبط میکروفون',
  ),

  // ── زبان‌ها ──
  _Article(
    'lang',
    {'en': 'Native vs target languages', 'fa': 'زبان مادری و زبان مقصد'},
    {
      'en': 'Native language = the language you understand best. Target languages = what you are learning (you can pick several). Drag the chips under “Translation display order” to reorder how translations appear.',
      'fa': 'زبان مادری = زبانی که بهتر می‌فهمی. زبان‌های مقصد = زبان‌هایی که یاد می‌گیری (می‌توانی چند تا انتخاب کنی). برای تغییر ترتیب نمایش ترجمه‌ها، چیپ‌های «ترتیب نمایش ترجمه» را بکش و جابه‌جا کن.',
    },
    'native target order drag reorder مادری مقصد ترتیب',
  ),
  _Article(
    'lang',
    {'en': 'Change the app’s interface language', 'fa': 'تغییر زبان رابط برنامه'},
    {
      'en': 'Open Settings (top corner) and choose a language under the app-language section. This only changes menus and texts, not the languages you learn.',
      'fa': 'تنظیمات را باز کن (گوشه‌ی بالا) و از بخش زبان نرم‌افزار زبان را انتخاب کن. این فقط منوها و متن‌ها را عوض می‌کند، نه زبان‌هایی که یاد می‌گیری.',
    },
    'interface ui language settings زبان نرم افزار رابط تنظیمات',
  ),

  // ── حل مشکل ──
  _Article(
    'fix',
    {'en': 'No sound', 'fa': 'صدا پخش نمی‌شود'},
    {
      'en': 'Check the phone volume and silent mode. In Settings › Reading voice, see whether the language is still downloading (percentage shown) or try switching to Phone’s voice.',
      'fa': 'صدای گوشی و حالت بی‌صدا را چک کن. در تنظیمات › صدای خوانش ببین دانلود آن زبان هنوز در جریان است (درصد نشان داده می‌شود) یا موقتاً «صدای گوشی» را انتخاب کن.',
    },
    'no sound silent mute بی صدا صدا نمیاد',
  ),
  _Article(
    'fix',
    {'en': 'Translations or stories do not load', 'fa': 'ترجمه یا داستان بارگذاری نمی‌شود'},
    {
      'en': 'These features need an internet connection. Check your connection, wait a moment, and try again. Previously translated words are remembered and work faster the second time.',
      'fa': 'این قابلیت‌ها به اینترنت نیاز دارند. اتصال را چک کن، کمی صبر کن و دوباره امتحان کن. ترجمه‌هایی که قبلاً گرفته شده ذخیره می‌شوند و بار دوم سریع‌تر نمایش داده می‌شوند.',
    },
    'internet offline error slow اینترنت خطا کند',
  ),
];

String _norm(String s) {
  var t = s.toLowerCase();
  const map = {
    'ي': 'ی', 'ك': 'ک', 'ة': 'ه', 'أ': 'ا', 'إ': 'ا', 'آ': 'ا', 'ۀ': 'ه',
    'á': 'a', 'à': 'a', 'é': 'e', 'è': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u',
    'ñ': 'n', 'ü': 'u', 'ö': 'o', 'ä': 'a', 'ß': 'ss', 'ç': 'c',
  };
  map.forEach((k, v) => t = t.replaceAll(k, v));
  return t
      .replaceAll(RegExp(r'[\u064B-\u065F\u200c\u200f\u200e]'), '')
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ');
}

/// دکمه‌ی ورود به مرکز راهنما (در تنظیمات).
class HelpCenterButton extends ConsumerWidget {
  const HelpCenterButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final fa = ref.watch(appPrefsProvider).uiLang == 'fa';
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.ink,
        side: BorderSide(color: c.cardBorder),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: Icon(Icons.help_outline_rounded, color: c.gold),
      label: Text(fa ? 'راهنما' : 'Help center'),
      onPressed: () => Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
            fullscreenDialog: true, builder: (_) => const HelpCenterPage()),
      ),
    );
  }
}

class HelpCenterPage extends ConsumerStatefulWidget {
  const HelpCenterPage({super.key});

  @override
  ConsumerState<HelpCenterPage> createState() => _HelpCenterPageState();
}

class _HelpCenterPageState extends ConsumerState<HelpCenterPage> {
  final _search = TextEditingController();
  String _cat = 'all';
  int? _open;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final lang = ref.watch(appPrefsProvider).uiLang;
    final fa = lang == 'fa';
    String t(Map<String, String> m) => m[lang] ?? m['en']!;
    final rtl = lang == 'fa' || lang == 'ar';

    final tokens = _norm(_search.text)
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();

    final scored = <MapEntry<_Article, int>>[];
    for (final a in _articles) {
      if (tokens.isEmpty && _cat != 'all' && a.cat != _cat) continue;
      if (tokens.isEmpty) {
        scored.add(MapEntry(a, 0));
        continue;
      }
      final title = _norm('${a.title['en']} ${a.title['fa']} ${t(a.title)}');
      final rest =
          _norm('${t(a.body)} ${a.body['en']} ${a.keywords}');
      var score = 0;
      var ok = true;
      for (final tok in tokens) {
        if (title.contains(tok)) {
          score += 3;
        } else if (rest.contains(tok)) {
          score += 1;
        } else {
          ok = false;
          break;
        }
      }
      if (ok) scored.add(MapEntry(a, score));
    }
    if (tokens.isNotEmpty) scored.sort((a, b) => b.value.compareTo(a.value));
    final list = scored.map((e) => e.key).toList();

    return Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: c.paper,
        appBar: AppBar(
          backgroundColor: c.paper,
          foregroundColor: c.ink,
          elevation: 0,
          title: Text(fa ? 'راهنما' : 'Help center',
              style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() => _open = null),
                decoration: InputDecoration(
                  hintText: fa ? 'جستجو در راهنما…' : 'Search the help…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => setState(() {
                            _search.clear();
                            _open = null;
                          }),
                        ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide(color: c.cardBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide(color: c.cardBorder),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _chip(c, fa ? 'همه' : 'All', Icons.apps_rounded,
                      _cat == 'all', () => setState(() {
                            _cat = 'all';
                            _open = null;
                          })),
                  for (final k in _cats)
                    _chip(c, t(k.label), k.icon, _cat == k.key,
                        () => setState(() {
                              _cat = k.key;
                              _open = null;
                            })),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: list.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Text(
                          fa
                              ? 'چیزی پیدا نشد. با کلمه‌ی دیگری امتحان کن.'
                              : 'Nothing found. Try another word.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: c.inkSoft, fontSize: 15),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final a = list[i];
                        final open = _open == i;
                        final cat = _cats.firstWhere((e) => e.key == a.cat);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: open ? c.gold : c.cardBorder),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => setState(() => _open = open ? null : i),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(cat.icon, size: 18, color: c.gold),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(t(a.title),
                                            style: TextStyle(
                                                color: c.ink,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700)),
                                      ),
                                      Icon(
                                          open
                                              ? Icons.expand_less_rounded
                                              : Icons.expand_more_rounded,
                                          color: c.inkSoft),
                                    ],
                                  ),
                                  if (tokens.isNotEmpty && !open)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(t(cat.label),
                                          style: TextStyle(
                                              color: c.inkSoft, fontSize: 11)),
                                    ),
                                  if (open)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 10),
                                      child: Text(t(a.body),
                                          style: TextStyle(
                                              color: c.ink,
                                              fontSize: 14,
                                              height: 1.7)),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.ink,
                      side: BorderSide(color: c.cardBorder),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: Icon(Icons.slideshow_rounded, color: c.gold),
                    label: Text(fa
                        ? 'نمایش دوباره‌ی معرفی'
                        : 'Show intro again'),
                    onPressed: () {
                      Navigator.of(context, rootNavigator: true)
                          .popUntil((r) => r.isFirst);
                      IntroOverlay.replay();
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(AppThemeColorsExt c, String label, IconData icon, bool sel,
      VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: sel ? c.gold : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: sel ? c.gold : c.cardBorder),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: sel ? Colors.white : c.inkSoft),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      color: sel ? Colors.white : c.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
