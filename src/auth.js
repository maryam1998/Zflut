// ---------------------------------------------------------------------------
// احراز هویت + سهمیه‌ی روزانه‌ی هر کاربر برای Worker
//
// جریان:
//   ۱) اپ بعد از لاگین، توکن Supabase را فقط یک‌بار به POST /api/session می‌دهد.
//   ۲) Worker با Supabase چکش می‌کند و یک «توکن نشست» امضاشده (HMAC) برمی‌گرداند (۱۴ روز اعتبار).
//   ۳) اپ (Flutter و بخش بومی اندروید) توکن را در هدر X-App-Token می‌فرستد؛ Worker بدونِ رفتن
//      سراغِ Supabase، فقط امضا را چک می‌کند (سریع) و سهمیه‌ی روزانه‌ی همان کاربر را می‌شمارد.
//
// Secrets لازم (wrangler secret put ...):
//   SESSION_SECRET   — یک رشته‌ی تصادفیِ بلند (۳۲ بایت به بالا)
//   SUPABASE_URL     — مثلاً https://xxxx.supabase.co
//   SUPABASE_ANON_KEY
//
// Vars اختیاری (wrangler.toml):
//   AUTH_MODE  = "on" (پیش‌فرض) | "log" (چک می‌کند و فقط لاگ می‌گیرد، ردّ نمی‌کند) | "off"
//   LIMIT_AI / LIMIT_TTS / LIMIT_MISC = سقفِ روزانه‌ی هر کاربر (پیش‌فرض ۶۰۰ / ۴۰۰۰ / ۳۰۰۰)
// ---------------------------------------------------------------------------

import { featureGate, isPro, isVipEmail } from "./usage.js";

const enc = new TextEncoder();
const SESSION_TTL_SEC = 14 * 24 * 3600;

function jsonResp(data, status, cors) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...cors },
  });
}

function b64uEncode(bytes) {
  let s = "";
  for (const b of new Uint8Array(bytes)) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function b64uDecode(str) {
  const p = str.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((str.length + 3) % 4);
  const bin = atob(p);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

async function hmacKey(secret, usages) {
  return crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, usages);
}

async function issueSessionToken(env, userId, email) {
  const exp = Math.floor(Date.now() / 1000) + SESSION_TTL_SEC;
  // em = ایمیلِ کاربر (برای تشخیصِ VIP بدونِ رفتن سراغِ Supabase)
  const payload = b64uEncode(enc.encode(JSON.stringify({ sub: userId, exp, em: String(email || "").toLowerCase() })));
  const key = await hmacKey(env.SESSION_SECRET, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode("v1." + payload));
  return { token: `v1.${payload}.${b64uEncode(sig)}`, exp };
}

/** {sub, exp} یا null */
export async function verifySessionToken(env, token) {
  try {
    const parts = String(token || "").split(".");
    if (parts.length !== 3 || parts[0] !== "v1") return null;
    const key = await hmacKey(env.SESSION_SECRET, ["verify"]);
    const ok = await crypto.subtle.verify("HMAC", key, b64uDecode(parts[2]), enc.encode(`v1.${parts[1]}`));
    if (!ok) return null;
    const p = JSON.parse(new TextDecoder().decode(b64uDecode(parts[1])));
    if (!p || !p.sub || !p.exp || p.exp < Math.floor(Date.now() / 1000)) return null;
    return p;
  } catch {
    return null;
  }
}

function tokenIssuer(accessToken) {
  // فقط برای عیب‌یابی: پروژه‌ی Supabaseی که این توکن را صادر کرده (iss) — راز نیست
  try {
    const p = JSON.parse(new TextDecoder().decode(b64uDecode(String(accessToken).split(".")[1])));
    return String(p.iss || "");
  } catch {
    return "unreadable";
  }
}

async function verifySupabaseUser(env, accessToken) {
  // مقدارها trim می‌شوند (فاصله/خطِ اضافه هنگامِ paste در داشبورد باعث ۴۰۱ می‌شد)
  const base = String(env.SUPABASE_URL).trim().replace(/\/+$/, "");
  const key = String(env.SUPABASE_ANON_KEY).trim();
  const r = await fetch(`${base}/auth/v1/user`, {
    headers: { apikey: key, Authorization: `Bearer ${accessToken}` },
  });
  if (!r.ok) {
    let body = "";
    try { body = (await r.text()).slice(0, 200); } catch { /* ignore */ }
    console.log("session: supabase rejected", r.status, body,
      "| worker=", base, "| token iss=", tokenIssuer(accessToken));
    return null;
  }
  const u = await r.json();
  return u && u.id ? u : null;
}

function bucketOf(pathname) {
  if (pathname === "/api/tts" || pathname === "/api/tts-gemini") return "tts";
  if (
    pathname === "/api/generate" ||
    pathname === "/api/transcribe" ||
    pathname === "/api/translate-subtitles" ||
    pathname === "/api/translate-text"
  ) return "ai";
  return "misc";
}

function limitFor(env, bucket) {
  const dflt = { ai: 600, tts: 4000, misc: 3000 }[bucket];
  const v = Number(env["LIMIT_" + bucket.toUpperCase()]);
  return Number.isFinite(v) && v > 0 ? v : dflt;
}

let rateReady = false;

/** true = مجاز. اگر D1 در دسترس نباشد، سهمیه اعمال نمی‌شود (احراز هویت همچنان هست). */
async function underLimit(env, userId, bucket) {
  if (!env.TR_DB) return true;
  try {
    if (!rateReady) {
      await env.TR_DB.prepare("CREATE TABLE IF NOT EXISTS rate_limit (k TEXT PRIMARY KEY, n INTEGER NOT NULL)").run();
      rateReady = true;
    }
    const day = new Date().toISOString().slice(0, 10);
    const row = await env.TR_DB.prepare(
      "INSERT INTO rate_limit (k, n) VALUES (?1, 1) ON CONFLICT(k) DO UPDATE SET n = n + 1 RETURNING n"
    ).bind(`${day}:${bucket}:${userId}`).first();
    if (Math.random() < 0.01) {
      const old = new Date(Date.now() - 3 * 86400000).toISOString().slice(0, 10);
      await env.TR_DB.prepare("DELETE FROM rate_limit WHERE k < ?1").bind(old).run();
    }
    return !row || row.n <= limitFor(env, bucket);
  } catch {
    return true;
  }
}

/** POST /api/session — هدر Authorization: Bearer <access token سوپابیس> */
export async function handleSession(request, env, cors) {
  if (!env.SESSION_SECRET || !env.SUPABASE_URL || !env.SUPABASE_ANON_KEY) {
    return jsonResp({ error: "auth is not configured on the server" }, 500, cors);
  }
  const m = /^Bearer\s+(.+)$/i.exec(request.headers.get("Authorization") || "");
  if (!m) return jsonResp({ error: "login required" }, 401, cors);
  let user = null;
  try { user = await verifySupabaseUser(env, m[1]); } catch (e) { console.log("session: verify error", String(e)); }
  if (!user) return jsonResp({ error: "invalid login" }, 401, cors);
  const { token, exp } = await issueSessionToken(env, user.id, user.email);
  let pro = false;
  try { pro = await isPro(env, user.id, user.email); } catch { /* ignore */ }
  return jsonResp({ token, exp, pro }, 200, cors);
}

/** برای هر /api/* (جز /api/session): null = اجازه، وگرنه Response ردّ. */
export async function authGate(request, env, url, cors) {
  const mode = String(env.AUTH_MODE || "on").toLowerCase();
  if (mode === "off") return null;
  const enforce = mode !== "log";

  if (!env.SESSION_SECRET) {
    if (enforce) return jsonResp({ error: "auth is not configured on the server" }, 500, cors);
    return null;
  }
  const p = await verifySessionToken(env, request.headers.get("X-App-Token"));
  if (!p) {
    if (!enforce) { console.log("auth(log): missing/invalid token", url.pathname); return null; }
    return jsonResp({ error: "login required" }, 401, cors);
  }
  const bucket = bucketOf(url.pathname);
  // 👑 VIP هم مثلِ Pro سقفِ روزانه دارد (فقط سقفِ «کل عمر» برداشته شده) — برای سنجشِ مصرفِ واقعی
  if (!(await underLimit(env, p.sub, bucket))) {
    if (!enforce) { console.log("auth(log): over limit", bucket); return null; }
    return jsonResp({ error: "daily limit reached, try again tomorrow" }, 429, cors);
  }
  // 💎 سقفِ «کل عمر» برای هر بخشِ نسخه‌ی رایگان (۴۰۲ اگر تمام شده)
  const gated = await featureGate(request, env, url, p, cors);
  if (gated) {
    if (!enforce) { console.log("auth(log): free limit", url.pathname); return null; }
    return gated;
  }
  return null;
}
