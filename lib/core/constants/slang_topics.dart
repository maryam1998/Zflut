/// دسته‌بندیِ موضوعیِ لغاتِ «Slang».
/// مقدارِ `category` هر لغت در فایلِ assets/data/slang_words.json همین `key` است.
class SlangTopic {
  final String key;
  final String fa;
  final String en;
  const SlangTopic(this.key, this.fa, this.en);

  String label(String uiLang) => uiLang == 'fa' || uiLang == 'ar' ? fa : en;
}

const List<SlangTopic> kSlangTopics = [
  SlangTopic('people', 'آدم‌ها و شخصیت', 'People & personality'),
  SlangTopic('emotions', 'احساسات و خلق‌وخو', 'Feelings & mood'),
  SlangTopic('love', 'عشق و روابط', 'Love & relationships'),
  SlangTopic('fun', 'مهمانی، موسیقی و سرگرمی', 'Party, music & fun'),
  SlangTopic('food', 'خوراک و نوشیدنی', 'Food & drink'),
  SlangTopic('money', 'پول و خرید', 'Money & shopping'),
  SlangTopic('work', 'کار و شغل', 'Work & career'),
  SlangTopic('school', 'مدرسه و تحصیل', 'School & study'),
  SlangTopic('crime', 'جرم، پلیس و قانون', 'Crime, police & law'),
  SlangTopic('health', 'سلامت و بدن', 'Health & body'),
  SlangTopic('travel', 'سفر و حمل‌ونقل', 'Travel & transport'),
  SlangTopic('home', 'خانه و زندگی روزمره', 'Home & daily life'),
  SlangTopic('tech', 'موبایل، اینترنت و فناوری', 'Phone, internet & tech'),
  SlangTopic('exclaim', 'واکنش و تعجب', 'Reactions & exclamations'),
  SlangTopic('idioms', 'اصطلاحات رایج', 'Common idioms'),
  SlangTopic('phrases', 'جملات روزمره', 'Everyday phrases'),
  SlangTopic('modern', 'اسلنگ نسل جدید و اینترنتی', 'Modern & online slang'),
  SlangTopic('abbrev', 'مخفف و املای محاوره‌ای', 'Abbreviations & casual spelling'),
  SlangTopic('proverbs', 'ضرب‌المثل‌ها', 'Proverbs'),
  SlangTopic('other', 'سایر', 'Other'),
];

SlangTopic? slangTopicByKey(String? key) {
  if (key == null) return null;
  for (final t in kSlangTopics) {
    if (t.key == key) return t;
  }
  return null;
}
