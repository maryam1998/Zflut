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
//   DAILY_<FEATURE>       = "30"           سقفِ روزانه‌ی هر بخش — پیش‌فرض فقط برای کاربرِ رایگان
//   DAILY_APPLY_TO_PRO    = "1"            (اختیاری) سقفِ روزانه‌ی بالا برای Pro/VIP هم اعمال شود
//
// سیاستِ «کل عمر» (برای کاربرِ رایگان): جدول‌های feature_usage و feature_session کلیدشان
// (user_id, feature) است، بدونِ تاریخ ← یعنی FREE_LIMIT_VIDEOCALL = تعدادِ جلسه در «کل عمر».
// بعد از تمام‌شدنِ آن، جلسه‌ی تازه هیچ‌وقت مجاز نیست (۴۰۲)، چه ۳۰ دقیقه بگذرد چه یک ماه.
// سقفِ روزانه (feature_daily) جداست و کلیدش (user_id, feature, day) است.
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
  import:    { window: 0 },   // ایمپورتِ تبِ داستان‌ساز (PDF/عکس/SRT/لینک/متن) — هر بار شروع
};

// مسیرهایی که خودشان مشخص می‌کنند کدام بخش‌اند (بدونِ هدر؛ برای بخشِ بومیِ اندروید)
const PATH_FEATURE = {
  "/api/youtube-captions": "ytsub",
  "/api/translate-subtitles": "ytsub",
  "/api/youtube-resolve": "ytsub",
};

// 🆓 بخش‌هایی که سقفِ «کل عمر» ندارند (رایگانِ همیشگی)؛ فقط سقفِ روزانه‌ی سرور روشان اعمال می‌شود.
const LIFETIME_EXEMPT = new Set(["ytsub"]);

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

export function isVipEmail(env, email) {
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
  await env.TR_DB.batch([
    // 📅 سقفِ روزانه‌ی هر بخش — سمتِ سرور (identity, feature, day, count)
    env.TR_DB.prepare(
      "CREATE TABLE IF NOT EXISTS feature_daily (" +
        "user_id TEXT NOT NULL, feature TEXT NOT NULL, day TEXT NOT NULL, n INTEGER NOT NULL DEFAULT 0, " +
        "last_at INTEGER NOT NULL DEFAULT 0, last_use TEXT NOT NULL DEFAULT '', " +
        "PRIMARY KEY (user_id, feature, day))"
    ),
    // 🔁 شناسه‌ی «استفاده» (X-Use-Id) برای تشخیصِ retry — تعدادِ retryِ رایگان محدود و زمان‌دار است
    env.TR_DB.prepare(
      "CREATE TABLE IF NOT EXISTS use_log (k TEXT PRIMARY KEY, ph TEXT NOT NULL DEFAULT '', n INTEGER NOT NULL, t INTEGER NOT NULL)"
    ),
    // ⏱️ شروعِ نشستِ رایگانِ تماس (برای محدودیتِ طولِ جلسه)
    env.TR_DB.prepare(
      "CREATE TABLE IF NOT EXISTS feature_session (" +
        "user_id TEXT NOT NULL, feature TEXT NOT NULL, start_at INTEGER NOT NULL, " +
        "PRIMARY KEY (user_id, feature))"
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
    console.error("[FAIL-OPEN] isPro error", String(e));
  }
  proCache.set(userId, { pro, t: Date.now() });
  return pro;
}

// ───────────── retry (X-Use-Id) ─────────────
// قبلاً هر درخواستی که X-Use-Id آخرین استفاده را تکرار می‌کرد «retry» حساب می‌شد و بی‌نهایت رایگان بود
// (کافی بود با curl همیشه یک id ثابت بفرستند). حالا هر استفاده‌ی شمرده‌شده حداکثر RETRY_FREE_MAX
// تکرارِ رایگان، آن هم فقط تا RETRY_WINDOW_MS بعد از شمارش، دارد؛ بعدش دوباره شمرده می‌شود.
// 🔗 retry فقط وقتی رایگان است که «همان پرامپت» (هش) با همان X-Use-Id بیاید؛ پرامپتِ متفاوت با id تکراری
// یک استفاده‌ی جدید است و شمرده می‌شود. (جوابِ retry هم از کشِ مشترکِ پرامپت در D1 می‌آید، نه AI.)
// (کلاینتِ اپ حداکثر ۲ بار تلاشِ دوباره می‌زند و هر تلاش چند ثانیه فاصله دارد.)
const RETRY_FREE_MAX = 2;
const RETRY_WINDOW_MS = 300000;

function useKey(scope, userId, feature, useId) {
  return `${scope}|${userId}|${feature}|${useId}`;
}

/** true = این درخواست retryِ یک استفاده‌ی قبلاً شمرده‌شده است (اتمیک؛ شمارنده‌ی retry را زیاد می‌کند). */
async function isFreeRetry(env, scope, userId, feature, useId, ph, now) {
  if (!useId) return false;
  const r = await env.TR_DB.prepare(
    "UPDATE use_log SET n = n + 1 WHERE k = ?1 AND ph = ?2 AND t > ?3 AND n <= ?4 RETURNING n"
  ).bind(useKey(scope, userId, feature, useId), ph || "", now - RETRY_WINDOW_MS, RETRY_FREE_MAX).first();
  return !!r;
}

/** بعد از هر «شمارشِ واقعی» صدا زده می‌شود تا retryهای بعدیِ همین id رایگان باشند (محدود). */
async function markUse(env, scope, userId, feature, useId, ph, now) {
  if (!useId) return;
  await env.TR_DB.prepare(
    "INSERT INTO use_log (k, ph, n, t) VALUES (?1, ?2, 1, ?3) ON CONFLICT(k) DO UPDATE SET ph = ?2, n = 1, t = ?3"
  ).bind(useKey(scope, userId, feature, useId), ph || "", now).run();
  if (Math.random() < 0.01) {
    await env.TR_DB.prepare("DELETE FROM use_log WHERE t < ?1").bind(now - 3600000).run();
  }
}

// ───────────── مصرفِ یک بار ─────────────
/** {ok, used, limit}. اگر D1 خراب/نبود → ok (نباید کاربر را الکی قفل کند). */
export async function consume(env, userId, feature, useId, ph = "") {
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
      if (useId && (await isFreeRetry(env, "life", userId, feature, useId, ph, now))) {
        return { ok: true, used: row.n, limit, fresh: false };
      }
      // ادامه‌ی همان نشست
      if (win > 0 && row.n > 0 && now - row.last_at < win) {
        await env.TR_DB.prepare(
          "UPDATE feature_usage SET last_at = ?3 WHERE user_id = ?1 AND feature = ?2"
        ).bind(userId, feature, now).run();
        return { ok: true, used: row.n, limit, fresh: false };
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
    await markUse(env, "life", userId, feature, useId, ph, now);
    return { ok: true, used: r.n, limit, fresh: true };
  } catch (e) {
    console.error("[FAIL-OPEN] consume error — سقفِ کل‌عمر بی‌صدا خاموش شد", String(e));
    return { ok: true, used: 0, limit };
  }
}

// فقط این بخش‌ها اجازه دارند با هدرِ X-Feature روی /api/generate بیایند (همه‌ی بخش‌های AI یک مسیر دارند،
// پس تشخیصِ بخش از روی مسیر ممکن نیست). بقیه (ytsub، live، magnifier) هرگز از هدر پذیرفته نمی‌شوند.
const HEADER_FEATURES = {
  "/api/generate": new Set(["example", "grammar", "story", "chat", "videocall"]),
};

/**
 * بخشِ یک درخواست. مسیر حاکم است:
 *  - مسیری که در PATH_FEATURE هست → همان بخش (هدر نادیده گرفته می‌شود)
 *  - مسیری که در HEADER_FEATURES هست → هدر فقط اگر جزو بخش‌های مجازِ همان مسیر باشد
 *  - هر مسیرِ دیگر → null (شمرده نمی‌شود)
 * این‌طور کاربرِ رایگان نمی‌تواند با X-Feature: ytsub (که سقفِ کل‌عمر ندارد) روی /api/generate
 * سقفِ مثال/گرامر/چت را دور بزند، و هدرِ اشتباه روی مسیرِ یوتیوب شمارنده‌ی بخشِ دیگر را مصرف نمی‌کند.
 */
export function featureOf(request, url) {
  const byPath = PATH_FEATURE[url.pathname];
  if (byPath) return byPath;
  const allowed = HEADER_FEATURES[url.pathname];
  if (!allowed) return null;
  const h = (request.headers.get("X-Feature") || "").trim().toLowerCase();
  return allowed.has(h) ? h : null;
}

/** سقفِ روزانه‌ی یک بخش. DAILY_<FEATURE> در wrangler.toml؛ نبود/۰ = بدونِ سقف. */
export function dailyLimitOf(env, feature) {
  const v = Number(env[`DAILY_${feature.toUpperCase()}`]);
  return Number.isFinite(v) && v > 0 ? Math.floor(v) : 0;
}

/** {ok, used, limit}. هر «استفاده‌ی جدید» یک بار حساب می‌شود (retry و ادامه‌ی نشست حساب نمی‌شود). سمتِ سرور و اتمیک. */
export async function consumeDaily(env, userId, feature, useId, ph = "", limitOverride = 0) {
  const limit = limitOverride > 0 ? limitOverride : dailyLimitOf(env, feature);
  if (!limit || !env.TR_DB) return { ok: true, used: 0, limit };
  try {
    await ensureTables(env);
    const now = Date.now();
    const day = new Date(now).toISOString().slice(0, 10);
    const win = (FEATURES[feature]?.window || 0) * 60000;
    const row = await env.TR_DB.prepare(
      "SELECT n, last_at, last_use FROM feature_daily WHERE user_id = ?1 AND feature = ?2 AND day = ?3"
    ).bind(userId, feature, day).first();
    if (row) {
      if (useId && (await isFreeRetry(env, "day", userId, feature, useId, ph, now))) {
        return { ok: true, used: row.n, limit };
      }
      if (win > 0 && row.n > 0 && now - row.last_at < win) {
        await env.TR_DB.prepare(
          "UPDATE feature_daily SET last_at = ?4 WHERE user_id = ?1 AND feature = ?2 AND day = ?3"
        ).bind(userId, feature, day, now).run();
        return { ok: true, used: row.n, limit };
      }
    }
    const r = await env.TR_DB.prepare(
      "INSERT INTO feature_daily (user_id, feature, day, n, last_at, last_use) VALUES (?1, ?2, ?3, 1, ?4, ?5) " +
        "ON CONFLICT(user_id, feature, day) DO UPDATE SET n = n + 1, last_at = ?4, last_use = ?5 WHERE n < ?6 " +
        "RETURNING n"
    ).bind(userId, feature, day, now, useId || "", limit).first();
    if (!r) return { ok: false, used: row ? row.n : limit, limit };
    await markUse(env, "day", userId, feature, useId, ph, now);
    if (Math.random() < 0.01) {
      const old = new Date(now - 7 * 86400000).toISOString().slice(0, 10);
      await env.TR_DB.prepare("DELETE FROM feature_daily WHERE day < ?1").bind(old).run();
    }
    return { ok: true, used: r.n, limit };
  } catch (e) {
    console.error("[FAIL-OPEN] consumeDaily error — سقفِ روزانه بی‌صدا خاموش شد", String(e));
    return { ok: true, used: 0, limit };
  }
}

/** سقفِ روزانه‌ی اختصاصیِ Pro/VIP برای یک بخش. PRO_DAILY_<FEATURE> در wrangler.toml؛ نبود/۰ = بدونِ سقف. */
export function proDailyLimitOf(env, feature) {
  const v = Number(env[`PRO_DAILY_${feature.toUpperCase()}`]);
  return Number.isFinite(v) && v > 0 ? Math.floor(v) : 0;
}

/**
 * پیش‌فرض: سقفِ روزانه‌ی هر بخش فقط برای کاربرِ رایگان است؛ Pro/VIP فقط سقفِ کلیِ روزانه‌ی auth.js
 * (LIMIT_AI / LIMIT_TTS / LIMIT_MISC) را دارند. با DAILY_APPLY_TO_PRO="1" به Pro/VIP هم اعمال می‌شود.
 */
function dailyAppliesToPro(env) {
  return ["1", "true", "on", "yes"].includes(String(env.DAILY_APPLY_TO_PRO || "").trim().toLowerCase());
}

/**
 * 🌐 سقفِ روزانه برای «درخواست‌های بدونِ بخش» (ترجمه و هر درخواستِ /api/generate بدونِ X-Feature معتبر)
 * و /api/translate-text. فقط وقتی صدا زده می‌شود که کش (D1) جواب نداشته و واقعاً به AI می‌رود؛
 * پس ترجمه‌های کش‌شده هیچ سهمیه‌ای مصرف نمی‌کنند. برای همه‌ی کاربران (رایگان/Pro/VIP).
 * DAILY_TRANSLATE در wrangler.toml؛ نبود/۰ = بدونِ سقف. null = اجازه، وگرنه Response ۴۲۹.
 */
export async function aiMissGate(env, userId, cors) {
  const d = await consumeDaily(env, userId, "translate", "");
  if (d.ok) return null;
  console.warn(`[LIMIT] daily_feature_limit user=${userId} feature=translate limit=${d.limit}`);
  return dailyResponse("translate", d.limit, cors);
}

function dailyResponse(feature, limit, cors) {
  return jsonResp({ error: "daily limit reached, try again tomorrow", code: "daily_feature_limit", feature, limit }, 429, cors);
}

// ⏱️ طولِ جلسه‌ی رایگانِ تماس (ثانیه). FREE_CALL_SECONDS در wrangler.toml؛ ۰/نبود = بدونِ محدودیتِ طول.
const SESSION_LIMITED = new Set(["videocall"]);
function freeSessionSeconds(env) {
  const v = Number(env.FREE_CALL_SECONDS);
  return Number.isFinite(v) && v > 0 ? Math.floor(v) : 0;
}

/** برای کاربرِ رایگان: true = هنوز در سقفِ زمانیِ جلسه. fresh=true یعنی جلسه‌ی تازه شروع شده. */
async function sessionTimeOk(env, userId, feature, fresh) {
  const secs = freeSessionSeconds(env);
  if (!secs || !SESSION_LIMITED.has(feature) || !env.TR_DB) return true;
  try {
    await ensureTables(env);
    const now = Date.now();
    if (fresh) {
      await env.TR_DB.prepare(
        "INSERT INTO feature_session (user_id, feature, start_at) VALUES (?1, ?2, ?3) " +
          "ON CONFLICT(user_id, feature) DO UPDATE SET start_at = ?3"
      ).bind(userId, feature, now).run();
      return true;
    }
    const row = await env.TR_DB.prepare(
      "SELECT start_at FROM feature_session WHERE user_id = ?1 AND feature = ?2"
    ).bind(userId, feature).first();
    if (!row) return true;
    return now - row.start_at <= secs * 1000;
  } catch (e) {
    console.error("[FAIL-OPEN] sessionTimeOk error — سقفِ طولِ جلسه خاموش شد", String(e));
    return true;
  }
}

/** هشِ (prompt + maxTokens) بدنه‌ی /api/generate؛ اگر بدنه خراب بود "" (بدونِ اینکه بدنه‌ی اصلی مصرف شود). */
async function promptHash(request) {
  try {
    const b = await request.clone().json();
    const data = new TextEncoder().encode(JSON.stringify([String(b?.prompt ?? ""), Number(b?.maxTokens) || 0]));
    const dg = new Uint8Array(await crypto.subtle.digest("SHA-256", data));
    return [...dg.slice(0, 12)].map((x) => x.toString(16).padStart(2, "0")).join("");
  } catch {
    return "";
  }
}

/** داخلِ authGate صدا زده می‌شود. null = اجازه، وگرنه Response (402 رایگان / 429 سقفِ روزانه). */
export async function featureGate(request, env, url, session, cors) {
  const feature = featureOf(request, url);
  if (!feature) return null;
  const useId = (request.headers.get("X-Use-Id") || "").slice(0, 64);
  // 🔗 هشِ پرامپت (فقط برای /api/generate): retry باید «همان پرامپت» باشد
  let ph = "";
  if (useId && url.pathname === "/api/generate") {
    const len = Number(request.headers.get("Content-Length") || 0);
    if (len > 250000) {
      return jsonResp({ error: "prompt too long", code: "prompt_too_long" }, 413, cors);
    }
    ph = await promptHash(request);
  }
  const pro = await isPro(env, session.sub, session.em);

  if (!pro && !LIFETIME_EXEMPT.has(feature)) {
    // سقفِ «کل عمر» + سقفِ طولِ جلسه (رایگان)
    const r = await consume(env, session.sub, feature, useId, ph);
    if (!r.ok) {
      console.warn(`[LIMIT] free_limit user=${session.sub} feature=${feature} limit=${r.limit} used=${r.used}`);
      return limitResponse(feature, r.limit, cors);
    }
    if (!(await sessionTimeOk(env, session.sub, feature, r.fresh === true))) {
      console.warn(`[LIMIT] free_session_over user=${session.sub} feature=${feature}`);
      return jsonResp({ error: MSG_FA, code: "free_session_over", feature }, 402, cors);
    }
  }
  // 📅 سقفِ روزانه‌ی هر بخش — سمتِ سرور؛ پیش‌فرض فقط رایگان (Pro/VIP فقط با DAILY_APPLY_TO_PRO)
  if (!pro || dailyAppliesToPro(env)) {
    const d = await consumeDaily(env, session.sub, feature, useId, ph);
    if (!d.ok) {
      console.warn(`[LIMIT] daily_feature_limit user=${session.sub} feature=${feature} limit=${d.limit}`);
      return dailyResponse(feature, d.limit, cors);
    }
  } else {
    // 💎 سقفِ روزانه‌ی اختصاصیِ Pro/VIP (فقط بخش‌هایی که PRO_DAILY_<FEATURE> دارند، مثلاً PRO_DAILY_STORY)
    const pl = proDailyLimitOf(env, feature);
    if (pl > 0) {
      const d = await consumeDaily(env, session.sub, feature, useId, ph, pl);
      if (!d.ok) {
        console.warn(`[LIMIT] pro_daily_feature_limit user=${session.sub} feature=${feature} limit=${d.limit}`);
        return dailyResponse(feature, d.limit, cors);
      }
    }
  }
  return null;
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
    const bid = String(body.id || "").slice(0, 64);
    if (!pro || dailyAppliesToPro(env)) {
      const dd = await consumeDaily(env, session.sub, feature, bid);
      if (!dd.ok) return dailyResponse(feature, dd.limit, cors);
    }
    if (pro) return jsonResp({ ok: true, pro: true }, 200, cors);
    const r = await consume(env, session.sub, feature, bid);
    if (!r.ok) return limitResponse(feature, r.limit, cors);
    return jsonResp({ ok: true, used: r.used, limit: r.limit }, 200, cors);
  }

  return jsonResp({ error: "not found" }, 404, cors);
}
