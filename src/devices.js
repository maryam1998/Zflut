// ---------------------------------------------------------------------------
// 🔒 جلوگیری از اشتراکِ اکانت (بدونِ بلاک کردنِ ورود)
//
//  • سهمیه‌ی دستگاه: رایگان ۱ / Pro ۱ (DEVICE_LIMIT_FREE / DEVICE_LIMIT_PRO)
//  • دستگاهِ جدید همیشه وارد می‌شود؛ اگر سهمیه پر باشد، قدیمی‌ترین دستگاه خودکار خارج می‌شود.
//  • شرط‌های «۴ دستگاه در ۲۴ ساعت» و «۳ تعویض در ۳۰ روز» فقط لاگ می‌شوند (هیچ‌وقت ورود را رد نمی‌کنند).
//  • «خروج از همه‌ی دستگاه‌ها» فقط با کدِ ایمیل (OTPِ Supabase) انجام می‌شود.
//  • ممنوع (پیاده نشده): بلاکِ ورود، سقفِ تعویض، IP، دست‌زدن به سهمیه‌ی AI.
//
// Vars (wrangler.toml):
//   DEVICE_MODE         = "off" | "log" (فقط ثبت و لاگ، هیچ دستگاهی خارج نمی‌شود) | "on"
//   DEVICE_ALLOW_LEGACY = "on" (پیش‌فرض؛ اپ‌های قدیمی بدونِ شناسه‌ی دستگاه) | "off"
//   DEVICE_LIMIT_FREE / DEVICE_LIMIT_PRO = سهمیه (پیش‌فرض ۱)
// ---------------------------------------------------------------------------

import { isPro } from "./usage.js";

const DAY = 86400000;
const OTP_MAX_AGE_SEC = 10 * 60;

export function deviceMode(env) {
  const m = String(env.DEVICE_MODE || "log").toLowerCase();
  return m === "on" || m === "off" ? m : "log";
}

export function legacyAllowed(env) {
  return String(env.DEVICE_ALLOW_LEGACY || "on").toLowerCase() !== "off";
}

function limitFor(env, pro) {
  const v = Number(pro ? env.DEVICE_LIMIT_PRO : env.DEVICE_LIMIT_FREE);
  return Number.isFinite(v) && v >= 1 ? Math.floor(v) : 1;
}

function clean(v, max) {
  return String(v == null ? "" : v).replace(/[\u0000-\u001f]/g, " ").trim().slice(0, max);
}

export function cleanDeviceId(v) {
  const s = clean(v, 80);
  return /^[A-Za-z0-9_-]{8,80}$/.test(s) ? s : "";
}

let ready = false;
async function ensureTables(env) {
  if (ready) return;
  await env.TR_DB.batch([
    env.TR_DB.prepare(
      "CREATE TABLE IF NOT EXISTS devices (" +
        "user_id TEXT NOT NULL, device_id TEXT NOT NULL, type TEXT NOT NULL DEFAULT '', " +
        "model TEXT NOT NULL DEFAULT '', created INTEGER NOT NULL, last_seen INTEGER NOT NULL, " +
        "revoked INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (user_id, device_id))"
    ),
    env.TR_DB.prepare("CREATE INDEX IF NOT EXISTS idx_devices_user ON devices (user_id, revoked, last_seen)"),
    env.TR_DB.prepare(
      "CREATE TABLE IF NOT EXISTS device_events (" +
        "id INTEGER PRIMARY KEY AUTOINCREMENT, user_id TEXT NOT NULL, device_id TEXT NOT NULL DEFAULT '', " +
        "kind TEXT NOT NULL, detail TEXT NOT NULL DEFAULT '', ts INTEGER NOT NULL)"
    ),
    env.TR_DB.prepare("CREATE INDEX IF NOT EXISTS idx_devev_user ON device_events (user_id, kind, ts)"),
  ]);
  ready = true;
}

async function logEvent(env, userId, deviceId, kind, detail) {
  try {
    await env.TR_DB.prepare(
      "INSERT INTO device_events (user_id, device_id, kind, detail, ts) VALUES (?1, ?2, ?3, ?4, ?5)"
    ).bind(userId, deviceId || "", kind, clean(detail, 200), Date.now()).run();
  } catch (e) {
    console.error("[device] log failed", String(e));
  }
  console.log(`[DEVICE] ${kind} user=${userId} device=${deviceId || "-"} ${detail || ""}`);
}

/**
 * ثبتِ دستگاه هنگامِ ساختنِ نشست. هیچ‌وقت ورود را رد نمی‌کند، مگر دستگاهی که قبلاً
 * خارج شده (revoked) و دوباره با همان شناسه می‌آید → {revoked:true} (اپ باید خارج شود و شناسه‌ی تازه بسازد).
 * → { revoked, evicted: [deviceId...], suspicious: [...] }
 */
export async function registerDevice(env, userId, email, deviceId, info) {
  const out = { revoked: false, evicted: [], suspicious: [] };
  const mode = deviceMode(env);
  if (mode === "off" || !env.TR_DB || !deviceId) return out;
  try {
    await ensureTables(env);
    const now = Date.now();
    const row = await env.TR_DB.prepare(
      "SELECT revoked FROM devices WHERE user_id = ?1 AND device_id = ?2"
    ).bind(userId, deviceId).first();
    if (row && row.revoked) {
      if (mode === "on") { out.revoked = true; return out; }
    }
    const type = clean(info && info.type, 20);
    const model = clean(info && info.model, 60);
    if (row && !row.revoked) {
      await env.TR_DB.prepare(
        "UPDATE devices SET last_seen = ?3, type = ?4, model = ?5 WHERE user_id = ?1 AND device_id = ?2"
      ).bind(userId, deviceId, now, type, model).run();
      return out;
    }
    // دستگاهِ جدید
    await env.TR_DB.prepare(
      "INSERT INTO devices (user_id, device_id, type, model, created, last_seen, revoked) VALUES (?1, ?2, ?3, ?4, ?5, ?5, 0) " +
        "ON CONFLICT(user_id, device_id) DO UPDATE SET revoked = 0, last_seen = ?5, type = ?3, model = ?4"
    ).bind(userId, deviceId, type, model, now).run();
    await logEvent(env, userId, deviceId, "new_device", `${type} ${model}`);

    let pro = false;
    try { pro = await isPro(env, userId, email); } catch { /* ignore */ }
    const limit = limitFor(env, pro);
    const act = await env.TR_DB.prepare(
      "SELECT device_id FROM devices WHERE user_id = ?1 AND revoked = 0 AND device_id != ?2 ORDER BY last_seen ASC"
    ).bind(userId, deviceId).all();
    const others = (act && act.results) || [];
    // دستگاهِ جدید یک جا می‌گیرد؛ قدیمی‌ترین‌ها تا رسیدن به سهمیه خارج می‌شوند
    const over = others.length + 1 - limit;
    if (over > 0) {
      for (const d of others.slice(0, over)) {
        if (mode === "on") {
          await env.TR_DB.prepare(
            "UPDATE devices SET revoked = 1 WHERE user_id = ?1 AND device_id = ?2"
          ).bind(userId, d.device_id).run();
          await logEvent(env, userId, d.device_id, "evict", `by ${deviceId}`);
          out.evicted.push(d.device_id);
        } else {
          await logEvent(env, userId, d.device_id, "would_evict", `by ${deviceId}`);
        }
      }
    }
    // 📝 فقط لاگ — هرگز ردِ ورود
    const n24 = await env.TR_DB.prepare(
      "SELECT COUNT(DISTINCT device_id) AS n FROM device_events WHERE user_id = ?1 AND kind = 'new_device' AND ts > ?2"
    ).bind(userId, now - DAY).first();
    if (n24 && n24.n >= 4) {
      out.suspicious.push("devices_4_in_24h");
      await logEvent(env, userId, deviceId, "suspicious_4_devices_24h", `n=${n24.n}`);
    }
    const sw = await env.TR_DB.prepare(
      "SELECT COUNT(*) AS n FROM device_events WHERE user_id = ?1 AND kind IN ('evict','would_evict') AND ts > ?2"
    ).bind(userId, now - 30 * DAY).first();
    if (sw && sw.n >= 3) {
      out.suspicious.push("swaps_3_in_30d");
      await logEvent(env, userId, deviceId, "suspicious_3_swaps_30d", `n=${sw.n}`);
    }
  } catch (e) {
    console.error("[FAIL-OPEN] registerDevice error", String(e));
  }
  return out;
}

const activeCache = new Map(); // "uid:did" → { ok, t }

/** آیا این دستگاه هنوز مجاز است؟ (برای هر درخواست؛ ۳۰ ثانیه کش). خطای D1 = مجاز. */
export async function deviceActive(env, userId, deviceId) {
  if (deviceMode(env) !== "on" || !env.TR_DB || !deviceId) return true;
  const k = `${userId}:${deviceId}`;
  const hit = activeCache.get(k);
  const now = Date.now();
  if (hit && now - hit.t < 30000) return hit.ok;
  try {
    await ensureTables(env);
    const row = await env.TR_DB.prepare(
      "SELECT revoked, last_seen FROM devices WHERE user_id = ?1 AND device_id = ?2"
    ).bind(userId, deviceId).first();
    // ردیفی نیست (مثلاً پاک شده) = خارج‌شده
    const ok = !!row && !row.revoked;
    if (ok && now - row.last_seen > 10 * 60000) {
      await env.TR_DB.prepare(
        "UPDATE devices SET last_seen = ?3 WHERE user_id = ?1 AND device_id = ?2"
      ).bind(userId, deviceId, now).run();
    }
    activeCache.set(k, { ok, t: now });
    if (activeCache.size > 5000) activeCache.clear();
    return ok;
  } catch (e) {
    console.error("[FAIL-OPEN] deviceActive error", String(e));
    return true;
  }
}

function jsonResp(data, status, cors) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...cors },
  });
}

/** GET /api/devices — وضعیتِ اکانت + لیستِ دستگاه‌ها (با X-App-Token) */
export async function handleDevicesList(env, cors, sess) {
  const email = String(sess.em || "");
  let pro = false;
  try { pro = await isPro(env, sess.sub, email); } catch { /* ignore */ }
  const out = { pro, email, limit: limitFor(env, pro), mode: deviceMode(env), devices: [] };
  if (env.TR_DB && deviceMode(env) !== "off") {
    try {
      await ensureTables(env);
      const r = await env.TR_DB.prepare(
        "SELECT device_id, type, model, created, last_seen FROM devices WHERE user_id = ?1 AND revoked = 0 ORDER BY last_seen DESC"
      ).bind(sess.sub).all();
      out.devices = ((r && r.results) || []).map((d) => ({
        id: d.device_id,
        type: d.type,
        model: d.model,
        created: d.created,
        last_seen: d.last_seen,
        current: d.device_id === sess.did,
      }));
    } catch (e) {
      console.error("[device] list failed", String(e));
    }
  }
  return jsonResp(out, 200, cors);
}

function jwtClaims(token) {
  try {
    const b = String(token).split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    return JSON.parse(atob(b + "===".slice((b.length + 3) % 4)));
  } catch {
    return null;
  }
}

/**
 * POST /api/devices/logout-all — فقط با کدِ ایمیل.
 * هدر Authorization: Bearer <access token سوپابیس> که تازه با verifyOTP(email) گرفته شده
 * (claim «amr» باید یک ورودِ otp در ۱۰ دقیقه‌ی اخیر داشته باشد).
 */
export async function handleLogoutAll(request, env, cors, verifySupabaseUser) {
  if (deviceMode(env) !== "on") return jsonResp({ error: "not enabled" }, 403, cors);
  const m = /^Bearer\s+(.+)$/i.exec(request.headers.get("Authorization") || "");
  if (!m) return jsonResp({ error: "login required" }, 401, cors);
  let user = null;
  try { user = await verifySupabaseUser(env, m[1]); } catch { /* ignore */ }
  if (!user) return jsonResp({ error: "invalid login" }, 401, cors);
  const claims = jwtClaims(m[1]) || {};
  const now = Math.floor(Date.now() / 1000);
  const amr = Array.isArray(claims.amr) ? claims.amr : [];
  const fresh = amr.some((a) => a && (a.method === "otp" || a.method === "email_otp" || a.method === "magiclink") &&
    Number(a.timestamp) > now - OTP_MAX_AGE_SEC);
  if (!fresh) return jsonResp({ error: "email code required", code: "otp_required" }, 403, cors);
  if (!env.TR_DB) return jsonResp({ error: "unavailable" }, 503, cors);
  try {
    await ensureTables(env);
    await env.TR_DB.prepare("UPDATE devices SET revoked = 1 WHERE user_id = ?1").bind(user.id).run();
    await logEvent(env, user.id, "", "logout_all", "");
    for (const k of [...activeCache.keys()]) if (k.startsWith(user.id + ":")) activeCache.delete(k);
  } catch (e) {
    console.error("[device] logout-all failed", String(e));
    return jsonResp({ error: "failed" }, 500, cors);
  }
  return jsonResp({ ok: true }, 200, cors);
}
