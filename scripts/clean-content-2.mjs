// پاک‌سازیِ مرحله‌ی دوم (idempotent): node scripts/clean-content-2.mjs
//  1) ردیف‌های «پاسخ‌نامه‌ی درس» (pos=answer) از Slang حذف می‌شوند (لغت نیستند).
//  2) ترجمه‌های غلطِ مشخص اصلاح می‌شوند (tangle، pooh-pooh و ...).
//  3) آیتم‌های بی‌ارزشِ Vocabulary in Use که مثالشان فقط «There is a <همان عبارت>.» است حذف می‌شوند.
//  4) لغتِ رایگان (۱۰ لغتِ اولِ هر دسته) هرگز حذف نمی‌شود.
// بعد از اجرا: node scripts/build-paid-content.mjs --assets
import fs from "node:fs";
const read = (f) => JSON.parse(fs.readFileSync(`paid-content/${f}.json`, "utf8"));
const write = (f, d) => fs.writeFileSync(`paid-content/${f}.json`, JSON.stringify(d));
const FREE = (f) => new Set(JSON.parse(fs.readFileSync(`assets/data/${f}.json`, "utf8")).map((w) => w.id));

// ── Slang ──
{
  const list = read("slang_words");
  const free = FREE("slang_words");
  const FIX = {
    tangle: "درهم‌پیچیدگی، گره (مثلاً گرهِ ترافیکی)",
    "pooh-pooh": "کوچک شمردن، دست‌کم گرفتن",
  };
  let removed = 0, fixed = 0;
  const out = [];
  for (const w of list) {
    if (w.pos === "answer" && !free.has(w.id)) { removed++; continue; }
    if (FIX[w.en] && w.fa !== FIX[w.en]) { w.fa = FIX[w.en]; fixed++; }
    out.push(w);
  }
  write("slang_words", out);
  console.log(`slang_words: ${list.length} → ${out.length} (حذفِ ${removed} ردیفِ پاسخ‌نامه، اصلاحِ ${fixed} ترجمه)`);
}

// ── Vocabulary in Use ──
{
  const list = read("vocab_in_use_words");
  const free = FREE("vocab_in_use_words");
  const norm = (s) => String(s).toLowerCase().replace(/[^a-z ]+/g, "").replace(/\s+/g, " ").trim();
  const trivial = (w) => {
    const m = /^There (?:is|are) (?:a|an|some|a lot of) ([^,.;!?]+)[.!]?$/i.exec((w.example || "").trim());
    if (!m) return false;
    const tail = norm(m[1]).replace(/s$/, "");
    const en = norm(w.en).replace(/s$/, "");
    return tail === en; // مثال فقط خودِ عبارت را تکرار می‌کند
  };
  const out = list.filter((w) => !(trivial(w) && !free.has(w.id)));
  write("vocab_in_use_words", out);
  console.log(`vocab_in_use_words: ${list.length} → ${out.length} (حذفِ ${list.length - out.length} آیتمِ بی‌ارزش)`);
}
