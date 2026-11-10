// ---------------------------------------------------------------------------
// 💎 محتوای پولی (لغاتِ بعد از ۳۰ام + مکالمه‌های کامل) — فقط برای Pro/VIP
//
// داده در D1 (TR_DB) است؛ با `scripts/build-paid-content.mjs` + workflowِ seed-paid-content ریخته می‌شود:
//   paid_words(list, chunk, data)      تکه‌های JSONِ لغات
//   paid_conversations(kind, idx, …)   یک موضوع در هر ردیف
//   content_meta(key, version, count)  نسخه‌ی هر مجموعه (برای کشِ گوشی)
//
//   GET /api/content/manifest                      → {items:{"words:slang":{version,count}, …}}
//   GET /api/content/words?list=daily|slang|vocab  → {version, words:[…]}
//   GET /api/content/conversations?kind=daily|thematic → {version, topics:[…]}
//   GET /api/content/conversation?id=<شناسه>        → {version, topic:{…}}   (لود تنبل: فقط یک موضوع)
//   پارامترِ اختیاریِ v=<نسخه‌ی کشِ گوشی>: اگر یکی باشد فقط {notModified:true, version} برمی‌گردد.
// غیرِ Pro: 403 {code:"pro_required"}
// ---------------------------------------------------------------------------
import { isPro } from "./usage.js";

const WORD_LISTS = new Set(["daily", "slang", "vocab"]);
const CONV_KINDS = new Set(["daily", "thematic"]);
const MSG_FA = "این محتوا مخصوص نسخه‌ی Pro است.";

function jsonResp(body, status, cors) {
  return new Response(typeof body === "string" ? body : JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "private, no-store",
      ...cors,
    },
  });
}

async function metaOf(env, key) {
  return env.TR_DB.prepare("SELECT version, count FROM content_meta WHERE key = ?1")
    .bind(key)
    .first();
}

export async function handleContent(request, env, url, cors, session) {
  if (request.method !== "GET") return jsonResp({ error: "method not allowed" }, 405, cors);
  if (!(await isPro(env, session.sub, session.em))) {
    return jsonResp({ error: MSG_FA, code: "pro_required" }, 403, cors);
  }
  if (!env.TR_DB) return jsonResp({ error: "content store unavailable", code: "not_ready" }, 503, cors);

  try {
    const path = url.pathname;

    if (path === "/api/content/manifest") {
      const { results } = await env.TR_DB.prepare(
        "SELECT key, version, count FROM content_meta"
      ).all();
      const items = {};
      for (const r of results || []) items[r.key] = { version: r.version, count: r.count };
      return jsonResp({ items }, 200, cors);
    }

    const have = (url.searchParams.get("v") || "").trim();

    if (path === "/api/content/words") {
      const list = url.searchParams.get("list") || "";
      if (!WORD_LISTS.has(list)) return jsonResp({ error: "bad list" }, 400, cors);
      const meta = await metaOf(env, "words:" + list);
      if (!meta) return jsonResp({ error: "content not seeded", code: "not_ready" }, 503, cors);
      if (have && have === meta.version) return jsonResp({ notModified: true, version: meta.version }, 200, cors);
      const { results } = await env.TR_DB.prepare(
        "SELECT data FROM paid_words WHERE list = ?1 ORDER BY chunk"
      ).bind(list).all();
      // هر ردیف یک آرایه‌ی JSON است → بدونِ parse کردنِ دوباره به هم می‌چسبانیم
      const body = (results || [])
        .map((r) => String(r.data).trim().replace(/^\[/, "").replace(/\]$/, ""))
        .filter(Boolean)
        .join(",");
      return jsonResp(`{"version":${JSON.stringify(meta.version)},"words":[${body}]}`, 200, cors);
    }

    if (path === "/api/content/conversations") {
      const kind = url.searchParams.get("kind") || "";
      if (!CONV_KINDS.has(kind)) return jsonResp({ error: "bad kind" }, 400, cors);
      const meta = await metaOf(env, "conv:" + kind);
      if (!meta) return jsonResp({ error: "content not seeded", code: "not_ready" }, 503, cors);
      if (have && have === meta.version) return jsonResp({ notModified: true, version: meta.version }, 200, cors);
      const { results } = await env.TR_DB.prepare(
        "SELECT data FROM paid_conversations WHERE kind = ?1 ORDER BY idx"
      ).bind(kind).all();
      const body = (results || []).map((r) => r.data).join(",");
      return jsonResp(`{"version":${JSON.stringify(meta.version)},"topics":[${body}]}`, 200, cors);
    }

    // 💎 لود تنبل: فقط یک موضوعِ مکالمه (فایلِ هر موضوع ~۲ تا ۱۰ کیلوبایت)
    if (path === "/api/content/conversation") {
      const id = (url.searchParams.get("id") || "").trim();
      if (!/^[a-z0-9-]{1,80}$/.test(id)) return jsonResp({ error: "bad id" }, 400, cors);
      const row = await env.TR_DB.prepare(
        "SELECT version, data FROM paid_conv_topics WHERE id = ?1"
      ).bind(id).first();
      if (!row) return jsonResp({ error: "topic not found", code: "not_found" }, 404, cors);
      if (have && have === row.version) return jsonResp({ notModified: true, version: row.version }, 200, cors);
      return jsonResp(`{"version":${JSON.stringify(row.version)},"topic":${row.data}}`, 200, cors);
    }

    return jsonResp({ error: "not found" }, 404, cors);
  } catch (e) {
    console.log("content error", String(e));
    return jsonResp({ error: "content error", code: "not_ready" }, 503, cors);
  }
}
