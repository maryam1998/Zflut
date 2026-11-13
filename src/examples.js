// ---------------------------------------------------------------------------
// 🧩 مثال‌سازِ مشترک (فقط Pro) — POST /api/word-example
//
// ایده: مثال‌هایی که AI برای یک لغت می‌سازد در D1 (جدول example_pool) ذخیره می‌شود و بین همه‌ی
// کاربرانِ Pro مشترک است. کاربرِ بعدی اول مثال‌های ذخیره‌شده را می‌بیند؛ فقط اگر تعدادشان کم بود
// (کمتر از EXAMPLE_POOL_MAX) و این کاربر هم همه‌شان را قبلاً دیده بود، AI یک مثال تازه می‌سازد.
// نتیجه: هزینه‌ی AI برای هر لغت حداکثر EXAMPLE_POOL_MAX مثال است، نه «تعداد کاربر × مثال».
//
// ورودی:  { word, lang, have:[متنِ مثال‌هایی که کاربر همین الان دارد], meaning?, nativeLabel? }
// خروجی:  { text, source:"pool"|"ai", total }   یا   { exhausted:true, total }
// غیرِ Pro: 403 {code:"pro_required"}
//
// Vars اختیاری (wrangler.toml):  EXAMPLE_POOL_MAX = "8"
// ---------------------------------------------------------------------------
import { isPro } from "./usage.js";

const WORD_RE = /^[\p{L}\p{M}0-9][\p{L}\p{M}0-9 '’.,!?()\/&-]{0,59}$/u;
const LANG_RE = /^[a-z]{2,3}(-[A-Za-z]{2,4})?$/;

let poolReady = false;
async function ensurePool(env) {
  if (poolReady) return;
  await env.TR_DB.batch([
    env.TR_DB.prepare(
      "CREATE TABLE IF NOT EXISTS example_pool (" +
        "k TEXT NOT NULL, text TEXT NOT NULL, provider TEXT NOT NULL DEFAULT '', created INTEGER NOT NULL, " +
        "PRIMARY KEY (k, text))"
    ),
    env.TR_DB.prepare("CREATE INDEX IF NOT EXISTS example_pool_k ON example_pool (k, created)"),
  ]);
  poolReady = true;
}

const norm = (s) => String(s || "").trim().toLowerCase().replace(/\s+/g, " ");

function poolMax(env) {
  const v = Number(env.EXAMPLE_POOL_MAX);
  return Number.isFinite(v) && v > 0 ? Math.min(Math.floor(v), 30) : 8;
}

function jsonResp(data, status, cors) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...cors },
  });
}

/** helpers = توابعِ index.js (برای اینکه کدِ پرووایدرها دو جا کپی نشود) */
export async function handleWordExample(request, env, ctx, cors, session, helpers) {
  if (request.method !== "POST") return jsonResp({ error: "method not allowed" }, 405, cors);
  if (!(await isPro(env, session.sub, session.em))) {
    return jsonResp({ error: "Pro required", code: "pro_required" }, 403, cors);
  }
  if (!env.TR_DB) return jsonResp({ error: "store unavailable", code: "not_ready" }, 503, cors);

  let body;
  try { body = await request.json(); } catch { return jsonResp({ error: "Invalid JSON body" }, 400, cors); }
  const word = String(body?.word || "").trim();
  const lang = String(body?.lang || "").trim();
  if (!WORD_RE.test(word) || !LANG_RE.test(lang)) return jsonResp({ error: "bad word or lang" }, 400, cors);
  const have = (Array.isArray(body?.have) ? body.have : [])
    .slice(0, 30)
    .map((t) => norm(String(t || "").slice(0, 400)));
  const haveSet = new Set(have);
  const k = `${lang}|${norm(word)}`;

  try {
    await ensurePool(env);
    const { results } = await env.TR_DB.prepare(
      "SELECT text FROM example_pool WHERE k = ?1 ORDER BY created LIMIT 40"
    ).bind(k).all();
    const pool = (results || []).map((r) => r.text);

    // ۱) مثالی که این کاربر هنوز ندیده → از جدول (بدونِ AI، بدونِ هزینه)
    const unseen = pool.filter((t) => !haveSet.has(norm(t)));
    if (unseen.length) {
      const text = unseen[Math.floor(Math.random() * unseen.length)];
      return jsonResp({ text, source: "pool", total: pool.length }, 200, cors);
    }

    // ۲) همه را دیده/ندارد و جدول هنوز پر نشده → AI یک مثالِ تازه می‌سازد و ذخیره می‌کند
    const max = poolMax(env);
    if (pool.length >= max) return jsonResp({ exhausted: true, total: pool.length }, 200, cors);

    const meaning = String(body?.meaning || "").slice(0, 120);
    const nativeLabel = String(body?.nativeLabel || "").slice(0, 40);
    const used = [...new Set([...pool, ...(Array.isArray(body?.have) ? body.have.slice(0, 30).map(String) : [])])];
    const prompt = helpers.buildPrompt({ word, lang, meaning, nativeLabel, used });
    // ⚖️ سقفِ سراسریِ روزانه + همزمانیِ Pro. پر بود → فقط از استخر (مثالِ تازه ساخته نمی‌شود)
    let gate = { deny: null, release: async () => {} };
    if (helpers.beginAi) {
      gate = await helpers.beginAi("ai");
      if (gate.deny) {
        return gate.capped ? jsonResp({ exhausted: true, total: pool.length }, 200, cors) : gate.deny;
      }
    }
    const chain = helpers.getProviderChain(env);
    const errors = [];
    try {
    for (const provider of chain) {
      try {
        const raw = await helpers.withTimeout(helpers.callProvider(provider, prompt, 200, env), 12000, provider);
        let text = helpers.sanitizeAiText(raw).replace(/^["'«»“”\s]+|["'«»“”.\s]+$/g, "").trim();
        const bad = helpers.badAiOutputReason(text, prompt);
        if (bad) throw new Error(`unusable output (${bad})`);
        if (!text || text.includes("\n") || text.length > 300 || text.length < 8) throw new Error("not a single sentence");
        if (used.some((u) => norm(u) === norm(text))) throw new Error("duplicate");
        // درجِ اتمیک: فقط اگر هنوز زیرِ سقف است
        await env.TR_DB.prepare(
          "INSERT OR IGNORE INTO example_pool (k, text, provider, created) " +
            "SELECT ?1, ?2, ?3, ?4 WHERE (SELECT COUNT(*) FROM example_pool WHERE k = ?1) < ?5"
        ).bind(k, text, provider, Date.now(), max).run();
        ctx.waitUntil(helpers.recordUsage(env, request, { feature: "example", provider, cached: false, prompt, text }));
        return jsonResp({ text, source: "ai", total: Math.min(pool.length + 1, max) }, 200, cors);
      } catch (e) {
        errors.push(`${provider}: ${e.message}`);
      }
    }
    console.error("[AI-FAIL] /api/word-example:", errors.join(" | ").slice(0, 600));
    return jsonResp({ error: "generation failed", code: "ai_failed" }, 502, cors);
    } finally {
      await gate.release();
    }
  } catch (e) {
    console.error("word-example error", String(e));
    return jsonResp({ error: "word-example error", code: "not_ready" }, 503, cors);
  }
}
