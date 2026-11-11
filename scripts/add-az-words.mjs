// وصل کردنِ لیستِ A–Z (hope_data/WORDS_AZ.js، ~۶٬۱۷۹ لغت) به دیکشنری — idempotent:
//   node scripts/add-az-words.mjs
// • لغاتی که از قبل در paid-content/daily_words.json هست (همان en، بدونِ توجه به حروفِ بزرگ/کوچک) دست نمی‌خورد.
// • بقیه با شناسه‌ی تازه (از ۷۰۰۰۰۰ به بعد) اضافه می‌شوند. شناسه‌های قدیمیِ A–Z با شناسه‌ی
//   Vocabulary in Use (۲۰۰۰۰۰+) و لغاتِ روزمره تداخل داشتند، برای همین دوباره شماره‌گذاری می‌شوند.
// • id ≥ 500000 ⇒ طبقِ قانونِ build-paid-content هرگز رایگان نمی‌شود (سقفِ رایگان همان قبلی می‌ماند).
// • pos به برچسب‌هایی که WordCard می‌شناسد نرمال می‌شود.
// بعد از اجرا:
//   node scripts/build-paid-content.mjs --assets && node scripts/build-paid-content.mjs --sql content_seed
import fs from "node:fs";

const SRC = "hope_data/WORDS_AZ.js";
const FILE = "paid-content/daily_words.json";
const FIRST_ID = 700000;

function parseExportArray(path, name) {
  const src = fs.readFileSync(path, "utf8");
  const sm = new RegExp(`export\\s+const\\s+${name}\\s*=\\s*\\[`).exec(src);
  if (!sm) throw new Error(`${name} not found in ${path}`);
  const start = sm.index + sm[0].length - 1;
  const endRe = /\n\];/g;
  endRe.lastIndex = start;
  const em = endRe.exec(src);
  if (!em) throw new Error(`end of ${name} not found in ${path}`);
  return Function(`"use strict"; return (${src.slice(start, em.index + 2)});`)();
}

const POS = {
  "indefinite article": "article",
  "definite article": "article",
  number: "numeral",
  "ordinal number": "numeral",
  "modal verb": "auxiliary",
  "linking verb": "auxiliary",
  "infinitive marker": "other",
  vocab: "other",
};
const normPos = (p) => POS[p] ?? p ?? "other";

const az = parseExportArray(SRC, "WORDS_AZ");
const list = JSON.parse(fs.readFileSync(FILE, "utf8"));
const have = new Set(list.map((w) => w.en.trim().toLowerCase()));
let id = Math.max(FIRST_ID - 1, ...list.map((w) => w.id)) + 1;

const stat = {};
let skipped = 0;
for (const w of az) {
  const en = String(w.en ?? "").trim();
  const fa = String(w.fa ?? "").trim();
  if (!en || !fa || have.has(en.toLowerCase())) { skipped++; continue; }
  list.push({ id: id++, level: w.level, pos: normPos(w.pos), en, fa });
  have.add(en.toLowerCase());
  stat[w.level] = (stat[w.level] || 0) + 1;
}
fs.writeFileSync(FILE, JSON.stringify(list));
console.log("A–Z:", az.length, "| تکراری/ردشده:", skipped, "| اضافه‌شده:", stat);
console.log("daily_words (دیکشنری):", list.length);
