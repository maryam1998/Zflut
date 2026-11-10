// ---------------------------------------------------------------------------
// جدا کردنِ «محتوای رایگان» از «محتوای پولی»
//
// منبعِ کامل: paid-content/*.json  (داخلِ اپ بسته‌بندی نمی‌شود؛ فقط به D1 می‌رود)
//
//   node scripts/build-paid-content.mjs --assets
//       ← نسخه‌ی رایگان را در assets/data/ می‌نویسد (۳۰ لغتِ اول + دو موضوعِ مکالمه با جمله‌های A1)
//   node scripts/build-paid-content.mjs --sql content_seed
//       ← فایل‌های SQL برای ریختنِ محتوای پولی در D1 (جدول‌های paid_words / paid_conversations / content_meta)
//
// برای تغییرِ محتوا: فایل‌های paid-content/ را عوض کن (نه assets/data) و دوباره اجرا کن.
// ---------------------------------------------------------------------------
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";

const FREE_WORDS = 30;
const FREE_TOPICS = ["Greetings and Small Talk", "Introducing People"];
const FREE_LEVEL = "A1";

const SRC = "paid-content";
const WORD_LISTS = { daily: "daily_words", slang: "slang_words", vocab: "vocab_in_use_words" };
const CONV_KINDS = { daily: "daily_conversations", thematic: "thematic_conversations" };

const read = (n) => JSON.parse(fs.readFileSync(path.join(SRC, n + ".json"), "utf8"));
const hash = (s) => crypto.createHash("sha1").update(s).digest("hex").slice(0, 12);
const q = (s) => "'" + String(s).replace(/'/g, "''") + "'";

function freeConversations(kind, topics) {
  return topics.map((t) => {
    if (kind === "daily" && FREE_TOPICS.includes(t.topic)) {
      // دو موضوعِ رایگان: فقط جمله‌های A1 (ساختارِ سناریوها حفظ می‌شود)
      return {
        ...t,
        scenarios: t.scenarios.map((s) => ({
          ...s,
          speakerA: (s.speakerA || []).filter((l) => l.level === FREE_LEVEL),
          speakerB: (s.speakerB || []).filter((l) => l.level === FREE_LEVEL),
        })),
      };
    }
    // موضوعِ پولی: فقط نام (برای نشان دادنِ کارتِ قفل‌شده)
    return { topic: t.topic, scenarios: [] };
  });
}

const args = process.argv.slice(2);

if (args.includes("--assets")) {
  for (const f of Object.values(WORD_LISTS)) {
    fs.writeFileSync(`assets/data/${f}.json`, JSON.stringify(read(f).slice(0, FREE_WORDS)));
  }
  for (const [kind, f] of Object.entries(CONV_KINDS)) {
    fs.writeFileSync(`assets/data/${f}.json`, JSON.stringify(freeConversations(kind, read(f))));
  }
  console.log("assets/data: free versions written");
}

const si = args.indexOf("--sql");
if (si >= 0) {
  const out = args[si + 1] || "content_seed";
  fs.rmSync(out, { recursive: true, force: true });
  fs.mkdirSync(out, { recursive: true });

  const stmts = [
    "CREATE TABLE IF NOT EXISTS paid_words (list TEXT NOT NULL, chunk INTEGER NOT NULL, data TEXT NOT NULL, PRIMARY KEY (list, chunk))",
    "CREATE TABLE IF NOT EXISTS paid_conversations (kind TEXT NOT NULL, idx INTEGER NOT NULL, topic TEXT NOT NULL, data TEXT NOT NULL, PRIMARY KEY (kind, idx))",
    "CREATE TABLE IF NOT EXISTS content_meta (key TEXT PRIMARY KEY, version TEXT NOT NULL, count INTEGER NOT NULL DEFAULT 0)",
    "DELETE FROM paid_words",
    "DELETE FROM paid_conversations",
    "DELETE FROM content_meta",
  ];

  // لغات: هرچه بعد از ۳۰ تای اول است، در تکه‌های حداکثر ~۶۰KB (سقفِ هر دستورِ D1 صد کیلوبایت است)
  for (const [list, f] of Object.entries(WORD_LISTS)) {
    const paid = read(f).slice(FREE_WORDS);
    let chunk = [], bytes = 0, n = 0;
    const flush = () => {
      if (!chunk.length) return;
      stmts.push(`INSERT INTO paid_words (list, chunk, data) VALUES (${q(list)}, ${n++}, ${q(JSON.stringify(chunk))})`);
      chunk = []; bytes = 0;
    };
    for (const w of paid) {
      const b = Buffer.byteLength(JSON.stringify(w), "utf8") + 1;
      if (bytes + b > 60000) flush();
      chunk.push(w); bytes += b;
    }
    flush();
    stmts.push(`INSERT INTO content_meta (key, version, count) VALUES (${q("words:" + list)}, ${q(hash(JSON.stringify(paid)))}, ${paid.length})`);
  }

  // مکالمه‌ها: کلِ هر موضوع (همه‌ی سطح‌ها) — برای Pro جایگزینِ نسخه‌ی رایگان می‌شود
  for (const [kind, f] of Object.entries(CONV_KINDS)) {
    const topics = read(f);
    topics.forEach((t, i) => {
      const s = JSON.stringify(t);
      if (Buffer.byteLength(s, "utf8") > 90000) throw new Error(`topic too large for one D1 statement: ${t.topic}`);
      stmts.push(`INSERT INTO paid_conversations (kind, idx, topic, data) VALUES (${q(kind)}, ${i}, ${q(t.topic)}, ${q(s)})`);
    });
    stmts.push(`INSERT INTO content_meta (key, version, count) VALUES (${q("conv:" + kind)}, ${q(hash(JSON.stringify(topics)))}, ${topics.length})`);
  }

  // تقسیم به فایل‌های ≤ ~۸۰۰KB
  let part = [], size = 0, idx = 0;
  const write = () => {
    if (!part.length) return;
    fs.writeFileSync(path.join(out, `part-${String(idx++).padStart(3, "0")}.sql`), part.join(";\n") + ";\n");
    part = []; size = 0;
  };
  for (const s of stmts) {
    const b = Buffer.byteLength(s, "utf8");
    if (size + b > 800000) write();
    part.push(s); size += b;
  }
  write();
  console.log(`${stmts.length} statements → ${idx} file(s) in ${out}/`);
}
