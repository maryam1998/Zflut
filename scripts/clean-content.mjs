// پاک‌سازیِ محتوای پولی (idempotent): node scripts/clean-content.mjs
//  1) تکراریِ «دقیق» (همان en + همان fa) از slang و vocab_in_use حذف می‌شود؛ اولین مورد در فایل می‌ماند.
//     لغت‌هایی که en یکسان ولی معنیِ متفاوت دارند (مثلاً دو معنیِ یک لغت) دست‌نخورده می‌مانند.
//  2) لغتی که در بخشِ رایگان (۱۰ لغتِ اولِ هر دسته) است هرگز حذف نمی‌شود.
//  3) آیتم‌های «شبیهِ جمله» در slang حذف نمی‌شوند؛ فقط در paid-content/_review/ برای بازبینیِ دستی فهرست می‌شوند.
// بعد از اجرا: node scripts/build-paid-content.mjs --assets  (ایندکس و فایل‌های رایگان دوباره ساخته می‌شوند)
import fs from "node:fs";

const norm = (s) => String(s).toLowerCase().replace(/[\u200c\s]+/g, " ").replace(/[.,!?;:"'()\u060c]+/g, "").trim();
const read = (f) => JSON.parse(fs.readFileSync(`paid-content/${f}.json`, "utf8"));
const write = (f, d) => fs.writeFileSync(`paid-content/${f}.json`, JSON.stringify(d));
const FREE = (f) => new Set(JSON.parse(fs.readFileSync(`assets/data/${f}.json`, "utf8")).map((w) => w.id));

function dedupe(name) {
  const list = read(name);
  const free = FREE(name);
  const seen = new Map(); // key → id نگه‌داشته‌شده
  const out = [];
  let removed = 0;
  for (const w of list) {
    const k = norm(w.en) + "|" + norm(w.fa);
    if (seen.has(k) && !free.has(w.id)) { removed++; continue; }
    if (!seen.has(k)) seen.set(k, w.id);
    out.push(w);
  }
  write(name, out);
  console.log(`${name}: ${list.length} → ${out.length} (حذفِ ${removed} تکراریِ دقیق)`);
  return out;
}

dedupe("vocab_in_use_words");
const slang = dedupe("slang_words");

// فهرستِ بازبینی: آیتم‌هایی در Slang که شبیهِ جمله‌ی کامل‌اند
const pat = /^(I|I'm|I've|I'll|I'd|My|He|She|We|They|You|Your|There|This|That|Do|Don't|Did|Are|Is|Can|Could|Would|What|Why|How|Where|When|Who|Please|Let's)\b/i;
const review = slang.filter((w) => pat.test(w.en.trim()) && w.en.trim().split(/\s+/).length >= 4);
fs.mkdirSync("paid-content/_review", { recursive: true });
fs.writeFileSync("paid-content/_review/slang_sentence_like.json", JSON.stringify(review.map(({ id, level, category, en, fa }) => ({ id, level, category, en, fa })), null, 1));
console.log(`review: ${review.length} آیتمِ شبیهِ جمله در paid-content/_review/slang_sentence_like.json`);
