// ---------------------------------------------------------------------------
// 🗄️ /api/tr-share — کشِ مشترکِ ترجمه‌های اصلاح‌شده‌ی کاربرها
//   op "get": { items: [{text}], source_lang_code, target_lang_code } → { results: [string|null, ...] }
//   op "put": { text, translation, source_lang_code, target_lang_code } → { ok: true }
// از همان جدول و همان کلیدِ /api/translate-text (gen_cache) استفاده می‌کند؛ پس
// translate-text هم ترجمه‌ی اصلاح‌شده را می‌بیند. هیچ AI صدا زده نمی‌شود (هزینه‌ی صفر).
// ردیف‌های این مسیر provider = "user" دارند (برای پاک‌سازی: DELETE FROM gen_cache WHERE provider='user').
// ---------------------------------------------------------------------------

const LANGS = new Set(["fa", "en", "it", "hi", "tr", "ar", "es", "de", "fr", "zh", "ko", "ru", "ja"]);
const MAX_TEXT = 300;      // مثلِ سقفِ /api/translate-text: متنِ بلندِ کاربر وارد کشِ مشترک نمی‌شود
const MAX_TRANSLATION = 1200;
const MAX_BATCH = 40;

function resp(data, status, cors) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...cors },
  });
}

function norm(body) {
  const target = String(body?.target_lang_code ?? "").toLowerCase();
  const source = String(body?.source_lang_code ?? "auto").toLowerCase() || "auto";
  if (!LANGS.has(target)) return null;
  if (source !== "auto" && !LANGS.has(source)) return null;
  return { source, target };
}

export async function handleTrShare(request, env, ctx, cors, deps) {
  const { genCacheKey, genCacheGet, genCachePut } = deps;
  let body;
  try {
    body = await request.json();
  } catch {
    return resp({ error: "Invalid JSON body" }, 400, cors);
  }
  const lp = norm(body);
  if (!lp) return resp({ error: "unsupported language" }, 400, cors);
  const { source, target } = lp;
  const keyOf = (text) => genCacheKey(`translate-text|${source}|${target}|${text}`, 0);

  if (body.op === "get") {
    const items = Array.isArray(body.items) ? body.items.slice(0, MAX_BATCH) : [];
    const results = await Promise.all(
      items.map(async (it) => {
        const text = String(it?.text ?? "").trim();
        if (!text || text.length > MAX_TEXT) return null;
        return (await genCacheGet(env, await keyOf(text))) || null;
      })
    );
    return resp({ results }, 200, cors);
  }

  if (body.op === "put") {
    const text = String(body.text ?? "").trim();
    const tr = String(body.translation ?? "").trim();
    if (!text || text.length > MAX_TEXT) return resp({ error: "bad text" }, 400, cors);
    if (!tr || tr.length > MAX_TRANSLATION) return resp({ error: "bad translation" }, 400, cors);
    if (source === target) return resp({ ok: false, skipped: "same-language" }, 200, cors);
    if (tr.toLowerCase() === text.toLowerCase()) return resp({ ok: false, skipped: "same-as-source" }, 200, cors);
    if (!/\p{L}/u.test(tr)) return resp({ ok: false, skipped: "no-letters" }, 200, cors);
    // نسبتِ طول (برای متن‌های بلندتر از ۲۰ نویسه؛ CJK کوتاه‌تر است)
    if (text.length >= 20) {
      const ratio = tr.length / text.length;
      if (ratio < 0.15 || ratio > 6) return resp({ ok: false, skipped: "bad-ratio" }, 200, cors);
    }
    await genCachePut(env, await keyOf(text), tr, "user");
    return resp({ ok: true }, 200, cors);
  }

  return resp({ error: "unknown op" }, 400, cors);
}
