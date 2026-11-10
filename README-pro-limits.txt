نسخه‌ی رایگان / Pro — راه‌اندازی
=================================
۱) wrangler.toml: مقدارِ VIP_EMAILS را به جیمیل‌های خودت تغییر بده (چندتا: با ویرگول).
   FREE_LIMIT = "2" سقفِ هر بخش است.
۲) Worker را دیپلوی کن:  npx wrangler deploy   (از پوشه‌ی ریشه، همان‌جا که src/index.js هست)
۳) محتوای پولی را در D1 بریز: در GitHub → Actions → «Seed paid content (D1)» → Run workflow
   (بعد از push این پچ هم خودکار اجرا می‌شود). به secretهای CLOUDFLARE_API_TOKEN و
   CLOUDFLARE_ACCOUNT_ID نیاز دارد و توکن باید دسترسیِ «D1 Edit» داشته باشد.
   ⚠️ تا این مرحله انجام نشود، کاربرانِ Pro فقط ۳۰ لغتِ اول و دو موضوعِ مکالمه را می‌بینند.
۴) یک بار از اپ خارج و وارد شو (برای VIP) و اپ را دوباره بیلد کن.

تغییرِ محتوا: فقط فایل‌های paid-content/*.json را عوض کن (منبعِ کامل؛ داخلِ اپ نمی‌رود).
نسخه‌ی رایگانِ assets/data/ از آن‌ها با این دستور ساخته می‌شود:
   node scripts/build-paid-content.mjs --assets
