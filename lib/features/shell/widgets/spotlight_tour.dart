import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/app_prefs_provider.dart';
import '../../../core/providers/language_selection_provider.dart';
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
const String _kStoryTourSeenKey = 'zflut-tour-story-seen-v1';
const String _kTransTourSeenKey = 'zflut-tour-trans-seen-v1';
const String _kPopupTourSeenKey = 'zflut-tour-popup-seen-v1';
const String _kConvTourSeenKey = 'zflut-tour-conv-seen-v1';

final Map<String, _TourTargetState> _targets = {};

/// چند ویجت می‌توانند یک id داشته باشند (مثلاً دکمه‌ی رفرشِ هر ردیفِ ترجمه)؛ تور اولین نمونه‌ی
/// «قابل‌دیدن» را انتخاب می‌کند. برای idهای تک‌نمونه رفتار همان قبل است.
final Map<String, Set<_TourTargetState>> _multi = {};

/// 🎓 متنی که تور می‌تواند «خودش» روی آن لغت بزند یا عبارت انتخاب کند (SelectableSyncText
/// خودش را ثبت می‌کند). [open] کارتِ ترجمه را باز می‌کند و Future برمی‌گرداند که با بسته‌شدنِ
/// کارت تمام می‌شود (null = نشد). [closeCard] کارتِ باز را می‌بندد.
class TourDemoSource {
  final Rect? Function() rect;
  final Future<void>? Function(bool phrase) open;
  final void Function() closeCard;
  const TourDemoSource({
    required this.rect,
    required this.open,
    required this.closeCard,
  });
}

final List<TourDemoSource> _demoSources = <TourDemoSource>[];

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
    (_multi[widget.id] ??= <_TourTargetState>{}).add(this);
  }

  @override
  void dispose() {
    if (identical(_targets[widget.id], this)) _targets.remove(widget.id);
    _multi[widget.id]?.remove(this);
    if (_multi[widget.id]?.isEmpty ?? false) _multi.remove(widget.id);
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

  /// اگر چند مرحله روی یک هدف باشند، id هدف (پیش‌فرض: همان [id]).
  final String? target;
  const _Step(this.id, this.icon, this.title, this.body, [this.hold, this.target]);
  String get tid => target ?? id;
}

const List<_Step> _steps = [
  _Step(
    'account',
    Icons.menu_rounded,
    {'en': 'Menu and settings', 'fa': 'منو و تنظیمات'},
    {
      'en': 'Themes, fonts, offline voices, your account and the help center are all here.',
      'fa': 'تم، فونت، صداهای آفلاین، حساب کاربری و مرکز راهنما اینجاست.',
    },
  ),
  _Step(
    'lang',
    Icons.translate_rounded,
    {'en': 'Your languages', 'fa': 'زبان‌های تو'},
    {
      'en': 'Pick your native language, then tap the circles to choose one or more languages to learn. Translations appear in all of them, side by side. Watch: the tour turns a circle on and off by itself.',
      'fa': 'زبان مادری‌ات را انتخاب کن، بعد روی دایره‌ها بزن و یک یا چند زبان برای یادگیری انتخاب کن. ترجمه‌ها به همه‌ی آن زبان‌ها، کنار هم نشان داده می‌شود. نگاه کن: تور خودش یک دایره را روشن و خاموش می‌کند.',
    },
  ),
  _Step(
    'tabs',
    Icons.dashboard_rounded,
    {'en': 'The four sections', 'fa': 'چهار بخش اصلی'},
    {
      'en': 'Talk: ready-made everyday conversations to practise. Story: build stories and read PDFs, photos and links. Words: your dictionary and saved words. Practice: review what you learned.',
      'fa': 'گفتگو: مکالمه‌های پرکاربرد برای تمرین. داستان: ساخت داستان و خواندن PDF، عکس و لینک. لغات: دیکشنری و لغت‌های ذخیره‌شده. مرور: تمرین و مرور آنچه یاد گرفته‌ای.',
    },
  ),
  _Step(
    'play',
    Icons.play_arrow_rounded,
    {'en': 'Play / pause', 'fa': 'پخش و توقف'},
    {
      'en': 'Reads the page aloud, one sentence at a time.',
      'fa': 'متن صفحه را جمله‌به‌جمله می‌خواند.',
    },
    {
      'en': 'Jumps to the line and tab that is being read.',
      'fa': 'به همان خط و همان تبی می‌روی که در حال خواندن است.',
    },
  ),
  _Step(
    'next',
    Icons.skip_next_rounded,
    {'en': 'Next / previous sentence', 'fa': 'جمله‌ی بعد و قبل'},
    {
      'en': 'Moves one sentence forward or back.',
      'fa': 'یک جمله جلو یا عقب می‌روی.',
    },
    {
      'en': 'Skips a few seconds forward or back.',
      'fa': 'چند ثانیه جلو یا عقب می‌پرد.',
    },
  ),
  _Step(
    'repeat',
    Icons.repeat_rounded,
    {'en': 'Repeat', 'fa': 'تکرار'},
    {
      'en': 'Each tap changes the repeat mode.',
      'fa': 'با هر لمس، حالت تکرار عوض می‌شود.',
    },
    {
      'en': 'Enter exactly how many times to repeat.',
      'fa': 'تعداد تکرار دلخواهت را وارد کن.',
    },
  ),
  _Step(
    'ab',
    Icons.linear_scale_rounded,
    {'en': 'Loop a section (A-B)', 'fa': 'تکرار یک قسمت (A-B)'},
    {
      'en': 'Mark the start and end of a part and only that part repeats. Useful for hard sentences.',
      'fa': 'شروع و پایان یک قسمت را علامت بزن تا فقط همان قسمت تکرار شود. برای جمله‌های سخت مناسب است.',
    },
  ),
  _Step(
    'rec',
    Icons.mic_rounded,
    {'en': 'Pronunciation practice', 'fa': 'تمرین تلفظ'},
    {
      'en': 'Record your voice and compare it with the original.',
      'fa': 'صدایت را ضبط کن و با تلفظ اصلی مقایسه کن.',
    },
  ),
  _Step(
    'speed',
    Icons.speed_rounded,
    {'en': 'Voice speed', 'fa': 'سرعت صدا'},
    {
      'en': 'Slow it down to hear every word, speed it up when it feels easy.',
      'fa': 'برای شنیدن دقیق کلمه‌ها صدا را کند کن؛ وقتی راحت شدی تندترش کن.',
    },
  ),
  _Step(
    'top',
    Icons.vertical_align_top_rounded,
    {'en': 'Back to top', 'fa': 'رفتن به بالا'},
    {
      'en': 'In a long list or text, one tap takes you back to the top.',
      'fa': 'در لیست یا متن بلند، با یک لمس به بالای صفحه برمی‌گردی.',
    },
  ),
];

/// تورِ تبِ «داستان‌ساز» — بارِ اولِ ورود به تب.
const List<_Step> _storySteps = [
  _Step(
    'st_modes',
    Icons.auto_stories_rounded,
    {'en': 'Four parts of Story', 'fa': 'چهار بخش داستان‌ساز'},
    {
      'en': 'Create story: an AI story built from your own words. Import and read: PDF, photo, link or text with translation. Saved: your stories and books. Save for next story: words you want in the next story.',
      'fa': 'ساخت داستان: داستانی با لغت‌های خودت. ایمپورت و خواندن: PDF، عکس، لینک یا متن را با ترجمه می‌خوانی. ذخیره‌شده‌ها: داستان‌ها و کتاب‌هایت. ذخیره برای داستان بعدی: لغت‌هایی که می‌خواهی در داستان بعدی بیایند.',
    },
  ),
  _Step(
    'st_settings',
    Icons.tune_rounded,
    {'en': 'Story settings', 'fa': 'تنظیم داستان'},
    {
      'en': 'Choose the story language, your level (A1 to C2), the type of content and the length.',
      'fa': 'زبان داستان، سطح خودت (A1 تا C2)، نوع محتوا و طول داستان را انتخاب کن.',
    },
  ),
  _Step(
    'st_words',
    Icons.spellcheck_rounded,
    {'en': 'Your words', 'fa': 'لغت‌های تو'},
    {
      'en': 'Type the words you want to learn, or pick from your saved words. The story is built around them.',
      'fa': 'لغت‌هایی که می‌خواهی یاد بگیری را بنویس یا از لغت‌های ذخیره‌شده‌ات انتخاب کن. داستان با همین لغت‌ها ساخته می‌شود.',
    },
  ),
  _Step(
    'st_trans',
    Icons.translate_rounded,
    {'en': 'Translations', 'fa': 'ترجمه‌ها'},
    {
      'en': 'Choose the languages you want the story translated into. Translations appear next to the text.',
      'fa': 'زبان‌هایی که می‌خواهی ترجمه‌ی داستان را به آن‌ها ببینی انتخاب کن. ترجمه‌ها کنار متن می‌آیند.',
    },
  ),
  _Step(
    'st_generate',
    Icons.auto_awesome_rounded,
    {'en': 'Create the story', 'fa': 'ساخت داستان'},
    {
      'en': 'After adding at least one word, tap here. Then you can read the story, listen to it and save it.',
      'fa': 'بعد از افزودن حداقل یک لغت، این دکمه را بزن. بعد می‌توانی داستان را بخوانی، گوش بدهی و ذخیره کنی.',
    },
  ),
];

/// تورِ زیرتبِ «ایمپورت و خواندن» (داستان‌ساز) — بارِ اولی که کاربر «ایمپورت» را می‌زند.
const List<_Step> _importSteps = [
  _Step(
    'imp_pdf',
    Icons.menu_book_rounded,
    {'en': 'PDF to read', 'fa': 'PDF برای خواندن'},
    {
      'en': 'Pick a text PDF. It is prepared sentence by sentence for reading. Tap any word, or select a phrase, to see its translation.',
      'fa': 'یک PDF متنی انتخاب کن. متنش جمله‌به‌جمله برای خواندن آماده می‌شود. روی هر لغت بزن یا چند کلمه را انتخاب کن تا ترجمه‌اش را ببینی.',
    },
  ),
  _Step(
    'imp_img',
    Icons.image_rounded,
    {'en': 'Photos', 'fa': 'عکس'},
    {
      'en': 'Choose a photo of a book page, a sign or a screenshot. The text inside the photo is read and you can translate it.',
      'fa': 'عکس صفحه‌ی کتاب، تابلو یا اسکرین‌شات را انتخاب کن. متن داخل عکس خوانده می‌شود و می‌توانی ترجمه‌اش کنی.',
    },
  ),
  _Step(
    'imp_view',
    Icons.auto_stories_rounded,
    {'en': 'PDF with original look + translation', 'fa': 'PDF با ظاهر اصلی + ترجمه'},
    {
      'en': 'Open a PDF with its original layout (scanned books too). The translation appears on the page itself and you can change its language any time.',
      'fa': 'PDF را با همان ظاهر اصلی باز کن (کتاب اسکن‌شده هم). ترجمه روی خود صفحه می‌آید و هر وقت خواستی زبانش را عوض می‌کنی.',
    },
  ),
  _Step(
    'imp_link',
    Icons.link_rounded,
    {'en': 'Link', 'fa': 'لینک'},
    {
      'en': 'Paste the address of an article or web page. Its text is brought in, ready to read and translate.',
      'fa': 'آدرس یک مقاله یا صفحه‌ی وب را بگذار. متنش وارد می‌شود و برای خواندن و ترجمه آماده است.',
    },
  ),
  _Step(
    'imp_paste',
    Icons.content_paste_rounded,
    {'en': 'Any text', 'fa': 'متن دلخواه'},
    {
      'en': 'Copy any text, paste it here and read it with translation.',
      'fa': 'هر متنی را کپی کن، اینجا بگذار و با ترجمه بخوانش.',
    },
  ),
  _Step(
    'imp_srt',
    Icons.subtitles_rounded,
    {'en': 'Subtitle translation (SRT)', 'fa': 'ترجمه‌ی زیرنویس (SRT)'},
    {
      'en': 'Load an .srt file, translate it into any language and save the new file. This one is free with no limit. The other imports are free twice, then need Pro.',
      'fa': 'فایل .srt را بارگذاری کن، به هر زبانی ترجمه کن و فایل جدید را ذخیره کن. این بخش رایگان و بدون محدودیت است. بقیه‌ی ایمپورت‌ها دو بار رایگان‌اند و بعد به Pro نیاز دارند.',
    },
  ),
];

/// تورِ «خوانشِ ترجمه‌ها» — بارِ اولی که پلیر می‌خواهد ترجمه‌ها را بخواند.
const List<_Step> _transSteps = [
  _Step(
    'tr_refresh',
    Icons.refresh_rounded,
    {'en': 'Translation not right?', 'fa': 'ترجمه‌اش خوب نیست؟'},
    {
      'en': 'The player reads the translations too. If one is wrong, tap the refresh button next to it to translate it again. The better version is saved.',
      'fa': 'پلیر ترجمه‌ها را هم می‌خواند. اگر ترجمه‌ای اشتباه بود، دکمه‌ی رفرش کنارش را بزن تا دوباره ترجمه شود. نسخه‌ی بهتر ذخیره می‌شود.',
    },
  ),
  _Step(
    'account',
    Icons.volume_off_rounded,
    {'en': 'Turn off translation reading', 'fa': 'خاموش کردن خواندن ترجمه'},
    {
      'en': "Don't want translations read aloud? Open Settings from here and turn off «Read translations inside the app».",
      'fa': 'نمی‌خواهی ترجمه‌ها خوانده شوند؟ از اینجا تنظیمات را باز کن و گزینه‌ی «خواندن ترجمه‌ها داخل برنامه» را خاموش کن.',
    },
  ),
];

/// تورِ کارتِ ترجمه (پاپ‌آپی که با لمسِ لغت یا انتخابِ عبارت باز می‌شود) — بارِ اول.
const List<_Step> _popupSteps = [
  _Step(
    'pc_trans',
    Icons.translate_rounded,
    {'en': 'Translation in all your languages', 'fa': 'ترجمه به همه‌ی زبان‌هایت'},
    {
      'en': 'The translation of the word or phrase you tapped shows here, in every language you selected.',
      'fa': 'ترجمه‌ی لغت یا عبارتی که زدی، به همه‌ی زبان‌هایی که انتخاب کرده‌ای، اینجا نشان داده می‌شود.',
    },
  ),
  _Step(
    'pc_speak',
    Icons.volume_up_rounded,
    {'en': 'Hear the pronunciation', 'fa': 'شنیدن تلفظ'},
    {
      'en': 'Plays the pronunciation. Each translation has its own play button too.',
      'fa': 'تلفظ را پخش می‌کند. کنار هر ترجمه هم یک دکمه‌ی پخش هست.',
    },
  ),
  _Step(
    'pc_retry',
    Icons.refresh_rounded,
    {'en': 'Translation not right?', 'fa': 'ترجمه‌اش خوب نیست؟'},
    {
      'en': 'Tap to translate it again.',
      'fa': 'این دکمه را بزن تا دوباره ترجمه شود.',
    },
  ),
  _Step(
    'pc_neural',
    Icons.hub_outlined,
    {'en': 'Neural path', 'fa': 'مسیر عصبی'},
    {
      'en': 'Shows how many times you have heard and repeated this word, so you can follow your review.',
      'fa': 'نشان می‌دهد چند بار این لغت را شنیده و تکرار کرده‌ای تا روند مرورت را ببینی.',
    },
  ),
  _Step(
    'pc_story',
    Icons.bookmark_rounded,
    {'en': 'Save for next story', 'fa': 'ذخیره برای داستان بعدی'},
    {
      'en': 'For a word or sentence that is hard, or that you want to learn better. It is used in your next story, and also stays in your dictionary and saved words (you can delete it any time). Pro feature.',
      'fa': 'برای لغت یا جمله‌ای که سخت است یا می‌خواهی بهتر یادش بگیری. در داستان بعدی استفاده می‌شود و در دیکشنری و لغت‌های ذخیره‌شده هم می‌ماند (هر وقت خواستی حذفش می‌کنی). ویژه‌ی Pro.',
    },
  ),
  _Step(
    'pc_grammar',
    Icons.extension_rounded,
    {'en': 'Add to grammar learning', 'fa': 'افزودن به یادگیری گرامر'},
    {
      'en': 'When you want to know the grammar of a sentence or word, tap here. Its explanation is saved in the Grammar section. Pro feature.',
      'fa': 'وقتی می‌خواهی گرامر یک جمله یا لغت را بدانی، این را بزن. توضیحش در بخش گرامر ذخیره می‌شود. ویژه‌ی Pro.',
    },
  ),
  _Step(
    'pc_leitner',
    Icons.style_outlined,
    {'en': 'Leitner box', 'fa': 'جعبه‌ی لایتنر'},
    {
      'en': 'Adds the word to a review box, so you see it again at the right times and remember it longer. Pro feature.',
      'fa': 'لغت را به یک جعبه‌ی مرور اضافه می‌کند تا در زمان‌های مناسب دوباره ببینی‌اش و بهتر یادت بماند. ویژه‌ی Pro.',
    },
  ),
];

/// تورِ تبِ «مکالمه» — بارِ اولِ ورود به تب (بعد از تورِ اصلی). تور خودش یک موضوع را
/// باز می‌کند، روی یک لغت می‌زند و یک عبارت را انتخاب می‌کند.
const List<_Step> _convSteps = [
  _Step(
    'cv_topic',
    Icons.grid_view_rounded,
    {'en': 'Pick a topic', 'fa': 'یک موضوع انتخاب کن'},
    {
      'en': 'Each card is a topic with ready-made conversations. Tap one to open it. When you tap Next, the tour opens one for you.',
      'fa': 'هر کارت یک موضوع با مکالمه‌های آماده است. با لمس کارت باز می‌شود. وقتی «بعدی» را بزنی، تور خودش یکی را برایت باز می‌کند.',
    },
  ),
  _Step(
    'cv_line',
    Icons.chat_bubble_outline_rounded,
    {'en': 'A conversation line', 'fa': 'یک جمله‌ی مکالمه'},
    {
      'en': 'Each line shows the sentence and its translation in every language you selected. «You hear» is the other person, «You say» is your reply.',
      'fa': 'هر خط، جمله و ترجمه‌اش را به همه‌ی زبان‌هایی که انتخاب کرده‌ای نشان می‌دهد. «می‌شنوی» حرف طرف مقابل است و «می‌گی» جواب توست.',
    },
  ),
  _Step(
    'cv_word',
    Icons.touch_app_rounded,
    {'en': 'Tap a word', 'fa': 'روی یک لغت بزن'},
    {
      'en': 'Watch: the tour taps a word for you. A card opens with its translation.',
      'fa': 'نگاه کن: تور خودش روی یک لغت می‌زند و کارتِ ترجمه‌اش باز می‌شود.',
    },
    null,
    'cv_line',
  ),
  _Step(
    'cv_phrase',
    Icons.format_color_text_rounded,
    {'en': 'Select a phrase', 'fa': 'چند کلمه را انتخاب کن'},
    {
      'en': 'Press and hold a word, then drag to select several words. Watch: the tour selects a phrase for you and its translation opens.',
      'fa': 'روی یک لغت نگه دار و بکش تا چند کلمه انتخاب شود. نگاه کن: تور خودش یک عبارت را انتخاب می‌کند و ترجمه‌اش باز می‌شود.',
    },
    null,
    'cv_line',
  ),
  _Step(
    'cv_done',
    Icons.check_circle_outline_rounded,
    {'en': 'Now it is your turn', 'fa': 'حالا نوبت توست'},
    {
      'en': 'In any section, tap a word or select a phrase. The translation card opens right there.',
      'fa': 'در هر بخشی روی یک لغت بزن یا چند کلمه را انتخاب کن؛ کارت ترجمه همان‌جا باز می‌شود.',
    },
    null,
    'cv_line',
  ),
];

const Map<String, Map<String, String>> _ui = {
  'skip': {'en': 'Skip', 'fa': 'رد کردن'},
  'next': {'en': 'Next', 'fa': 'بعدی'},
  'prev': {'en': 'Back', 'fa': 'قبلی'},
  'done': {'en': 'Got it', 'fa': 'فهمیدم'},
  'replay': {'en': 'App tour', 'fa': 'معرفیِ برنامه'},
  'hold': {'en': 'Long-press', 'fa': 'لمس طولانی'},
};

class SpotlightTour extends ConsumerStatefulWidget {
  const SpotlightTour({super.key});

  static final ValueNotifier<int> _replayTick = ValueNotifier<int>(0);

  /// نمایشِ دوباره‌ی تور (از تنظیمات).
  static void replay() => _replayTick.value++;

  static final ValueNotifier<int> _storyTick = ValueNotifier<int>(0);
  static bool _storyForce = false;

  /// تورِ تبِ «داستان‌ساز». force=true → همیشه؛ وگرنه فقط بارِ اولِ ورود به تب.
  static void startStory({bool force = false}) {
    _storyForce = force;
    _storyTick.value++;
  }

  static final ValueNotifier<int> _importTick = ValueNotifier<int>(0);
  static bool _importForce = false;

  /// تورِ زیرتبِ «ایمپورت و خواندن». force=true (دکمه‌ی راهنما) → همیشه؛ وگرنه فقط بارِ اول.
  static void startImport({bool force = false}) {
    _importForce = force;
    _importTick.value++;
  }

  static final ValueNotifier<int> _transTick = ValueNotifier<int>(0);
  static bool _transForce = false;

  /// تورِ «خوانشِ ترجمه‌ها»: فقط بارِ اول و فقط وقتی برنامه روی صفحه است.
  /// force=true (از تنظیمات) → همیشه.
  static void startTranslationReading({bool force = false}) {
    _transForce = force;
    try {
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
    } catch (_) {}
    _transTick.value++;
  }

  static final ValueNotifier<int> _convTick = ValueNotifier<int>(0);
  static bool _convForce = false;

  /// تورِ تبِ «مکالمه». force=true → همیشه؛ وگرنه فقط بارِ اول (و بعد از تورِ اصلی).
  static void startConv({bool force = false}) {
    _convForce = force;
    _convTick.value++;
  }

  /// تور از تبِ مکالمه می‌خواهد اولین موضوعِ باز را باز / دوباره به لیست برگردد.
  static final ValueNotifier<int> convOpenTopic = ValueNotifier<int>(0);
  static final ValueNotifier<int> convCloseTopic = ValueNotifier<int>(0);

  /// true = کارتِ بعدی که باز می‌شود حتماً تورِ کارت را نشان بدهد (یک‌بار مصرف می‌شود).
  static bool forcePopupTour = false;

  /// متن‌هایی که تور می‌تواند خودش رویشان لغت بزند / عبارت انتخاب کند.
  static void addDemoSource(TourDemoSource s) {
    if (!_demoSources.contains(s)) _demoSources.add(s);
  }

  static void removeDemoSource(TourDemoSource s) => _demoSources.remove(s);

  /// مرحله‌ی «ابزارهای شناور»: به داک (FeatureDock) می‌گوید باز شود.
  static final ValueNotifier<int> dockExpand = ValueNotifier<int>(0);

  /// true = تورِ کارتِ ترجمه در حال نمایش است (کارت در این مدت خودکار بسته نمی‌شود).
  static final ValueNotifier<bool> cardTourActive = ValueNotifier<bool>(false);
  static bool _cardTourRunning = false;

  /// 🎓 تورِ کارتِ ترجمه (پاپ‌آپ): فقط بارِ اولی که کارت باز می‌شود. روی همان Overlay
  /// و بالای کارت نشان داده می‌شود. force=true → همیشه.
  static void maybeStartCardTour(BuildContext context, {bool force = false}) {
    final forced = force || forcePopupTour;
    forcePopupTour = false;
    if (_cardTourRunning) return;
    ProviderContainer? container;
    OverlayState? overlay;
    try {
      container = ProviderScope.containerOf(context, listen: false);
      overlay = Overlay.of(context, rootOverlay: true);
    } catch (_) {
      return;
    }
    var seen = true;
    try {
      seen = container.read(sharedPrefsProvider).getBool(_kPopupTourSeenKey) ?? false;
    } catch (_) {}
    if (seen && !forced) return;
    final ctn = container;
    final ov = overlay;
    _cardTourRunning = true;
    cardTourActive.value = true;
    late final OverlayEntry entry;
    var removed = false;
    void close(bool markSeen) {
      if (removed) return;
      removed = true;
      try {
        entry.remove();
      } catch (_) {}
      _cardTourRunning = false;
      cardTourActive.value = false;
      if (markSeen) {
        try {
          ctn.read(sharedPrefsProvider).setBool(_kPopupTourSeenKey, true);
        } catch (_) {}
      }
    }

    entry = OverlayEntry(builder: (_) => _CardTourOverlay(onClose: close));
    // کمی صبر تا کارت و ترجمه‌ها روی صفحه بنشینند
    Future<void>.delayed(const Duration(milliseconds: 700), () {
      if (removed) return;
      try {
        ov.insert(entry);
      } catch (_) {
        removed = true;
        _cardTourRunning = false;
        cardTourActive.value = false;
      }
    });
  }

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
  String _group = 'main'; // 'main' | 'import' | 'story'
  List<_Step> get _list => _group == 'import'
      ? _importSteps
      : (_group == 'story'
          ? _storySteps
          : (_group == 'trans'
              ? _transSteps
              : (_group == 'conv' ? _convSteps : _steps)));
  int _i = -1;
  Rect? _prev;
  Rect? _last;
  Timer? _startTimer;
  Timer? _importTimer;
  Timer? _storyTimer;
  Timer? _transTimer;
  Timer? _convTimer;
  Timer? _stepTimer; // انتظار برای باز/بسته شدنِ موضوع در تبِ مکالمه
  Timer? _demoTimer; // نمایشِ خودکارِ لغت/عبارت
  Timer? _langTimer; // نمایشِ خودکارِ دایره‌های زبان
  List<String>? _langOrig; // زبان‌های مقصدِ اصلیِ کاربر (برای برگرداندن)
  int _demoTok = 0;
  bool _busy = false; // تور منتظر است صفحه عوض شود
  bool _demoRunning = false; // تور خودش دارد لغت می‌زند؛ لایه‌ی تور موقتاً پنهان است
  VoidCallback? _cardL;

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
    SpotlightTour._storyTick.addListener(_onStoryTick);
    SpotlightTour._transTick.addListener(_onTransTick);
    SpotlightTour._convTick.addListener(_onConvTick);
  }

  @override
  void dispose() {
    _startTimer?.cancel();
    SpotlightTour._replayTick.removeListener(_onReplay);
    SpotlightTour._importTick.removeListener(_onImportTick);
    SpotlightTour._storyTick.removeListener(_onStoryTick);
    SpotlightTour._transTick.removeListener(_onTransTick);
    SpotlightTour._convTick.removeListener(_onConvTick);
    _convTimer?.cancel();
    _stepTimer?.cancel();
    _stepLeave();
    _transTimer?.cancel();
    _storyTimer?.cancel();
    _importTimer?.cancel();
    _pulse.dispose();
    _move.dispose();
    super.dispose();
  }

  void _onReplay() {
    _startTimer?.cancel();
    _begin();
  }

  void _onTransTick() {
    if (_active) return;
    var seen = true;
    try {
      seen = ref.read(sharedPrefsProvider).getBool(_kTransTourSeenKey) ?? false;
    } catch (_) {}
    if (seen && !SpotlightTour._transForce) return;
    // کمی صبر تا ردیفِ ترجمه‌ی در حال خوانش روی صفحه بنشیند
    _transTimer?.cancel();
    _transTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted || _active) return;
      _begin(group: 'trans');
    });
  }

  void _onConvTick() {
    if (_active) return;
    var seen = true;
    var mainSeen = false;
    try {
      final prefs = ref.read(sharedPrefsProvider);
      seen = prefs.getBool(_kConvTourSeenKey) ?? false;
      mainSeen = prefs.getBool(_kTourSeenKey) ?? false;
    } catch (_) {}
    // خودکار فقط بعد از تورِ اصلی (که هنوز دیده نشده، با آن قاطی نشود)
    if (!SpotlightTour._convForce && (seen || !mainSeen)) return;
    _convTimer?.cancel();
    _convTimer = Timer(const Duration(milliseconds: 800), () {
      if (!mounted || _active) return;
      _begin(group: 'conv');
      if (!_active) {
        _convTimer = Timer(const Duration(milliseconds: 900), () {
          if (mounted && !_active) _begin(group: 'conv');
        });
      }
    });
  }

  void _onStoryTick() {
    if (_active) return;
    var seen = true;
    try {
      seen = ref.read(sharedPrefsProvider).getBool(_kStoryTourSeenKey) ?? false;
    } catch (_) {}
    if (seen && !SpotlightTour._storyForce) return;
    // کمی صبر تا کارت‌های تب روی صفحه بنشینند
    _storyTimer?.cancel();
    _storyTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted || _active) return;
      _begin(group: 'story');
      if (!_active) {
        _storyTimer = Timer(const Duration(milliseconds: 900), () {
          if (mounted && !_active) _begin(group: 'story');
        });
      }
    });
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
    final cands = _multi[id];
    if (cands != null && cands.length > 1) {
      for (final t in cands) {
        final r = t._rect;
        if (r == null) continue;
        final vis = r.intersect(Offset.zero & size);
        if (vis.width >= 6 && vis.height >= 6) return vis;
      }
      return null;
    }
    final r = _targets[id]?._rect;
    if (r == null) return null;
    final vis = r.intersect(Offset.zero & size);
    if (vis.width < 6 || vis.height < 6) return null;
    return vis;
  }

  void _begin({String group = 'main'}) {
    if (!mounted) return;
    _stepLeave();
    _stepTimer?.cancel();
    _busy = false;
    _demoRunning = false;
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
      if (_group == 'import' || _group == 'story' || _group == 'conv') {
        _targets[_list[j].tid]?._reveal();
      }
      final r = _usableRect(_list[j].tid, size);
      if (r != null) {
        _goTo(j);
        return true;
      }
    }
    return false;
  }

  void _goTo(int j) {
    setState(() {
      _prev = _last;
      _i = j;
    });
    _move.forward(from: 0);
    if (_list[j].id == 'dock') SpotlightTour.dockExpand.value++;
    _stepEnter();
  }

  /// مرحله‌ی قبلی. اگر هدفِ مرحله‌ی قبل روی صفحه نیست (مثلاً موضوعِ مکالمه باز شده)،
  /// در تبِ مکالمه خودِ تور صفحه را به حالتِ قبل برمی‌گرداند.
  void _back() {
    _stepLeave();
    final size = MediaQuery.of(context).size;
    for (var j = _i - 1; j >= 0; j--) {
      final tid = _list[j].tid;
      if (_group == 'import' || _group == 'story' || _group == 'conv') {
        _targets[tid]?._reveal();
      }
      if (_usableRect(tid, size) != null) {
        _goTo(j);
        return;
      }
      if (_group == 'conv' && tid == 'cv_topic') {
        SpotlightTour.convCloseTopic.value++;
        _waitFor('cv_topic', () => _goTo(j), onTimeout: () => _finish(markSeen: false));
        return;
      }
    }
  }

  bool _canBack(Size size) {
    if (_group == 'conv') return _i > 0;
    for (var j = _i - 1; j >= 0; j--) {
      if (_usableRect(_list[j].tid, size) != null) return true;
    }
    return false;
  }

  /// منتظر می‌ماند تا هدفِ [tid] روی صفحه بیاید (حداکثر ~۵ ثانیه)، بعد [then].
  void _waitFor(String tid, VoidCallback then, {VoidCallback? onTimeout}) {
    _stepTimer?.cancel();
    setState(() => _busy = true);
    var tries = 0;
    _stepTimer = Timer.periodic(const Duration(milliseconds: 200), (t) {
      tries++;
      if (!mounted) {
        t.cancel();
        return;
      }
      _targets[tid]?._reveal();
      final size = MediaQuery.of(context).size;
      if (_usableRect(tid, size) != null) {
        t.cancel();
        setState(() => _busy = false);
        then();
      } else if (tries > 25) {
        t.cancel();
        setState(() => _busy = false);
        if (onTimeout != null) onTimeout();
      }
    });
  }

  // ───────────── نمایشِ خودکار (دایره‌های زبان / لغت / عبارت) ─────────────

  void _stepEnter() {
    final id = _list[_i].id;
    if (_group == 'main' && id == 'lang') _langDemoStart();
    if (_group == 'conv' && id == 'cv_word') _selectDemoStart(false);
    if (_group == 'conv' && id == 'cv_phrase') _selectDemoStart(true);
  }

  void _stepLeave() {
    _langDemoStop();
    _selectDemoCancel();
  }

  /// تور خودش آخرین زبانِ انتخاب‌شده را خاموش و دوباره روشن می‌کند. (فقط وقتی
  /// دست‌کم دو زبان انتخاب شده؛ هیچ زبانِ تازه‌ای اضافه نمی‌شود، پس ترجمه‌ی جدیدی
  /// هم درخواست نمی‌شود.) با رفتن به مرحله‌ی بعد، انتخابِ اصلیِ کاربر برمی‌گردد.
  void _langDemoStart() {
    _langDemoStop();
    try {
      final sel = ref.read(languageSelectionProvider);
      final orig = List<String>.from(sel.targets);
      if (orig.length < 2) return;
      final notifier = ref.read(languageSelectionProvider.notifier);
      final fewer = orig.sublist(0, orig.length - 1);
      _langOrig = orig;
      var off = false;
      void tick() {
        if (!mounted || _langOrig == null) return;
        off = !off;
        notifier.setTargets(off ? fewer : orig);
      }

      _langTimer = Timer(const Duration(milliseconds: 1200), () {
        tick();
        _langTimer = Timer.periodic(
            const Duration(milliseconds: 1700), (_) => tick());
      });
    } catch (_) {}
  }

  void _langDemoStop() {
    _langTimer?.cancel();
    _langTimer = null;
    final o = _langOrig;
    _langOrig = null;
    if (o != null) {
      try {
        ref.read(languageSelectionProvider.notifier).setTargets(o);
      } catch (_) {}
    }
  }

  TourDemoSource? _pickDemoSource(Rect area) {
    TourDemoSource? best;
    var bestTop = double.infinity;
    for (final s in List<TourDemoSource>.of(_demoSources)) {
      final r = s.rect();
      if (r == null) continue;
      if (!area.inflate(4).contains(r.center)) continue;
      if (r.top < bestTop) {
        best = s;
        bestTop = r.top;
      }
    }
    return best;
  }

  void _selectDemoCancel() {
    _demoTok++;
    _demoTimer?.cancel();
    _demoTimer = null;
    final l = _cardL;
    if (l != null) {
      SpotlightTour.cardTourActive.removeListener(l);
      _cardL = null;
    }
    SpotlightTour.forcePopupTour = false;
    _demoRunning = false;
  }

  /// بعد از چند ثانیه (تا کاربر متنِ مرحله را بخواند) تور خودش روی یک لغت می‌زند
  /// ([phrase] = false) یا چند کلمه را انتخاب می‌کند ([phrase] = true). کارتِ ترجمه باز
  /// می‌شود؛ بعد از بسته شدنش تور خودکار به مرحله‌ی بعد می‌رود.
  void _selectDemoStart(bool phrase) {
    _selectDemoCancel();
    final tok = _demoTok;
    _demoTimer = Timer(const Duration(milliseconds: 2400), () {
      if (!mounted || tok != _demoTok || !_active) return;
      final size = MediaQuery.of(context).size;
      final area = _usableRect(_list[_i].tid, size);
      final src = area == null ? null : _pickDemoSource(area);
      Future<void>? f;
      if (src != null) {
        // لغتِ اول: تورِ کارت (پاپ‌آپ) هم نشان داده شود
        if (!phrase) SpotlightTour.forcePopupTour = true;
        try {
          f = src.open(phrase);
        } catch (_) {
          f = null;
        }
        SpotlightTour.forcePopupTour = false;
      }
      if (src == null || f == null) {
        _afterDemo(tok);
        return;
      }
      setState(() => _demoRunning = true);
      void closeLater(int ms) {
        _demoTimer = Timer(Duration(milliseconds: ms), () {
          try {
            src.closeCard();
          } catch (_) {}
        });
      }

      if (SpotlightTour.cardTourActive.value) {
        late VoidCallback l;
        l = () {
          if (SpotlightTour.cardTourActive.value) return;
          SpotlightTour.cardTourActive.removeListener(l);
          if (identical(_cardL, l)) _cardL = null;
          if (tok == _demoTok) closeLater(900);
        };
        _cardL = l;
        SpotlightTour.cardTourActive.addListener(l);
      } else {
        closeLater(3600);
      }
      f.whenComplete(() => _afterDemo(tok));
    });
  }

  void _afterDemo(int tok) {
    if (!mounted || tok != _demoTok || !_active) return;
    _demoRunning = false;
    _next();
  }

  void _finish({bool markSeen = true}) {
    _stepLeave();
    _stepTimer?.cancel();
    final wasMain = _group == 'main';
    if (markSeen) {
      try {
        ref.read(sharedPrefsProvider).setBool(
            _group == 'import'
                ? _kImportTourSeenKey
                : (_group == 'story'
                    ? _kStoryTourSeenKey
                    : (_group == 'trans'
                        ? _kTransTourSeenKey
                        : (_group == 'conv'
                            ? _kConvTourSeenKey
                            : _kTourSeenKey))),
            true);
      } catch (_) {}
    }
    _pulse.stop();
    _busy = false;
    _demoRunning = false;
    if (mounted) setState(() => _active = false);
    if (markSeen && wasMain) _maybeConvAfterMain();
  }

  /// تورِ اصلی تمام شد و کاربر روی تبِ مکالمه است → تورِ مکالمه بلافاصله بعدش.
  void _maybeConvAfterMain() {
    try {
      final path =
          GoRouter.of(context).routeInformationProvider.value.uri.path;
      if (path == '/conversations') {
        Future<void>.delayed(
            const Duration(milliseconds: 600), () => SpotlightTour.startConv());
      }
    } catch (_) {}
  }

  void _next() {
    final cur = _list[_i];
    _stepLeave();
    if (_group == 'conv' && cur.id == 'cv_topic') {
      // تور خودش اولین موضوعِ باز را باز می‌کند و منتظرِ آمدنِ اولین خط می‌ماند
      SpotlightTour.convOpenTopic.value++;
      _waitFor('cv_line', () {
        if (!_advance()) _finish();
      }, onTimeout: () => _finish(markSeen: false));
      return;
    }
    if (!_advance()) _finish();
  }

  @override
  Widget build(BuildContext context) {
    if (!_active || _i < 0) return const SizedBox.shrink();
    // تور خودش دارد روی لغت می‌زند: لایه‌ی تور تا بسته شدنِ کارتِ ترجمه پنهان است
    if (_demoRunning) return const SizedBox.shrink();
    // تور منتظر است صفحه عوض شود (باز/بسته شدنِ موضوع): فقط پرده‌ی تیره
    if (_busy) {
      return const Positioned.fill(
        child: AbsorbPointer(child: ColoredBox(color: Color(0xB8000000))),
      );
    }
    final c = context.appColors;
    final lang = ref.watch(appPrefsProvider).uiLang;
    String t(Map<String, String> m) => m[lang] ?? m['en']!;
    final rtl = lang == 'fa' || lang == 'ar';
    final step = _list[_i];
    final size = MediaQuery.of(context).size;
    final lastStep = !_hasLater(size);
    final canBack = _canBack(size);

    return Positioned.fill(
      child: Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: Material(
          type: MaterialType.transparency,
          child: AnimatedBuilder(
            animation: Listenable.merge([_pulse, _move]),
            builder: (context, _) {
              final cur = _usableRect(step.tid, size) ??
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
                          child: _card(c, step, t, lastStep, canBack, key: ValueKey(_i)),
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
    // مکالمه: مرحله‌های بعدی بعد از باز شدنِ موضوع می‌آیند
    if (_group == 'conv') return _i < _list.length - 1;
    for (var j = _i + 1; j < _list.length; j++) {
      // ایمپورت: هدفِ ثبت‌شده کافی است (در _advance به صفحه آورده می‌شود)
      if (_group == 'import' || _group == 'story'
          ? _targets[_list[j].tid]?._rect != null
          : _usableRect(_list[j].tid, size) != null) return true;
    }
    return false;
  }

  Widget _card(AppThemeColorsExt c, _Step step, String Function(Map<String, String>) t,
      bool lastStep, bool canBack,
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
              if (canBack) ...[
                TextButton(
                  onPressed: _back,
                  child: Text(t(_ui['prev']!),
                      style: TextStyle(color: c.inkSoft)),
                ),
                const SizedBox(width: 4),
              ],
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

/// مستطیلِ قابل‌دیدنِ یک هدف (برای تورِ کارت).
Rect? _rectForId(String id, Size size) {
  final cands = _multi[id];
  if (cands == null || cands.isEmpty) return null;
  for (final t in cands) {
    final r = t._rect;
    if (r == null) continue;
    final vis = r.intersect(Offset.zero & size);
    if (vis.width >= 6 && vis.height >= 6) return vis;
  }
  return null;
}

/// لایه‌ی تورِ کارتِ ترجمه — داخل Overlay، بالای خودِ کارت.
class _CardTourOverlay extends ConsumerStatefulWidget {
  final void Function(bool markSeen) onClose;
  const _CardTourOverlay({required this.onClose});

  @override
  ConsumerState<_CardTourOverlay> createState() => _CardTourOverlayState();
}

class _CardTourOverlayState extends ConsumerState<_CardTourOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1500))
    ..repeat();
  int _i = -1;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_advance()) _close(false);
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _close(bool markSeen) {
    if (_closed) return;
    _closed = true;
    widget.onClose(markSeen);
  }

  bool _advance() {
    if (!mounted) return false;
    final size = MediaQuery.of(context).size;
    for (var j = _i + 1; j < _popupSteps.length; j++) {
      if (_rectForId(_popupSteps[j].id, size) != null) {
        setState(() => _i = j);
        return true;
      }
    }
    return false;
  }

  bool _hasLater(Size size) {
    for (var j = _i + 1; j < _popupSteps.length; j++) {
      if (_rectForId(_popupSteps[j].id, size) != null) return true;
    }
    return false;
  }

  bool _canBack(Size size) {
    for (var j = _i - 1; j >= 0; j--) {
      if (_rectForId(_popupSteps[j].id, size) != null) return true;
    }
    return false;
  }

  void _back() {
    final size = MediaQuery.of(context).size;
    for (var j = _i - 1; j >= 0; j--) {
      if (_rectForId(_popupSteps[j].id, size) != null) {
        setState(() => _i = j);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_i < 0) return const SizedBox.shrink();
    final c = context.appColors;
    final lang = ref.watch(appPrefsProvider).uiLang;
    String t(Map<String, String> m) => m[lang] ?? m['en']!;
    final rtl = lang == 'fa' || lang == 'ar';
    final size = MediaQuery.of(context).size;
    final step = _popupSteps[_i];
    final r = _rectForId(step.id, size);
    if (r == null) {
      // کارت بسته شده یا هدف دیگر روی صفحه نیست → مرحله‌ی بعدی یا پایان
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _closed) return;
        if (!_advance()) _close(false);
      });
      return const SizedBox.shrink();
    }
    final hole = r.inflate(6);
    final below = hole.center.dy < size.height * 0.5;
    final last = !_hasLater(size);
    final canBack = _canBack(size);
    final shown = _popupSteps.indexOf(step) + 1;

    return Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            final cur = _rectForId(step.id, size) ?? r;
            final h = cur.inflate(6);
            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: CustomPaint(
                      painter:
                          _SpotPainter(hole: h, t: _pulse.value, color: c.gold),
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  top: below ? math.max(h.bottom + 16, 8.0) : null,
                  bottom: below ? null : math.max(size.height - h.top + 16, 8.0),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
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
                                  child: Icon(step.icon, size: 22, color: c.gold),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    t(step.title),
                                    style: TextStyle(
                                        color: c.ink,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800),
                                  ),
                                ),
                                Text('$shown/${_popupSteps.length}',
                                    style: TextStyle(
                                        color: c.inkSoft, fontSize: 12)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              t(step.body),
                              style: TextStyle(
                                  color: c.ink, fontSize: 14, height: 1.65),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                TextButton(
                                  onPressed: () => _close(true),
                                  child: Text(t(_ui['skip']!),
                                      style: TextStyle(color: c.inkSoft)),
                                ),
                                const Spacer(),
                                if (canBack) ...[
                                  TextButton(
                                    onPressed: _back,
                                    child: Text(t(_ui['prev']!),
                                        style: TextStyle(color: c.inkSoft)),
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: c.gold,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 22, vertical: 10),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12)),
                                  ),
                                  onPressed: () {
                                    if (last) {
                                      _close(true);
                                    } else if (!_advance()) {
                                      _close(true);
                                    }
                                  },
                                  child: Text(
                                    t(_ui[last ? 'done' : 'next']!),
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
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
/// آیا هدفِ تور همین الان روی صفحه دیده می‌شود؟
bool _onScreen(String id) {
  final list = _multi[id];
  if (list == null || list.isEmpty) return false;
  try {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final size = view.physicalSize / view.devicePixelRatio;
    for (final t in list) {
      final r = t._rect;
      if (r == null) continue;
      final vis = r.intersect(Offset.zero & size);
      if (vis.width >= 6 && vis.height >= 6) return true;
    }
  } catch (_) {}
  return false;
}

/// تورِ مناسبِ جایی که کاربر هست: زیرتبِ ایمپورت ← تورِ ایمپورت، ردیفِ ترجمه‌ی در حال
/// خوانش ← تورِ خوانشِ ترجمه، تبِ داستان ← تورِ داستان، بقیه‌ی تب‌ها ← تورِ اصلی.
void _replayFor(String path) {
  if (_importSteps.any((st) => st.id.startsWith('imp_') && _onScreen(st.id))) {
    SpotlightTour.startImport(force: true);
    return;
  }
  if (_onScreen('tr_refresh')) {
    SpotlightTour.startTranslationReading(force: true);
    return;
  }
  if (path == '/conversations') {
    SpotlightTour.startConv(force: true);
    return;
  }
  if (path == '/story') {
    SpotlightTour.startStory(force: true);
    return;
  }
  SpotlightTour.replay();
}

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
        // 🎓 تورِ همان تبی که کاربر الان در آن است (قبل از بسته‌شدنِ تنظیمات می‌خوانیم)
        var path = '';
        try {
          path = GoRouter.of(context).routeInformationProvider.value.uri.path;
        } catch (_) {}
        Navigator.of(context).pop();
        Future<void>.delayed(
            const Duration(milliseconds: 450), () => _replayFor(path));
      },
    );
  }
}
