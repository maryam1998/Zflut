// افزودنِ اسلنگِ سطحِ A1 به paid-content/slang_words.json — idempotent: node scripts/add-slang-a1.mjs
// فرمتِ هر خط:  en|category|fa|example      (category = کلیدِ kSlangTopics)
// لغتِ تکراری (در هر سه لیستِ slang / daily / vocab) اضافه نمی‌شود. شناسه‌ها از ۸۰۰۰۰۰ شروع می‌شوند
// (≥ ۵۰۰۰۰۰ ⇒ طبقِ build-paid-content هرگز رایگان نمی‌شود).
// بعد از اجرا: node scripts/build-paid-content.mjs --assets && node scripts/build-paid-content.mjs --sql content_seed
import fs from "node:fs";

const A1 = `
buddy|people|رفیق، دوست صمیمی|Thanks for your help, buddy!
dude|people|رفیق، داداش (خطاب غیررسمی)|Dude, you look tired today.
pal|people|رفیق|He is an old pal from school.
mate|people|رفیق (بریتانیایی)|Cheers, mate! See you tomorrow.
folks|people|جماعت، مردم|Good morning, folks! Let's start.
guys|people|بچه‌ها (خطاب جمع)|Hey guys, dinner is ready!
bro|people|داداش، رفیق|Bro, can you help me with this bag?
sis|people|آبجی، خواهر|Hi sis, how was your day?
kiddo|people|بچه‌جان|Come here, kiddo. It's time for bed.
bestie|people|بهترین دوست|She is my bestie. We talk every day.
roomie|people|هم‌اتاقی|My roomie cooks really good pasta.
newbie|people|تازه‌کار|I'm a newbie, so please be patient.
my folks|people|پدر و مادرم|My folks live in a small town.
loner|people|آدم تنها‌رو|He's a bit of a loner at school.
show-off|people|آدم پُز‌دهنده|Don't be such a show-off!
bummed|emotions|دلخور، دمغ|I'm bummed that it's raining today.
bummer|emotions|حیف! بد شد!|You missed the bus? What a bummer!
stoked|emotions|ذوق‌زده|I'm stoked about the trip!
pumped|emotions|پر انرژی و هیجان‌زده|I'm pumped for the game tonight.
beat|emotions|له و خسته|I'm beat. Let's go home.
wiped out|emotions|کاملاً بی‌حال و خسته|I was wiped out after the long walk.
stressed out|emotions|پر از استرس|She is stressed out about the exam.
grumpy|emotions|بدخلق، بداخم|Dad is grumpy before his coffee.
chill|emotions|آروم و بی‌خیال|Our teacher is really chill.
freaked out|emotions|وحشت‌زده، شوکه|I got freaked out by the loud noise.
over the moon|emotions|خیلی خوشحال|They were over the moon about the baby.
feel blue|emotions|دلگیر بودن|I feel blue when it rains all week.
crush|love|کسی که یه‌طرفه ازش خوشت میاد|I have a crush on a girl in my class.
ex|love|سابق، رابطه‌ی قبلی|My ex lives in another city now.
bae|love|عزیزم (اینترنتی)|Dinner with bae tonight!
hubby|love|شوهر (محاوره‌ای)|My hubby is cooking tonight.
sweetie|love|عزیزم، قربونت|Come here, sweetie. Let me help.
honey|love|عزیزم، جان دل|Honey, can you buy some milk?
BF|love|دوست‌پسر|Her BF is picking her up at six.
GF|love|دوست‌دختر|His GF is a doctor.
go out with|love|رابطه داشتن با، قرار گذاشتن با|He's been going out with Sara for a year.
ask out|love|دعوت به قرار کردن|He finally asked her out.
split up|love|از هم جدا شدن|They split up last month.
fall for|love|عاشق شدن|I think I'm falling for him.
hang out|fun|با دوستان وقت گذراندن|Let's hang out this weekend.
have a blast|fun|حسابی خوش گذراندن|We had a blast at the party.
kick back|fun|لم دادن و استراحت کردن|On Sundays I kick back and watch movies.
binge-watch|fun|پشت‌سرهم تماشا کردن|I binge-watched the whole series last night.
tunes|fun|آهنگ‌ها|Let's put on some tunes.
road trip|fun|سفر جاده‌ای|We're planning a road trip to the sea.
sleepover|fun|شب‌نشینی (خوابیدن خانه‌ی دوست)|She has a sleepover at her friend's house.
movie night|fun|شب فیلم|Friday is movie night at our house.
crash at|fun|شب جایی خوابیدن (موقتی)|You can crash at my place tonight.
pass out|fun|از حال رفتن، از خستگی بیهوش شدن|I was so tired that I passed out on the sofa.
grab a bite|food|یه چیزی خوردن|Let's grab a bite after class.
grab a coffee|food|یه قهوه خوردن|Do you want to grab a coffee?
starving|food|از گرسنگی مُردن|I'm starving! What's for lunch?
my treat|food|مهمونِ من|Dinner is my treat tonight.
on me|food|حساب با من|Put your wallet away. This one's on me.
takeout|food|غذای بیرون‌بر|Let's order takeout tonight.
cuppa|food|یه فنجون چای (بریتانیایی)|Fancy a cuppa?
yummy|food|خوشمزه|This cake is so yummy!
hangry|food|گرسنه و بداخلاق|I get hangry before lunch.
foodie|food|خوش‌خوراک، علاقه‌مند به غذا|My sister is a real foodie.
munchies|food|هوس خوراکی|I always get the munchies during a movie.
pig out|food|شکم‌چرانی کردن|We pigged out on pizza last night.
buck|money|یک دلار|The coffee costs three bucks.
broke|money|آس و پاس|I'm broke until Friday.
pricey|money|گران|This bag is a bit pricey.
a steal|money|خیلی ارزان، مفت|At that price, it's a steal!
rip-off|money|کلاه‌گذاری، گرون‌فروشی|Ten dollars for water? What a rip-off!
splurge|money|ولخرجی کردن|I splurged on new shoes.
chip in|money|سهم دادن|Let's all chip in for her gift.
split the bill|money|پول را تقسیم کردن|Shall we split the bill?
freebie|money|چیز مجانی|The bag was a freebie with the magazine.
cash|money|پول نقد|Do you take cash or card?
day off|work|روز تعطیل|I have a day off tomorrow.
clock in|work|ساعت ورود زدن|I clock in at nine every morning.
clock out|work|ساعت خروج زدن|She clocks out at five.
nine-to-five|work|کار اداری ثابت|I want a nine-to-five job.
gig|work|کار موقت، اجرا|I have a small gig on Saturday.
heads up|work|خبر قبلی، هشدار|Just a heads up, the meeting is at three.
on it|work|دارم انجامش میدم|Can you send the file? I'm on it.
ping me|work|بهم پیام بده|Ping me when you're ready.
get back to you|work|بعداً جواب می‌دم|Let me check and get back to you.
slack off|work|تنبلی کردن سر کار|Don't slack off. The deadline is tomorrow.
cram|school|شب امتحانی خوندن|I need to cram for the test.
pop quiz|school|امتحان سرزده|We had a pop quiz in math today.
skip class|school|کلاس را پیچوندن|Never skip class before an exam.
all-nighter|school|شب‌زنده‌داری برای درس|I pulled an all-nighter for the exam.
cheat sheet|school|برگه‌ی خلاصه (یادآور)|Make a cheat sheet for the grammar rules.
freshman|school|دانشجوی سال اول|She's a freshman at the university.
prof|school|استاد (کوتاه‌شده‌ی professor)|Our prof is giving a quiz tomorrow.
flunk|school|رد شدن در درس|I'm afraid I'll flunk chemistry.
straight A's|school|همه نمره‌ها عالی|He got straight A's this year.
under the weather|health|کسل، سرحال نیستم|I'm feeling a bit under the weather.
sick day|health|مرخصی استعلاجی|I took a sick day yesterday.
come down with|health|مریض شدن (با بیماری)|I think I'm coming down with a cold.
bug|health|ویروس (سرماخوردگی/ معده)|There's a stomach bug going around school.
doc|health|دکتر|I'm seeing the doc tomorrow.
flu shot|health|واکسن آنفولانزا|I got my flu shot yesterday.
sore|health|دردناک (عضله)|My legs are sore after the gym.
nap|health|چرت کوتاه|I'll take a quick nap after lunch.
catch some z's|health|خوابیدن|I need to catch some z's before the trip.
hit the hay|health|رفتن به رختخواب|It's late. I'm going to hit the hay.
hit the gym|health|رفتن به باشگاه|I hit the gym three times a week.
ride|travel|وسیله، رسوندن|Do you need a ride to the airport?
cab|travel|تاکسی|Let's take a cab. It's faster.
hop on|travel|سوار شدن|Hop on the bus at the next stop.
hit the road|travel|راه افتادن|We need to hit the road before six.
pit stop|travel|توقف کوتاه در راه|Let's make a quick pit stop for coffee.
tourist trap|travel|تله‌ی توریستی|That restaurant is a tourist trap.
on the go|travel|در حال حرکت، پرمشغله|I eat breakfast on the go.
carry-on|travel|بار دستی|I only have a carry-on.
crib|home|خونه (اسلنگ)|Nice crib! Is it new?
chores|home|کارهای خونه|We do the chores together on Sundays.
couch potato|home|آدم لم‌داده جلوی تی‌وی|Don't be a couch potato. Go outside!
tidy up|home|مرتب کردن|Please tidy up your room.
housewarming|home|جشن خانه‌ی نو|We're invited to a housewarming on Friday.
loo|home|دستشویی (بریتانیایی)|Excuse me, where is the loo?
fridge|home|یخچال|There's some juice in the fridge.
text|tech|پیامک دادن|Text me when you get home.
DM|tech|پیام خصوصی|Send me a DM with your number.
selfie|tech|سلفی|Let's take a selfie together!
google it|tech|بزنش تو گوگل|I don't know. Just google it.
scroll|tech|اسکرول کردن|I scroll through my phone every morning.
screenshot|tech|عکس از صفحه‌ی گوشی|Send me a screenshot of the message.
unfriend|tech|از دوستان حذف کردن|I unfriended him last year.
glitch|tech|ایراد فنی کوچک|There's a glitch in the app.
charger|tech|شارژر|Do you have a phone charger?
wow|exclaim|وای! عجب!|Wow! This view is amazing!
yay|exclaim|هورا! آخ جون!|Yay! We won the game!
oops|exclaim|اوپس! ببخشید!|Oops! I dropped my phone.
ouch|exclaim|آخ!|Ouch! That hurts.
yikes|exclaim|وای! (ترس یا تعجب)|Yikes! That spider is huge!
whoa|exclaim|وای! یه لحظه صبر کن!|Whoa, slow down! I can't follow you.
no way|exclaim|امکان نداره!|You won the prize? No way!
for real|exclaim|جدی؟ واقعاً؟|You're moving to Canada? For real?
my bad|exclaim|اشتباه از من بود|Oh, my bad! I sent you the wrong file.
no worries|exclaim|نگران نباش، مشکلی نیست|Sorry I'm late. No worries!
no biggie|exclaim|مهم نیست|You forgot my book? No biggie.
you bet|exclaim|حتماً! البته!|Can you help me? You bet!
sure thing|exclaim|حتماً، چشم|Could you close the door? Sure thing.
got it|exclaim|فهمیدم، باشه|Meet at six? Got it.
cool|exclaim|باحال، اوکی|You got a new bike? Cool!
awesome|exclaim|عالیه!|Awesome! See you there.
sweet|exclaim|عالیه! خوبه!|We have a free day? Sweet!
dang|exclaim|لعنتی (ملایم)|Dang, I forgot my keys!
uh-oh|exclaim|اوه اوه!|Uh-oh. I think we're lost.
nope|exclaim|نه|Is it raining? Nope.
yep|exclaim|آره|Are you ready? Yep.
nah|exclaim|نه (غیررسمی)|Want some more? Nah, I'm full.
uh-huh|exclaim|اوهوم (آره)|Did you finish? Uh-huh.
cheers|exclaim|مرسی، به سلامتی|Cheers for the lift!
what's up|phrases|چه خبر؟|Hey! What's up?
how's it going|phrases|اوضاع چطوره؟|Hi Tom, how's it going?
see ya|phrases|فعلاً، می‌بینمت|Okay, see ya tomorrow!
catch you later|phrases|بعداً می‌بینمت|I have to run. Catch you later!
long time no see|phrases|کم پیدایی!|Hey, long time no see!
take care|phrases|مراقب خودت باش|Bye now. Take care!
take it easy|phrases|آروم باش، خدانگهدار|Take it easy, and see you soon.
hang in there|phrases|مقاومت کن، دووم بیار|The exam is tough, but hang in there.
no rush|phrases|عجله‌ای نیست|Send it tomorrow. No rush.
sounds good|phrases|خوبه، موافقم|Dinner at seven? Sounds good.
works for me|phrases|برای من خوبه|Friday at three works for me.
I'm down|phrases|من موافقم، من هستم|Pizza tonight? I'm down.
count me in|phrases|روی من حساب کن|Going hiking? Count me in!
count me out|phrases|من نیستم|It's too late for me. Count me out.
I'm in|phrases|من هستم|A game of chess? I'm in.
I'm out|phrases|من نیستم، من رفتم|It's late. I'm out.
hold on|phrases|یه لحظه صبر کن|Hold on, I'll check my bag.
give me a sec|phrases|یه ثانیه بهم وقت بده|Give me a sec. I'm almost done.
be right back|phrases|الان برمی‌گردم|Be right back. I need some water.
same here|phrases|منم همین‌طور|I'm tired. Same here.
good for you|phrases|آفرین، خوش به حالت|You got the job? Good for you!
you got this|phrases|از پسش برمیای|The test is easy. You got this!
kind of|phrases|یه جورایی، تقریباً|It's kind of cold today.
a bunch of|phrases|یه عالمه، کلی|I have a bunch of work today.
a ton of|phrases|کلی، فراوان|There's a ton of traffic.
no kidding|phrases|جدی؟! شوخی نمی‌کنی!|You ran ten kilometers? No kidding!
gonna|abbrev|going to (می‌خوام)|I'm gonna call you tonight.
wanna|abbrev|want to (می‌خوای)|Do you wanna come with us?
gotta|abbrev|have to (باید)|I gotta go now.
gimme|abbrev|give me|Gimme a minute, please.
lemme|abbrev|let me|Lemme check my calendar.
dunno|abbrev|نمی‌دونم (I don't know)|I dunno. Maybe tomorrow?
kinda|abbrev|kind of (یه جورایی)|It's kinda expensive.
y'all|abbrev|شماها (you all)|Are y'all ready to order?
c'mon|abbrev|بیا دیگه (come on)|C'mon, we'll be late!
cuz|abbrev|چون (because)|I'm tired cuz I didn't sleep well.
tho|abbrev|هرچند (though)|It's cold tho. Take a coat.
pls|abbrev|لطفاً (please)|Call me back pls.
thx|abbrev|مرسی (thanks)|Thx for your help!
btw|abbrev|راستی (by the way)|Btw, the meeting is at five.
omg|abbrev|وای خدای من|Omg, I love this song!
lol|abbrev|(خنده) خیلی بامزه‌ست|That video is so funny, lol.
brb|abbrev|الان برمی‌گردم|Brb, my mom is calling.
idk|abbrev|نمی‌دونم|Idk what to wear tomorrow.
imo|abbrev|به نظر من|Imo, the first plan is better.
asap|abbrev|هرچه زودتر|Please reply asap.
ttyl|abbrev|بعداً حرف می‌زنیم|I have class now, ttyl!
fyi|abbrev|برای اطلاع شما|Fyi, the office closes at four today.
np|abbrev|مشکلی نیست|Thanks for the help! Np.
tbh|abbrev|راستش را بخواهی|Tbh, I didn't like the movie.
vibe|modern|حال و هوا، فضا|I love the vibe in this cafe.
lit|modern|عالی، شلوغ و پرانرژی|The party was lit!
slay|modern|ترکوندن، عالی عمل کردن|You slayed that presentation!
fam|modern|رفقا، خانواده‌ی صمیمی|Thanks, fam! You are the best.
lowkey|modern|یه جورایی (پنهانی)|I'm lowkey nervous about tomorrow.
no cap|modern|دروغ نمی‌گم، راست می‌گم|That was the best pizza ever, no cap.
sus|modern|مشکوک|That email looks sus. Don't click it.
mood|modern|دقیقاً حال منه|Monday mornings? Big mood.
fire|modern|فوق‌العاده، عالی|Your new song is fire!
cringe|modern|چندش‌آور، خجالت‌آور|That old photo is so cringe.
GOAT|modern|بهترین همه‌ی دوران|Messi is the GOAT for many fans.
flex|modern|پُز دادن|He likes to flex his new watch.
piece of cake|idioms|کار خیلی آسان|The test was a piece of cake.
break a leg|idioms|موفق باشی! (برای اجرا)|Break a leg at your concert tonight!
fingers crossed|idioms|به امید موفقیت|Fingers crossed for the interview!
just kidding|idioms|شوخی کردم|I'm leaving. Just kidding!
so far so good|idioms|تا اینجا که خوبه|How's the new job? So far so good.
once in a while|idioms|گهگاهی|I eat fast food once in a while.
keep in touch|idioms|در تماس بودن|Let's keep in touch after the course.
all set|idioms|همه‌چی آماده‌ست|Bags packed? Yes, we're all set.
`;

const read = (n) => {
  try { return JSON.parse(fs.readFileSync(`paid-content/${n}.json`, "utf8")); }
  catch { return []; }
};
const norm = (s) => String(s).toLowerCase().replace(/[’‘]/g, "'").replace(/^[«»"'.,!?;:()]+|[«»"'.,!?;:()]+$/g, "").trim();

const file = "paid-content/slang_words.json";
const list = read("slang_words");
const have = new Set([...list, ...read("daily_words"), ...read("vocab_in_use_words")].map((w) => norm(w.en)));
const CATS = new Set("people emotions love fun food money work school crime health travel home tech exclaim idioms phrases modern abbrev proverbs other".split(" "));

let id = Math.max(799999, ...list.filter((w) => w.id >= 800000).map((w) => w.id)) + 1;
let added = 0, skipped = 0;
for (const line of A1.trim().split("\n")) {
  const [en, category, fa, example] = line.split("|").map((s) => s.trim());
  if (!en || !fa || !example) throw new Error("خطِ ناقص: " + line);
  if (!CATS.has(category)) throw new Error("دسته‌ی نامعتبر: " + line);
  if (have.has(norm(en))) { skipped++; continue; }
  list.push({ id: id++, level: "A1", pos: category === "idioms" ? "idiom" : "slang", en, fa, category, example });
  have.add(norm(en));
  added++;
}
fs.writeFileSync(file, JSON.stringify(list));
console.log("slang_words:", list.length, "| A1 اضافه‌شده:", added, "| تکراری (رد شد):", skipped);
