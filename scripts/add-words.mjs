// افزودنِ لغاتِ جدید به لیستِ دیکشنری (paid-content/daily_words.json) — idempotent: node scripts/add-words.mjs
// فرمتِ هر خط:  en|pos|fa   (سطح از عنوانِ بخش می‌آید)
// لغتِ تکراری (همان en) اضافه نمی‌شود. شناسه‌ها از ۵۰۰۰۰۰ شروع می‌شوند.
// بعد از اجرا: node scripts/build-paid-content.mjs --assets && node scripts/build-paid-content.mjs --sql content_seed
import fs from "node:fs";

const C2 = `
ubiquitous|adjective|همه‌جاحاضر، فراگیر
ephemeral|adjective|زودگذر، ناپایدار
meticulous|adjective|وسواسی، بسیار دقیق
obsequious|adjective|چاپلوس، متملق
pernicious|adjective|مخرب، زیان‌بار
quintessential|adjective|نمونه‌ی اعلا، ذاتی
recalcitrant|adjective|سرکش، نافرمان
sanguine|adjective|خوش‌بین، امیدوار
taciturn|adjective|کم‌حرف، ساکت
tenacious|adjective|سمج، مصمم
vindictive|adjective|کینه‌جو
zealous|adjective|پرشور، متعصب
abstruse|adjective|پیچیده، دشوارفهم
acrimonious|adjective|تلخ و خصمانه
alacrity|noun|چابکی، شور و اشتیاق
ameliorate|verb|بهبود بخشیدن
anachronistic|adjective|نابهنگام
apocryphal|adjective|مشکوک‌الاصل، غیرموثق
arcane|adjective|رمزآلود، ویژه‌ی اهل فن
ascetic|adjective|زاهدانه
assiduous|adjective|پرتلاش، پشتکاردار
austere|adjective|ساده و سخت‌گیر، بی‌پیرایه
belligerent|adjective|جنگ‌طلب، ستیزه‌جو
benevolent|adjective|نیکوکار، خیرخواه
bombastic|adjective|پرطمطراق
capricious|adjective|هوسباز، دمدمی‌مزاج
censure|verb|سرزنش کردن، نکوهش کردن
circumspect|adjective|محتاط، محتاط و محاسبه‌گر
clandestine|adjective|پنهانی، مخفیانه
cogent|adjective|قانع‌کننده، مستدل
conundrum|noun|معما، مسئله‌ی دشوار
corroborate|verb|تأیید کردن، تقویت کردن (با شواهد)
credulous|adjective|زودباور
culpable|adjective|مقصر
cursory|adjective|سرسری، شتاب‌زده
dearth|noun|کمبود، فقدان
debilitating|adjective|ناتوان‌کننده
deleterious|adjective|زیان‌آور
denigrate|verb|بدنام کردن، تحقیر کردن
desultory|adjective|بی‌هدف، نامنظم
diatribe|noun|حمله‌ی لفظی تند
dichotomy|noun|دوگانگی، تقابل
diffident|adjective|کم‌رو، بی‌اعتمادبه‌نفس
disparage|verb|تحقیر کردن، کوچک شمردن
dissemble|verb|وانمود کردن، پنهان‌کاری کردن
disseminate|verb|پراکندن، منتشر کردن
ebullient|adjective|سرزنده، پرهیجان
eclectic|adjective|التقاطی، گزینشی
efficacious|adjective|مؤثر
egregious|adjective|فاحش، آشکارا بد
elucidate|verb|روشن کردن، توضیح دادن
emulate|verb|الگو قرار دادن، تقلید کردن
enervate|verb|بی‌رمق کردن
enigmatic|adjective|مرموز، معمایی
equivocal|adjective|مبهم، دوپهلو
erudite|adjective|فاضل، دانشمند
esoteric|adjective|رمزی، مخصوص خواص
exacerbate|verb|وخیم‌تر کردن
exculpate|verb|تبرئه کردن
exemplary|adjective|نمونه، سرمشق
exonerate|verb|تبرئه کردن
expedient|adjective|مصلحت‌آمیز، به‌صرفه
extraneous|adjective|نامربوط، زائد
facetious|adjective|شوخی‌آمیز (در زمان نامناسب)
fastidious|adjective|وسواسی، سخت‌پسند
fatuous|adjective|احمقانه
fervent|adjective|پرشور، مشتاق
fortuitous|adjective|اتفاقی، خوش‌شانسانه
fractious|adjective|بدخلق، ستیزه‌جو
frugal|adjective|مقتصد، صرفه‌جو
garrulous|adjective|وراج
gregarious|adjective|اجتماعی، معاشرتی
guileless|adjective|ساده‌دل، بی‌ریا
hackneyed|adjective|پیش‌پاافتاده، کلیشه‌ای
harbinger|noun|پیش‌آگهی، نشانه‌ی آغاز
hegemony|noun|سلطه، برتری
iconoclast|noun|سنت‌شکن
idiosyncrasy|noun|ویژگی خاص، خصیصه‌ی فردی
ignominious|adjective|ننگین، شرم‌آور
immutable|adjective|تغییرناپذیر
impeccable|adjective|بی‌نقص
impecunious|adjective|بی‌پول، ندار
imperious|adjective|مستبد، آمرانه
impervious|adjective|نفوذناپذیر، بی‌تأثیر
implacable|adjective|سازش‌ناپذیر
inchoate|adjective|نوپا، در مراحل آغازین
incongruous|adjective|ناهماهنگ، نامتناسب
indefatigable|adjective|خستگی‌ناپذیر
indolent|adjective|تنبل، کاهل
ineffable|adjective|وصف‌ناپذیر
inexorable|adjective|تغییرناپذیر، اجتناب‌ناپذیر
ingenuous|adjective|ساده‌دل، صادق
inimical|adjective|دشمنانه، مضر
innocuous|adjective|بی‌ضرر
insidious|adjective|موذیانه، نامحسوس
intransigent|adjective|لجوج، سازش‌ناپذیر
inundate|verb|غرق کردن، سرازیر شدن
inveterate|adjective|دیرینه، ریشه‌دار
irascible|adjective|زودخشم
laconic|adjective|مختصر و مفید
languid|adjective|بی‌حال، سست
largesse|noun|بخشش، سخاوت
latent|adjective|نهفته، پنهان
lethargic|adjective|بی‌حال، کسل
loquacious|adjective|پرگو
lucid|adjective|روشن، گویا
magnanimous|adjective|بزرگوار، بخشنده
malevolent|adjective|بدخواه
malleable|adjective|انعطاف‌پذیر، شکل‌پذیر
mellifluous|adjective|شیرین و دلنشین (صدا)
mercurial|adjective|دمدمی‌مزاج، متلون
mitigate|verb|تخفیف دادن، کاهش دادن
mundane|adjective|عادی، دنیوی
munificent|adjective|بسیار بخشنده
nefarious|adjective|شرورانه، پلید
neophyte|noun|تازه‌کار، نوآموز
noxious|adjective|زیان‌آور، سمی
nuance|noun|ظرافت، تفاوت ظریف
obdurate|adjective|یک‌دنده، سنگ‌دل
obfuscate|verb|مبهم کردن
obstreperous|adjective|پرسروصدا، سرکش
obviate|verb|برطرف کردن، بی‌نیاز کردن
onerous|adjective|طاقت‌فرسا، سنگین
opaque|adjective|مات، نامفهوم
ostentatious|adjective|پرزرق‌وبرق، خودنمایانه
panacea|noun|درمان همه‌ی دردها
paradigm|noun|الگو، چارچوب فکری
parsimonious|adjective|خسیس، بسیار صرفه‌جو
pedantic|adjective|فضل‌فروش، موشکاف
penchant|noun|گرایش، علاقه‌ی ویژه
penurious|adjective|فقیر، خسیس
perfunctory|adjective|سرسری، تشریفاتی
pervasive|adjective|فراگیر
phlegmatic|adjective|خونسرد، بی‌تفاوت
pithy|adjective|موجز و پرمعنا
placate|verb|آرام کردن، دلجویی کردن
platitude|noun|سخن پیش‌پاافتاده
plethora|noun|فراوانی، انبوه
poignant|adjective|دردناک، تأثرانگیز
pragmatic|adjective|عمل‌گرا، واقع‌بین
precarious|adjective|متزلزل، خطرناک
precipitate|verb|شتاب بخشیدن، به‌سرعت پدید آوردن
prescient|adjective|آینده‌نگر
prevaricate|verb|طفره رفتن
prodigal|adjective|ولخرج
prolific|adjective|پرتولید، پربار
propensity|noun|تمایل، گرایش
propitious|adjective|مساعد، خجسته
prudent|adjective|محتاط، عاقل
pugnacious|adjective|ستیزه‌جو
punctilious|adjective|بسیار دقیق (در آداب)
pusillanimous|adjective|ترسو، بزدل
quixotic|adjective|آرمان‌گرای غیرواقع‌بین
rancorous|adjective|کینه‌توز
recondite|adjective|پیچیده و کم‌شناخته
redolent|adjective|یادآور، خوش‌بو
refute|verb|رد کردن (با دلیل)
relegate|verb|تنزل دادن، سپردن
reticent|adjective|کم‌حرف، محتاط در سخن
reverent|adjective|محترمانه، با احترام
rhetoric|noun|فنِ سخنوری، لفاظی
rudimentary|adjective|ابتدایی، مقدماتی
sagacious|adjective|دوراندیش، زیرک
salient|adjective|برجسته، مهم
sardonic|adjective|تمسخرآمیز، نیشدار
scrupulous|adjective|وجدانی، بسیار دقیق
sedulous|adjective|پرکار، کوشا
serendipity|noun|کشف اتفاقیِ خوش‌یمن
sycophant|noun|متملق، چاپلوس
spurious|adjective|جعلی، ساختگی
squander|verb|هدر دادن، تلف کردن
staunch|adjective|وفادار، مصمم
stoic|adjective|صبور، بردبار
stringent|adjective|سخت‌گیرانه
sublime|adjective|شکوهمند، متعالی
substantiate|verb|اثبات کردن، مستند کردن
supercilious|adjective|متکبر، از بالا نگرنده
surreptitious|adjective|دزدکی، پنهانی
tangential|adjective|حاشیه‌ای، کم‌ربط
tedious|adjective|خسته‌کننده، ملال‌آور
temerity|noun|جسارت، گستاخی
tenuous|adjective|سست، ضعیف
terse|adjective|کوتاه و بی‌پرده
trepidation|noun|نگرانی، اضطراب
truculent|adjective|ستیزه‌جو، پرخاشگر
turbulent|adjective|پرتلاطم، آشفته
tyro|noun|مبتدی، تازه‌کار
unassailable|adjective|خدشه‌ناپذیر
unequivocal|adjective|صریح، بی‌ابهام
unwarranted|adjective|بی‌دلیل، ناموجه
urbane|adjective|مؤدب و فرهیخته
vacillate|verb|مردد بودن، دودل بودن
vehement|adjective|شدید، پرشور
venerable|adjective|محترم، سالخورده و ارجمند
veracity|noun|راستی، صحت
verbose|adjective|پرگو، حاشیه‌پرداز
vex|verb|آزردن، عصبانی کردن
vicarious|adjective|غیرمستقیم، جانشینی
vilify|verb|بدنام کردن، افترا زدن
virulent|adjective|کشنده، بسیار تند
vitriolic|adjective|گزنده، تلخ و زهرآلود
volatile|adjective|ناپایدار، منفجرشونده
voracious|adjective|حریص، پرخور
wane|verb|کم‌فروغ شدن، رو به کاهش رفتن
whimsical|adjective|هوسی، شوخ‌طبع و غیرمعمول
winsome|adjective|دلنشین، جذاب
zenith|noun|اوج، قله
`;

const B1 = `
achieve|verb|به دست آوردن، موفق شدن
adapt|verb|سازگار شدن، تطبیق دادن
admit|verb|اعتراف کردن، پذیرفتن
afford|verb|از پس هزینه‌ی چیزی برآمدن
agreement|noun|توافق، موافقت
announce|verb|اعلام کردن
anxious|adjective|نگران، مضطرب
apologize|verb|عذرخواهی کردن
appointment|noun|قرار ملاقات
approach|noun|رویکرد، شیوه
approve|verb|تأیید کردن
arrange|verb|ترتیب دادن، هماهنگ کردن
aspect|noun|جنبه، وجه
assume|verb|فرض کردن
attitude|noun|نگرش، طرز برخورد
audience|noun|مخاطبان، تماشاگران
available|adjective|در دسترس، موجود
aware|adjective|آگاه، مطلع
background|noun|پیشینه، زمینه
benefit|noun|فایده، مزیت
border|noun|مرز
budget|noun|بودجه
campaign|noun|کارزار، مبارزه‌ی تبلیغاتی
cancel|verb|لغو کردن
candidate|noun|نامزد، داوطلب
capable|adjective|توانا، قادر
career|noun|مسیر شغلی
casual|adjective|غیررسمی، راحت
cause|noun|علت، دلیل
challenge|noun|چالش، مسئله‌ی دشوار
charity|noun|مؤسسه‌ی خیریه
chief|adjective|اصلی، ارشد
claim|verb|ادعا کردن
clue|noun|سرنخ
colleague|noun|همکار
commit|verb|متعهد شدن، مرتکب شدن
community|noun|جامعه، جمع
complain|verb|شکایت کردن
complex|adjective|پیچیده
concentrate|verb|تمرکز کردن
conclude|verb|نتیجه گرفتن، به پایان رساندن
conduct|verb|انجام دادن، هدایت کردن
confident|adjective|مطمئن، با اعتماد به نفس
conflict|noun|تعارض، درگیری
consequence|noun|پیامد، نتیجه
consider|verb|در نظر گرفتن
constant|adjective|پیوسته، ثابت
contact|verb|تماس گرفتن
contribute|verb|مشارکت کردن، سهیم بودن
convince|verb|متقاعد کردن
cope|verb|کنار آمدن، از پس برآمدن
courage|noun|شجاعت
crowd|noun|جمعیت
curious|adjective|کنجکاو
current|adjective|کنونی، جاری
damage|noun|خسارت، آسیب
deadline|noun|مهلت، سررسید
deal with|verb|سروکار داشتن با، رسیدگی کردن به
decade|noun|دهه
decline|verb|رد کردن، کاهش یافتن
define|verb|تعریف کردن
delay|noun|تأخیر
deliver|verb|تحویل دادن، ارائه دادن
demand|noun|تقاضا، درخواست
depend|verb|وابسته بودن
describe|verb|توصیف کردن
deserve|verb|سزاوار بودن
destroy|verb|نابود کردن
detail|noun|جزئیات
determine|verb|تعیین کردن، مصمم شدن
develop|verb|توسعه دادن، رشد کردن
disagree|verb|مخالف بودن
disappointed|adjective|ناامید، دلسرد
discuss|verb|بحث کردن
distance|noun|فاصله
document|noun|سند، مدرک
doubt|noun|تردید، شک
economy|noun|اقتصاد
effort|noun|تلاش، کوشش
election|noun|انتخابات
emergency|noun|وضعیت اضطراری
emphasis|noun|تأکید
encourage|verb|تشویق کردن
enormous|adjective|بسیار بزرگ، عظیم
environment|noun|محیط، محیط زیست
equipment|noun|تجهیزات
essential|adjective|ضروری
estimate|verb|تخمین زدن
evidence|noun|شواهد، مدرک
exchange|verb|مبادله کردن، عوض کردن
exhausted|adjective|خسته‌ی مفرط
expand|verb|گسترش دادن
expense|noun|هزینه
experience|noun|تجربه
expert|noun|متخصص
explore|verb|کاوش کردن
expose|verb|آشکار کردن، در معرض قرار دادن
fault|noun|تقصیر، ایراد
feature|noun|ویژگی
figure out|verb|فهمیدن، پی بردن
financial|adjective|مالی
flexible|adjective|انعطاف‌پذیر
focus|verb|تمرکز کردن
force|verb|مجبور کردن
foreign|adjective|خارجی
generation|noun|نسل
genuine|adjective|واقعی، اصیل
goal|noun|هدف
grateful|adjective|سپاسگزار
guarantee|noun|ضمانت
habit|noun|عادت
handle|verb|اداره کردن، از پس چیزی برآمدن
harm|noun|آسیب، زیان
helpful|adjective|مفید، کمک‌کننده
hesitate|verb|تردید کردن
honest|adjective|صادق، درستکار
hurry|verb|عجله کردن
identify|verb|شناسایی کردن
ignore|verb|نادیده گرفتن
impact|noun|تأثیر
impressive|adjective|تحسین‌برانگیز
improve|verb|بهبود دادن
income|noun|درآمد
increase|verb|افزایش یافتن
independent|adjective|مستقل
influence|noun|نفوذ، تأثیر
inform|verb|مطلع کردن
injury|noun|جراحت
insist|verb|اصرار کردن
instance|noun|نمونه، مورد
instruction|noun|دستورالعمل
insurance|noun|بیمه
intend|verb|قصد داشتن
interrupt|verb|حرف کسی را قطع کردن
introduce|verb|معرفی کردن
invest|verb|سرمایه‌گذاری کردن
involve|verb|شامل شدن، درگیر کردن
issue|noun|موضوع، مسئله
journey|noun|سفر
judge|verb|قضاوت کردن
justice|noun|عدالت
likely|adjective|محتمل
limit|noun|حد، محدودیت
location|noun|مکان، موقعیت
maintain|verb|حفظ کردن، نگهداری کردن
major|adjective|عمده، مهم
manage|verb|مدیریت کردن، از پس چیزی برآمدن
mention|verb|اشاره کردن
mood|noun|حال و هوا، خلق
motivation|noun|انگیزه
narrow|adjective|باریک، محدود
negotiate|verb|مذاکره کردن
nervous|adjective|عصبی، نگران
obvious|adjective|آشکار، بدیهی
occur|verb|رخ دادن
offer|verb|پیشنهاد دادن
opportunity|noun|فرصت
opinion|noun|نظر، عقیده
organize|verb|سازماندهی کردن
original|adjective|اصلی، بدیع
outcome|noun|نتیجه، پیامد
overcome|verb|غلبه کردن بر
patient|adjective|صبور
perform|verb|اجرا کردن، انجام دادن
permit|verb|اجازه دادن
persuade|verb|قانع کردن، ترغیب کردن
pressure|noun|فشار
prevent|verb|جلوگیری کردن
priority|noun|اولویت
process|noun|فرایند
progress|noun|پیشرفت
promote|verb|ترویج دادن، ارتقا دادن
protect|verb|محافظت کردن
provide|verb|فراهم کردن
purpose|noun|هدف، منظور
quality|noun|کیفیت
realize|verb|پی بردن، متوجه شدن
recommend|verb|توصیه کردن
reduce|verb|کاهش دادن
reflect|verb|بازتاب دادن، تأمل کردن
refuse|verb|امتناع کردن
regret|verb|پشیمان بودن، متأسف بودن
relationship|noun|رابطه
relevant|adjective|مرتبط
rely on|verb|تکیه کردن بر
remove|verb|برداشتن، حذف کردن
replace|verb|جایگزین کردن
represent|verb|نمایندگی کردن، نشان دادن
reputation|noun|شهرت، اعتبار
require|verb|نیاز داشتن، ایجاب کردن
research|noun|پژوهش
resist|verb|مقاومت کردن
resource|noun|منبع
respond|verb|پاسخ دادن
responsible|adjective|مسئول
result|noun|نتیجه
reveal|verb|فاش کردن
risk|noun|خطر، ریسک
role|noun|نقش
schedule|noun|برنامه‌ی زمانی
section|noun|بخش
secure|adjective|امن، مطمئن
senior|adjective|ارشد، مسن‌تر
shortage|noun|کمبود
significant|adjective|قابل‌توجه، مهم
similar|adjective|مشابه
skill|noun|مهارت
solve|verb|حل کردن
source|noun|منبع
stable|adjective|پایدار
standard|noun|استاندارد، معیار
strategy|noun|راهبرد
stress|noun|استرس
struggle|verb|دست‌وپنجه نرم کردن
suffer|verb|رنج بردن
suggest|verb|پیشنهاد کردن
support|verb|حمایت کردن
survive|verb|زنده ماندن
suspect|verb|مظنون بودن، گمان بردن
task|noun|وظیفه، کار
temporary|adjective|موقت
tend to|verb|گرایش داشتن به
tension|noun|تنش، کشیدگی
threat|noun|تهدید
tradition|noun|سنت
transport|noun|حمل‌ونقل
trust|verb|اعتماد کردن
unusual|adjective|غیرعادی
upset|adjective|ناراحت
urgent|adjective|فوری
valuable|adjective|ارزشمند
variety|noun|تنوع
volunteer|noun|داوطلب
warn|verb|هشدار دادن
wealth|noun|ثروت
witness|noun|شاهد
`;

const parse = (txt, level) =>
  txt.trim().split("\n").map((l) => {
    const [en, pos, fa] = l.split("|").map((s) => s.trim());
    return { level, pos, en, fa };
  });

const file = "paid-content/daily_words.json";
const list = JSON.parse(fs.readFileSync(file, "utf8"));
const have = new Set(list.map((w) => w.en.toLowerCase()));
let id = Math.max(499999, ...list.filter((w) => w.id >= 500000).map((w) => w.id)) + 1;
const stat = {};
for (const [lv, txt] of [["C2", C2], ["B1", B1]]) {
  for (const w of parse(txt, lv)) {
    if (!w.en || !w.fa || have.has(w.en.toLowerCase())) continue;
    list.push({ id: id++, ...w });
    have.add(w.en.toLowerCase());
    stat[lv] = (stat[lv] || 0) + 1;
  }
}
fs.writeFileSync(file, JSON.stringify(list));
console.log("daily_words:", list.length, "اضافه‌شده:", stat);
