// ---------------------------------------------------------------------------
// 🌍 پیش‌ترجمه‌ی «محتوای رایگان» با یک مدل قوی → کشِ مشترکِ D1 (جدول gen_cache)
//
// چرا: ترجمه‌های کش‌شده از سهمیه‌ی AI کم نمی‌شوند. کاربرِ رایگانِ تازه همه‌چیز را آماده می‌گیرد،
// بدونِ اینکه به AI، ML Kit یا مترجمِ رایگان (با کیفیتِ پایین) نیاز داشته باشد.
//
// چه چیزی ترجمه می‌شود (همان محتوای رایگانِ داخلِ اپ؛ از assets/data/ خوانده می‌شود):
//   • تب Talk: جمله‌های A1 موضوعِ «Greetings and Small Talk» + عنوان و توضیحِ سناریوها
//   • لغاتِ رایگان: دیکشنری من (food)، Vocabulary in use (health)، Slang (people) + جمله‌ی مثالِ لغات
//
// اجرا (از ریشه‌ی پروژه):
//   GEMINI_API_KEY=...  node scripts/pretranslate-free.mjs         ← ترجمه می‌کند و SQL می‌سازد (tr_seed/)
//   node scripts/pretranslate-free.mjs --sql-only                  ← فقط از ترجمه‌های ذخیره‌شده SQL می‌سازد
//   for f in tr_seed/*.sql; do npx wrangler d1 execute phrasebook-tr-cache --remote --file="$f"; done
// (یا از GitHub Actions: «Pre-translate free content (D1)» — فایلِ scripts/pretranslate-free.workflow.yml)
//
// تنظیمات (متغیرِ محیطی، همه اختیاری جز کلید):
//   GEMINI_API_KEY   کلیدِ Gemini.   (یا OPENAI_API_KEY + PRETR_BASE_URL برای هر سرویسِ سازگار با OpenAI)
//   PRETR_MODEL      نامِ مدل. پیش‌فرض: GEMINI_MODEL از wrangler.toml
//   PRETR_LANGS      زبان‌ها با ویرگول؛ پیش‌فرض: همه‌ی زبان‌های Worker به‌جز en
//
// ⚠️ کلید کش باید دقیقاً مثلِ trCacheKey در src/index.js باشد (TR_MODEL_VERSION از wrangler.toml خوانده می‌شود).
//    اگر روزی TR_MODEL_VERSION را عوض کردی، این اسکریپت را دوباره اجرا کن.
// ---------------------------------------------------------------------------
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";

const LANG_NAMES = {
  fa: "Persian", it: "Italian", hi: "Hindi", tr: "Turkish", ar: "Arabic", es: "Spanish",
  de: "German", fr: "French", zh: "Chinese (Simplified)", ko: "Korean", ru: "Russian", ja: "Japanese",
};
// هدف‌هایی که الفبای غیرلاتین دارند: خروجیشان باید حتماً از همان الفبا حرف داشته باشد (کنترلِ کیفیت)
const SCRIPT_RE = {
  fa: /[\u0600-\u06FF]/, ar: /[\u0600-\u06FF]/, hi: /[\u0900-\u097F]/, zh: /[\u4E00-\u9FFF]/,
  ko: /[\uAC00-\uD7AF]/, ru: /[\u0400-\u04FF]/, ja: /[\u3040-\u30FF\u4E00-\u9FFF]/,
};

const OUT_DIR = "tr_seed";
const CACHE_FILE = path.join(OUT_DIR, "translations.json"); // پیشرفت (اگر وسط کار قطع شد، ادامه می‌دهد)
const BATCH = 20;
const CONCURRENCY = 3;

const args = process.argv.slice(2);
const SQL_ONLY = args.includes("--sql-only");

// ───────── تنظیمات از wrangler.toml ─────────
const toml = fs.existsSync("wrangler.toml") ? fs.readFileSync("wrangler.toml", "utf8") : "";
const tomlVar = (k) => (toml.match(new RegExp(`^\\s*${k}\\s*=\\s*"([^"]*)"`, "m")) || [])[1];
const MV = (tomlVar("TR_MODEL_VERSION") || "1").trim() || "1";

const LANGS = (process.env.PRETR_LANGS || Object.keys(LANG_NAMES).join(","))
  .split(",").map((s) => s.trim()).filter((l) => LANG_NAMES[l]);

// ───────── جمع‌کردنِ متن‌های رایگان ─────────
const readJson = (p) => JSON.parse(fs.readFileSync(p, "utf8"));
/** @type {Map<string,{text:string, kind:string, hint?:string, fa?:string}>} */
const items = new Map();
function add(text, kind, extra = {}) {
  const t = String(text ?? "").trim();
  if (!t || t.length > 300) return;
  const prev = items.get(t);
  if (prev) {
    if (extra.fa && !prev.fa) prev.fa = extra.fa;
    if (extra.hint && !prev.hint) prev.hint = extra.hint;
    return;
  }
  items.set(t, { text: t, kind, ...extra });
}

function collect() {
  // تب Talk
  const convDir = "assets/data/conversations";
  for (const f of fs.existsSync(convDir) ? fs.readdirSync(convDir) : []) {
    if (!f.endsWith(".json")) continue;
    const t = readJson(path.join(convDir, f));
    for (const s of t.scenarios || []) {
      const lines = [...(s.speakerA || []), ...(s.speakerB || [])];
      if (!lines.length) continue; // سناریوی بدونِ جمله‌ی رایگان
      add(s.scenario, "title");
      add(s.context, "sentence");
      for (const l of lines) add(l.en, "sentence", l.fa ? { fa: l.fa } : {});
    }
  }
  // لغاتِ رایگان
  for (const f of ["daily_words", "vocab_in_use_words", "slang_words"]) {
    const p = `assets/data/${f}.json`;
    if (!fs.existsSync(p)) continue;
    for (const w of readJson(p)) {
      const hint = [w.pos, w.fa].filter(Boolean).join(" — ");
      add(w.en, "word", { hint, ...(w.fa ? { fa: w.fa } : {}) });
      if (w.example) add(w.example, "sentence");
      if (w.collocation) add(w.collocation, "phrase");
    }
  }
}

// ───────── مدل ─────────
const GEMINI_KEY = process.env.GEMINI_API_KEY || "";
const OPENAI_KEY = process.env.OPENAI_API_KEY || "";
const MODEL = process.env.PRETR_MODEL || tomlVar("GEMINI_MODEL") || "gemini-2.5-pro";
const BASE_URL = (process.env.PRETR_BASE_URL || "https://api.openai.com/v1").replace(/\/$/, "");

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function callModel(prompt) {
  for (let attempt = 0; attempt < 5; attempt++) {
    try {
      let raw;
      if (GEMINI_KEY) {
        const r = await fetch(
          `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(MODEL)}:generateContent`,
          {
            method: "POST",
            headers: { "Content-Type": "application/json", "x-goog-api-key": GEMINI_KEY },
            body: JSON.stringify({
              contents: [{ role: "user", parts: [{ text: prompt }] }],
              generationConfig: { temperature: 0.2, responseMimeType: "application/json" },
            }),
          }
        );
        if (!r.ok) throw new Error(`HTTP ${r.status} ${(await r.text()).slice(0, 200)}`);
        const j = await r.json();
        raw = (j.candidates?.[0]?.content?.parts || []).map((p) => p.text || "").join("");
      } else {
        const r = await fetch(`${BASE_URL}/chat/completions`, {
          method: "POST",
          headers: { "Content-Type": "application/json", Authorization: `Bearer ${OPENAI_KEY}` },
          body: JSON.stringify({
            model: MODEL,
            temperature: 0.2,
            response_format: { type: "json_object" },
            messages: [{ role: "user", content: prompt }],
          }),
        });
        if (!r.ok) throw new Error(`HTTP ${r.status} ${(await r.text()).slice(0, 200)}`);
        const j = await r.json();
        raw = j.choices?.[0]?.message?.content || "";
      }
      const clean = raw.replace(/^```(?:json)?\s*|\s*```$/g, "").trim();
      return JSON.parse(clean);
    } catch (e) {
      const wait = 2000 * 2 ** attempt;
      console.warn(`  ⚠️ ${e.message} — تلاشِ دوباره ${attempt + 1}/5 بعد از ${wait / 1000}s`);
      await sleep(wait);
    }
  }
  return null;
}

function buildPrompt(lang, batch) {
  const label = LANG_NAMES[lang];
  const list = batch.map((it, i) => ({
    i,
    text: it.text,
    kind: it.kind,
    ...(it.hint ? { meaning_hint: it.hint } : {}),
  }));
  return (
    `You are a professional translator for an English-learning app. Translate every item below from English into ${label}.\n` +
    `Rules:\n` +
    `- Translate by meaning, the way a native speaker would naturally say it. Idioms, slang, greetings and fixed expressions get a natural ${label} equivalent, never word for word.\n` +
    `- kind "word": give the most common everyday ${label} word for that sense (use meaning_hint — part of speech and a Persian gloss — to pick the right sense). No explanations.\n` +
    `- kind "sentence"/"title"/"phrase": a natural, friendly, correct translation with the same tone. Keep people's names as names (use the usual spelling in ${label}).\n` +
    `- Output plain text only: no quotes around the translation, no HTML entities, no notes, no transliteration, no original text.\n` +
    `Return ONLY a JSON object {"t":[...]} with exactly ${batch.length} strings, in the same order as the items.\n\n` +
    JSON.stringify(list)
  );
}

function bad(src, out, lang) {
  if (typeof out !== "string") return "not a string";
  const o = out.trim();
  if (!o) return "empty";
  if (o.length > 1200) return "too long";
  if (/&#?\w+;/.test(o)) return "html entity";
  if (/^["“”«»]|["“”«»]$/.test(o)) return "wrapped in quotes";
  if (SCRIPT_RE[lang] && !SCRIPT_RE[lang].test(o)) return "wrong script";
  if (!SCRIPT_RE[lang] && src.split(/\s+/).length > 3 && o.toLowerCase() === src.toLowerCase()) return "unchanged";
  return null;
}

// ───────── اجرا ─────────
fs.mkdirSync(OUT_DIR, { recursive: true });
/** @type {Record<string,string>}  کلید: lang|text */
const done = fs.existsSync(CACHE_FILE) ? readJson(CACHE_FILE) : {};
const save = () => fs.writeFileSync(CACHE_FILE, JSON.stringify(done));

collect();
if (!items.size) throw new Error("هیچ محتوای رایگانی پیدا نشد. اول: node scripts/build-paid-content.mjs --assets");
console.log(`${items.size} متنِ رایگان × ${LANGS.length} زبان | مدل: ${GEMINI_KEY ? "gemini" : "openai-compatible"}/${MODEL} | TR_MODEL_VERSION=${MV}`);

if (!SQL_ONLY) {
  if (!GEMINI_KEY && !OPENAI_KEY) throw new Error("GEMINI_API_KEY (یا OPENAI_API_KEY) لازم است.");

  // فارسی: اگر خودِ فایل ترجمه‌ی فارسی دارد (fa)، همان را بگذار؛ اپ هم همان را نشان می‌دهد.
  for (const it of items.values()) if (it.fa && LANGS.includes("fa")) done[`fa|${it.text}`] ??= it.fa;

  const jobs = [];
  for (const lang of LANGS) {
    const todo = [...items.values()].filter((it) => !done[`${lang}|${it.text}`]);
    for (let i = 0; i < todo.length; i += BATCH) jobs.push({ lang, batch: todo.slice(i, i + BATCH) });
  }
  console.log(`${jobs.length} درخواست برای ترجمه`);

  let next = 0, failed = 0;
  async function worker() {
    while (next < jobs.length) {
      const { lang, batch } = jobs[next++];
      const res = await callModel(buildPrompt(lang, batch));
      const arr = res && Array.isArray(res.t) ? res.t : null;
      if (!arr || arr.length !== batch.length) {
        // دسته خراب بود → تک‌تک امتحان کن
        for (const it of batch) {
          const r1 = await callModel(buildPrompt(lang, [it]));
          const o = r1 && Array.isArray(r1.t) ? r1.t[0] : null;
          const why = bad(it.text, o, lang);
          if (why) { failed++; console.warn(`  ✗ [${lang}] "${it.text}" → ${why}`); continue; }
          done[`${lang}|${it.text}`] = o.trim();
        }
      } else {
        batch.forEach((it, i) => {
          const why = bad(it.text, arr[i], lang);
          if (why) { failed++; console.warn(`  ✗ [${lang}] "${it.text}" → ${why}`); return; }
          done[`${lang}|${it.text}`] = arr[i].trim();
        });
      }
      save();
      console.log(`  ✓ ${lang} (${next}/${jobs.length})`);
    }
  }
  await Promise.all(Array.from({ length: CONCURRENCY }, worker));
  save();
  if (failed) console.warn(`⚠️ ${failed} مورد ترجمه نشد (ردشان کردم؛ اسکریپت را دوباره اجرا کن تا فقط همان‌ها تکرار شوند).`);
}

// ───────── ساختنِ SQL ─────────
// کلید دقیقاً مثلِ Worker: sha256(JSON.stringify([`translate-text|source|target|text`, 0])) و در نسخه‌ی مدلِ ≠ 1 پیشوندِ mv<نسخه>|
const keyOf = (source, target, text) => {
  const base = `translate-text|${source}|${target}|${text}`;
  const prompt = MV === "1" ? base : `mv${MV}|${base}`;
  return crypto.createHash("sha256").update(JSON.stringify([prompt, 0]), "utf8").digest("hex");
};
const q = (s) => "'" + String(s).replace(/'/g, "''") + "'";

const stmts = [
  "CREATE TABLE IF NOT EXISTS gen_cache (k TEXT PRIMARY KEY, v TEXT NOT NULL, provider TEXT, created INTEGER NOT NULL)",
];
const now = Date.now();
let rows = 0;
for (const it of items.values()) {
  for (const lang of LANGS) {
    const v = done[`${lang}|${it.text}`];
    if (!v) continue;
    // هم مبدأِ «en» و هم «auto» (اپ هرکدام را بفرستد، پیدا می‌شود).
    // ترجمه‌ی اصلاح‌شده‌ی خودِ کاربران (provider = 'user') هرگز رونویسی نمی‌شود.
    for (const source of ["en", "auto"]) {
      stmts.push(
        `INSERT INTO gen_cache (k, v, provider, created) VALUES (${q(keyOf(source, lang, it.text))}, ${q(v)}, 'seed', ${now}) ` +
          `ON CONFLICT(k) DO UPDATE SET v = excluded.v, provider = excluded.provider, created = excluded.created WHERE gen_cache.provider IS NOT 'user'`
      );
      rows++;
    }
  }
}
for (const f of fs.readdirSync(OUT_DIR)) if (f.endsWith(".sql")) fs.rmSync(path.join(OUT_DIR, f));
let part = [], size = 0, idx = 0;
const flush = () => {
  if (!part.length) return;
  fs.writeFileSync(path.join(OUT_DIR, `part-${String(idx++).padStart(3, "0")}.sql`), part.join(";\n") + ";\n");
  part = []; size = 0;
};
for (const s of stmts) {
  const b = Buffer.byteLength(s, "utf8");
  if (size + b > 500000) flush();
  part.push(s); size += b;
}
flush();
console.log(`${rows} ردیفِ کش → ${idx} فایل SQL در ${OUT_DIR}/`);
