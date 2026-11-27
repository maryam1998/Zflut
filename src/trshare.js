// ---------------------------------------------------------------------------
// 🗄️ /api/tr-share — کشِ مشترکِ ترجمه‌های اصلاح‌شده‌ی کاربرها
//   op "get": { items: [{text}], source_lang_code, target_lang_code } → { results: [string|null, ...] }
//   op "put": { text, translation, source_lang_code, target_lang_code, verified: true } → { ok: true }
//     🔒 فقط «پیشنهادِ تأییدشده با AI» (verified:true) پذیرفته می‌شود؛ بدونِ آن نادیده گرفته می‌شود.
//     🗳️ رای‌گیری: ترجمه‌ی ↻ هرگز مستقیم وارد D1 (gen_cache) نمی‌شود؛ به‌عنوان «رای» در tr_votes و
//     «پیشنهاد» در tr_suggest ثبت می‌شود. فقط وقتی ≥ TR_VOTE_MIN_USERS (پیش‌فرض ۳) کاربرِ «متفاوت»
//     (اکانتِ متفاوت) همین ترجمه را پیشنهاد دهند و مجموعِ «وزنِ» رای‌ها ≥ TR_VOTE_MIN_WEIGHT (پیش‌فرض ۳)
//     باشد، رسمی می‌شود (جایگزینِ ردیفِ gen_cache). وزن: Pro ×۲، و سنِ اکانت: <۳ روز ۰٫۲۵، <۱۴ روز ۰٫۵،
//     <۹۰ روز ۱، بیشتر ۱٫۲۵. هر کاربر برای هر متن فقط یک رای فعال دارد (رای تازه، قبلی را برمی‌دارد).
//     بازبینی: SELECT * FROM tr_suggest ORDER BY n DESC;  SELECT * FROM tr_votes;
// از همان جدول و همان کلیدِ /api/translate-text (gen_cache) استفاده می‌کند؛ پس
// translate-text هم ترجمه‌ی اصلاح‌شده را می‌بیند. هیچ AI صدا زده نمی‌شود (هزینه‌ی صفر).
// ردیف‌های این مسیر provider = "user" دارند (برای پاک‌سازی: DELETE FROM gen_cache WHERE provider='user').
// ---------------------------------------------------------------------------

import { verifySessionToken } from "./auth.js";
import { isPro } from "./usage.js";

const LANGS = new Set(["fa", "en", "it", "hi", "tr", "ar", "es", "de", "fr", "zh", "ko", "ru", "ja"]);
const MAX_TEXT = 300;      // مثلِ سقفِ /api/translate-text: متنِ بلندِ کاربر وارد کشِ مشترک نمی‌شود
const MAX_TRANSLATION = 1200;
const MAX_BATCH = 40;

// 🗳️ رای‌گیری (با متغیرهای محیطیِ اختیاری قابل‌تنظیم؛ بدونِ تغییرِ wrangler.toml پیش‌فرض‌ها کار می‌کنند)
const DAY_MS = 86400000;
const VOTE_TTL_MS = 30 * DAY_MS; // رای/پیشنهادی که در ۳۰ روز به حدِ نصاب نرسد پاک می‌شود

/** وزنِ رای: Pro دو برابر؛ اکانتِ قدیمی‌تر بیشتر؛ اکانتِ تازه‌وارد تقریباً بی‌اثر (ضدِ اسپم). */
export function voteWeight({ pro, ageMs }) {
  const d = Math.max(0, Number(ageMs) || 0) / DAY_MS;
  const age = d < 3 ? 0.25 : d < 14 ? 0.5 : d < 90 ? 1 : 1.25;
  return age * (pro ? 2 : 1);
}

function voteLimits(env) {
  const u = Number(env && env.TR_VOTE_MIN_USERS);
  const w = Number(env && env.TR_VOTE_MIN_WEIGHT);
  return {
    minUsers: Number.isFinite(u) && u >= 1 ? Math.floor(u) : 3,
    minWeight: Number.isFinite(w) && w > 0 ? w : 3,
  };
}

// ⏳ بدونِ TTLِ زمانی؛ فقط پاک‌سازیِ ۳ ساله (scheduled در index.js). کلید = هشِ متن + TR_MODEL_VERSION.

// یک کوئریِ SQL برای کلِ دسته (به‌جای یک کوئری برای هر مورد — سقفِ D1 رایگان ۵۰ کوئری در هر درخواست است).
// اگر برای زبانِ مبدأِ دقیق چیزی نبود، ترجمه‌ی ذخیره‌شده با مبدأِ "auto" هم قبول است.
async function lookupMany(env, deps, texts, source, target) {
  const { genCacheGet, trCacheKey } = deps;
  const valid = texts.map((t) => !!t && t.length <= MAX_TEXT);
  const exact = await Promise.all(
    texts.map((t, i) => (valid[i] ? trCacheKey(env, source, target, t) : null))
  );
  const auto = source === "auto"
    ? exact
    : await Promise.all(texts.map((t, i) => (valid[i] ? trCacheKey(env, "auto", target, t) : null)));
  const keys = [...new Set([...exact, ...auto].filter(Boolean))];
  if (!keys.length) return texts.map(() => null);

  const rows = new Map();
  try {
    if (!env.TR_DB) return texts.map(() => null);
    const ph = keys.map((_, i) => `?${i + 1}`).join(",");
    const res = await env.TR_DB.prepare(
      `SELECT k, v, provider, created FROM gen_cache WHERE k IN (${ph})`
    ).bind(...keys).all();
    for (const r of res.results || []) rows.set(r.k, r);
  } catch {
    // جدول هنوز ساخته نشده یا خطای D1 → مسیرِ قدیمیِ تک‌به‌تک (که جدول را هم می‌سازد)
    return Promise.all(
      texts.map(async (t, i) => (valid[i] ? (await genCacheGet(env, exact[i])) || null : null))
    );
  }
  const fresh = (r) => !!(r && r.v);
  return texts.map((t, i) => {
    if (!valid[i]) return null;
    const a = rows.get(exact[i]);
    if (fresh(a)) return a.v;
    const b = rows.get(auto[i]);
    return fresh(b) ? b.v : null;
  });
}

function resp(data, status, cors) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...cors },
  });
}

function norm(body) {
  const target = String(body?.target_lang_code ?? "").toLowerCase();
  const source = String(body?.source_lang_code ?? "auto").toLowerCase() || "auto";
  if (!LANGS.has(target)) return null;
  if (source !== "auto" && !LANGS.has(source)) return null;
  return { source, target };
}

// ردیفِ موجودِ کشِ مشترک (v و provider) یا null
async function existingRow(env, deps, key) {
  try {
    if (env.TR_DB) {
      const r = await env.TR_DB.prepare("SELECT v, provider FROM gen_cache WHERE k = ?1").bind(key).first();
      return r ? { v: r.v, provider: r.provider } : null;
    }
  } catch {
    // جدول هنوز ساخته نشده → مسیرِ ساده‌ی پایین
  }
  const v = await deps.genCacheGet(env, key);
  return v ? { v, provider: "?" } : null;
}

// 🗳️ سنِ اکانت (میلی‌ثانیه): قدیمی‌ترین دستگاهِ ثبت‌شده‌ی کاربر؛ اگر نبود، اولین رایِ خودش در همین جدول.
async function accountAgeMs(env, userId) {
  const now = Date.now();
  try {
    const r = await env.TR_DB.prepare("SELECT MIN(created) AS t FROM devices WHERE user_id = ?1").bind(userId).first();
    if (r && r.t) return Math.max(0, now - Number(r.t));
  } catch {
    // جدولِ devices نیست (حالتِ دستگاه خاموش) → از اولین رای
  }
  try {
    const r = await env.TR_DB.prepare("SELECT MIN(ts) AS t FROM tr_votes WHERE user_id = ?1").bind(userId).first();
    if (r && r.t) return Math.max(0, now - Number(r.t));
  } catch {
    // ignore
  }
  return 0;
}

let votesReady = false;
async function ensureVoteTables(env) {
  if (votesReady) return;
  await env.TR_DB.batch([
    env.TR_DB.prepare(
      "CREATE TABLE IF NOT EXISTS tr_suggest (k TEXT NOT NULL, v TEXT NOT NULL, text TEXT, src TEXT, tgt TEXT, n INTEGER NOT NULL DEFAULT 1, created INTEGER NOT NULL, PRIMARY KEY (k, v))"
    ),
    env.TR_DB.prepare(
      "CREATE TABLE IF NOT EXISTS tr_votes (k TEXT NOT NULL, v TEXT NOT NULL, user_id TEXT NOT NULL, w REAL NOT NULL, ts INTEGER NOT NULL, PRIMARY KEY (k, v, user_id))"
    ),
    env.TR_DB.prepare("CREATE INDEX IF NOT EXISTS idx_tr_votes_user ON tr_votes (user_id, k)"),
  ]);
  votesReady = true;
}

// 🗳️ رای کاربر به یک ترجمه‌ی پیشنهادی. خروجی: { promoted, users, weight } یا null (خطا/بدونِ D1).
// ترجمه‌ی موجودِ D1 فقط وقتی عوض می‌شود که حدِ نصابِ «کاربرِ متفاوت + وزن» پر شود.
async function castVote(env, deps, { key, text, source, target, tr, userId, pro }) {
  if (!env.TR_DB) return null;
  try {
    await ensureVoteTables(env);
    const now = Date.now();
    const ageMs = await accountAgeMs(env, userId);
    const w = voteWeight({ pro, ageMs });
    await env.TR_DB.batch([
      // هر کاربر برای هر متن فقط یک رای فعال دارد
      env.TR_DB.prepare("DELETE FROM tr_votes WHERE k = ?1 AND user_id = ?2 AND v <> ?3").bind(key, userId, tr),
      env.TR_DB.prepare(
        "INSERT INTO tr_votes (k, v, user_id, w, ts) VALUES (?1, ?2, ?3, ?4, ?5) ON CONFLICT(k, v, user_id) DO UPDATE SET w = ?4, ts = ?5"
      ).bind(key, tr, userId, w, now),
      env.TR_DB.prepare(
        "INSERT INTO tr_suggest (k, v, text, src, tgt, n, created) VALUES (?1, ?2, ?3, ?4, ?5, 0, ?6) ON CONFLICT(k, v) DO NOTHING"
      ).bind(key, tr, text, source, target, now),
    ]);
    const agg = await env.TR_DB.prepare(
      "SELECT COUNT(*) AS c, COALESCE(SUM(w), 0) AS s FROM tr_votes WHERE k = ?1 AND v = ?2"
    ).bind(key, tr).first();
    const users = Number(agg?.c || 0);
    const weight = Number(agg?.s || 0);
    await env.TR_DB.prepare("UPDATE tr_suggest SET n = ?3 WHERE k = ?1 AND v = ?2").bind(key, tr, users).run();
    const { minUsers, minWeight } = voteLimits(env);
    let promoted = false;
    if (users >= minUsers && weight >= minWeight) {
      // ✅ حدِ نصاب پر شد → ترجمه‌ی رسمی (جایگزینِ ردیفِ فعلی)؛ بعد رای‌ها و پیشنهادهای رقیبِ این متن پاک می‌شوند
      await deps.genCachePut(env, key, tr, "vote");
      await env.TR_DB.batch([
        env.TR_DB.prepare("DELETE FROM tr_votes WHERE k = ?1").bind(key),
        env.TR_DB.prepare("DELETE FROM tr_suggest WHERE k = ?1").bind(key),
      ]);
      promoted = true;
    }
    if (Math.random() < 0.02) {
      const old = now - VOTE_TTL_MS;
      await env.TR_DB.batch([
        env.TR_DB.prepare("DELETE FROM tr_votes WHERE ts < ?1").bind(old),
        env.TR_DB.prepare("DELETE FROM tr_suggest WHERE created < ?1 AND k NOT IN (SELECT k FROM tr_votes)").bind(old),
      ]);
    }
    return { promoted, users, weight };
  } catch (e) {
    console.error("[tr-vote] failed", String(e));
    return null;
  }
}

export async function handleTrShare(request, env, ctx, cors, deps) {
  const { genCacheGet, trCacheKey } = deps;
  let body;
  try {
    body = await request.json();
  } catch {
    return resp({ error: "Invalid JSON body" }, 400, cors);
  }
  const lp = norm(body);
  if (!lp) return resp({ error: "unsupported language" }, 400, cors);
  const { source, target } = lp;
  const keyOf = (text) => trCacheKey(env, source, target, text);

  if (body.op === "get") {
    const items = Array.isArray(body.items) ? body.items.slice(0, MAX_BATCH) : [];
    const texts = items.map((it) => String(it?.text ?? "").trim());
    const results = await lookupMany(env, deps, texts, source, target);
    return resp({ results }, 200, cors);
  }

  if (body.op === "put") {
    const text = String(body.text ?? "").trim();
    const tr = String(body.translation ?? "").trim();
    if (!text || text.length > MAX_TEXT) return resp({ error: "bad text" }, 400, cors);
    if (!tr || tr.length > MAX_TRANSLATION) return resp({ error: "bad translation" }, 400, cors);
    if (source === target) return resp({ ok: false, skipped: "same-language" }, 200, cors);
    if (tr.toLowerCase() === text.toLowerCase()) return resp({ ok: false, skipped: "same-as-source" }, 200, cors);
    if (!/\p{L}/u.test(tr)) return resp({ ok: false, skipped: "no-letters" }, 200, cors);
    // نسبتِ طول (برای متن‌های بلندتر از ۲۰ نویسه؛ CJK کوتاه‌تر است)
    if (text.length >= 20) {
      const ratio = tr.length / text.length;
      if (ratio < 0.15 || ratio > 6) return resp({ ok: false, skipped: "bad-ratio" }, 200, cors);
    }
    // 🔒 فقط پیشنهادِ تأییدشده با AI. کلاینت‌های قدیمی (بدونِ verified) و ↻ی ساده نادیده گرفته می‌شوند.
    if (body.verified !== true) return resp({ ok: true, skipped: "unverified" }, 200, cors);
    const key = await keyOf(text);
    // 🗳️ رای‌دهنده باید اکانتِ مشخص داشته باشد (توکنِ نشست)؛ بدونِ آن رای نمی‌شمارد
    const sess = await verifySessionToken(env, request.headers.get("X-App-Token"));
    if (!sess || !sess.sub) return resp({ ok: true, skipped: "no-user" }, 200, cors);
    // ترجمه‌ی موجود (کلیدِ دقیقِ مبدأ یا «auto») که با پیشنهاد یکی است → رای لازم نیست
    const existing = await existingRow(env, deps, key)
      || (source !== "auto" ? await existingRow(env, deps, await trCacheKey(env, "auto", target, text)) : null);
    if (existing && existing.v === tr) return resp({ ok: true, skipped: "same" }, 200, cors);
    let pro = false;
    try { pro = await isPro(env, sess.sub, sess.em); } catch { /* ignore */ }
    // ⚠️ هیچ‌وقت مستقیم در D1 نمی‌نویسیم؛ فقط رای
    const vote = await castVote(env, deps, { key, text, source, target, tr, userId: sess.sub, pro });
    if (vote && vote.promoted) return resp({ ok: true, promoted: true }, 200, cors);
    return resp({ ok: true, queued: "vote" }, 200, cors);
  }

  return resp({ error: "unknown op" }, 400, cors);
}
