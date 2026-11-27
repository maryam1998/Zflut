// ---------------------------------------------------------------------------
// ⚖️ مدیریتِ بار (الهام از DeepSeek؛ با سقف‌های عددی چون GPU نداریم و API شخص ثالث صدا می‌زنیم)
//
// ۱) محدودیتِ همزمانی (فقط Pro/VIP):
//    هر کاربر حداکثر PRO_MAX_CONCURRENT درخواستِ AI «هم‌زمان در حالِ پردازش» دارد (پیش‌فرض ۲).
//    بیشتر که شد درخواست در «صفِ FIFO» می‌ماند (رد نمی‌شود)؛ اگر صف از PRO_QUEUE_MAX (پیش‌فرض ۱۰)
//    بیشتر شود یا بیش از PRO_QUEUE_WAIT_MS (پیش‌فرض ۶۰ ثانیه) منتظر بماند → ۴۲۹ «الان شلوغه…».
//    چون Worker حافظه‌ی مشترک ندارد، «جای پارک»ها (lease) و صف در D1 نگه‌داری می‌شوند.
//
// ۲) سقفِ سراسریِ روزانه (همه‌ی کاربران، حتی Pro):
//    جدول global_daily(day, ai_count, whisper_count). فقط درخواستِ‌هایی که واقعاً به AI/Whisper
//    می‌رسند (کش‌نخورده‌ها) شمرده می‌شوند؛ جواب از کش/استخر هیچ سهمیه‌ای مصرف نمی‌کند.
//    پر شد → ۴۲۹ (code=daily_limit تا اپ همان لحظه پیامِ «سقفِ امروز تمام شد» را نشان بدهد).
//
// Vars اختیاری (wrangler.toml) — ۰ = خاموش:
//   PRO_MAX_CONCURRENT = "2"      PRO_QUEUE_MAX = "10"      PRO_QUEUE_WAIT_MS = "60000"
//   GLOBAL_DAILY_AI = "5000"      GLOBAL_DAILY_WHISPER = "3000"
//
// اگر D1 خراب/نبود، هر دو سقف بی‌صدا خاموش می‌شوند (کاربر الکی قفل نشود).
// ---------------------------------------------------------------------------
import { verifySessionToken } from "./auth.js";
import { isPro, isVipEmail, featureOf } from "./usage.js";

const MSG_BUSY = "الان شلوغه، چند لحظه دیگه (try again in 5s)";
// پیامِ سقفِ per-user عمداً مثلِ خطای موقتِ AI است (نه «سقف/محدودیت»)؛ اپ ۵xx را «AI جواب نمی‌دهد» نشان می‌دهد.
const MSG_UNAVAILABLE = "AI service is temporarily unavailable. Please try again in a few minutes.";
const MSG_CAP = "ظرفیتِ هوش مصنوعیِ امروز تکمیل شده؛ فردا دوباره امتحان کن.";
const MSG_CAP_FREE = "ظرفیتِ رایگانِ هوش مصنوعیِ امروز تکمیل شده؛ ترجمه‌ی دستگاه و کشِ مشترک فعال می‌ماند.";

function intVar(env, key, dflt) {
  const raw = env[key];
  if (raw === undefined || raw === null || String(raw).trim() === "") return dflt;
  const v = Number(raw);
  return Number.isFinite(v) && v >= 0 ? Math.floor(v) : dflt;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const noop = async () => {};

function jsonResp(data, status, cors, extra = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...extra, ...cors },
  });
}

// ───────────── جدول‌ها ─────────────
let ready = false;
async function ensure(env) {
  if (ready) return;
  await env.TR_DB.batch([
    env.TR_DB.prepare(
      "CREATE TABLE IF NOT EXISTS global_daily (" +
        "day TEXT PRIMARY KEY, ai_count INTEGER NOT NULL DEFAULT 0, whisper_count INTEGER NOT NULL DEFAULT 0)"
    ),
    env.TR_DB.prepare(
      "CREATE TABLE IF NOT EXISTS ai_slot (id TEXT PRIMARY KEY, user_id TEXT NOT NULL, exp INTEGER NOT NULL)"
    ),
    env.TR_DB.prepare("CREATE INDEX IF NOT EXISTS ai_slot_user ON ai_slot (user_id, exp)"),
    env.TR_DB.prepare(
      "CREATE TABLE IF NOT EXISTS ai_queue (" +
        "ticket INTEGER PRIMARY KEY AUTOINCREMENT, user_id TEXT NOT NULL, t INTEGER NOT NULL)"
    ),
    env.TR_DB.prepare("CREATE INDEX IF NOT EXISTS ai_queue_user ON ai_queue (user_id, ticket)"),
  ]);
  ready = true;
}

// ───────────── ۱.۵) سقفِ روزانه‌ی هر کاربر (per-user) ─────────────
// USER_DAILY_AI (رایگان) و PRO_USER_DAILY_AI (Pro/VIP) = حداکثرِ درخواست‌هایی که در روزِ UTC واقعاً به AI می‌رسند.
// ۰/نبود = خاموش. پر شد → 503 با پیامِ «AI موقتاً در دسترس نیست» (نه 429/402) تا کاربر سقف را نبیند.
// بدونِ نشست (AUTH_MODE≠on) هویتی نیست → اعمال نمی‌شود. D1 خراب → اجازه.
let userCapReady = false;
async function takeUser(env, userId, pro) {
  const cap = intVar(env, pro ? "PRO_USER_DAILY_AI" : "USER_DAILY_AI", 0);
  if (!cap || !env.TR_DB || !userId) return { ok: true };
  try {
    if (!userCapReady) {
      await env.TR_DB.prepare(
        "CREATE TABLE IF NOT EXISTS user_ai_daily (user_id TEXT NOT NULL, day TEXT NOT NULL, n INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (user_id, day))"
      ).run();
      userCapReady = true;
    }
    const day = new Date().toISOString().slice(0, 10);
    const r = await env.TR_DB.prepare(
      "INSERT INTO user_ai_daily (user_id, day, n) VALUES (?1, ?2, 1) " +
        "ON CONFLICT(user_id, day) DO UPDATE SET n = n + 1 WHERE n < ?3 RETURNING n"
    ).bind(userId, day, cap).first();
    if (!r) {
      console.warn(`[LIMIT] user_daily_ai user=${userId} cap=${cap} pro=${pro}`);
      return { ok: false };
    }
    if (Math.random() < 0.01) {
      const old = new Date(Date.now() - 7 * 86400000).toISOString().slice(0, 10);
      await env.TR_DB.prepare("DELETE FROM user_ai_daily WHERE day < ?1").bind(old).run();
    }
    return { ok: true };
  } catch (e) {
    console.error("[FAIL-OPEN] user daily cap error", String(e));
    return { ok: true };
  }
}

// ───────────── ۱.۶) امتیازِ ماهانه‌ی هر کاربر (Credits) — فقط سمتِ سرور، نامرئی برای کاربر ─────────────
// PRO_MONTHLY_CREDITS (پیش‌فرض ۹۰۰۰) / FREE_MONTHLY_CREDITS (پیش‌فرض ۰ = خاموش). ۰ = بدونِ سقف.
// هزینه‌ی هر درخواستِ «واقعاً AI» (کش‌ها هیچ‌وقت شمرده نمی‌شوند): ترجمه ۱، ویدیوکال ۲، داستان ۱۰ (قابلِ تغییر با CREDIT_COSTS).
// کاربر هیچ نشانگر/پیامی نمی‌بیند. وقتی امتیازِ ماهانه تمام شد:
//   • ترجمه (silent:"translate") → ۴۲۹ با کدِ «ai_busy»؛ اپ بی‌صدا چند دقیقه مکث می‌کند و با ML Kit/کش ادامه می‌دهد.
//   • چت / ویدیوکال / داستان / گرامر / مثال / زیرنویس → «خطا نمی‌دهد»: beginAi مقدارِ degraded:true برمی‌گرداند و
//     صدازننده فقط از زنجیره‌ی «مدل‌های رایگان» (AI_PROVIDER_FREE) جواب می‌سازد. این درخواست‌ها هزینه‌ای ندارند، پس
//     از سقفِ سراسریِ AI (که برای هزینه‌ی DeepSeek است) هم کم نمی‌شوند و در کشِ مشترک نوشته نمی‌شوند.
// ادمین: ردیفِ user_credits (capped_at) و بخشِ «رسیده به سقفِ امتیاز» در /admin/usage-report.
const DEFAULT_COSTS = { story: 10, videocall: 2, ytsub: 3, grammar: 2, chat: 1, example: 1, translate: 1 };
function creditCostOf(env, feature, override) {
  if (Number.isFinite(override) && override > 0) return Math.floor(override);
  let map = DEFAULT_COSTS;
  if (env.CREDIT_COSTS) {
    try { map = { ...DEFAULT_COSTS, ...JSON.parse(env.CREDIT_COSTS) }; } catch { /* پیش‌فرض */ }
  }
  return Math.max(1, Math.floor(Number(map[feature]) || 1));
}

let creditsReady = false;
async function ensureCredits(env) {
  if (creditsReady) return;
  await env.TR_DB.batch([
    env.TR_DB.prepare(
      "CREATE TABLE IF NOT EXISTS user_credits (user_id TEXT NOT NULL, month TEXT NOT NULL, used INTEGER NOT NULL DEFAULT 0, " +
        "capped_at INTEGER, PRIMARY KEY (user_id, month))"
    ),
    // 📒 دفترِ ریز مصرف (فقط برای پنلِ ادمین): هر کاربر × ماه × قابلیت
    //   credits = امتیازِ مصرف‌شده، calls = تعدادِ درخواستِ پولی، free_calls = درخواست‌هایی که بعد از سقف با مدل‌های رایگان جواب گرفتند
    env.TR_DB.prepare(
      "CREATE TABLE IF NOT EXISTS user_credit_features (user_id TEXT NOT NULL, month TEXT NOT NULL, feature TEXT NOT NULL, " +
        "credits INTEGER NOT NULL DEFAULT 0, calls INTEGER NOT NULL DEFAULT 0, free_calls INTEGER NOT NULL DEFAULT 0, " +
        "PRIMARY KEY (user_id, month, feature))"
    ),
  ]);
  creditsReady = true;
}

/** {ok:true, used} = امتیاز کم شد؛ {ok:false} = سقفِ ماهانه پر است (کاربر نباید چیزی بفهمد؛ بالادست به مدلِ رایگان می‌رود). */
async function takeCredits(env, userId, pro, cost, feature) {
  const cap = intVar(env, pro ? "PRO_MONTHLY_CREDITS" : "FREE_MONTHLY_CREDITS", pro ? 9000 : 0);
  if (!cap || !env.TR_DB || !userId) return { ok: true };
  try {
    await ensureCredits(env);
    const month = new Date().toISOString().slice(0, 7);
    const r = await env.TR_DB.prepare(
      "INSERT INTO user_credits (user_id, month, used) VALUES (?1, ?2, ?3) " +
        "ON CONFLICT(user_id, month) DO UPDATE SET used = used + ?3 WHERE used + ?3 <= ?4 RETURNING used"
    ).bind(userId, month, cost, cap).first();
    if (!r) {
      await env.TR_DB.batch([
        env.TR_DB.prepare(
          "UPDATE user_credits SET capped_at = COALESCE(capped_at, ?3) WHERE user_id = ?1 AND month = ?2"
        ).bind(userId, month, Date.now()),
        env.TR_DB.prepare(
          "INSERT INTO user_credit_features (user_id, month, feature, free_calls) VALUES (?1, ?2, ?3, 1) " +
            "ON CONFLICT(user_id, month, feature) DO UPDATE SET free_calls = free_calls + 1"
        ).bind(userId, month, feature || "other"),
      ]);
      console.warn(`[CAP] credits user=${userId} month=${month} cap=${cap} pro=${pro} feature=${feature}`);
      return { ok: false };
    }
    await env.TR_DB.prepare(
      "INSERT INTO user_credit_features (user_id, month, feature, credits, calls) VALUES (?1, ?2, ?3, ?4, 1) " +
        "ON CONFLICT(user_id, month, feature) DO UPDATE SET credits = credits + ?4, calls = calls + 1"
    ).bind(userId, month, feature || "other", cost).run();
    if (Math.random() < 0.005) {
      const old = new Date(Date.now() - 100 * 86400000).toISOString().slice(0, 7);
      await env.TR_DB.batch([
        env.TR_DB.prepare("DELETE FROM user_credits WHERE month < ?1").bind(old),
        env.TR_DB.prepare("DELETE FROM user_credit_features WHERE month < ?1").bind(old),
      ]);
    }
    return { ok: true, used: r.used };
  } catch (e) {
    console.error("[FAIL-OPEN] credits error", String(e));
    return { ok: true };
  }
}

// ───────────── ۱) همزمانی + صفِ FIFO ─────────────
const QUEUE_ALIVE_MS = 10000; // هر منتظر هر ~۴۰۰ms «زنده بودنش» را تازه می‌کند؛ ردیفِ مرده بعد از این حذف می‌شود
const POLL_MS = 400;
const LEASE_MS = 150000; // اگر release نشد (کرش)، جای پارک بعد از این خودش آزاد می‌شود

/** {ok:true, release} یا {ok:false, busy:true}. D1 خراب → ok (بدونِ محدودیت). */
async function acquireSlot(env, userId) {
  const max = intVar(env, "PRO_MAX_CONCURRENT", 2);
  if (!max || !env.TR_DB) return { ok: true, release: noop };
  const qMax = intVar(env, "PRO_QUEUE_MAX", 10);
  const maxWait = intVar(env, "PRO_QUEUE_WAIT_MS", 60000);
  const id = crypto.randomUUID();
  let ticket = null;

  const release = async () => {
    try {
      await env.TR_DB.prepare("DELETE FROM ai_slot WHERE id = ?1").bind(id).run();
    } catch { /* lease خودش منقضی می‌شود */ }
  };
  const dropTicket = async () => {
    if (ticket == null) return;
    try {
      await env.TR_DB.prepare("DELETE FROM ai_queue WHERE ticket = ?1").bind(ticket).run();
    } catch { /* ردیفِ مرده خودش حذف می‌شود */ }
  };
  // اتمیک: فقط اگر هنوز جای پارکِ خالی هست
  const tryTake = async () => {
    const now = Date.now();
    const r = await env.TR_DB.prepare(
      "INSERT INTO ai_slot (id, user_id, exp) SELECT ?1, ?2, ?3 " +
        "WHERE (SELECT COUNT(*) FROM ai_slot WHERE user_id = ?2 AND exp > ?4) < ?5 RETURNING id"
    ).bind(id, userId, now + LEASE_MS, now, max).first();
    return !!r;
  };

  try {
    await ensure(env);
    if (Math.random() < 0.02) {
      const now = Date.now();
      await env.TR_DB.batch([
        env.TR_DB.prepare("DELETE FROM ai_slot WHERE exp < ?1").bind(now),
        env.TR_DB.prepare("DELETE FROM ai_queue WHERE t < ?1").bind(now - 60000),
      ]);
    }

    // مسیرِ سریع: صف خالی است و جای پارک هست
    const w = await env.TR_DB.prepare(
      "SELECT COUNT(*) AS c FROM ai_queue WHERE user_id = ?1 AND t > ?2"
    ).bind(userId, Date.now() - QUEUE_ALIVE_MS).first();
    if (!(w && w.c > 0) && (await tryTake())) return { ok: true, release };

    // صف (اتمیک: اگر از سقفِ صف بیشتر شود ردیفی درج نمی‌شود → «شلوغه»)
    const q = await env.TR_DB.prepare(
      "INSERT INTO ai_queue (user_id, t) SELECT ?1, ?2 " +
        "WHERE (SELECT COUNT(*) FROM ai_queue WHERE user_id = ?1 AND t > ?3) < ?4 RETURNING ticket"
    ).bind(userId, Date.now(), Date.now() - QUEUE_ALIVE_MS, qMax).first();
    if (!q) return { ok: false, busy: true };
    ticket = q.ticket;

    const deadline = Date.now() + maxWait;
    while (Date.now() < deadline) {
      await sleep(POLL_MS);
      const now = Date.now();
      await env.TR_DB.prepare("UPDATE ai_queue SET t = ?2 WHERE ticket = ?1").bind(ticket, now).run();
      const head = await env.TR_DB.prepare(
        "SELECT MIN(ticket) AS h FROM ai_queue WHERE user_id = ?1 AND t > ?2"
      ).bind(userId, now - QUEUE_ALIVE_MS).first();
      // FIFO: فقط اولین نفرِ صف اجازه‌ی گرفتنِ جای پارک دارد
      if (head && head.h === ticket && (await tryTake())) {
        await dropTicket();
        return { ok: true, release };
      }
    }
    await dropTicket();
    return { ok: false, busy: true };
  } catch (e) {
    console.error("[FAIL-OPEN] concurrency limit error — محدودیتِ همزمانی بی‌صدا خاموش شد", String(e));
    await dropTicket();
    await release();
    return { ok: true, release: noop };
  }
}

// ───────────── ۲) سقفِ سراسریِ روزانه (افتِ تدریجی + سهمِ رزروِ Pro) ─────────────
// GLOBAL_DAILY_AI = سقفِ کل. PRO_RESERVE_PCT (پیش‌فرض ۲۰) درصدی از سقف که فقط Pro/VIP می‌تواند مصرف کند:
//   رایگان‌ها فقط تا (۱۰۰ − PRO_RESERVE_PCT)٪ سقف، Pro تا ۱۰۰٪. هر دو در «یک» کوئریِ اتمیکِ D1.
// REVIEW_OFF_PCT (پیش‌فرض ۷۰): از این درصدِ مصرفِ سراسری به بعد، بازبینیِ ترجمه خاموش می‌شود (در index.js).
/** {ok, n, cap, pct}. kind = "ai" | "whisper". pro=true → سقفِ کامل. D1 خراب → ok. */
export async function takeGlobal(env, kind, pro = false) {
  const isAi = kind !== "whisper";
  const cap = intVar(env, isAi ? "GLOBAL_DAILY_AI" : "GLOBAL_DAILY_WHISPER", isAi ? 30000 : 3000);
  if (!cap || !env.TR_DB) return { ok: true };
  const reservePct = isAi ? Math.min(intVar(env, "PRO_RESERVE_PCT", 20), 90) : 0;
  const myCap = pro || !reservePct ? cap : Math.max(1, Math.floor((cap * (100 - reservePct)) / 100));
  try {
    await ensure(env);
    const day = new Date().toISOString().slice(0, 10);
    const col = isAi ? "ai_count" : "whisper_count";
    const r = await env.TR_DB.prepare(
      `INSERT INTO global_daily (day, ai_count, whisper_count) VALUES (?1, ?2, ?3) ` +
        `ON CONFLICT(day) DO UPDATE SET ${col} = ${col} + 1 WHERE ${col} < ?4 RETURNING ${col} AS n`
    ).bind(day, isAi ? 1 : 0, isAi ? 0 : 1, myCap).first();
    if (!r) {
      console.warn(`[LIMIT] global_daily_cap kind=${kind} cap=${cap} myCap=${myCap} pro=${pro}`);
      // «free_share» = سهمِ رایگان پر شده ولی Pro هنوز جا دارد؛ «global» = کلِ سقف پر شده
      return { ok: false, scope: myCap < cap ? "free_share" : "global", cap };
    }
    if (Math.random() < 0.01) {
      const old = new Date(Date.now() - 14 * 86400000).toISOString().slice(0, 10);
      await env.TR_DB.prepare("DELETE FROM global_daily WHERE day < ?1").bind(old).run();
    }
    return { ok: true, n: r.n, cap, pct: Math.round((r.n / cap) * 100) };
  } catch (e) {
    console.error("[FAIL-OPEN] global daily cap error — سقفِ سراسری بی‌صدا خاموش شد", String(e));
    return { ok: true };
  }
}

/**
 * قبل از هر تماسِ واقعی با AI/Whisper صدا بزن (بعد از کش/استخر).
 *   opts.queue = false → فقط سقفِ سراسری (برای ترجمه‌ی کوتاه و زیرنویس که چندتا موازی می‌آیند)
 * برمی‌گرداند {deny, release, capped}: اگر deny ≠ null آن را برگردان؛ وگرنه کارت را بکن و آخرش release() بزن.
 */
export async function beginAi(request, env, kind, cors, opts = {}) {
  let release = noop;
  const sess = env.TR_DB ? await verifySessionToken(env, request.headers.get("X-App-Token")) : null;
  const pro = sess ? await isPro(env, sess.sub, sess.em) : false;
  // 👑 VIP (ایمیلِ داخلِ VIP_EMAILS): بدونِ سقفِ روزانه‌ی کاربر و بدونِ صفِ همزمانی (سقفِ سراسریِ همه‌ی کاربران باقی می‌ماند)
  const vip = !!sess && isVipEmail(env, sess.em);
  // 👤 سقفِ روزانه‌ی هر کاربر (فقط AI، نه Whisper) — قبل از صف و سقفِ سراسری، تا کاربرِ پرمصرف سهمِ بقیه را نخورد
  if (sess && !vip && kind !== "whisper") {
    const u = await takeUser(env, sess.sub, pro);
    if (!u.ok) {
      return {
        deny: jsonResp({ error: MSG_UNAVAILABLE, code: "ai_unavailable" }, 503, cors),
        release: noop,
      };
    }
  }
  // 🪙 امتیازِ ماهانه (نامرئی): قبل از صف و سقفِ سراسری
  let degraded = false;
  if (sess && !vip && kind !== "whisper") {
    let feat = opts.feature || "";
    if (!feat) {
      try { feat = featureOf(request, new URL(request.url)) || "translate"; } catch { feat = "translate"; }
    }
    const c = await takeCredits(env, sess.sub, pro, creditCostOf(env, feat, opts.cost), feat);
    if (!c.ok) {
      // ترجمه: اپ با ۴۲۹ بی‌صدا به ML Kit/کش می‌رود
      if (opts.silent === "translate") {
        return {
          deny: jsonResp({ error: MSG_UNAVAILABLE, code: "ai_busy" }, 429, cors, { "Retry-After": "3600" }),
          release: noop,
        };
      }
      // بقیه: خطا نمی‌دهیم؛ صدازننده با مدل‌های رایگان جواب می‌دهد
      degraded = true;
    }
  }
  if (opts.queue !== false && env.TR_DB) {
    if (sess && pro && !vip) {
      const s = await acquireSlot(env, sess.sub);
      if (!s.ok) {
        console.warn(`[LIMIT] busy user=${sess.sub}`);
        return {
          deny: jsonResp({ error: MSG_BUSY, code: "busy" }, 429, cors, { "Retry-After": "5" }),
          release: noop,
        };
      }
      release = s.release;
    }
  }
  // 👑 VIP: سقفِ سراسریِ AI هم رویش اعمال نمی‌شود (Whisper مستثنا نیست چون سقفِ خودِ Cloudflare دارد)
  // 🆓 درخواستِ degraded (مدلِ رایگان) هزینه‌ای ندارد → از سقفِ سراسریِ هزینه کم نمی‌شود
  const g = (vip || degraded) && kind !== "whisper" ? { ok: true } : await takeGlobal(env, kind, pro);
  if (!g.ok) {
    await release();
    return {
      // code=daily_limit تا اپِ فعلی بدونِ تلاشِ دوباره، همان لحظه پیامِ «سقفِ امروز تمام شد» را نشان بدهد
      // scope=free_share: فقط سهمِ رایگان پر شده (Pro ادامه دارد) → اپ ترجمه‌ی دستگاه/کش را نگه می‌دارد
      deny: jsonResp(
        { error: g.scope === "free_share" ? MSG_CAP_FREE : MSG_CAP, code: "daily_limit", scope: g.scope || "global" },
        429, cors, { "Retry-After": "300" }
      ),
      release: noop,
      capped: true,
    };
  }
  return { deny: null, release, pct: g.pct, pro, degraded };
}
