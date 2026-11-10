// ---------------------------------------------------------------------------
// سهمیه‌ی «کل عمر» برای کاربرانِ رایگان + تشخیصِ کاربرِ Pro / VIP
//
// • هر بخش (feature) برای هر کاربر یک شمارنده‌ی دائمی در D1 دارد (جدول feature_usage) —
//   با پاک‌کردنِ اپ یا نصبِ دوباره ریست نمی‌شود، چون به user_id حساب گوگل وصل است.
// • وقتی شمارنده به سقف برسد: HTTP 402 + پیامِ فارسی.
// • Pro = (۱) ایمیل در VIP_EMAILS (wrangler.toml)  یا  (۲) ردیفِ plan='pro' در جدول entitlements.
//   Pro/VIP بدونِ محدودیت است.
//
// Vars اختیاری (wrangler.toml):
//   FREE_LIMIT            = "2"            سقفِ پیش‌فرضِ هر بخش
//   FREE_LIMIT_<FEATURE>  = "5"            سقفِ اختصاصیِ یک بخش (مثلاً FREE_LIMIT_STORY)
//   VIP_EMAILS            = "a@gmail.com, b@gmail.com"
// ---------------------------------------------------------------------------

/**
 * window = دقیقه. 0 → هر درخواست/شروع یک بار حساب می‌شود.
 * window > 0 → «یک نشست»: تا وقتی بینِ درخواست‌ها کمتر از این فاصله باشد، همان یک بار حساب می‌شود
 * (برای چت/تماس/زیرنویس که یک استفاده چندین درخواست دارد).
 */
export const FEATURES = {
  example:   { window: 0 },   // مثال‌ساز (AI)
  grammar:   { window: 0 },   // گرامر (AI)
  story:     { window: 0 },   // داستان‌ساز (AI)
  chat:      { window: 30 },  // چت (AI)
  videocall: { window: 30 },  // ویدیوکال AI
  live:      { window: 0 },   // ترجمه‌ی زنده (هر بار شروع)
  magnifier: { window: 0 },   // ذره‌بین (هر بار شروع)
  ytsub:     { window: 60 },  // ترجمه‌ی یوتیوب (نشست)
};

// مسیرهایی که خودشان مشخص می‌کنند کدام بخش‌اند (بدونِ هدر؛ برای بخشِ بومیِ اندروید)
const PATH_FEATURE = {
  "/api/youtube-captions": "ytsub",
  "/api/translate-subtitles": "ytsub",
  "/api/youtube-resolve": "ytsub",
};

const MSG_FA = "سقف استفاده‌ی رایگان از این بخش تمام شده. برای استفاده‌ی نامحدود، نسخه‌ی Pro را بخرید.";

function jsonResp(data, status, cors) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...cors },
  });
}

export function limitOf(env, feature) {
  for (const k of [`FREE_LIMIT_${feature.toUpperCase()}`, "FREE_LIMIT"]) {
    const v = Number(env[k]);
    if (Number.isFinite(v) && v >= 0 && env[k] !== undefined && env[k] !== "") return Math.floor(v);
  }
  return 2;
}

function limitResponse(feature, limit, cors) {
  return jsonResp({ error: MSG_FA, code: "free_limit", feature, limit }, 402, cors);
}

// ───────────── ایمیل / VIP ─────────────
export function normEmail(e) {
  const s = String(e || "").trim().toLowerCase();
  const at = s.lastIndexOf("@");
  if (at < 1) return s;
  const local = s.slice(0, at), dom = s.slice(at + 1);
  if (dom === "gmail.com" || dom === "googlemail.com") {
    // جیمیل نقطه و بعد از + را نادیده می‌گیرد
    return local.split("+")[0].replace(/\./g, "") + "@gmail.com";
  }
  return s;
}

function isVipEmail(env, email) {
  if (!email) return false;
  const want = normEmail(email);
  return String(env.VIP_EMAILS || "")
    .split(/[,\s;]+/)
    .map(normEmail)
    .filter(Boolean)
    .includes(want);
}

// ───────────── جدول‌ها ─────────────
let tablesReady = false;
async function ensureTables(env) {
  if (tablesReady) return;
  await env.TR_DB.batch([
    env.TR_DB.prepare(
      "CREATE TABLE IF NOT EXISTS feature_usage (" +
        "user_id TEXT NOT NULL, feature TEXT NOT NULL, n INTEGER NOT NULL DEFAULT 0, " +
        "last_at INTEGER NOT NULL DEFAULT 0, last_use TEXT NOT NULL DEFAULT '', " +
        "PRIMARY KEY (user_id, feature))"
    ),
    env.TR_DB.prepare(
      "CREATE TABLE IF NOT EXISTS entitlements (" +
        "user_id TEXT PRIMARY KEY, plan TEXT NOT NULL, pro_until INTEGER, " +
        "source TEXT, note TEXT, updated INTEGER NOT NULL DEFAULT 0)"
    ),
  ]);
  tablesReady = true;
}

// ───────────── Pro؟ ─────────────
const proCache = new Map(); // userId → {pro, t}
export async function isPro(env, userId, email) {
  if (isVipEmail(env, email)) return true;
  if (!env.TR_DB) return false;
  const hit = proCache.get(userId);
  if (hit && Date.now() - hit.t < 60000) return hit.pro;
  let pro = false;
  try {
    await ensureTables(env);
    const row = await env.TR_DB.prepare(
      "SELECT plan, pro_until FROM entitlements WHERE user_id = ?1"
    ).bind(userId).first();
    pro = !!row && row.plan === "pro" && (!row.pro_until || row.pro_until > Date.now());
  } catch (e) {
    console.log("isPro error", String(e));
  }
  proCache.set(userId, { pro, t: Date.now() });
  return pro;
}

// ───────────── مصرفِ یک بار ─────────────
/** {ok, used, limit}. اگر D1 خراب/نبود → ok (نباید کاربر را الکی قفل کند). */
export async function consume(env, userId, feature, useId) {
  const limit = limitOf(env, feature);
  if (!env.TR_DB) return { ok: true, used: 0, limit };
  try {
    await ensureTables(env);
    const now = Date.now();
    const win = (FEATURES[feature]?.window || 0) * 60000;
    const row = await env.TR_DB.prepare(
      "SELECT n, last_at, last_use FROM feature_usage WHERE user_id = ?1 AND feature = ?2"
    ).bind(userId, feature).first();

    if (row) {
      // تلاشِ دوباره‌ی همان درخواست (retry) دوباره حساب نمی‌شود
      if (useId && row.last_use === useId) return { ok: true, used: row.n, limit };
      // ادامه‌ی همان نشست
      if (win > 0 && row.n > 0 && now - row.last_at < win) {
        await env.TR_DB.prepare(
          "UPDATE feature_usage SET last_at = ?3 WHERE user_id = ?1 AND feature = ?2"
        ).bind(userId, feature, now).run();
        return { ok: true, used: row.n, limit };
      }
    }
    if (limit <= 0) return { ok: false, used: row ? row.n : 0, limit };

    // شمارش اتمیک: فقط اگر هنوز زیر سقف باشد زیاد می‌شود
    const r = await env.TR_DB.prepare(
      "INSERT INTO feature_usage (user_id, feature, n, last_at, last_use) VALUES (?1, ?2, 1, ?3, ?4) " +
        "ON CONFLICT(user_id, feature) DO UPDATE SET n = n + 1, last_at = ?3, last_use = ?4 WHERE n < ?5 " +
        "RETURNING n"
    ).bind(userId, feature, now, useId || "", limit).first();
    if (!r) return { ok: false, used: row ? row.n : limit, limit };
    return { ok: true, used: r.n, limit };
  } catch (e) {
    console.log("consume error", String(e));
    return { ok: true, used: 0, limit };
  }
}

export function featureOf(request, url) {
  const h = (request.headers.get("X-Feature") || "").trim().toLowerCase();
  if (h && FEATURES[h]) return h;
  return PATH_FEATURE[url.pathname] || null;
}

/** داخلِ authGate صدا زده می‌شود. null = اجازه، وگرنه Response 402. */
export async function featureGate(request, env, url, session, cors) {
  const feature = featureOf(request, url);
  if (!feature) return null;
  if (await isPro(env, session.sub, session.em)) return null;
  const useId = (request.headers.get("X-Use-Id") || "").slice(0, 64);
  const r = await consume(env, session.sub, feature, useId);
  return r.ok ? null : limitResponse(feature, r.limit, cors);
}

/**
 * GET  /api/usage → {pro, features:{x:{used,limit}}}
 * POST /api/use   → {feature, id?} — شروعِ یک استفاده (برای بخش‌هایی که درخواستِ AI ندارند: ذره‌بین، ترجمه‌ی زنده)
 * session = payload توکنِ نشست (از index.js).
 */
export async function handleUsage(request, env, url, cors, session) {
  const pro = await isPro(env, session.sub, session.em);

  if (url.pathname === "/api/usage" && request.method === "GET") {
    const features = {};
    for (const f of Object.keys(FEATURES)) features[f] = { used: 0, limit: limitOf(env, f) };
    if (env.TR_DB) {
      try {
        await ensureTables(env);
        const { results } = await env.TR_DB.prepare(
          "SELECT feature, n FROM feature_usage WHERE user_id = ?1"
        ).bind(session.sub).all();
        for (const r of results || []) if (features[r.feature]) features[r.feature].used = r.n;
      } catch (e) {
        console.log("usage error", String(e));
      }
    }
    return jsonResp({ pro, features }, 200, cors);
  }

  if (url.pathname === "/api/use" && request.method === "POST") {
    let body = {};
    try { body = await request.json(); } catch { /* خالی */ }
    const feature = String(body.feature || "").toLowerCase();
    if (!FEATURES[feature]) return jsonResp({ error: "unknown feature" }, 400, cors);
    if (pro) return jsonResp({ ok: true, pro: true }, 200, cors);
    const r = await consume(env, session.sub, feature, String(body.id || "").slice(0, 64));
    if (!r.ok) return limitResponse(feature, r.limit, cors);
    return jsonResp({ ok: true, used: r.used, limit: r.limit }, 200, cors);
  }

  return jsonResp({ error: "not found" }, 404, cors);
}
