// ---------------------------------------------------------------------------
// 📊 گزارشِ مصرفِ AI — فقط «ثبت و گزارش»؛ هیچ سقف/کش/زنجیره‌ای را تغییر نمی‌دهد.
//
// • هر درخواستِ AI در جدولِ تجمیعیِ ai_usage_daily (روز × کاربر × قابلیت × ارائه‌دهنده × کش؟) شمرده می‌شود.
// • cached=1  → از کشِ مشترکِ D1 جواب آمده (هزینه‌ی API ندارد)،  cached=0 → واقعاً به API رسیده.
// • توکن‌ها «تخمینی»اند (ارائه‌دهنده‌ها در زنجیره توکنِ واقعی برنمی‌گردانند): لاتین ≈ ۴ کاراکتر، غیرِ لاتین ≈ ۲.
// • هزینه‌ی تخمینی = توکن × تعرفه‌ی همان ارائه‌دهنده (دلار برای هر یک میلیون توکن).
//
// Vars / Secrets اختیاری:
//   AI_PRICING         = {"gemini":[1.25,10.00],"deepseek":[0.28,0.42],"default":[0,0]}   [ورودی, خروجی] به دلار/۱M توکن
//   AI_ALERT_COST_USD  = "0.50"   هشدار: هزینه‌ی تخمینیِ یک کاربر در یک روز بیشتر از این شد
//   AI_ALERT_CALLS     = "400"    هشدار: تعدادِ درخواستِ API یک کاربر در یک روز بیشتر از این شد
//   ADMIN_KEY (secret) = کلیدِ دسترسی به پنل:  /admin/usage-report?key=...   و پنلِ امتیازها:  /admin/credits?key=...
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

    // 🪙 امتیازِ ماهانه (فقط ادمین می‌بیند؛ کاربر هیچ نشانگری ندارد): چه کسانی کِی به سقف رسیدند + پرمصرف‌ترین‌ها
    const month = /^\d{4}-\d{2}$/.test(url.searchParams.get("month") || "") ? url.searchParams.get("month") : today.slice(0, 7);
    let capped = [], topCredits = [], globalToday = null;
    try {
      await env.TR_DB.prepare(
        "CREATE TABLE IF NOT EXISTS user_credits (user_id TEXT NOT NULL, month TEXT NOT NULL, used INTEGER NOT NULL DEFAULT 0, " +
          "capped_at INTEGER, PRIMARY KEY (user_id, month))"
      ).run();
      const em = "(SELECT email FROM ai_usage_daily u WHERE u.user_id = c.user_id AND u.email != '' LIMIT 1)";
      capped = (await env.TR_DB.prepare(
        `SELECT c.user_id uid, ${em} email, c.used, c.capped_at FROM user_credits c WHERE c.month = ?1 AND c.capped_at IS NOT NULL ORDER BY c.capped_at DESC LIMIT 200`
      ).bind(month).all()).results || [];
      topCredits = (await env.TR_DB.prepare(
        `SELECT c.user_id uid, ${em} email, c.used, c.capped_at FROM user_credits c WHERE c.month = ?1 ORDER BY c.used DESC LIMIT 30`
      ).bind(month).all()).results || [];
      globalToday = await env.TR_DB.prepare("SELECT ai_count, whisper_count FROM global_daily WHERE day = ?1").bind(today).first();
    } catch { /* جدول‌ها هنوز ساخته نشده‌اند */ }
    const fmtT = (ms) => (ms ? new Date(ms).toISOString().replace("T", " ").slice(0, 16) + " UTC" : "—");
    const capCap = Number(env.GLOBAL_DAILY_AI) > 0 ? Number(env.GLOBAL_DAILY_AI) : 0;

    if (url.searchParams.get("format") === "json") {
      return new Response(JSON.stringify({ from, to, byFeature, byProvider, byUser, byDay, alerts, month, capped, topCredits, globalToday }, null, 1),
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
${globalToday ? `<p>⚖️ سقفِ سراسریِ AI امروز: <b>${esc(globalToday.ai_count)}</b>${capCap ? " از " + esc(capCap) + " (" + Math.round((globalToday.ai_count / capCap) * 100) + "٪)" : ""}</p>` : ""}
${table("🪙 رسیده به سقفِ امتیازِ ماهانه — " + month + " (" + capped.length + " نفر)", ["کاربر", "امتیازِ مصرفی", "زمانِ رسیدن"], capped.map((r) => [r.email || r.uid, r.used, fmtT(r.capped_at)]))}
${table("🪙 پرمصرف‌ترین‌ها از نظرِ امتیاز — " + month, ["کاربر", "امتیازِ مصرفی", "رسیده به سقف؟"], topCredits.map((r) => [r.email || r.uid, r.used, r.capped_at ? fmtT(r.capped_at) : "—"]))}
${table("هر قابلیت", ["قابلیت", ...H.slice(1)], byFeature.map(row))}
${table("هر ارائه‌دهنده (فقط درخواست‌های API)", ["ارائه‌دهنده", ...H.slice(1)], byProvider.map(row))}
${table("هر کاربر (۲۰۰ مورد اول؛ برای جزئیات ?user=email)", ["کاربر", ...H.slice(1)], byUser.map((r) => row({ ...r, k: r.k || r.uid })))}
${table("هر روز", ["روز", ...H.slice(1)], byDay.map(row))}</html>`;
    return new Response(html, { headers: { "Content-Type": "text/html; charset=utf-8" } });
  } catch (e) {
    return plain("error: " + String(e), 500);
  }
}


// ───────────── 🪙 پنلِ امتیازها (Credits Metrics) — فقط ادمین ─────────────
/** GET /admin/credits?key=ADMIN_KEY[&month=YYYY-MM][&q=email][&sort=used|capped|recent][&format=json] */
export async function handleAdminCredits(request, env, url) {
  const plain = (t, s) => new Response(t, { status: s, headers: { "Content-Type": "text/plain; charset=utf-8" } });
  if (!env.ADMIN_KEY) return plain("not found", 404);
  const given = String(url.searchParams.get("key") || "");
  const want = String(env.ADMIN_KEY);
  let diff = given.length ^ want.length;
  for (let i = 0; i < want.length; i++) diff |= (given.charCodeAt(i) || 0) ^ want.charCodeAt(i);
  if (diff !== 0) return plain("forbidden", 403);
  if (!env.TR_DB) return plain("D1 not configured", 500);
  try {
    await ensure(env);
    await env.TR_DB.batch([
      env.TR_DB.prepare(
        "CREATE TABLE IF NOT EXISTS user_credits (user_id TEXT NOT NULL, month TEXT NOT NULL, used INTEGER NOT NULL DEFAULT 0, capped_at INTEGER, PRIMARY KEY (user_id, month))"
      ),
      env.TR_DB.prepare(
        "CREATE TABLE IF NOT EXISTS user_credit_features (user_id TEXT NOT NULL, month TEXT NOT NULL, feature TEXT NOT NULL, " +
          "credits INTEGER NOT NULL DEFAULT 0, calls INTEGER NOT NULL DEFAULT 0, free_calls INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (user_id, month, feature))"
      ),
    ]);
    const month = /^\d{4}-\d{2}$/.test(url.searchParams.get("month") || "") ? url.searchParams.get("month") : new Date().toISOString().slice(0, 7);
    const q = (url.searchParams.get("q") || "").trim().toLowerCase();
    const sort = url.searchParams.get("sort") || "used";
    const cap = Number(env.PRO_MONTHLY_CREDITS) > 0 ? Math.floor(Number(env.PRO_MONTHLY_CREDITS)) : 9000;

    const em = "(SELECT email FROM ai_usage_daily u WHERE u.user_id = c.user_id AND u.email != '' LIMIT 1)";
    const order = sort === "capped" ? "c.capped_at IS NULL, c.capped_at ASC" : sort === "recent" ? "c.rowid DESC" : "c.used DESC";
    const users = ((await env.TR_DB.prepare(
      `SELECT c.user_id uid, ${em} email, c.used, c.capped_at FROM user_credits c WHERE c.month = ?1 ORDER BY ${order} LIMIT 1000`
    ).bind(month).all()).results || []).filter((r) => !q || String(r.email || "").toLowerCase().includes(q) || r.uid === q);

    const feats = (await env.TR_DB.prepare(
      "SELECT user_id uid, feature, credits, calls, free_calls FROM user_credit_features WHERE month = ?1"
    ).bind(month).all()).results || [];
    const byUser = new Map();
    for (const f of feats) { if (!byUser.has(f.uid)) byUser.set(f.uid, []); byUser.get(f.uid).push(f); }

    const featTotals = {};
    for (const f of feats) {
      const t = (featTotals[f.feature] ||= { credits: 0, calls: 0, free_calls: 0 });
      t.credits += f.credits; t.calls += f.calls; t.free_calls += f.free_calls;
    }
    const totalUsed = users.reduce((a, r) => a + r.used, 0);
    const cappedN = users.filter((r) => r.capped_at).length;
    const freeCalls = Object.values(featTotals).reduce((a, t) => a + t.free_calls, 0);

    const rows = users.map((r) => {
      const fl = (byUser.get(r.uid) || []).sort((a, b) => b.credits - a.credits);
      return {
        user: r.email || r.uid, uid: r.uid, used: r.used, cap, pct: Math.round((r.used / cap) * 100),
        capped_at: r.capped_at || null,
        features: Object.fromEntries(fl.map((f) => [f.feature, { credits: f.credits, calls: f.calls, free_calls: f.free_calls }])),
      };
    });

    if (url.searchParams.get("format") === "json") {
      return new Response(JSON.stringify({ month, cap, users: rows.length, capped: cappedN, totalUsed, freeCallsAfterCap: freeCalls, featTotals, rows }, null, 1),
        { headers: { "Content-Type": "application/json; charset=utf-8" } });
    }

    const fmtT = (ms) => (ms ? new Date(ms).toISOString().replace("T", " ").slice(0, 16) + " UTC" : "—");
    const key = encodeURIComponent(given);
    const base = `/admin/credits?key=${key}`;
    const bar = (pct) => `<div class="bar"><i style="width:${Math.min(100, pct)}%" class="${pct >= 100 ? "full" : pct >= 80 ? "hi" : ""}"></i></div>`;
    const featTxt = (o) => Object.entries(o.features).map(([k, v]) => `${esc(k)}: ${v.credits}${v.free_calls ? ` <span class="g">(+${v.free_calls} رایگان)</span>` : ""}`).join(" · ") || "—";
    const body = rows.map((o) => `<tr class="${o.capped_at ? "cap" : ""}"><td class="l">${esc(o.user)}</td><td>${o.used} / ${o.cap}</td>` +
      `<td>${bar(o.pct)}<small>${o.pct}٪</small></td><td>${o.capped_at ? "🔴 " + esc(fmtT(o.capped_at)) : "—"}</td><td class="l">${featTxt(o)}</td></tr>`).join("");
    const ft = Object.entries(featTotals).sort((a, b) => b[1].credits - a[1].credits)
      .map(([k, t]) => `<tr><td>${esc(k)}</td><td>${t.calls}</td><td>${t.credits}</td><td>${t.free_calls}</td></tr>`).join("");
    const html = `<!doctype html><html lang="fa" dir="rtl"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>پنل امتیازها</title><style>body{font:14px system-ui,sans-serif;margin:16px;background:#faf6ea;color:#222}h1{font-size:20px}h2{margin:22px 0 6px;font-size:16px}
.cards{display:flex;flex-wrap:wrap;gap:10px}.card{background:#fff;border:1px solid #e3d8b8;border-radius:10px;padding:10px 16px;min-width:130px}.card b{display:block;font-size:22px}
.w{overflow-x:auto}table{border-collapse:collapse;min-width:100%;background:#fff}th,td{border:1px solid #e3d8b8;padding:5px 8px;text-align:center;white-space:nowrap}th{background:#f1e6bf}
td.l{text-align:right}tr.cap td{background:#fff1f0}.bar{width:90px;height:8px;background:#eee;border-radius:4px;display:inline-block;overflow:hidden;vertical-align:middle;margin-inline-end:6px}
.bar i{display:block;height:100%;background:#4caf50}.bar i.hi{background:#ff9800}.bar i.full{background:#d32f2f}.g{color:#2e7d32}small{color:#666}
form{margin:10px 0}input,select,button{padding:5px 8px;font:inherit}a{color:#1a5fb4}</style>
<h1>🪙 پنل امتیازهای ماهانه — ${esc(month)}</h1>
<form method="get" action="/admin/credits"><input type="hidden" name="key" value="${esc(given)}">
ماه: <input name="month" value="${esc(month)}" size="8"> جست‌وجوی ایمیل: <input name="q" value="${esc(q)}">
مرتب‌سازی: <select name="sort"><option value="used"${sort === "used" ? " selected" : ""}>بیشترین مصرف</option><option value="capped"${sort === "capped" ? " selected" : ""}>زمانِ رسیدن به سقف</option><option value="recent"${sort === "recent" ? " selected" : ""}>تازه‌ترین</option></select>
<button>نمایش</button> <a href="${base}&month=${esc(month)}&format=json">JSON</a> · <a href="/admin/usage-report?key=${key}">گزارش هزینه‌ی AI</a></form>
<div class="cards"><div class="card"><b>${users.length}</b>کاربرِ فعال</div><div class="card"><b>${cappedN}</b>رسیده به سقف (${cap})</div>
<div class="card"><b>${totalUsed}</b>مجموع امتیازِ مصرفی</div><div class="card"><b>${freeCalls}</b>درخواستِ بعد از سقف (مدل رایگان/ML Kit)</div></div>
<h2>مصرفِ هر کاربر</h2><div class="w"><table><tr><th>کاربر</th><th>مصرف / سقف</th><th>درصد</th><th>زمانِ رسیدن به سقف</th><th>ریز مصرف به تفکیکِ قابلیت (امتیاز)</th></tr>${body || '<tr><td colspan="5">داده‌ای نیست</td></tr>'}</table></div>
<h2>جمعِ هر قابلیت</h2><div class="w"><table><tr><th>قابلیت</th><th>درخواستِ پولی</th><th>امتیازِ مصرفی</th><th>درخواستِ رایگان بعد از سقف</th></tr>${ft || '<tr><td colspan="4">—</td></tr>'}</table></div>
<small>«درخواستِ رایگان بعد از سقف» = چند بار کاربری که امتیازش تمام شده بی‌صدا با مدل رایگان جواب گرفته؛ ترجمه‌ها در این عدد با ML Kit گوشی هم می‌روند ولی فقط درخواست‌هایی که به Worker رسیده‌اند شمرده می‌شوند.
ساعتِ همه‌ی زمان‌ها UTC است و امتیازها اولِ هر ماهِ UTC صفر می‌شوند.</small></html>`;
    return new Response(html, { headers: { "Content-Type": "text/html; charset=utf-8" } });
  } catch (e) {
    return plain("error: " + String(e), 500);
  }
}
