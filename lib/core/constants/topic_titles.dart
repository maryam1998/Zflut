// 📁 مسیر: lib/core/constants/topic_titles.dart
//
// نامِ نمایشیِ موضوع‌های مکالمه طبق زبانِ رابط:
//  • داده‌ی موضوع‌ها دو شکل دارد: «English» (روزمره) و «فارسی (English)» (موضوعی).
//  • رابط فارسی ← همیشه فارسی؛ بقیه‌ی زبان‌ها ← همیشه انگلیسی.
// کلیدهای ذخیره (خوانده‌شده‌ها، آیکون و ...) همچنان رشته‌ی خامِ موضوع است؛
// فقط «نمایش» عوض می‌شود.

final RegExp _faChars = RegExp(r'[\u0600-\u06FF]');
final RegExp _paren = RegExp(r'^(.*?)\s*\(([^()]*)\)\s*$');

const Map<String, String> _kDailyFa = {
  'Greetings and Small Talk': 'سلام و احوال‌پرسی',
  'Introducing People': 'معرفی کردن افراد',
  'Visiting an Old Friend': 'دیدار با دوست قدیمی',
  'Getting Acquainted (Personal Questions)': 'آشنایی (سؤال‌های شخصی)',
  'Invitations': 'دعوت‌ها',
  'Accepting or Refusing an Invitation': 'پذیرفتن یا رد کردن دعوت',
  'Saying Goodbye': 'خداحافظی',
  'Telephone Conversation': 'مکالمه‌ی تلفنی',
  'Transportation': 'حمل‌ونقل',
  'Gas Station and Auto Repair': 'پمپ بنزین و تعمیرگاه خودرو',
  'Weather and Seasons': 'آب‌وهوا و فصل‌ها',
  'At a Restaurant / Café': 'در رستوران / کافه',
  'Shopping (Clothes and General)': 'خرید (لباس و عمومی)',
  'At a Hotel': 'در هتل',
  "Health and Doctor's Visit": 'سلامت و مراجعه به پزشک',
  'Asking for Directions / Landmarks': 'پرسیدن آدرس / مکان‌های شاخص',
  'Plans and Free Time (Hobbies)': 'برنامه‌ها و اوقات فراغت (سرگرمی‌ها)',
  'Work and Workplace': 'کار و محل کار',
  'Time and Appointments': 'زمان و قرار ملاقات',
  'Expressing Opinions and Feelings': 'بیان نظر و احساسات',
  'Asking for Help and Clarification': 'درخواست کمک و توضیح',
  'Politeness and Compliments': 'ادب و تعارف',
  'Travel and Experiences': 'سفر و تجربه‌ها',
  'Apologies and Forgiveness': 'عذرخواهی و بخشش',
  'Family and Cultural Questions': 'سؤال‌های خانوادگی و فرهنگی',
  'Sports and Fitness': 'ورزش و تناسب اندام',
  'Technology and Communication': 'فناوری و ارتباطات',
  'Holidays and Celebrations': 'تعطیلات و جشن‌ها',
  'Pets and Animals': 'حیوانات خانگی و جانوران',
  'Learning a Language': 'یادگیری زبان',
  'Emergency Situations': 'شرایط اضطراری',
  'City Attractions and Sightseeing': 'جاذبه‌های شهر و گردش',
  'Schools and Education': 'مدرسه و آموزش',
  'Money and Expenses': 'پول و هزینه‌ها',
  'Books and Reading': 'کتاب و مطالعه',
  'Environment and Nature': 'محیط زیست و طبیعت',
  'Cooking and Recipes': 'آشپزی و دستور پخت',
  'Movies and TV Series': 'فیلم و سریال',
  'Music': 'موسیقی',
  'Banking and Financial Services': 'بانک و خدمات مالی',
  'Post Office and Mail': 'پست و نامه',
  'Neighbors and Community': 'همسایه‌ها و جامعه',
  'Future Plans and Dreams': 'برنامه‌ها و رؤیاهای آینده',
  'Memories and Past Experiences': 'خاطرات و تجربه‌های گذشته',
};

/// نامِ نمایشیِ موضوع. [uiLang] کدِ زبانِ رابط (مثلاً 'fa' یا 'en').
String topicTitle(String raw, String uiLang) {
  final t = raw.trim();
  String? fa;
  var en = t;
  final m = _paren.firstMatch(t);
  if (m != null && _faChars.hasMatch(m.group(1)!)) {
    fa = m.group(1)!.trim();
    en = m.group(2)!.trim();
  } else if (_faChars.hasMatch(t)) {
    fa = t;
  }
  if (uiLang == 'fa') return fa ?? _kDailyFa[en] ?? en;
  return en;
}
