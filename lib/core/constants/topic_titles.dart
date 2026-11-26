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
  // 🎒 Primary School ▸ A2
  'Shopping at a Store': 'خرید از فروشگاه',
  'Ordering Food at a Restaurant': 'سفارش غذا در رستوران',
  'Asking the Way': 'پرسیدن آدرس',
  'Booking a Hotel Room': 'رزرو اتاق هتل',
  'My Daily Routine': 'برنامه‌ی روزانه‌ی من',
  'Talking About the Weather': 'صحبت درباره‌ی آب‌وهوا',
  'Talking About Hobbies': 'صحبت درباره‌ی سرگرمی‌ها',
  'Buying Clothes': 'خرید لباس',
  'At the Pharmacy': 'رفتن به داروخانه',
  'Asking the Time and Date': 'پرسیدن ساعت و تاریخ',
  'At School': 'در مدرسه',
  'What I Did Last Weekend': 'آخر هفته‌ی گذشته چه کردم',
  'Plans for Tomorrow': 'برنامه‌ها برای فردا',
  'Phone Calls and Messages': 'تماس تلفنی و پیام',
  'Making Plans with Friends': 'برنامه‌ریزی با دوستان',
  'A Visit to the Doctor': 'مراجعه به پزشک',
  'Taking Public Transport': 'استفاده از حمل‌ونقل عمومی',
  'My Home and Neighborhood': 'خانه و محله‌ی من',
  'Describing People': 'توصیف آدم‌ها',
  'Talking About Jobs': 'صحبت درباره‌ی شغل‌ها',
  'Comparing Things': 'مقایسه‌ی چیزها',
  'Asking for Help in English': 'کمک خواستن به انگلیسی',
  'Texts and Short Emails': 'پیام و ایمیل کوتاه',
  'Birthdays and Celebrations': 'تولد و جشن‌ها',
  // 🎒 Primary School ▸ A1
  'Introducing Yourself': 'معرفی خود',
  'Hello and Goodbye': 'سلام و خداحافظی',
  'In the Classroom': 'در کلاس',
  'My Body Hurts / At the Doctor': 'بدنم درد می‌کند / نزد دکتر',
  'My House and Rooms': 'خانه‌ی من و اتاق‌ها',
  'Getting Dressed': 'لباس پوشیدن',
  'Toys and Playing in the Yard': 'اسباب‌بازی و بازی در حیاط',
  'How Is the Weather Today?': 'امروز هوا چطور است؟',
  'Name and Age': 'نام و سن',
  'My Morning': 'صبح من',
  'Washing Hands and Brushing Teeth': 'شستن دست و مسواک زدن',
  'Snack Time': 'وقت میان‌وعده',
  'Park and Zoo': 'پارک و باغ‌وحش',
  'Please, Thank You and Sorry': 'لطفاً، ممنون و ببخشید',
  'Days of the Week': 'روزهای هفته',
  'My Birthday': 'تولد من',
  'Where Is It?': 'کجاست؟',
  'Asking Permission: Can I ...?': 'اجازه گرفتن: می‌شود …؟',
  'My Family': 'خانواده‌ی من',
  'What Is This?': 'این چیست؟',
  'Colors and Numbers': 'رنگ‌ها و اعداد',
  'Animals I Know': 'حیوان‌هایی که می‌شناسم',
  'How Do You Feel?': 'حال شما چطور است؟',
  'Asking for Water, Food or Help': 'درخواست آب، غذا یا کمک',
  "I Want / I Don't Want": 'می‌خواهم / نمی‌خواهم',
  'At the Supermarket': 'در سوپرمارکت',
  'Lunch at School': 'ناهار در مدرسه',
  'Bedtime': 'وقت خواب',
  'On the School Bus': 'در سرویس مدرسه',
  'At the Beach': 'در ساحل',
  'Making Friends': 'دوست پیدا کردن',
  'People Who Help Us': 'کسانی که به ما کمک می‌کنند',
  'Big and Small': 'بزرگ و کوچک',
  'Seasons and Clothes': 'فصل‌ها و لباس‌ها',
  'Art Time': 'وقت نقاشی',
  'Tidy-Up Time': 'وقت مرتب کردن',
  'My Pet': 'حیوان خانگی من',
  'My Five Senses': 'حس‌های پنج‌گانه من',
  'On the Farm': 'در مزرعه',
  'What Time Is It?': 'ساعت چند است؟',
  'Simon Says': 'سایمون می‌گوید',
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
