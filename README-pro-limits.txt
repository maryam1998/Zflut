نسخه‌ی رایگان / Pro — راه‌اندازی
=================================
۱) VIP_EMAILS را به‌صورت Secret بگذار (نه داخل wrangler.toml): npx wrangler secret put VIP_EMAILS ← جیمیل‌ها با ویرگول.
   FREE_LIMIT = "2" سقفِ هر بخش است.
۲) Worker را دیپلوی کن:  npx wrangler deploy   (از پوشه‌ی ریشه، همان‌جا که src/index.js هست)
۳) محتوای پولی را در D1 بریز: در GitHub → Actions → «Seed paid content (D1)» → Run workflow
   (بعد از push این پچ هم خودکار اجرا می‌شود). به secretهای CLOUDFLARE_API_TOKEN و
   CLOUDFLARE_ACCOUNT_ID نیاز دارد و توکن باید دسترسیِ «D1 Edit» داشته باشد.
   ⚠️ تا این مرحله انجام نشود، کاربرانِ Pro فقط لغاتِ رایگان (ده لغتِ اولِ هر دسته) و دو موضوعِ مکالمه را می‌بینند.
   بعد از هر تغییرِ قانونِ لغاتِ رایگان (مثلاً FREE_PER_GROUP) این مرحله را دوباره اجرا کن؛
   push با GITHUB_TOKEN (پچ zip) این workflow را خودکار راه نمی‌اندازد → دستی Run workflow بزن.
۴) یک بار از اپ خارج و وارد شو (برای VIP) و اپ را دوباره بیلد کن.

تغییرِ محتوا: فقط فایل‌های paid-content/*.json را عوض کن (منبعِ کامل؛ داخلِ اپ نمی‌رود).
نسخه‌ی رایگانِ assets/data/ (ده لغتِ اولِ هر دسته + words_index.json = شمارِ کلِ لغاتِ هر دسته) از آن‌ها با این دستور ساخته می‌شود:
   node scripts/build-paid-content.mjs --assets

────────────────────────────────────────
محتوای رایگان (نسخه‌ی فعلی)
  • تب Talk (مکالمه): فقط موضوع «Greetings and Small Talk» و فقط سطح A1
  • دیکشنری من: ده لغتِ دست‌چینِ «Food & drink»
  • Vocabulary in use: ده لغتِ دست‌چینِ «Health & illness»
  • Slang: ده لغتِ دست‌چینِ «People & personality»
  عوض‌کردنِ لغاتِ رایگان: فهرستِ FREE_PICKS در scripts/build-paid-content.mjs → سپس
     node scripts/build-paid-content.mjs --assets
  و workflow «Seed paid content (D1)» را اجرا کن (بعد از پچ zip خودکار اجرا می‌شود).

پیش‌ترجمه‌ی محتوای رایگان (کشِ D1، بدونِ مصرفِ سهمیه‌ی AI)
     scripts/pretranslate-free.mjs   (راهنما: بالای همان فایل و scripts/pretranslate-free.workflow.yml)
