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
import { isPro } from "./usage.js";

const MSG_BUSY = "الان شلوغه، چند لحظه دیگه (try again in 5s)";
const MSG_CAP = "ظرفیتِ هوش مصنوعیِ امروز تکمیل شده؛ فردا دوباره امتحان کن.";

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

// ───────────── ۲) سقفِ سراسریِ روزانه ─────────────
/** {ok}. kind = "ai" | "whisper". D1 خراب → ok. */
export async function takeGlobal(env, kind) {
  const isAi = kind !== "whisper";
  const cap = intVar(env, isAi ? "GLOBAL_DAILY_AI" : "GLOBAL_DAILY_WHISPER", isAi ? 5000 : 3000);
  if (!cap || !env.TR_DB) return { ok: true };
  try {
    await ensure(env);
    const day = new Date().toISOString().slice(0, 10);
    const col = isAi ? "ai_count" : "whisper_count";
    const r = await env.TR_DB.prepare(
      `INSERT INTO global_daily (day, ai_count, whisper_count) VALUES (?1, ?2, ?3) ` +
        `ON CONFLICT(day) DO UPDATE SET ${col} = ${col} + 1 WHERE ${col} < ?4 RETURNING ${col} AS n`
    ).bind(day, isAi ? 1 : 0, isAi ? 0 : 1, cap).first();
    if (!r) {
      console.warn(`[LIMIT] global_daily_cap kind=${kind} cap=${cap}`);
      return { ok: false };
    }
    if (Math.random() < 0.01) {
      const old = new Date(Date.now() - 14 * 86400000).toISOString().slice(0, 10);
      await env.TR_DB.prepare("DELETE FROM global_daily WHERE day < ?1").bind(old).run();
    }
    return { ok: true, n: r.n };
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
  if (opts.queue !== false && env.TR_DB) {
    const sess = await verifySessionToken(env, request.headers.get("X-App-Token"));
    if (sess && (await isPro(env, sess.sub, sess.em))) {
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
  const g = await takeGlobal(env, kind);
  if (!g.ok) {
    await release();
    return {
      // code=daily_limit تا اپِ فعلی بدونِ تلاشِ دوباره، همان لحظه پیامِ «سقفِ امروز تمام شد» را نشان بدهد
      deny: jsonResp({ error: MSG_CAP, code: "daily_limit", scope: "global" }, 429, cors),
      release: noop,
      capped: true,
    };
  }
  return { deny: null, release };
}
