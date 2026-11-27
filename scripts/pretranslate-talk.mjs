// ---------------------------------------------------------------------------
// 💬 پیش‌ترجمه‌ی «همه‌ی مکالماتِ تب Talk» (همه‌ی سطح‌ها، رایگان و پولی) با DeepSeek → کشِ مشترکِ D1 (جدول gen_cache)
//
// چرا: وقتی کاربرِ اول می‌آید همه‌چیز از قبل در D1 ترجمه شده؛ نه AI صدا زده می‌شود، نه سهمیه‌ی کسی مصرف می‌شود،
//      نه هزینه‌ای به تو می‌خورد (ترجمه‌ی کش‌شده برای همیشه رایگان است). «لغات» را اسکریپتِ pretranslate-words.mjs پوشش می‌دهد.
//
// ورودی: منبعِ کاملِ مکالمات (paid-content/*_conversations.json؛ اگر نبود assets/data/pro_conv_bundle.bin) + assets/data/conversations/*.json
//   از هر سناریو: عنوان (scenario)، توضیح (context) و تک‌تکِ جمله‌های speakerA / speakerB (en).
//   جمله‌ی بلندتر از ۳۰۰ کاراکتر رد می‌شود (سقفِ /api/translate-text در Worker). تکراری‌ها یک‌بار شمرده می‌شوند.
//
// اجرا (از ریشه‌ی پروژه) — دقیقاً مثلِ pretranslate-words:
//   DEEPSEEK_API_KEY=... node scripts/pretranslate-talk.mjs                  ← ترجمه (قابلِ ادامه)
//   DEEPSEEK_API_KEY=... node scripts/pretranslate-talk.mjs --upload         ← ترجمه + ریختن در D1
//   node scripts/pretranslate-talk.mjs --upload-only                         ← فقط آپلودِ ترجمه‌های آماده
//   node scripts/pretranslate-talk.mjs --report                              ← فقط گزارش (بدونِ هزینه)
//
// گزینه‌ها (آرگومان یا متغیرِ محیطی): --max-cost=3.5 | --langs=es,de | --sources=en,auto | --translate-fa | --d1-rows=90000
//   (همان معنیِ pretranslate-words.mjs). برای آپلود: CLOUDFLARE_API_TOKEN (D1 Edit) و CLOUDFLARE_ACCOUNT_ID.
//
// ♻️ ادامه (Resume): پیشرفت در tr_seed/talk-*.json ذخیره می‌شود. فارسی: همان fa خودِ فایل (بدونِ هزینه)؛ برای عنوان/توضیحِ سناریو که fa ندارند AI می‌سازد.
// ⚠️ کلید کش دقیقاً مثلِ trCacheKey در src/index.js است (TR_MODEL_VERSION از wrangler.toml). ترجمه‌ی اصلاح‌شده‌ی کاربران (provider='user') رونویسی نمی‌شود.
// ---------------------------------------------------------------------------
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { spawnSync } from "node:child_process";

const LANG_NAMES = {
  fa: "Persian", it: "Italian", hi: "Hindi", tr: "Turkish", ar: "Arabic", es: "Spanish",
  de: "German", fr: "French", zh: "Chinese (Simplified)", ko: "Korean", ru: "Russian", ja: "Japanese",
};
const SCRIPT_RE = {
  fa: /[\u0600-\u06FF]/, ar: /[\u0600-\u06FF]/, hi: /[\u0900-\u097F]/, zh: /[\u4E00-\u9FFF]/,
  ko: /[\uAC00-\uD7AF]/, ru: /[\u0400-\u04FF]/, ja: /[\u3040-\u30FF\u4E00-\u9FFF]/,
};

const OUT_DIR = "tr_seed";
const TR_FILE = path.join(OUT_DIR, "talk-translations.json"); // کلید: lang|text → ترجمه
const UP_FILE = path.join(OUT_DIR, "talk-uploaded.json");     // کلید: lang|text → true (آپلودشده)
const STATE_FILE = path.join(OUT_DIR, "talk-state.json");     // هزینه و شمارنده‌ها (تجمعی)
const BATCH = 20;
const CONCURRENCY = 3;

// ───────── آرگومان‌ها ─────────
const args = process.argv.slice(2);
const flag = (n) => args.includes(`--${n}`);
const opt = (n, env, dflt) => {
  const a = args.find((x) => x.startsWith(`--${n}=`));
  return a ? a.slice(n.length + 3) : (process.env[env] ?? dflt);
};
const REPORT = flag("report");
const UPLOAD_ONLY = flag("upload-only");
const UPLOAD = flag("upload") || UPLOAD_ONLY;
const TRANSLATE_FA = flag("translate-fa");
const MAX_COST = Number(opt("max-cost", "PRETR_MAX_COST_USD", "0")) || 0; // ۰ = بدونِ سقف
const D1_ROWS = Number(opt("d1-rows", "PRETR_D1_DAILY_ROWS", "90000")) || 90000;
const LANGS = String(opt("langs", "PRETR_LANGS", Object.keys(LANG_NAMES).join(",")))
  .split(",").map((s) => s.trim()).filter((l) => LANG_NAMES[l]);
const SOURCES = String(opt("sources", "PRETR_SOURCES", "en,auto")).split(",").map((s) => s.trim()).filter(Boolean);

// ───────── wrangler.toml ─────────
const toml = fs.existsSync("wrangler.toml") ? fs.readFileSync("wrangler.toml", "utf8") : "";
const tomlVar = (k) => (toml.match(new RegExp(`^\\s*${k}\\s*=\\s*"([^"]*)"`, "m")) || [])[1];
const MV = (tomlVar("TR_MODEL_VERSION") || "1").trim() || "1";
const DB_NAME = tomlVar("database_name") || "phrasebook-tr-cache";

// ───────── جمع‌کردنِ جمله‌های مکالمه ─────────
/** @type {Map<string,{text:string,hint:string,fa:string,kind:string}>} */
const items = new Map();
const MAX_LEN = 300; // سقفِ /api/translate-text
function add(textRaw, kind, fa = "") {
  const text = String(textRaw ?? "").trim();
  if (!text || text.length > MAX_LEN || !/\p{L}/u.test(text)) return;
  const prev = items.get(text);
  if (prev) { if (fa && !prev.fa) { prev.fa = fa; prev.hint = fa; } return; }
  items.set(text, { text, kind, fa, hint: fa });
}
function addTopics(list) {
  for (const t of Array.isArray(list) ? list : []) {
    for (const s of t.scenarios || []) {
      add(s.scenario, "title");
      add(s.context, "sentence");
      for (const l of [...(s.speakerA || []), ...(s.speakerB || [])]) {
        add(l.en, "sentence", typeof l.fa === "string" ? l.fa.trim() : "");
      }
    }
  }
}
/** منبعِ کاملِ مکالمات: ۱) paid-content/*_conversations.json  ۲) اگر نبود، assets/data/pro_conv_bundle.bin (XOR با همان کلیدِ build-pro-bundle.mjs) */
function loadFullTopics() {
  const out = [];
  for (const f of ["daily_conversations.json", "thematic_conversations.json"]) {
    const p = path.join("paid-content", f);
    if (fs.existsSync(p)) out.push({ name: p, topics: JSON.parse(fs.readFileSync(p, "utf8")) });
  }
  if (out.length) return out;
  const bin = path.join("assets", "data", "pro_conv_bundle.bin");
  if (fs.existsSync(bin)) {
    const buf = Buffer.from(fs.readFileSync(bin));
    const k = Buffer.from("lingova-pro-conv-v1");
    for (let i = 0; i < buf.length; i++) buf[i] ^= k[i % k.length];
    const obj = JSON.parse(buf.toString("utf8"));
    return [{ name: "pro_conv_bundle.bin", topics: Object.values(obj) }];
  }
  console.warn("  ⚠️ نه paid-content/ هست نه pro_conv_bundle.bin؛ فقط نسخه‌ی رایگانِ داخلِ assets/data خوانده می‌شود.");
  return ["daily_conversations.json", "thematic_conversations.json"]
    .map((f) => path.join("assets", "data", f))
    .filter((p) => fs.existsSync(p))
    .map((p) => ({ name: p, topics: JSON.parse(fs.readFileSync(p, "utf8")) }));
}
async function collect() {
  for (const { name, topics } of loadFullTopics()) {
    const before = items.size;
    addTopics(topics);
    console.log(`  ${name}: +${items.size - before} متنِ تازه`);
  }
  const cdir = path.join("assets", "data", "conversations");
  if (fs.existsSync(cdir)) {
    const before = items.size;
    for (const f of fs.readdirSync(cdir)) {
      if (!f.endsWith(".json")) continue;
      const j = JSON.parse(fs.readFileSync(path.join(cdir, f), "utf8"));
      addTopics(Array.isArray(j) ? j : [j]);
    }
    console.log(`  assets/data/conversations/*.json: +${items.size - before} متنِ تازه`);
  }
}

// ───────── ذخیره/بارگذاری ─────────
fs.mkdirSync(OUT_DIR, { recursive: true });
const readJson = (p, d) => (fs.existsSync(p) ? JSON.parse(fs.readFileSync(p, "utf8")) : d);
const done = readJson(TR_FILE, {});
const uploaded = readJson(UP_FILE, {});
const state = readJson(STATE_FILE, { cost_usd: 0, calls: 0, in_tok: 0, out_tok: 0 });
const saveDone = () => fs.writeFileSync(TR_FILE, JSON.stringify(done));
const saveUp = () => fs.writeFileSync(UP_FILE, JSON.stringify(uploaded));
const saveState = () => fs.writeFileSync(STATE_FILE, JSON.stringify(state));

// ───────── مدل (DeepSeek / سازگار با OpenAI) ─────────
const API_KEY = process.env.DEEPSEEK_API_KEY || process.env.PRETR_API_KEY || process.env.OPENAI_API_KEY || "";
const BASE_URL = (process.env.PRETR_BASE_URL || "https://api.deepseek.com").replace(/\/$/, "");
const MODEL = process.env.PRETR_MODEL || tomlVar("DEEPSEEK_MODEL") || "deepseek-chat";
const PRICE_IN = Number(process.env.PRETR_PRICE_IN || 0.28);
const PRICE_OUT = Number(process.env.PRETR_PRICE_OUT || 0.42);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let runCost = 0;
let stopped = false;

async function callModel(prompt) {
  for (let attempt = 0; attempt < 5; attempt++) {
    if (stopped) return null;
    try {
      const r = await fetch(`${BASE_URL}/chat/completions`, {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${API_KEY}` },
        body: JSON.stringify({
          model: MODEL,
          temperature: 0.2,
          response_format: { type: "json_object" },
          messages: [{ role: "user", content: prompt }],
        }),
      });
      if (!r.ok) throw new Error(`HTTP ${r.status} ${(await r.text()).slice(0, 160)}`);
      const j = await r.json();
      const inTok = j.usage?.prompt_tokens || 0, outTok = j.usage?.completion_tokens || 0;
      const c = (inTok * PRICE_IN + outTok * PRICE_OUT) / 1e6;
      state.calls++; state.in_tok += inTok; state.out_tok += outTok; state.cost_usd += c; runCost += c;
      if (MAX_COST && runCost >= MAX_COST) stopped = true; // بعد از همین دسته متوقف می‌شود
      const raw = j.choices?.[0]?.message?.content || "";
      return JSON.parse(raw.replace(/^```(?:json)?\s*|\s*```$/g, "").trim());
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
  const list = batch.map((it, i) => ({ i, text: it.text, kind: it.kind, ...(it.hint ? { persian_gloss: it.hint } : {}) }));
  return (
    `You are a professional translator for an English-learning app. Translate every item below from English into ${label}.\n` +
    `Rules:\n` +
    `- Translate by meaning, the way a native speaker would naturally say it in a friendly everyday conversation. Idioms, slang, greetings and fixed expressions get a natural ${label} equivalent, never word for word.\n` +
    `- persian_gloss (if present) only clarifies the intended meaning; do not translate from it and do not copy it.\n` +
    `- kind "title": a short natural scenario title. kind "sentence": a complete natural sentence with the same tone and punctuation. Keep people's names as names (usual spelling in ${label}).\n` +
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
  return null;
}

// ───────── کلید و SQL (مثلِ Worker) ─────────
const keyOf = (source, target, text) => {
  const base = `translate-text|${source}|${target}|${text}`;
  const prompt = MV === "1" ? base : `mv${MV}|${base}`;
  return crypto.createHash("sha256").update(JSON.stringify([prompt, 0]), "utf8").digest("hex");
};
const q = (s) => "'" + String(s).replace(/'/g, "''") + "'";
const insertSql = (source, lang, text, v, now) =>
  `INSERT INTO gen_cache (k, v, provider, created) VALUES (${q(keyOf(source, lang, text))}, ${q(v)}, 'seed', ${now}) ` +
  `ON CONFLICT(k) DO UPDATE SET v = excluded.v, provider = excluded.provider, created = excluded.created WHERE gen_cache.provider IS NOT 'user'`;

// ───────── گزارش ─────────
function report(extra = "") {
  const total = items.size * LANGS.length;
  let have = 0, up = 0;
  for (const it of items.values()) for (const l of LANGS) {
    if (done[`${l}|${it.text}`]) have++;
    if (uploaded[`${l}|${it.text}`]) up++;
  }
  const pct = (n) => (total ? ((n / total) * 100).toFixed(1) : "0.0");
  const remaining = total - have;
  const perCall = state.calls ? state.cost_usd / state.calls : 0.0004;
  const estLeft = (remaining / BATCH) * perCall;
  console.log("\n══════════ گزارش پیش‌ترجمه‌ی مکالمات Talk ══════════");
  console.log(`متن: ${items.size} | زبان: ${LANGS.length} | کل ترجمه: ${total}`);
  console.log(`ترجمه‌شده: ${have} (${pct(have)}٪) | باقی‌مانده: ${remaining}`);
  console.log(`آپلودشده در D1: ${up} (${pct(up)}٪)`);
  console.log(`هزینه‌ی تجمعی: $${state.cost_usd.toFixed(4)} (${state.calls} درخواست) | این اجرا: $${runCost.toFixed(4)}`);
  console.log(`برآورد هزینه‌ی باقی‌مانده: ~$${estLeft.toFixed(2)}`);
  if (extra) console.log(extra);
}

// ───────── ترجمه ─────────
async function translate() {
  if (!API_KEY) throw new Error("DEEPSEEK_API_KEY (یا PRETR_API_KEY / OPENAI_API_KEY) لازم است.");
  // فارسی: همان fa خودِ فایل مکالمات (بدونِ هزینه) مگر --translate-fa
  if (!TRANSLATE_FA && LANGS.includes("fa")) {
    for (const it of items.values()) if (it.fa) done[`fa|${it.text}`] ??= it.fa;
  }
  const jobs = [];
  for (const lang of LANGS) {
    const todo = [...items.values()].filter((it) => !done[`${lang}|${it.text}`]);
    for (let i = 0; i < todo.length; i += BATCH) jobs.push({ lang, batch: todo.slice(i, i + BATCH) });
  }
  console.log(`${jobs.length} درخواست (دسته‌ی ${BATCH}تایی) | مدل: ${MODEL} | سقفِ هزینه‌ی این اجرا: ${MAX_COST ? "$" + MAX_COST : "بدون سقف"}`);

  let next = 0, failed = 0, finished = 0;
  async function worker() {
    while (next < jobs.length && !stopped) {
      const { lang, batch } = jobs[next++];
      const res = await callModel(buildPrompt(lang, batch));
      const arr = res && Array.isArray(res.t) ? res.t : null;
      if (!arr || arr.length !== batch.length) {
        if (stopped) break;
        for (const it of batch) { // دسته خراب → تک‌تک
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
      finished++;
      saveDone(); saveState();
      if (finished % 10 === 0) console.log(`  ✓ ${finished}/${jobs.length} | $${runCost.toFixed(3)}`);
    }
  }
  await Promise.all(Array.from({ length: CONCURRENCY }, worker));
  saveDone(); saveState();
  if (stopped) console.log(`⏸️ به سقفِ هزینه رسید ($${runCost.toFixed(3)}). دوباره اجرا کن تا ادامه یابد.`);
  if (failed) console.warn(`⚠️ ${failed} مورد ردشد؛ اجرای بعدی فقط همان‌ها را تکرار می‌کند.`);
}

// ───────── آپلود در D1 (قابل ادامه) ─────────
function upload() {
  const now = Date.now();
  const pending = [];
  for (const it of items.values()) for (const lang of LANGS) {
    const k = `${lang}|${it.text}`;
    if (done[k] && !uploaded[k]) pending.push({ k, lang, text: it.text, v: done[k] });
  }
  if (!pending.length) { console.log("☁️ چیزی برای آپلود نیست."); return; }
  console.log(`☁️ ${pending.length} ترجمه برای آپلود (${SOURCES.join("+")}؛ سقفِ ${D1_ROWS} ردیف در این اجرا)`);
  const perItem = SOURCES.length;
  const create = "CREATE TABLE IF NOT EXISTS gen_cache (k TEXT PRIMARY KEY, v TEXT NOT NULL, provider TEXT, created INTEGER NOT NULL)";
  let rows = 0, i = 0;
  while (i < pending.length && rows + perItem <= D1_ROWS) {
    const chunk = []; let size = 0;
    const take = [];
    while (i < pending.length && chunk.length < 800 && size < 400000 && rows + (take.length + 1) * perItem <= D1_ROWS) {
      const p = pending[i++];
      for (const s of SOURCES) {
        const stmt = insertSql(s, p.lang, p.text, p.v, now);
        chunk.push(stmt); size += Buffer.byteLength(stmt, "utf8");
      }
      take.push(p);
    }
    if (!take.length) break;
    const file = path.join(OUT_DIR, "talk-upload.sql");
    fs.writeFileSync(file, create + ";\n" + chunk.join(";\n") + ";\n");
    const r = spawnSync("npx", ["wrangler", "d1", "execute", DB_NAME, "--remote", `--file=${file}`],
      { stdio: "inherit", shell: process.platform === "win32" });
    if (r.status !== 0) { console.error("❌ آپلود خطا داد؛ متوقف شد (پیشرفتِ قبلی حفظ شده)."); break; }
    for (const p of take) uploaded[p.k] = true;
    rows += take.length * perItem;
    saveUp();
    console.log(`  ☁️ ${rows} ردیف ریخته شد`);
  }
  if (i < pending.length) console.log(`⏸️ سقفِ ردیفِ روزانه‌ی D1 (${D1_ROWS}). فردا دوباره --upload-only بزن.`);
}

// ───────── اجرا ─────────
console.log("خواندن فایل‌های مکالمه…");
await collect();
if (!items.size) throw new Error("هیچ مکالمه‌ای پیدا نشد (assets/data/ را چک کن).");
console.log(`جمعاً ${items.size} متنِ یکتا × ${LANGS.length} زبان | TR_MODEL_VERSION=${MV}`);

if (!REPORT && !UPLOAD_ONLY) await translate();
if (UPLOAD && !REPORT) upload();
report();
