// ---------------------------------------------------------------------------
// 📊 گزارشِ مصرفِ AI — فقط «ثبت و گزارش»؛ هیچ سقف/کش/زنجیره‌ای را تغییر نمی‌دهد.
//
// • هر درخواستِ AI در جدولِ تجمیعیِ ai_usage_daily (روز × کاربر × قابلیت × ارائه‌دهنده × کش؟) شمرده می‌شود.
// • cached=1  → از کشِ مشترکِ D1 جواب آمده (هزینه‌ی API ندارد)،  cached=0 → واقعاً به API رسیده.
// • توکن‌ها «تخمینی»اند (ارائه‌دهنده‌ها در زنجیره توکنِ واقعی برنمی‌گردانند): لاتین ≈ ۴ کاراکتر، غیرِ لاتین ≈ ۲.
// • هزینه‌ی تخمینی = توکن × تعرفه‌ی همان ارائه‌دهنده (دلار برای هر یک میلیون توکن).
//
// Vars / Secrets اختیاری:
//   AI_PRICING         = {"gemini":[0.30,2.50],"deepseek":[0.28,0.42],"default":[0,0]}   [ورودی, خروجی] به دلار/۱M توکن
//   AI_ALERT_COST_USD  = "0.50"   هشدار: هزینه‌ی تخمینیِ یک کاربر در یک روز بیشتر از این شد
//   AI_ALERT_CALLS     = "400"    هشدار: تعدادِ درخواستِ API یک کاربر در یک روز بیشتر از این شد
//   ADMIN_KEY (secret) = کلیدِ دسترسی به پنل:  /admin/usage-report?key=...
// ---------------------------------------------------------------------------
import { verifySessionToken } from "./auth.js";

let ready = false;
async function ensure(env) {
  if (ready) return;
  await env.TR_DB.prepare(
    "CREATE TABLE IF NOT EXISTS ai_usage_daily (" +
      "day TEXT NOT NULL, user_id TEXT NOT NULL, email TEXT NOT NULL DEFAULT '', " +
      "feature TEXT NOT NULL, provider TEXT NOT NULL, cached INTEGER NOT NULL, " +
      "calls INTEGER NOT NULL DEFAULT 0, in_tok INTEGER NOT NULL DEFAULT 0, " +
      "out_tok INTEGER NOT NULL DEFAULT 0, cost_micro INTEGER NOT NULL DEFAULT 0, " +
      "PRIMARY KEY (day, user_id, feature, provider, cached))"
  ).run();
  ready = true;
}

export function estTokens(s) {
  const t = String(s || "");
  if (!t) return 0;
  let non = 0;
  for (let i = 0; i < t.length; i++) if (t.charCodeAt(i) > 0x2ff) non++;
  return Math.ceil(t.length / (non / t.length > 0.3 ? 2 : 4));
}

let pricingSrc = null, pricing = {};
function priceOf(env, provider) {
  const raw = String(env.AI_PRICING || "");
  if (raw !== pricingSrc) {
    pricingSrc = raw;
    try { pricing = raw ? JSON.parse(raw) : {}; } catch { pricing = {}; }
  }
  const p = pricing[provider] || pricing.default || [0, 0];
  return [Number(p[0]) || 0, Number(p[1]) || 0];
}

function featureFrom(request, fallback) {
  const h = (request.headers.get("X-Feature") || "").trim().toLowerCase();
  return /^[a-z_]{1,24}$/.test(h) ? h : fallback;
}

/** ثبتِ یک درخواست. هرگز خطا پرتاب نمی‌کند. */
export async function recordUsage(env, request, o) {
  if (!env.TR_DB) return;
  try {
    const sess = await verifySessionToken(env, request.headers.get("X-App-Token"));
    if (!sess || !sess.sub) return;
    await ensure(env);
    const cached = o.cached ? 1 : 0;
    const provider = String(o.provider || "n/a").slice(0, 24);
    const inTok = cached ? 0 : estTokens(o.prompt);
    const outTok = cached ? 0 : estTokens(o.text);
    const [pi, po] = cached ? [0, 0] : priceOf(env, provider);
    const cost = Math.round(inTok * pi + outTok * po); // میکرو‌دلار
    const day = new Date().toISOString().slice(0, 10);
    const feature = featureFrom(request, o.feature || "other");
    await env.TR_DB.prepare(
      "INSERT INTO ai_usage_daily (day,user_id,email,feature,provider,cached,calls,in_tok,out_tok,cost_micro) " +
        "VALUES (?1,?2,?3,?4,?5,?6,1,?7,?8,?9) " +
        "ON CONFLICT(day,user_id,feature,provider,cached) DO UPDATE SET " +
        "calls=calls+1, in_tok=in_tok+?7, out_tok=out_tok+?8, cost_micro=cost_micro+?9, email=?3"
    ).bind(day, sess.sub, String(sess.em || "").toLowerCase(), feature, provider, cached, inTok, outTok, cost).run();
  } catch (e) {
    console.log("recordUsage error", String(e));
  }
}

// ───────────── پنلِ مدیریت ─────────────
const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
const usd = (micro) => "$" + ((micro || 0) / 1e6).toFixed(4);

function table(title, head, rows) {
  return `<h2>${esc(title)}</h2><div class="w"><table><tr>${head.map((h) => `<th>${esc(h)}</th>`).join("")}</tr>` +
    rows.map((r) => `<tr>${r.map((c) => `<td>${esc(c)}</td>`).join("")}</tr>`).join("") + "</table></div>";
}

/** GET /admin/usage-report?key=ADMIN_KEY[&from=YYYY-MM-DD&to=YYYY-MM-DD&user=email&format=json] */
export async function handleAdminReport(request, env, url) {
  const plain = (t, s) => new Response(t, { status: s, headers: { "Content-Type": "text/plain; charset=utf-8" } });
  if (!env.ADMIN_KEY) return plain("not found", 404);
  // مقایسه‌ی زمان‌ثابت (در برابر timing attack)
  const given = String(url.searchParams.get("key") || "");
  const want = String(env.ADMIN_KEY);
  let diff = given.length ^ want.length;
  for (let i = 0; i < want.length; i++) diff |= (given.charCodeAt(i) || 0) ^ want.charCodeAt(i);
  if (diff !== 0) return plain("forbidden", 403);
  if (!env.TR_DB) return plain("D1 not configured", 500);
  try {
    await ensure(env);
    const D = /^\d{4}-\d{2}-\d{2}$/;
    const today = new Date().toISOString().slice(0, 10);
    const from = D.test(url.searchParams.get("from") || "") ? url.searchParams.get("from")
      : new Date(Date.now() - 29 * 86400000).toISOString().slice(0, 10);
    const to = D.test(url.searchParams.get("to") || "") ? url.searchParams.get("to") : today;
    const user = (url.searchParams.get("user") || "").trim().toLowerCase();
    const where = "day >= ?1 AND day <= ?2" + (user ? " AND (lower(email) = ?3 OR user_id = ?3)" : "");
    const bind = user ? [from, to, user] : [from, to];
    const SUMS = "SUM(calls) calls, SUM(CASE WHEN cached=1 THEN calls ELSE 0 END) cache_calls, " +
      "SUM(CASE WHEN cached=0 THEN calls ELSE 0 END) api_calls, SUM(in_tok) in_tok, SUM(out_tok) out_tok, SUM(cost_micro) cost";
    const q = async (sql) => (await env.TR_DB.prepare(sql).bind(...bind).all()).results || [];

    const byFeature = await q(`SELECT feature k, ${SUMS} FROM ai_usage_daily WHERE ${where} GROUP BY feature ORDER BY cost DESC, calls DESC`);
    const byProvider = await q(`SELECT provider k, ${SUMS} FROM ai_usage_daily WHERE ${where} AND cached=0 GROUP BY provider ORDER BY calls DESC`);
    const byUser = await q(`SELECT email k, user_id uid, ${SUMS} FROM ai_usage_daily WHERE ${where} GROUP BY user_id ORDER BY cost DESC, api_calls DESC LIMIT 200`);
    const byDay = await q(`SELECT day k, ${SUMS} FROM ai_usage_daily WHERE ${where} GROUP BY day ORDER BY day DESC`);

    // ⚠️ هشدارِ مصرفِ غیرعادی (روز × کاربر)
    const aCost = Number(env.AI_ALERT_COST_USD) > 0 ? Number(env.AI_ALERT_COST_USD) * 1e6 : Infinity;
    const aCalls = Number(env.AI_ALERT_CALLS) > 0 ? Number(env.AI_ALERT_CALLS) : Infinity;
    const perDay = await q(`SELECT day, email, user_id uid, SUM(CASE WHEN cached=0 THEN calls ELSE 0 END) api_calls, SUM(cost_micro) cost FROM ai_usage_daily WHERE ${where} GROUP BY day, user_id`);
    const alerts = perDay.filter((r) => r.cost > aCost || r.api_calls > aCalls);

    if (url.searchParams.get("format") === "json") {
      return new Response(JSON.stringify({ from, to, byFeature, byProvider, byUser, byDay, alerts }, null, 1),
        { headers: { "Content-Type": "application/json; charset=utf-8" } });
    }
    const H = ["", "درخواست", "از کش", "به API", "توکن ورودی*", "توکن خروجی*", "هزینه*"];
    const row = (r) => [r.k || "(نامشخص)", r.calls, r.cache_calls, r.api_calls, r.in_tok, r.out_tok, usd(r.cost)];
    const html = `<!doctype html><html lang="fa" dir="rtl"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>گزارش مصرف AI</title><style>body{font:14px system-ui,sans-serif;margin:16px;background:#faf6ea;color:#222}
h2{margin:22px 0 6px;font-size:16px}.w{overflow-x:auto}table{border-collapse:collapse;min-width:100%;background:#fff}
th,td{border:1px solid #e3d8b8;padding:5px 8px;text-align:center;white-space:nowrap}th{background:#f1e6bf}.a{color:#b00020}
small{color:#666}</style>
<h1>📊 مصرف AI — ${esc(from)} تا ${esc(to)}${user ? " — " + esc(user) : ""}</h1>
<small>* توکن و هزینه تخمینی‌اند (چهار کاراکتر لاتین یا دو کاراکتر غیرلاتین ≈ یک توکن؛ تعرفه از AI_PRICING). «از کش» هزینه‌ی API ندارد.
ترجمه‌ی رایگان/کلاینتی و صدای آنلاین (TTS) اینجا شمرده نمی‌شوند.</small>
${alerts.length ? table("⚠️ هشدار مصرف غیرعادی", ["روز", "کاربر", "درخواست API", "هزینه*"], alerts.map((r) => [r.day, r.email || r.uid, r.api_calls, usd(r.cost)])) : ""}
${table("هر قابلیت", ["قابلیت", ...H.slice(1)], byFeature.map(row))}
${table("هر ارائه‌دهنده (فقط درخواست‌های API)", ["ارائه‌دهنده", ...H.slice(1)], byProvider.map(row))}
${table("هر کاربر (۲۰۰ مورد اول؛ برای جزئیات ?user=email)", ["کاربر", ...H.slice(1)], byUser.map((r) => row({ ...r, k: r.k || r.uid })))}
${table("هر روز", ["روز", ...H.slice(1)], byDay.map(row))}</html>`;
    return new Response(html, { headers: { "Content-Type": "text/html; charset=utf-8" } });
  } catch (e) {
    return plain("error: " + String(e), 500);
  }
}
