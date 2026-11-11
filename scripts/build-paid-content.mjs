// ---------------------------------------------------------------------------
// جدا کردنِ «محتوای رایگان» از «محتوای پولی»
//
// منبعِ کامل: paid-content/*.json  (داخلِ اپ بسته‌بندی نمی‌شود؛ فقط به D1 می‌رود)
//
//   node scripts/build-paid-content.mjs --assets
//       ← نسخه‌ی رایگان را در assets/data/ می‌نویسد:
//         • لغات: ده لغتِ اولِ «هر دسته» (دیکشنری: هر موضوع، Slang: هر دسته، Vocab in use: هر موضوعِ اصلی)
//         • assets/data/words_index.json: شمارِ کلِ لغاتِ هر دسته به‌تفکیکِ سطح (برای نمایشِ «قفل‌شده‌ها» به کاربرِ رایگان)
//         • دو موضوعِ مکالمه با جمله‌های A1
//   node scripts/build-paid-content.mjs --sql content_seed
//       ← فایل‌های SQL برای ریختنِ محتوای پولی در D1 (جدول‌های paid_words / paid_conversations / content_meta)
//
// برای تغییرِ محتوا: فایل‌های paid-content/ را عوض کن (نه assets/data) و دوباره اجرا کن.
// ---------------------------------------------------------------------------
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";

const FREE_PER_GROUP = 10; // 💎 تعدادِ لغتِ رایگان در هر دسته (باید با kFreeWordsPerGroup در pro_status.dart یکی باشد)
const FREE_TOPICS = ["Greetings and Small Talk", "Introducing People"];
const FREE_LEVEL = "A1";

const SRC = "paid-content";
const WORD_LISTS = { daily: "daily_words", slang: "slang_words", vocab: "vocab_in_use_words" };
const CONV_KINDS = { daily: "daily_conversations", thematic: "thematic_conversations" };

// 🌍 ترجمه‌ی فارسیِ جمله‌ها (fa) در فایل‌ها بماند؟ false = فقط متنِ انگلیسی؛ ترجمه را سیستمِ ترجمه‌ی اپ انجام می‌دهد.
// جمله‌های جدید همیشه فقط en دارند؛ این گزینه فقط روی جمله‌های قدیمیِ دارای fa اثر می‌گذارد.
const KEEP_FA = true;

const read = (n) => JSON.parse(fs.readFileSync(path.join(SRC, n + ".json"), "utf8"));
const hash = (s) => crypto.createHash("sha1").update(s).digest("hex").slice(0, 12);
const q = (s) => "'" + String(s).replace(/'/g, "''") + "'";

// ─────────── شناسه‌ی هر موضوع (نامِ فایل / ردیفِ D1) ───────────
// daily: «Greetings and Small Talk» → d-greetings-and-small-talk
// thematic: «طبیعت (Nature)» → t-nature   (از متنِ داخلِ پرانتز)
function topicId(kind, topic) {
  const m = topic.match(/\(([^)]+)\)/);
  const base = (m ? m[1] : topic)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return (kind === "daily" ? "d-" : "t-") + base;
}

// نسخه‌ی فایل: بدونِ fa (اگر KEEP_FA=false) و بدونِ فیلدهای خالی
function cleanTopic(t) {
  return {
    ...t,
    scenarios: (t.scenarios || []).map((s) => ({
      ...s,
      speakerA: (s.speakerA || []).map(cleanLine),
      speakerB: (s.speakerB || []).map(cleanLine),
    })),
  };
}
function cleanLine(l) {
  const o = { en: l.en, level: l.level };
  if (KEEP_FA && l.fa) o.fa = l.fa;
  return o;
}

// فهرستِ مرتبِ همه‌ی موضوع‌ها (daily بعد thematic) با شناسه و نسخه‌ی محتوای کامل
function allTopics() {
  const out = [];
  const seen = new Set();
  for (const [kind, f] of Object.entries(CONV_KINDS)) {
    read(f).forEach((t, i) => {
      const id = topicId(kind, t.topic);
      if (seen.has(id)) throw new Error(`duplicate topic id: ${id} (${t.topic})`);
      seen.add(id);
      const full = cleanTopic(t);
      out.push({ id, kind, idx: i, topic: t.topic, full, ver: hash(JSON.stringify(full)) });
    });
  }
  return out;
}

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


// ایندکسِ «شمارشِ» مکالمه‌ها (assets/data/conversations_index.json):
// نسخه‌ی رایگانِ اپ فقط نامِ موضوع‌های پولی را دارد، ولی کاربرِ رایگان باید ببیند هر موضوع
// در هر سطح چند جمله دارد (و چندتایش قفل است). این فایل فقط «عدد» است، نه خودِ جمله‌ها.
//   s = تعدادِ سناریوها | t = کلِ جمله‌ها به‌تفکیکِ سطح (A1..C2) | f = جمله‌های رایگان به‌تفکیکِ سطح
function buildConvIndex() {
  const out = { v: 2, freeLevel: FREE_LEVEL, freeTopics: FREE_TOPICS, list: [], topics: {} };
  for (const t of allTopics()) out.list.push({ id: t.id, kind: t.kind, topic: t.topic, ver: t.ver });
  for (const [kind, f] of Object.entries(CONV_KINDS)) {
    for (const t of read(f)) {
      const e = { s: t.scenarios.length, t: [0, 0, 0, 0, 0, 0], f: [0, 0, 0, 0, 0, 0] };
      const free = kind === "daily" && FREE_TOPICS.includes(t.topic);
      for (const s of t.scenarios) {
        for (const l of [...(s.speakerA || []), ...(s.speakerB || [])]) {
          const i = LEVELS.indexOf(l.level);
          if (i < 0) continue;
          e.t[i]++;
          if (free && l.level === FREE_LEVEL) e.f[i]++;
        }
      }
      out.topics[t.topic] = e;
    }
  }
  return out;
}


// ─────────── دسته‌بندیِ لغات (باید با اپ یکی باشد) ───────────
const LEVELS = ["A1", "A2", "B1", "B2", "C1", "C2"];

function unq(raw) {
  return raw.replace(/\\(u[0-9a-fA-F]{4}|.)/g, (_, e) => {
    if (e.length === 5) return String.fromCharCode(parseInt(e.slice(1), 16));
    if (e === "n") return "\n";
    if (e === "t") return "\t";
    return e; // \' \" \\ \$
  });
}

function dartMap(file, name) {
  const src = fs.readFileSync(file, "utf8");
  const i = src.indexOf(name + " = {");
  if (i < 0) throw new Error(`${name} not found in ${file}`);
  const j = src.indexOf("\n};", i);
  const body = src.slice(i, j);
  const out = new Map();
  const re = /(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")\s*:\s*(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")/g;
  let m;
  while ((m = re.exec(body))) out.set(unq(m[1] ?? m[2]), unq(m[3] ?? m[4]));
  return out;
}

// kVocabTopics: دسته‌ی ریز ← کلیدِ موضوعِ اصلی
function vocabCategoryToTopic(file) {
  const src = fs.readFileSync(file, "utf8");
  const a = src.indexOf("const List<VocabTopic> kVocabTopics = [");
  const b = src.indexOf("\n];", a);
  const body = src.slice(a, b);
  const out = new Map();
  const re = /VocabTopic\(\s*'([^']+)'\s*,\s*'(?:[^'\\]|\\.)*'\s*,\s*'(?:[^'\\]|\\.)*'\s*,\s*\[([\s\S]*?)\]\s*\)/g;
  let m;
  while ((m = re.exec(body))) {
    const key = m[1];
    const cre = /'((?:[^'\\]|\\.)*)'/g;
    let c;
    while ((c = cre.exec(m[2]))) out.set(unq(c[1]), key);
  }
  return out;
}

const EDGE = /^[«»"'.,!?;:()\u060C\u061B\u061F]+|[«»"'.,!?;:()\u060C\u061B\u061F]+$/g;
const cleanToken = (s) => String(s).toLowerCase().replace(EDGE, "").trim();

function buildTopicTools() {
  const dictFile = "lib/core/constants/dictionary_topics.dart";
  const kw = dartMap(dictFile, "kDictKeywordTopic");
  const ph = dartMap(dictFile, "kDictPhraseTopic");
  const v2d = dartMap(dictFile, "kVocabToDictTopic");
  const s2d = dartMap(dictFile, "kSlangToDictTopic");
  const cat2topic = vocabCategoryToTopic("lib/core/constants/vocab_topics.dart");

  const keywordTopic = (token) => {
    if (kw.has(token)) return kw.get(token);
    const c = [];
    if (token.endsWith("ies") && token.length > 4) c.push(token.slice(0, -3) + "y");
    if (token.endsWith("es") && token.length > 3) c.push(token.slice(0, -2));
    if (token.endsWith("s") && token.length > 3) c.push(token.slice(0, -1));
    if (token.endsWith("ed") && token.length > 4) { c.push(token.slice(0, -2)); c.push(token.slice(0, -1)); }
    if (token.endsWith("ing") && token.length > 5) { const b = token.slice(0, -3); c.push(b); c.push(b + "e"); }
    if (token.endsWith("ly") && token.length > 4) c.push(token.slice(0, -2));
    for (const x of c) if (kw.has(x)) return kw.get(x);
    return null;
  };

  // ایندکسِ «لغت ← موضوعِ دیکشنری» از Vocabulary in Use و Slang (مثلِ _topicIndexProvider)
  const idx = new Map();
  const put = (k, t) => { if (k && !idx.has(k)) idx.set(k, t); };
  for (const w of read("vocab_in_use_words")) {
    const vt = cat2topic.get(w.category);
    const t = vt ? v2d.get(vt) : null;
    if (t) put(cleanToken(w.en), t);
  }
  for (const w of read("slang_words")) {
    const t = s2d.get(w.category);
    if (t) put(cleanToken(w.en), t);
  }

  // مثلِ dictTopicOf در my_dictionary_provider.dart
  const dictTopicOf = (w) => {
    const k = cleanToken(w.en);
    const isExpr = w.pos === "idiom" || w.pos === "slang";
    const manual = ph.get(k) ?? (isExpr ? undefined : kw.get(k));
    if (manual) return manual;
    if (idx.has(k)) return idx.get(k);
    if (isExpr) return "talk";
    const toks = k.split(/\s+/).map(cleanToken).filter((t) => t.length > 2);
    const votes = new Map();
    for (const t of toks) {
      const tp = keywordTopic(t) ?? idx.get(t);
      if (tp) votes.set(tp, (votes.get(tp) ?? 0) + 1);
    }
    if (votes.size) {
      let best = votes.keys().next().value;
      for (const [k2, v] of votes) if (v > votes.get(best)) best = k2;
      return best;
    }
    return "other";
  };

  return { cat2topic, dictTopicOf };
}

// هر لیست: [{...word, o: ترتیبِ اصلی}] + گروهِ هر لغت
function prepareList(list, tools) {
  const file = WORD_LISTS[list];
  const words = read(file).map((w, o) => ({ ...w, o }));
  const groupOf = (w) => {
    if (list === "daily") return w.category || tools.dictTopicOf(w);
    if (list === "slang") return w.category || "other";
    return tools.cat2topic.get(w.category) || "_"; // vocab: موضوعِ اصلی
  };
  for (const w of words) {
    w.__g = groupOf(w);
    if (list === "daily") w.category = w.__g; // اپ موضوعِ لغاتِ روزمره را از همین می‌خواند
  }
  // ده لغتِ اولِ هر گروه (به ترتیبِ فایل) رایگان است
  const taken = new Map();
  for (const w of words) {
    const n = taken.get(w.__g) ?? 0;
    // لغاتِ افزوده‌شده با scripts/add-words.mjs (id ≥ 500000) هرگز رایگان نمی‌شوند
    w.__free = n < FREE_PER_GROUP && !(Number(w.id) >= 500000);
    if (w.__free) taken.set(w.__g, n + 1);
  }
  return words;
}

const strip = ({ __g, __free, ...w }) => w;

function buildIndex(prepared) {
  const lvIdx = (l) => LEVELS.indexOf(l);
  const blank = () => ({ t: [0, 0, 0, 0, 0, 0], f: [0, 0, 0, 0, 0, 0] });
  const out = { v: 1, perGroup: FREE_PER_GROUP };
  for (const [list, words] of Object.entries(prepared)) {
    const groups = {};
    const cats = {};
    for (const w of words) {
      const li = lvIdx(w.level);
      if (li < 0) continue;
      const g = (groups[w.__g] ??= blank());
      g.t[li]++;
      if (w.__free) g.f[li]++;
      if (list === "vocab") {
        const c = (cats[w.category] ??= blank());
        c.t[li]++;
        if (w.__free) c.f[li]++;
      }
    }
    out[list] = list === "vocab" ? { groups, cats } : { groups };
  }
  return out;
}

const args = process.argv.slice(2);

const tools = buildTopicTools();
const prepared = Object.fromEntries(Object.keys(WORD_LISTS).map((l) => [l, prepareList(l, tools)]));

if (args.includes("--assets")) {
  for (const [list, f] of Object.entries(WORD_LISTS)) {
    fs.writeFileSync(
      `assets/data/${f}.json`,
      JSON.stringify(prepared[list].filter((w) => w.__free).map(strip))
    );
  }
  fs.writeFileSync("assets/data/words_index.json", JSON.stringify(buildIndex(prepared)));
  // 💎 مکالمه‌ها: هر موضوع یک فایل. فقط موضوع‌های رایگان (و فقط جمله‌های A1) داخلِ اپ می‌آیند.
  // بقیه فقط در D1 هستند و موقعِ بازکردنِ موضوع دانلود می‌شوند (لود تنبل).
  const convDir = "assets/data/conversations";
  fs.rmSync(convDir, { recursive: true, force: true });
  fs.mkdirSync(convDir, { recursive: true });
  for (const f of Object.values(CONV_KINDS)) fs.rmSync(`assets/data/${f}.json`, { force: true });
  for (const t of allTopics()) {
    if (t.kind !== "daily" || !FREE_TOPICS.includes(t.topic)) continue;
    const [free] = freeConversations("daily", [t.full]);
    fs.writeFileSync(path.join(convDir, `${t.id}.json`), JSON.stringify(free));
  }
  fs.writeFileSync("assets/data/conversations_index.json", JSON.stringify(buildConvIndex()));
  console.log("assets/data: free words + conversations/<id>.json (free topics) + indexes written");
}

const si = args.indexOf("--sql");
if (si >= 0) {
  const out = args[si + 1] || "content_seed";
  fs.rmSync(out, { recursive: true, force: true });
  fs.mkdirSync(out, { recursive: true });

  const stmts = [
    "CREATE TABLE IF NOT EXISTS paid_words (list TEXT NOT NULL, chunk INTEGER NOT NULL, data TEXT NOT NULL, PRIMARY KEY (list, chunk))",
    "CREATE TABLE IF NOT EXISTS paid_conversations (kind TEXT NOT NULL, idx INTEGER NOT NULL, topic TEXT NOT NULL, data TEXT NOT NULL, PRIMARY KEY (kind, idx))",
    "CREATE TABLE IF NOT EXISTS paid_conv_topics (id TEXT PRIMARY KEY, kind TEXT NOT NULL, idx INTEGER NOT NULL, topic TEXT NOT NULL, version TEXT NOT NULL, data TEXT NOT NULL)",
    "CREATE TABLE IF NOT EXISTS content_meta (key TEXT PRIMARY KEY, version TEXT NOT NULL, count INTEGER NOT NULL DEFAULT 0)",
    "DELETE FROM paid_words",
    "DELETE FROM paid_conversations",
    "DELETE FROM paid_conv_topics",
    "DELETE FROM content_meta",
  ];

  // لغات: هرچه رایگان نیست (بعد از ده لغتِ اولِ هر دسته)، در تکه‌های حداکثر ~۶۰KB (سقفِ هر دستورِ D1 صد کیلوبایت است)
  for (const list of Object.keys(WORD_LISTS)) {
    const paid = prepared[list].filter((w) => !w.__free).map(strip);
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

  // مکالمه‌ها (لود تنبل): یک ردیف برای هر موضوعِ کامل، با نسخه‌ی خودش. اپ فقط موضوعِ بازشده را می‌گیرد.
  for (const t of allTopics()) {
    const s = JSON.stringify(t.full);
    if (Buffer.byteLength(s, "utf8") > 90000) throw new Error(`topic too large for one D1 statement: ${t.topic}`);
    stmts.push(`INSERT INTO paid_conv_topics (id, kind, idx, topic, version, data) VALUES (${q(t.id)}, ${q(t.kind)}, ${t.idx}, ${q(t.topic)}, ${q(t.ver)}, ${q(s)})`);
  }

  // ⚠️ مسیرِ قدیمی (نسخه‌های قدیمیِ اپ): کلِ لیست در یک پاسخ — برای سازگاری نگه داشته شده
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
