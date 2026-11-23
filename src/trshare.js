// ---------------------------------------------------------------------------
// 🗄️ /api/tr-share — کشِ مشترکِ ترجمه‌های اصلاح‌شده‌ی کاربرها
//   op "get": { items: [{text}], source_lang_code, target_lang_code } → { results: [string|null, ...] }
//   op "put": { text, translation, source_lang_code, target_lang_code, verified: true } → { ok: true }
//     🔒 فقط «پیشنهادِ تأییدشده با AI» (verified:true) پذیرفته می‌شود؛ بدونِ آن نادیده گرفته می‌شود.
//     ترجمه‌ی موجود در کشِ مشترک (ساخته‌ی AI یا قبلاً ذخیره‌شده) هرگز جایگزین نمی‌شود: اگر ردیفی
//     نبود همین ذخیره می‌شود؛ اگر بود، فقط در جدولِ tr_suggest به‌عنوان پیشنهاد (با شمارنده) ثبت می‌شود
//     و هیچ‌جا به کاربرها نشان داده نمی‌شود (برای بازبینیِ دستیِ مدیر).
// از همان جدول و همان کلیدِ /api/translate-text (gen_cache) استفاده می‌کند؛ پس
// translate-text هم ترجمه‌ی اصلاح‌شده را می‌بیند. هیچ AI صدا زده نمی‌شود (هزینه‌ی صفر).
// ردیف‌های این مسیر provider = "user" دارند (برای پاک‌سازی: DELETE FROM gen_cache WHERE provider='user').
// ---------------------------------------------------------------------------

const LANGS = new Set(["fa", "en", "it", "hi", "tr", "ar", "es", "de", "fr", "zh", "ko", "ru", "ja"]);
const MAX_TEXT = 300;      // مثلِ سقفِ /api/translate-text: متنِ بلندِ کاربر وارد کشِ مشترک نمی‌شود
const MAX_TRANSLATION = 1200;
const MAX_BATCH = 40;

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

// 📝 پیشنهادِ کاربر برای ترجمه‌ای که قفل است؛ فقط ذخیره می‌شود، به کسی نمایش داده نمی‌شود.
// بازبینی: SELECT * FROM tr_suggest ORDER BY n DESC;
async function saveSuggestion(env, key, text, source, target, tr) {
  try {
    if (!env.TR_DB) return;
    await env.TR_DB.prepare(
      "CREATE TABLE IF NOT EXISTS tr_suggest (k TEXT NOT NULL, v TEXT NOT NULL, text TEXT, src TEXT, tgt TEXT, n INTEGER NOT NULL DEFAULT 1, created INTEGER NOT NULL, PRIMARY KEY (k, v))"
    ).run();
    await env.TR_DB.prepare(
      "INSERT INTO tr_suggest (k, v, text, src, tgt, n, created) VALUES (?1, ?2, ?3, ?4, ?5, 1, ?6) ON CONFLICT(k, v) DO UPDATE SET n = n + 1"
    ).bind(key, tr, text, source, target, Date.now()).run();
  } catch {
    // پیشنهاد مهم نیست؛ خطا نباید چیزی را خراب کند
  }
}

export async function handleTrShare(request, env, ctx, cors, deps) {
  const { genCacheGet, genCachePut, trCacheKey } = deps;
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
    // ترجمه‌ی موجود (کلیدِ دقیقِ مبدأ یا «auto») = قفل؛ هرگز جایگزین نمی‌شود
    const existing = await existingRow(env, deps, key)
      || (source !== "auto" ? await existingRow(env, deps, await trCacheKey(env, "auto", target, text)) : null);
    if (!existing) {
      await genCachePut(env, key, tr, "user");
      return resp({ ok: true }, 200, cors);
    }
    if (existing.v === tr) return resp({ ok: true, skipped: "same" }, 200, cors);
    await saveSuggestion(env, key, text, source, target, tr);
    return resp({ ok: true, queued: "suggestion" }, 200, cors);
  }

  return resp({ error: "unknown op" }, 400, cors);
}
