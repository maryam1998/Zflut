// ---------------------------------------------------------------------------
// LingoLearn — Cloudflare Worker backend
// مسیر این فایل باید دقیقاً src/index.js باشه (طبق wrangler.toml).
// ---------------------------------------------------------------------------

import { handleTranscribe } from "./transcribe.js";
import { handleWordExample } from "./examples.js";
import { authGate, handleSession, verifySessionToken, handleDevices, handleDevicesLogoutAll } from "./auth.js";
import { handleUsage, featureOf, aiMissGate } from "./usage.js";
import { handleContent } from "./content.js";
import { recordUsage, handleAdminReport, handleAdminCredits } from "./metrics.js";
import { beginAi } from "./load.js";
import { handleTrShare } from "./trshare.js";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, X-App-Token, Authorization, X-Feature, X-Use-Id, X-Device-Id, X-Device-Type, X-Device-Model",
};

export default {
  // 🧹 پاک‌سازیِ هفتگیِ کش (cron در wrangler.toml): فقط ردیف‌های قدیمی‌تر از ۳ سال؛ ترجمه‌های اصلاح‌شده‌ی کاربرها (provider='user') هیچ‌وقت پاک نمی‌شوند.
  async scheduled(event, env, ctx) {
    if (!env.TR_DB) return;
    ctx.waitUntil(
      (async () => {
        try {
          await genCacheInit(env);
          await env.TR_DB.prepare("DELETE FROM gen_cache WHERE created < ?1 AND (provider IS NULL OR provider != 'user')")
            .bind(Date.now() - GEN_CACHE_PURGE_MS)
            .run();
        } catch (e) {
          console.error("[gen_cache purge]", e && e.message);
        }
      })()
    );
  },

  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { headers: CORS_HEADERS });
    }

    if (url.pathname === "/" && request.method === "GET") {
      return json({ ok: true, message: "Phrasebook backend is running" });
    }

    if (url.pathname === "/health" && request.method === "GET") {
      return json({
        ok: true,
        providers: getProviderChain(env),
        hfTts: {
          fa: hfTtsConfigStatus(env, "fa"),
          ar: hfTtsConfigStatus(env, "ar"),
        },
      });
    }

    // 📊 پنلِ گزارشِ مصرفِ AI (با ADMIN_KEY؛ جدا از /api/*)
    if (url.pathname === "/admin/usage-report" && request.method === "GET") {
      return handleAdminReport(request, env, url);
    }
    // 🪙 پنلِ امتیازهای ماهانه (Metrics): مصرفِ هر کاربر + زمانِ رسیدن به سقف
    if (url.pathname === "/admin/credits" && request.method === "GET") {
      return handleAdminCredits(request, env, url);
    }

    // 🔐 ورود: توکنِ Supabase → توکنِ نشستِ امضاشده (فقط همین مسیر بدونِ X-App-Token است)
    if (url.pathname === "/api/session" && request.method === "POST") {
      return handleSession(request, env, CORS_HEADERS);
    }

    // 🔒 دستگاه‌های متصل (لیست) و «خروج از همه‌ی دستگاه‌ها» (با کدِ ایمیل)
    if (url.pathname === "/api/devices" && request.method === "GET") {
      return handleDevices(request, env, CORS_HEADERS);
    }
    if (url.pathname === "/api/devices/logout-all" && request.method === "POST") {
      return handleDevicesLogoutAll(request, env, CORS_HEADERS);
    }

    // 💎 وضعیتِ سهمیه‌ی رایگان / شروعِ یک استفاده (بدونِ شمارشِ سهمیه‌ی روزانه)
    if ((url.pathname === "/api/use" && request.method === "POST") ||
        (url.pathname === "/api/usage" && request.method === "GET")) {
      const sess = await verifySessionToken(env, request.headers.get("X-App-Token"));
      if (!sess) return new Response(JSON.stringify({ error: "login required" }), {
        status: 401, headers: { "Content-Type": "application/json", ...CORS_HEADERS } });
      return handleUsage(request, env, url, CORS_HEADERS, sess);
    }

    // 💎 محتوای پولی (فقط Pro) — توکنِ نشست + چکِ پلن داخلِ handleContent
    if (url.pathname.startsWith("/api/content/")) {
      const sess = await verifySessionToken(env, request.headers.get("X-App-Token"));
      if (!sess) return new Response(JSON.stringify({ error: "login required" }), {
        status: 401, headers: { "Content-Type": "application/json", ...CORS_HEADERS } });
      return handleContent(request, env, url, CORS_HEADERS, sess);
    }

    // 🔐 همه‌ی بقیه‌ی /api/* نیاز به توکنِ نشست + سهمیه‌ی روزانه‌ی هر کاربر دارند
    if (url.pathname.startsWith("/api/")) {
      const denied = await authGate(request, env, url, CORS_HEADERS);
      if (denied) return denied;
    }

    // 📊 ثبتِ مصرف (فقط شمارش؛ تبدیلِ گفتار و ترجمه‌ی زیرنویس)
    if (request.method === "POST" &&
        (url.pathname === "/api/transcribe" || url.pathname === "/api/translate-subtitles")) {
      ctx.waitUntil(recordUsage(env, request, {
        feature: url.pathname === "/api/transcribe" ? "stt" : "ytsub", provider: "n/a" }));
    }

    // 🧩 مثال‌سازِ مشترکِ Pro (کشِ سراسریِ مثال‌ها در D1؛ AI فقط وقتی مثالِ تازه لازم است)
    if (url.pathname === "/api/word-example") {
      const sess = await verifySessionToken(env, request.headers.get("X-App-Token"));
      if (!sess) return json({ error: "login required" }, 401);
      return handleWordExample(request, env, ctx, CORS_HEADERS, sess, {
        buildPrompt: buildExamplePrompt,
        getProviderChain, getFreeChainFor, callProvider, withTimeout, sanitizeAiText, badAiOutputReason, recordUsage,
        beginAi: (kind, opts) => beginAi(request, env, kind, CORS_HEADERS, opts),
      });
    }

    // ⭐ NEW: تبدیل صدا به متن با Whisper (Cloudflare Workers AI)
    if (url.pathname === "/api/transcribe" && request.method === "POST") {
      // ⚖️ همزمانیِ Pro + سقفِ سراسریِ روزانه‌ی Whisper
      const gate = await beginAi(request, env, "whisper", CORS_HEADERS);
      if (gate.deny) return gate.deny;
      try {
        return await handleTranscribe(request, env);
      } finally {
        await gate.release();
      }
    }

    // 🔇 TTS آنلاین حذف شد (هزینه + مجوز). صدا فقط آفلاین: بسته‌ی صوتی اپ یا TTS خودِ گوشی.
    if (url.pathname === "/api/tts" || url.pathname === "/api/tts-gemini") {
      return json({ error: "online TTS removed; use offline voice", code: "tts_removed" }, 410);
    }

    if (url.pathname === "/api/youtube-captions" && request.method === "GET") {
      const videoId = (url.searchParams.get("videoId") || "").trim();
      const lang = (url.searchParams.get("lang") || "en").trim();
      if (!videoId) return json({ error: "videoId is required" }, 400);
      if (!/^[A-Za-z0-9_-]{5,32}$/.test(videoId) || !/^[A-Za-z0-9_-]{1,16}$/.test(lang)) {
        return json({ error: "invalid videoId or lang" }, 400);
      }
      try {
        const result = await fetchYoutubeCaptions(videoId, lang, env);
        return json(result);
      } catch (e) {
        return json({ ok: false, error: e.message || "Could not fetch captions", noCaptions: !!e.noCaptions }, 502);
      }
    }

    // 📺 ترجمه‌ی زیرنویس یوتیوب به‌صورت chunk (چند خط + جمله‌های همسایه به‌عنوان زمینه)
    if (url.pathname === "/api/translate-subtitles" && request.method === "POST") {
      let body;
      try {
        body = await request.json();
      } catch {
        return json({ error: "Invalid JSON body" }, 400);
      }
      try {
        return json(await translateSubtitleChunk(body, env, ctx,
          () => beginAi(request, env, "ai", CORS_HEADERS, { queue: false })));
      } catch (e) {
        if (e && e.gateResponse) return e.gateResponse; // سقفِ سراسریِ روزانه
        return json({ error: e.message || "subtitle translation failed" }, 502);
      }
    }

    // 📺 وقتی MediaSession آی‌دی ویدیو نمی‌ده، از روی عنوان (+مدت و کانال) آی‌دی رو پیدا می‌کنه
    if (url.pathname === "/api/youtube-resolve" && request.method === "GET") {
      const title = (url.searchParams.get("title") || "").trim().slice(0, 200);
      const channel = (url.searchParams.get("channel") || "").trim().slice(0, 100);
      const durationSec = Number(url.searchParams.get("durationSec") || 0) || 0;
      if (!title) return json({ error: "title is required" }, 400);
      try {
        return json(await resolveYoutubeVideoId(title, channel, durationSec));
      } catch (e) {
        return json({ error: e.message || "could not resolve video" }, 502);
      }
    }

    // 🗄️ ترجمه‌ی متنِ کوتاه با کشِ مشترکِ همه‌ی کاربرها (اپ اول همین را صدا می‌زند)
    if (url.pathname === "/api/translate-text" && request.method === "POST") {
      return handleTranslateText(request, env, ctx);
    }

    // 📦 ترجمه‌ی دسته‌ایِ متن‌های کوتاه (تا ۲۰ تا در یک درخواست): کش‌ها همان‌جا جواب می‌گیرند، فقط کش‌نشده‌ها با «یک» تماسِ AI
    if (url.pathname === "/api/translate-batch" && request.method === "POST") {
      return handleTranslateBatch(request, env, ctx);
    }

    // 🗄️ کشِ مشترکِ ترجمه‌های اصلاح‌شده (↻ کاربرها) — بدونِ AI، فقط D1
    if (url.pathname === "/api/tr-share" && request.method === "POST") {
      return handleTrShare(request, env, ctx, CORS_HEADERS, { genCacheKey, genCacheGet, genCachePut, trCacheKey });
    }

    if (url.pathname === "/api/generate" && request.method === "POST") {
      let body;
      try {
        body = await request.json();
      } catch {
        return json({ error: "Invalid JSON body" }, 400);
      }
      const { prompt, maxTokens } = body || {};
      if (!prompt || typeof prompt !== "string") {
        return json({ error: "prompt (string) is required" }, 400);
      }
      const capped = Math.min(Math.max(Number(maxTokens) || 1000, 1), 8192);
      // 🔒 سقفِ طولِ پرامپت (هزینه‌ی توکنِ ورودی). env.MAX_PROMPT_CHARS قابلِ تنظیم؛ پیش‌فرض ۳۰٬۰۰۰ نویسه.
      const maxPrompt = Number(env.MAX_PROMPT_CHARS) > 0 ? Number(env.MAX_PROMPT_CHARS) : 30000;
      if (prompt.length > maxPrompt) return json({ error: "prompt too long", code: "prompt_too_long", max: maxPrompt }, 413);

      // کشِ مشترکِ D1: همان پرامپت (با همان سقفِ توکن) دوباره به هوش مصنوعی نمی‌رود.
      // برای «مثالِ جدید/بازتولید» کلاینت می‌تواند { "noCache": true } بفرستد.
      const useCache = !body.noCache;
      const cacheKey = useCache ? await genCacheKey(prompt, capped) : null;
      if (cacheKey) {
        const hit = await genCacheGet(env, cacheKey);
        if (hit) {
          ctx.waitUntil(recordUsage(env, request, { feature: "other", provider: "cache", cached: true }));
          return json({ text: hit, provider: "cache", cached: true });
        }
      }

      // 🌐 درخواستِ بدونِ X-Feature معتبر (ترجمه/تأیید/کلاینتِ دست‌ساز) فقط وقتی که کش جواب نداشت سقفِ روزانه‌ی خودش را مصرف می‌کند
      if (!featureOf(request, url)) {
        const over = await missGate(request, env);
        if (over) return over;
      }

      // ⚖️ همزمانیِ Pro (حداکثر ۲ هم‌زمان، بقیه در صفِ FIFO) + سقفِ سراسریِ روزانه — فقط وقتی کش جواب نداشت
      const gate = await beginAi(request, env, "ai", CORS_HEADERS);
      if (gate.deny) return gate.deny;
      try {
        // 🎚️ زنجیره‌ی ارزان برای کارهای ساده (چت/تصحیح/گرامر/ترجمه/...) و زنجیره‌ی
        // قوی فقط برای داستان؛ اگر AI_PROVIDER_LIGHT / AI_PROVIDER_STRONG ست نشده
        // باشد همان AI_PROVIDER قبلی استفاده می‌شود (رفتارِ فعلی بدونِ تغییر).
        // 🪙 امتیازِ ماهانه تمام شده؟ (gate.degraded) → بی‌صدا فقط مدل‌های رایگان؛ بدونِ هیچ پیامی برای کاربر
        const feat = featureOf(request, url);
        const chain = gate.degraded ? getFreeChainFor(env, feat) : getProviderChainFor(env, feat);
        const errors = [];
        // سقفِ زمانِ هر پرووایدر: یکی که کند/بی‌صدا شد، کلِ درخواست را معطل نکند و
        // زنجیره سریع برود سراغِ بعدی. متنِ کوتاه ≈ ۵ ثانیه؛ متنِ بلند (داستان) بیشتر.
        const perProviderMs = Math.min(45000, 4000 + capped * 10);
        for (const provider of chain) {
          try {
            const raw = await withTimeout(callProvider(provider, prompt, capped, env), perProviderMs, provider);
            // خروجیِ «فکرکردن»/«گارد (User Safety: safe)»/پرامپتِ برگشتی جواب نیست؛
            // به‌جای فرستادنش به اپ، همین‌جا رد می‌شود و پرووایدرِ بعدی امتحان می‌شود.
            const text = sanitizeAiText(raw);
            const bad = badAiOutputReason(text, prompt);
            if (bad) throw new Error(`unusable output (${bad})`);
            // خروجیِ مدلِ رایگان در کشِ مشترکِ همه‌ی کاربرها نوشته نمی‌شود (کیفیتِ کمتر نباید به بقیه برسد)
            if (cacheKey && !gate.degraded) ctx.waitUntil(genCachePut(env, cacheKey, text, provider));
            ctx.waitUntil(recordUsage(env, request, { feature: "other", provider, cached: false, prompt, text }));
            return json({ text, provider });
          } catch (e) {
            errors.push(`${provider}: ${e.message}`);
          }
        }
        console.error("[AI-FAIL] /api/generate همه‌ی پرووایدرها خطا دادند:", errors.join(" | ").slice(0, 900));
        return json({ error: errors.join(" | ") }, 502);
      } finally {
        await gate.release();
      }
    }

    return json({ error: "Not found" }, 404);
  },
};

// پرامپتِ مثال‌ساز (همان متنِ پرامپتِ اپ در word_examples.dart)
function buildExamplePrompt({ word, lang, meaning, nativeLabel, used }) {
  const langNames = { en: "English", fa: "Persian", ar: "Arabic", de: "German", fr: "French", es: "Spanish", it: "Italian", tr: "Turkish", ru: "Russian" };
  const langLabel = langNames[lang.split("-")[0]] || lang;
  const avoid = used.length
    ? "Do NOT reuse or closely paraphrase any of these already-used examples for this same word:\n" +
      used.slice(0, 20).map((u, i) => `${i + 1}. ${String(u).slice(0, 300)}`).join("\n") + "\n\n"
    : "";
  const mean = meaning ? ` (its ${nativeLabel || "native-language"} meaning is: "${meaning}")` : "";
  return (
    `Write exactly ONE natural example sentence in ${langLabel} that uses the word/expression "${word}"${mean} ` +
    "in a way that reflects REAL, current, everyday usage — the kind of sentence a native speaker might actually say or write today. " +
    "Avoid textbook-sounding, generic sentences. " +
    "Keep it natural length (roughly 8-20 words), grammatically correct, and appropriate for a language learner to study.\n\n" +
    `${avoid}Respond with ONLY the example sentence itself in ${langLabel} — no quotes, no translation, no numbering, no explanation, nothing else.`
  );
}

// سقفِ روزانه‌ی درخواست‌های کش‌نشده‌ی بدونِ بخش (ترجمه). فقط در AUTH_MODE=on اعمال می‌شود.
async function missGate(request, env) {
  if (String(env.AUTH_MODE || "on").toLowerCase() !== "on") return null;
  const sess = await verifySessionToken(env, request.headers.get("X-App-Token"));
  return sess ? aiMissGate(env, sess.sub, CORS_HEADERS, sess.em) : null;
}

// --- /api/translate-text -----------------------------------------------------
// ورودی: { text, source_lang_code ("auto" هم می‌شود), target_lang_code } → خروجی: { text, provider, cached }
// کش: همان جدولِ gen_cache (کلیدِ جدا از پرامپت‌های generate). مسیر/زنجیره‌ی پرووایدرها مثلِ generate است.
const TT_LANGS = {
  fa: "Persian", en: "English", it: "Italian", hi: "Hindi", tr: "Turkish", ar: "Arabic",
  es: "Spanish", de: "German", fr: "French", zh: "Chinese", ko: "Korean", ru: "Russian", ja: "Japanese",
};

// 🔌 قطع‌کننده‌ی مدار (per-isolate): پرووایدری که پشتِ‌هم خطا بدهد چند ثانیه کنار گذاشته می‌شود تا صف پشتِ یک سرویسِ خراب نماند.
//   CB_FAILS (پیش‌فرض ۳) خطای پشتِ‌هم → CB_COOL_MS (پیش‌فرض ۶۰ ثانیه) کنار.
const CB_STATE = new Map();
function numVar(env, key, dflt) {
  const raw = env && env[key];
  if (raw === undefined || raw === null || String(raw).trim() === "") return dflt;
  const v = Number(raw);
  return Number.isFinite(v) && v >= 0 ? v : dflt;
}
function cbOpen(p) {
  const s = CB_STATE.get(p);
  return !!(s && s.until > Date.now());
}
function cbOk(p) {
  CB_STATE.delete(p);
}
function cbFail(env, p) {
  const s = CB_STATE.get(p) || { fails: 0, until: 0 };
  s.fails++;
  if (s.fails >= numVar(env, "CB_FAILS", 3)) {
    s.until = Date.now() + numVar(env, "CB_COOL_MS", 60000);
    s.fails = 0;
    console.warn(`[CB] provider=${p} کنار گذاشته شد`);
  }
  CB_STATE.set(p, s);
}

// 🤝 ادغامِ درخواست‌های هم‌زمانِ یک متن (per-isolate): ۵۰ نفر همزمان یک جمله → فقط «یک» تماسِ AI؛ بقیه منتظرِ همان نتیجه می‌مانند.
const TT_INFLIGHT = new Map();

async function handleTranslateText(request, env, ctx) {
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }
  const text = String(body?.text ?? "").trim();
  const target = String(body?.target_lang_code ?? "").toLowerCase();
  const source = String(body?.source_lang_code ?? "auto").toLowerCase() || "auto";
  const native = nativeLang(body); // زبانِ بومیِ کاربر (اختیاری) — برای نمایش‌ندادنِ رومی‌سازیِ زبانِ خودش
  if (!text) return json({ error: "text is required" }, 400);
  if (text.length > 300) return json({ error: "text too long" }, 400);
  // 🕵️ پیش‌نویسِ مشکوکِ رایگان (ML Kit/مترجمِ آنلاین) از اپ: اگر باشد، AI «بازبینی/اصلاح» می‌کند نه ترجمه از صفر
  const draft = String(body?.draft ?? "").trim().slice(0, 600);
  if (!TT_LANGS[target]) return json({ error: "unsupported target language" }, 400);
  if (source !== "auto" && !TT_LANGS[source]) return json({ error: "unsupported source language" }, 400);

  const cacheKey = await trCacheKey(env, source, target, text);
  const level = parseLevel(body?.level);
  const context = cleanCtx(body?.context);
  const nextLine = cleanCtx(body?.next);
  // 🔁 ↻ کاربر: ترجمه‌ی ردشده (reject) را به مدل می‌گوییم و کش را دور می‌زنیم. سقفِ بازتولید برای هر متن (TR_REJECT_MAX در ۲۴ ساعت،
  //    برای همه‌ی کاربرها) تا هزینه بالا نرود؛ بعد از سقف همان ترجمه‌ی کش برمی‌گردد (confirmed). نتیجه‌ی تازه جای ردیفِ قدیمیِ کش می‌نشیند.
  const reject = String(body?.reject ?? "").trim().slice(0, 600);
  if (reject) {
    const cur = await genCacheGet(env, cacheKey);
    if (cur && cur.trim() !== reject) {
      // کسی قبلاً اصلاحش کرده؛ همان را بده (بدونِ AI)
      return json({ text: cur, provider: "cache", cached: true, ...(await romanField(env, target, native, cur)) });
    }
    if (cur && !(await rejectBudget(env, cacheKey))) {
      return json({ text: cur, provider: "cache", cached: true, confirmed: true, ...(await romanField(env, target, native, cur)) });
    }
    const { resp } = await translateLeader(request, env, ctx, { text, target, source, cacheKey, draft: "", native, level, context, nextLine, reject: cur ? reject : "" });
    return resp;
  }
  const hit = await genCacheGet(env, cacheKey);
  if (hit) {
    ctx.waitUntil(recordUsage(env, request, { feature: "translate", provider: "cache", cached: true }));
    return json({ text: hit, provider: "cache", cached: true, ...(await romanField(env, target, native, hit)) });
  }

  // 🤝 اگر همین متن همین الان در همین isolate در حالِ ترجمه است، منتظرِ همان بمان (بدونِ مصرفِ سهمیه/AI)
  const pending = TT_INFLIGHT.get(cacheKey);
  if (pending) {
    try {
      const r = await pending;
      ctx.waitUntil(recordUsage(env, request, { feature: "translate", provider: "cache", cached: true }));
      return json({ text: r.text, provider: r.provider, cached: true, coalesced: true, ...(await romanField(env, target, native, r.text, r.roman)) });
    } catch {
      // رهبر شکست خورد/رد شد → خودمان امتحان می‌کنیم (سهمیه‌ی خودمان را هم می‌دهیم)
    }
  }
  let settle, fail;
  const flight = new Promise((res, rej) => { settle = res; fail = rej; });
  flight.catch(() => {});
  TT_INFLIGHT.set(cacheKey, flight);
  let lease = null;
  try {
    // 🤝 بین‌isolate: اگر isolateِ دیگری همین متن را همین الان ترجمه می‌کند، منتظرِ کشِ او بمان (بدونِ AI و سهمیه)
    lease = await trLeaseAcquire(env, [cacheKey]);
    if (!lease.owned.has(cacheKey)) {
      const got = await trWaitCache(env, [cacheKey]);
      const v = got.get(cacheKey);
      if (v) {
        settle({ text: v, provider: "cache" });
        ctx.waitUntil(recordUsage(env, request, { feature: "translate", provider: "cache", cached: true }));
        return json({ text: v, provider: "cache", cached: true, coalesced: true, ...(await romanField(env, target, native, v)) });
      }
      // رهبر شکست خورد/دیر کرد → خودمان امتحان می‌کنیم (بدونِ قفل؛ fail-open)
    }
    const { resp, result } = await translateLeader(request, env, ctx, { text, target, source, cacheKey, draft, native, level, context, nextLine });
    if (result) settle(result); else fail(new Error("leader-failed"));
    return resp;
  } catch (e) {
    fail(e);
    throw e;
  } finally {
    TT_INFLIGHT.delete(cacheKey);
    await trLeaseRelease(env, lease);
  }
}

async function translateLeader(request, env, ctx, { text, target, source, cacheKey, draft = "", native = "", level = "", context = "", nextLine = "", reject = "" }) {
  const none = (resp) => ({ resp, result: null });

  // 🌐 فقط ترجمه‌ی کش‌نشده (واقعاً AI) از سقفِ روزانه‌ی DAILY_TRANSLATE مصرف می‌کند
  const over = await missGate(request, env);
  if (over) return none(over);
  // ⚖️ سقفِ سراسریِ روزانه (فقط کش‌نشده‌ها؛ بدونِ صف چون ترجمه‌های کوتاه موازی می‌آیند)
  //    افتِ تدریجی: سهمِ رزروِ Pro، و pct برای خاموش‌کردنِ بازبینی در بار بالا
  const capGate = await beginAi(request, env, "ai", CORS_HEADERS, { queue: false, cost: 1, feature: "translate", silent: "translate" });
  if (capGate.deny) return none(capGate.deny);

  const label = TT_LANGS[target];
  const romanTarget = romanOn(env, target);
  // 🔤 زبان‌های غیرلاتین: خروجی JSON {"t": ترجمه, "r": رومی‌سازی}؛ بقیه مثلِ قبل «فقط متنِ ترجمه»
  const tail = romanTarget
    ? `Respond with ONLY a JSON object {"t":"<the translation>","r":"<its romanization>"} — "t" is the ${label} translation itself (no quotes around it, no explanation, no original text); ` +
      `"r" is the romanization of that same translation in Latin letters only: ${ROMAN_STYLE[target]}. Nothing else.`
    : null;
  const idiom = idiomRule(label, level);
  const ctxTxt = ctxLine(context, nextLine);
  const rejectNote = reject
    ? `A learner flagged this earlier ${label} translation as possibly wrong: ${reject}\n` +
      `Translate again carefully from the meaning of the source text. If the earlier translation is in fact correct, output it exactly unchanged; otherwise output the correct translation. `
    : "";
  const prompt = draft
    ? `You are a strict ${label} translation reviewer for a language-learning app.\n` +
      `Source text: ${text}\n` + ctxTxt +
      `Draft ${label} translation (made by a free machine translator, suspected to be literal, unnatural or wrong): ${draft}\n` +
      `If the draft is accurate, complete and natural, output it unchanged. Otherwise output the natural ${label} translation a native speaker would actually say. ` +
      idiom +
      trStyle(target) +
      (tail || "Respond with ONLY the final translation itself — no quotes, no explanation, no original text, nothing else.")
    : `Translate the following text into ${label} by meaning, the way a native speaker would naturally say it. ` +
      idiom + rejectNote +
      trStyle(target) +
      (tail || "Respond with ONLY the translation itself — no quotes, no explanation, no original text, nothing else.") + "\n\n" +
      ctxTxt +
      `Text: ${text}`;
  const maxTokens = romanTarget
    ? Math.min(Math.max(Math.floor(text.length * 1.5) + 224, 320), 1000) // ترجمه + رومی‌سازی + ساختارِ JSON
    : Math.min(Math.max(Math.floor(text.length / 2) + 96, 128), 600);
  // 🧠 ترجمه با مدل‌های قوی‌تر (فقط وقتی AI_PROVIDER_TRANSLATE / *_MODEL_TRANSLATE ست شده)؛ نتیجه در D1 برای همه می‌ماند
  const { chain: trChain, env: trEnv, strong } = translateSetup(env);
  const perProviderMs = Math.min(30000, (strong ? 12000 : 4000) + maxTokens * 10);
  // ⏱️ سقفِ کلِ زمانِ زنجیره (به‌جای جمعِ تایم‌اوتِ همه‌ی پرووایدرها) — زیرِ بارِ زیاد درخواست بی‌نهایت معلق نمی‌ماند
  const budgetMs = numVar(env, "TR_TOTAL_BUDGET_MS", 22000);
  const deadline = Date.now() + budgetMs;
  const errors = [];
  for (const provider of trChain) {
    const left = deadline - Date.now();
    if (left < 1500) { errors.push("budget exhausted"); break; }
    if (cbOpen(provider)) { errors.push(`${provider}: circuit-open`); continue; }
    try {
      // Gemini 2.5 Pro «فکر» می‌کند و فکر از سقفِ توکن کم می‌شود → سقفِ بیشتر تا خروجی خالی نشود
      const mt = strong && provider === "gemini" ? maxTokens + 2000 : maxTokens;
      const raw = await withTimeout(callProvider(provider, prompt, mt, trEnv), Math.min(perProviderMs, left), provider);
      let rawTr = raw;
      let roman = "";
      if (romanTarget) {
        const obj = parseJsonObject(raw);
        if (obj && typeof obj.t === "string") { rawTr = obj.t; roman = typeof obj.r === "string" ? obj.r : ""; }
        else if (/^\s*[{\[]/.test(sanitizeAiText(raw))) throw new Error("unusable output (bad-json)"); // JSON خراب را به‌عنوانِ ترجمه نپذیر
        // مدل JSON نداد و متنِ ساده داد → همان ترجمه است، بدونِ رومی‌سازی
      }
      let out = sanitizeAiText(rawTr).trim();
      // گیومه‌ی دورِ خروجی را بردار
      out = out.replace(/^["“”«»]+|["“”«»]+$/g, "").trim();
      const bad = badAiOutputReason(out, prompt);
      if (bad) throw new Error(`unusable output (${bad})`);
      // 🛡️ قبل از ورود به کشِ مشترکِ همه‌ی کاربرها: خروجی باید واقعاً به زبانِ مقصد باشد
      if (!trScriptOk(target, text, out)) throw new Error("unusable output (wrong-script)");
      roman = romanTarget ? cleanRoman(target, out, roman) : "";
      cbOk(provider);
      // 🔎 بازبینیِ دوم (TR_REVIEW="1") — با «مدل‌های رایگان/ارزان» (AI_PROVIDER_REVIEW)، نه همان مدلِ ترجمه:
      //   • وقتی مصرفِ سراسری ≥ REVIEW_OFF_PCT (پیش‌فرض ۷۰٪) خاموش است (افتِ تدریجی؛ اول بازبینی قطع می‌شود)
      //   • بودجه‌ی زمانیِ محدود (TR_REVIEW_TIMEOUT_MS)؛ هر خطا/تایم‌اوت/خروجیِ مشکوک = همان ترجمه‌ی اول
      const loadHigh = typeof capGate.pct === "number" && capGate.pct >= numVar(env, "REVIEW_OFF_PCT", 70);
      if (String(env.TR_REVIEW || "") === "1" && !loadHigh && !draft) { // با draft خودِ DeepSeek بازبین است؛ بازبینیِ دوم لازم نیست
        const rleft = deadline - Date.now();
        if (rleft > 1500) {
          const reviewed = await trReviewFree(env, text, out, label, target, maxTokens, rleft, level, context);
          if (reviewed !== out) roman = ""; // ترجمه عوض شد → رومی‌سازیِ نسخه‌ی قبلی دیگر درست نیست
          out = reviewed;
        }
      }
      await genCachePut(env, cacheKey, out, provider); // 🤝 قبل از آزادشدنِ اجاره‌ی D1 باید نوشته شده باشد
      if (roman) await genCachePut(env, await trRomanKey(target, out), roman, provider);
      ctx.waitUntil(recordUsage(env, request, { feature: "translate", provider, cached: false, prompt, text: out }));
      return {
        resp: json({ text: out, provider, ...(roman && showRoman(env, target, native) ? { roman } : {}) }),
        result: { text: out, provider, roman },
      };
    } catch (e) {
      cbFail(env, provider);
      errors.push(`${provider}: ${e.message}`);
    }
  }
  console.error("[AI-FAIL] /api/translate-text همه‌ی پرووایدرها خطا دادند:", errors.join(" | ").slice(0, 900));
  return none(json({ error: errors.join(" | ") }, 502));
}

// 📦 /api/translate-batch ------------------------------------------------------
// ورودی: { items: [text, ...≤۲۰ (هر کدام تا ۲۰۰۰ کاراکتر)], source_lang_code, target_lang_code } → { results: [string|null, ...], provider }
// • کش‌ها با «یک» کوئریِ D1 جواب می‌گیرند و هیچ سهمیه‌ای مصرف نمی‌کنند.
// • کش‌نشده‌ها با «یک» تماسِ AI (JSON) ترجمه می‌شوند؛ امتیازِ ماهانه = تعدادِ کش‌نشده‌ها (cost).
// • بازبینی (TR_REVIEW=1) هم «یک» تماسِ دسته‌ایِ رایگان است (مثلِ translate-text؛ در بارِ بالا خاموش).
// • مورد نامعتبر = null (کلاینت همان را تک‌به‌تک امتحان می‌کند).
// • 📖 پاراگراف‌های داستان: هر مورد تا TB_MAX_ITEM_CHARS (پیش‌فرض ۲۰۰۰) کاراکتر؛ مجموعِ متن‌های کش‌نشده‌ی یک درخواست تا
//   TB_MAX_TOTAL_CHARS (پیش‌فرض ۵۰۰۰) — موردهای اضافه null برمی‌گردند (کلاینت در درخواستِ بعدی می‌فرستد).
//   سهمیه = مجموعِ ceil(طول / TB_COST_CHARS) (پیش‌فرض ۳۰۰) برای هر مورد؛ پس متنِ کوتاه مثلِ قبل «۱» حساب می‌شود.
const TB_MAX = 20;

function parseJsonObject(raw) {
  const t = sanitizeAiText(raw).trim().replace(/^```(?:json)?\s*|\s*```$/g, "").trim();
  try { return JSON.parse(t); } catch { /* ادامه */ }
  const m = t.match(/\{[\s\S]*\}/);
  if (m) { try { return JSON.parse(m[0]); } catch { /* ادامه */ } }
  return null;
}

async function handleTranslateBatch(request, env, ctx) {
  let body;
  try { body = await request.json(); } catch { return json({ error: "Invalid JSON body" }, 400); }
  const target = String(body?.target_lang_code ?? "").toLowerCase();
  const source = String(body?.source_lang_code ?? "auto").toLowerCase() || "auto";
  const native = nativeLang(body); // زبانِ بومیِ کاربر (اختیاری) — برای نمایش‌ندادنِ رومی‌سازیِ زبانِ خودش
  if (!TT_LANGS[target]) return json({ error: "unsupported target language" }, 400);
  if (source !== "auto" && !TT_LANGS[source]) return json({ error: "unsupported source language" }, 400);
  const raw = Array.isArray(body?.items) ? body.items.slice(0, TB_MAX) : [];
  const texts = raw.map((x) => String(x ?? "").trim());
  const itemMax = Math.max(300, Math.min(4000, numVar(env, "TB_MAX_ITEM_CHARS", 2000)));
  const valid = texts.map((t) => !!t && t.length <= itemMax && /\p{L}/u.test(t));
  const results = texts.map(() => null);
  // 🕵️ drafts[i] (اختیاری): پیش‌نویسِ مشکوکِ رایگانِ مورد i برای بازبینی/اصلاح ('' = ترجمه از صفر)
  const rawDrafts = Array.isArray(body?.drafts) ? body.drafts.slice(0, TB_MAX) : [];
  const drafts = texts.map((_, i) => String(rawDrafts[i] ?? "").trim().slice(0, 2400));
  // 🎓 levels[i] / contexts[i] (اختیاری): سطحِ جمله و خطِ قبلیِ مکالمه ('' = ندارد)
  const rawLv = Array.isArray(body?.levels) ? body.levels.slice(0, TB_MAX) : [];
  const rawCx = Array.isArray(body?.contexts) ? body.contexts.slice(0, TB_MAX) : [];
  const rawNx = Array.isArray(body?.nexts) ? body.nexts.slice(0, TB_MAX) : [];
  const levels = texts.map((_, i) => parseLevel(rawLv[i]));
  const ctxs = texts.map((_, i) => cleanCtx(rawCx[i]));
  const nxs = texts.map((_, i) => cleanCtx(rawNx[i]));
  if (!valid.some(Boolean)) return json({ results, provider: "none" });

  // ۱) کش: یک کوئری برای همه
  const keys = await Promise.all(texts.map((t, i) => (valid[i] ? trCacheKey(env, source, target, t) : null)));
  const rows = new Map();
  try {
    const uniq = [...new Set(keys.filter(Boolean))];
    if (env.TR_DB && uniq.length) {
      await genCacheInit(env);
      const ph = uniq.map((_, i) => `?${i + 1}`).join(",");
      const res = await env.TR_DB.prepare(`SELECT k, v FROM gen_cache WHERE k IN (${ph})`).bind(...uniq).all();
      for (const r of res.results || []) rows.set(r.k, r.v);
    }
  } catch { /* کش خراب = همه miss */ }
  let miss = [];
  texts.forEach((t, i) => {
    if (!valid[i]) return;
    const v = rows.get(keys[i]);
    if (v) results[i] = v; else miss.push(i);
  });
  // 📏 سقفِ مجموعِ کاراکترِ کش‌نشده‌ها در یک تماسِ AI (اولین مورد همیشه می‌ماند)
  {
    const totalMax = Math.max(itemMax, numVar(env, "TB_MAX_TOTAL_CHARS", 5000));
    let acc = 0;
    const kept = [];
    for (const idx of miss) {
      const len = texts[idx].length;
      if (kept.length && acc + len > totalMax) continue;
      acc += len;
      kept.push(idx);
    }
    miss = kept;
  }
  if (!miss.length) {
    ctx.waitUntil(recordUsage(env, request, { feature: "translate", provider: "cache", cached: true }));
    const romans = await batchRomans(env, target, native, results);
    return json({ results, provider: "cache", cached: true, ...(romans ? { romans } : {}) });
  }

  // 🤝 ادغامِ هم‌زمان‌ها (بین isolateها): برای هر کلیدِ کش‌نشده اجاره می‌گیریم؛ آن‌هایی که دستِ دیگری است منتظر می‌مانیم (بدونِ AI/سهمیه).
  const lease = await trLeaseAcquire(env, miss.map((idx) => keys[idx]));
  const waitIdx = miss.filter((idx) => !lease.owned.has(keys[idx]));
  miss = miss.filter((idx) => lease.owned.has(keys[idx]));
  const waitP = waitIdx.length ? trWaitCache(env, waitIdx.map((idx) => keys[idx])) : null;
  const mergeWaited = async () => {
    if (!waitP) return;
    const got = await waitP;
    for (const idx of waitIdx) { const v = got.get(keys[idx]); if (v) results[idx] = v; } // نرسیده = null (اپ بی‌صدا ML Kit/تلاشِ بعدی)
  };
  if (!miss.length) {
    await mergeWaited();
    ctx.waitUntil(recordUsage(env, request, { feature: "translate", provider: "cache", cached: true }));
    const romans = await batchRomans(env, target, native, results);
    return json({ results, provider: "cache", cached: true, coalesced: true, ...(romans ? { romans } : {}) });
  }
  try {
  // ۲) سهمیه‌ها فقط برای کش‌نشده‌ها
  const over = await missGate(request, env);
  if (over) return over;
  const costChars = Math.max(100, numVar(env, "TB_COST_CHARS", 300));
  const costUnits = miss.reduce((a, idx) => a + Math.max(1, Math.ceil(texts[idx].length / costChars)), 0);
  const capGate = await beginAi(request, env, "ai", CORS_HEADERS,
    { queue: false, cost: costUnits, feature: "translate", silent: "translate" });
  if (capGate.deny) return capGate.deny;

  // ۳) یک تماسِ AI برای همه‌ی کش‌نشده‌ها
  const label = TT_LANGS[target];
  const romanTarget = romanOn(env, target);
  const list = miss.map((idx, n) => {
    const it = { i: n, text: texts[idx] };
    if (drafts[idx]) it.draft = drafts[idx];
    if (levels[idx]) it.level = levels[idx];
    if (ctxs[idx]) it.context = ctxs[idx];
    if (nxs[idx]) it.next = nxs[idx];
    return it;
  });
  const prompt =
    `Translate every item below into ${label} by meaning, the way a native speaker would naturally say it. ` +
    `Idioms, slang, rhyming or fixed expressions and greeting/farewell formulas must be rendered with their real meaning or a natural ${label} equivalent, never word for word. ` +
    (list.some((x) => isBeginner(x.level))
      ? `Exception: items with "level":"A1" or "A2" are simple beginner sentences — translate them plainly and literally as meant in the dialogue; do NOT treat them as idioms or figures of speech unless unmistakably a fixed expression, and never invent another meaning. `
      : "") +
    (list.some((x) => x.context || x.next)
      ? `An item's "context" is the previous line and "next" is the following line of the same dialogue, for understanding only (e.g. to pick the right sense of an ambiguous word such as "run", "play", "right") — never translate or output them. `
      : "") +
    trStyle(target) +
    (list.some((x) => x.draft)
      ? `Items that include a "draft" carry a free machine translation suspected to be literal, unnatural or wrong: review it — keep it unchanged only if it is accurate and natural, otherwise correct it. `
      : "") +
    (romanTarget
      ? `Return ONLY a JSON object {"t":[...],"r":[...]} where both arrays have exactly ${miss.length} strings, in the same order as the items: ` +
        `t[i] is the ${label} translation (no quotes around it, no explanations, no original text) and r[i] is the romanization of that same t[i] in Latin letters only: ${ROMAN_STYLE[target]}.\n\n`
      : `Return ONLY a JSON object {"t":[...]} with exactly ${miss.length} strings (no quotes around them, no explanations, no original text), in the same order as the items.\n\n`) +
    JSON.stringify(list);
  const totalLen = miss.reduce((a, idx) => a + texts[idx].length, 0);
  const maxTokens = Math.min(
    Math.max(totalLen * (romanTarget ? 3 : 1) + (romanTarget ? 120 : 64) * miss.length, 400),
    Math.max(1000, numVar(env, "TB_MAX_TOKENS", 6000)) + (romanTarget ? 2000 : 0)
  );
  const { chain: trChain, env: trEnv, strong } = translateSetup(env);
  const perProviderMs = Math.min(30000, 8000 + maxTokens * 8);
  const deadline = Date.now() + numVar(env, "TB_TOTAL_BUDGET_MS", Math.max(22000, numVar(env, "TR_TOTAL_BUDGET_MS", 22000)));
  const errors = [];
  for (const provider of trChain) {
    const left = deadline - Date.now();
    if (left < 1500) { errors.push("budget exhausted"); break; }
    if (cbOpen(provider)) { errors.push(`${provider}: circuit-open`); continue; }
    try {
      const mt = strong && provider === "gemini" ? maxTokens + 2000 : maxTokens;
      const rawOut = await withTimeout(callProvider(provider, prompt, mt, trEnv), Math.min(perProviderMs, left), provider);
      const obj = parseJsonObject(rawOut);
      const arr = obj && Array.isArray(obj.t) ? obj.t : null;
      if (!arr || arr.length !== miss.length) throw new Error("unusable output (bad-json)");
      const outs = miss.map((idx, n) => {
        let o = typeof arr[n] === "string" ? sanitizeAiText(arr[n]).trim().replace(/^["“”«»]+|["“”«»]+$/g, "").trim() : "";
        if (!o || badAiOutputReason(o, prompt) || !trScriptOk(target, texts[idx], o)) return null;
        if (o.toLowerCase() === texts[idx].toLowerCase() && texts[idx].split(/\s+/).length > 2) return null;
        return o;
      });
      if (!outs.some(Boolean)) throw new Error("unusable output (all-invalid)");
      // 🔤 رومی‌سازیِ هر مورد (r[i]؛ نامعتبر/نبودن = "" و فقط ترجمه می‌ماند)
      const rarr = romanTarget && Array.isArray(obj.r) ? obj.r : [];
      const romAI = outs.map((o, n) => (o && romanTarget ? cleanRoman(target, o, rarr[n]) : ""));
      cbOk(provider);
      // 🔎 بازبینیِ دسته‌ایِ رایگان (بارِ بالا = خاموش)
      const loadHigh = typeof capGate.pct === "number" && capGate.pct >= numVar(env, "REVIEW_OFF_PCT", 70);
      const rleft = deadline - Date.now();
      if (String(env.TR_REVIEW || "") === "1" && !loadHigh && rleft > 1500) {
        const okIdx = outs.map((o, n) => (o ? n : -1)).filter((n) => n >= 0);
        const revised = await trReviewBatchFree(env, okIdx.map((n) => ({ src: texts[miss[n]], out: outs[n], level: levels[miss[n]] })), label, target, maxTokens, rleft);
        okIdx.forEach((n, k) => {
          if (revised[k] !== outs[n]) romAI[n] = ""; // ترجمه عوض شد → رومی‌سازیِ نسخه‌ی قبلی دیگر درست نیست
          outs[n] = revised[k];
        });
      }
      const puts = [];
      const knownRoman = new Map();
      miss.forEach((idx, n) => {
        if (!outs[n]) return;
        results[idx] = outs[n];
        puts.push(genCachePut(env, keys[idx], outs[n], provider));
        if (romAI[n]) {
          knownRoman.set(idx, romAI[n]);
          puts.push(trRomanKey(target, outs[n]).then((k) => genCachePut(env, k, romAI[n], provider)));
        }
      });
      await Promise.all(puts); // 🤝 قبل از آزادشدنِ اجاره‌ها در کش نوشته شود
      await mergeWaited();
      ctx.waitUntil(recordUsage(env, request, { feature: "translate", provider, cached: false, prompt, text: outs.filter(Boolean).join("\n") }));
      const romans = await batchRomans(env, target, native, results, knownRoman);
      return json({ results, provider, ...(romans ? { romans } : {}) });
    } catch (e) {
      cbFail(env, provider);
      errors.push(`${provider}: ${e.message}`);
    }
  }
  console.error("[AI-FAIL] /api/translate-batch همه‌ی پرووایدرها خطا دادند:", errors.join(" | ").slice(0, 900));
  return json({ error: errors.join(" | ") }, 502);
  } finally {
    await trLeaseRelease(env, lease);
  }
}

// 🔎 بازبینیِ دسته‌ایِ ترجمه با مدل‌های رایگان؛ هر خطا/مورد مشکوک = همان ترجمه‌ی اول. خروجی هم‌طولِ ورودی.
async function trReviewBatchFree(env, pairs, label, target, maxTokens, leftMs) {
  const outs = pairs.map((p) => p.out);
  if (!pairs.length) return outs;
  const { chain, env: rEnv } = reviewSetup(env);
  const timeoutMs = Math.min(numVar(env, "TR_REVIEW_TIMEOUT_MS", 3500) * 2, leftMs);
  const rp =
    `You are a strict ${label} translation reviewer. For each item, if the proposed translation is accurate, complete and sounds natural to a native ${label} speaker, return it exactly unchanged; ` +
    `otherwise return a corrected ${label} translation (by meaning; idioms and slang rendered naturally, never word for word). ` +
    (pairs.some((p) => isBeginner(p.level))
      ? `Exception: for items with "level":"A1" or "A2" (simple beginner sentences) change the translation ONLY if it is clearly wrong; a plain, literal, accurate translation must stay exactly unchanged — never rephrase it for style or turn it into an idiom. `
      : "") +
    trStyle(target) +
    `Return ONLY a JSON object {"t":[...]} with exactly ${pairs.length} strings, in the same order, no explanations.\n\n` +
    JSON.stringify(pairs.map((p, i) => (p.level ? { i, level: p.level, source: p.src, translation: p.out } : { i, source: p.src, translation: p.out })));
  let tried = 0;
  for (const provider of chain) {
    if (tried >= 2) break;
    if (cbOpen(provider)) continue;
    tried++;
    try {
      const rawOut = await withTimeout(callProvider(provider, rp, maxTokens, rEnv), timeoutMs, provider);
      const obj = parseJsonObject(rawOut);
      const arr = obj && Array.isArray(obj.t) ? obj.t : null;
      if (!arr || arr.length !== pairs.length) throw new Error("bad-json");
      cbOk(provider);
      return pairs.map((p, i) => {
        const rev = typeof arr[i] === "string" ? sanitizeAiText(arr[i]).trim().replace(/^["“”«»]+|["“”«»]+$/g, "").trim() : "";
        if (!rev || badAiOutputReason(rev, rp) || !trScriptOk(target, p.src, rev)) return p.out;
        if (rev.length > p.out.length * 3 + 60 || rev.length < p.out.length * 0.4) return p.out;
        return rev;
      });
    } catch {
      cbFail(env, provider);
    }
  }
  return outs;
}

// 🛡️ آیا خروجی خطِ زبانِ مقصد را دارد؟ (فقط برای متن‌های ≥ ۲ کلمه؛ اسمِ تکی مثل Netflix می‌تواند بدونِ تغییر بماند)
const TR_SCRIPTS = {
  fa: /[؀-ۿ]/, ar: /[؀-ۿ]/, hi: /[ऀ-ॿ]/, zh: /[一-鿿]/,
  ja: /[぀-ヿ一-鿿]/, ko: /[가-힯]/, ru: /[Ѐ-ӿ]/,
};
function trScriptOk(target, text, out) {
  const re = TR_SCRIPTS[target];
  if (!re) return true;
  if (String(text).trim().split(/\s+/).length < 2) return true;
  if (!/\p{L}/u.test(text)) return true;
  return re.test(out);
}

// 🔤 رومی‌سازی (Romanization) --------------------------------------------------------------------------------
// برای زبان‌هایی که الفبایشان لاتین نیست و کاربر نمی‌تواند بخواندشان (هندی، چینی، ژاپنی، کره‌ای، روسی)، AI «همزمان با ترجمه»
// خوانشِ لاتینِ ترجمه را هم می‌دهد (همان تماسِ AI؛ فقط چند توکنِ بیشتر). TR_ROMAN="0" در wrangler.toml همه را خاموش می‌کند.
//
// 🗄️ کش: رومی‌سازی با کلیدِ «زبانِ مقصد + خودِ متنِ ترجمه‌شده» ذخیره می‌شود (نه متنِ مبدأ). پس اگر ترجمه بعداً اصلاح شد
//    (↻ کاربر / seed)، رومی‌سازیِ قدیمی خودبه‌خود کنار می‌رود و ردیفِ ترجمه (کلیدِ قبلی) دست‌نخورده می‌ماند.
//
// 🙈 نمایش: اگر زبانِ مقصد = زبانِ بومیِ کاربر (native_lang_code در بدنه‌ی درخواست)، رومی‌سازی در پاسخ «نمی‌آید»
//    (کاربرِ هندی که ترجمه‌ی هندی گرفته، دوناگری را می‌خواند). برای کشِ مشترک همیشه تولید و ذخیره می‌شود.
const ROMAN_LANGS = new Set(["hi", "zh", "ja", "ko", "ru"]);
const ROMAN_STYLE = {
  hi: "Hinglish-style Latin spelling as Hindi is typed in English letters, e.g. «aap kaise hain?», «mera naam Ali hai» — plain ASCII, no diacritics",
  zh: "Hanyu Pinyin with tone marks (e.g. «nǐ hǎo»), syllables of the same word joined, words separated by spaces",
  ja: "Hepburn romaji, words separated by spaces, particles written as pronounced (は→wa, を→o, へ→e)",
  ko: "Revised Romanization of Korean as pronounced (e.g. «annyeonghaseyo»), words separated by spaces",
  ru: "simple ASCII transliteration of Russian (ж=zh, х=kh, ц=ts, ч=ch, ш=sh, щ=shch, ы=y, ю=yu, я=ya; no accents or stress marks)",
};
function romanOn(env, target) {
  return ROMAN_LANGS.has(target) && String((env && env.TR_ROMAN) ?? "1") !== "0";
}
function showRoman(env, target, native) {
  return romanOn(env, target) && target !== native;
}
// 🎓 سطح و زمینه‌ی جمله (اختیاری، از اپ): جمله‌های ساده‌ی A1/A2 باید «ساده و تحت‌اللفظیِ درست» ترجمه شوند، نه اصطلاح‌محور.
//    context = خطِ قبلیِ همان مکالمه (فقط برای فهمِ معنی). کلیدِ کش عوض نمی‌شود (کشِ مشترک همان می‌ماند).
function parseLevel(v) {
  const s = String(v ?? "").trim().toUpperCase();
  return /^(A1|A2|B1|B2|C1|C2)$/.test(s) ? s : "";
}
function cleanCtx(v) {
  return String(v ?? "").replace(/[\u0000-\u001f\u007f"]+/g, " ").replace(/\s+/g, " ").trim().slice(0, 200);
}
function isBeginner(level) { return level === "A1" || level === "A2"; }
const IDIOM_EXAMPLE = `(e.g. "See you later, alligator!" is just a playful goodbye: drop the animal and the rhyme). `;
function idiomRule(label, level) {
  if (isBeginner(level)) {
    return `This is a simple beginner-level (${level}) sentence from a dialogue: translate it plainly and literally, as the words are meant in the conversation. ` +
      `Do NOT treat it as an idiom, joke or figure of speech unless it is unmistakably a fixed expression (e.g. "See you later, alligator!"); never invent an extra or different meaning. `;
  }
  return `Idioms, slang, rhyming or fixed expressions and greeting/farewell formulas must be rendered with their real meaning or a natural ${label} equivalent, never word for word ` + IDIOM_EXAMPLE;
}
function ctxLine(context, next = "") {
  return (context ? `Context — the previous line of the same dialogue, for understanding only (do NOT translate or output it): "${context}"\n` : "") +
    (next ? `Context — the next line of the same dialogue, for understanding only (do NOT translate or output it): "${next}"\n` : "");
}
// بازبین برای A1/A2: فقط خطای واقعی را درست کند؛ ترجمه‌ی درست را برای «طبیعی‌تر شدن» یا اصطلاح‌سازی عوض نکند
const BEGINNER_REVIEW = `For simple beginner (A1/A2) sentences, change the translation ONLY if it is clearly wrong (wrong meaning, wrong grammar, wrong language); ` +
  `a plain, literal and accurate translation must be kept exactly unchanged — never rephrase it for style and never turn it into an idiom. `;
function nativeLang(body) {
  const n = String(body?.native_lang_code ?? "").toLowerCase();
  return TT_LANGS[n] ? n : "";
}
async function trRomanKey(target, text) {
  return genCacheKey(`roman|${target}|${text}`, 0);
}
// خروجیِ رومی‌سازیِ AI را بررسی می‌کند؛ نامعتبر = "" (ترجمه همچنان استفاده می‌شود، فقط رومی‌سازی ذخیره/نمایش داده نمی‌شود)
function cleanRoman(target, out, raw) {
  let r = typeof raw === "string" ? sanitizeAiText(raw).trim().replace(/^[\"“”«»]+|[\"“”«»]+$/g, "").trim() : "";
  if (!r || r.length > out.length * 4 + 80) return "";
  if (TR_SCRIPTS[target] && TR_SCRIPTS[target].test(r)) return ""; // هنوز الفبای اصلی دارد = رومی‌سازی نیست
  if (!/[A-Za-z\u00C0-\u024F]/.test(r)) return ""; // حرفِ لاتین ندارد
  if (/&#?\w+;|[{}\[\]]/.test(r)) return "";
  if (r.toLowerCase() === out.toLowerCase()) return ""; // چیزِ جدیدی نیست (مثلِ «OK»)
  return r;
}
// فیلدِ roman برای پاسخِ translate-text ({} یا {roman}). known = رومی‌سازیِ تازه‌ساخته؛ وگرنه از D1 می‌خوانیم.
async function romanField(env, target, native, text, known = "") {
  if (!showRoman(env, target, native)) return {};
  const r = known || (await genCacheGet(env, await trRomanKey(target, text))) || "";
  return r ? { roman: r } : {};
}
// رومی‌سازیِ «دسته‌ای» برای translate-batch: آرایه‌ی هم‌طولِ results ("" = ندارد) یا null اگر نباید نمایش داده شود.
async function batchRomans(env, target, native, results, known = new Map()) {
  if (!showRoman(env, target, native)) return null;
  const romans = results.map((_, i) => known.get(i) || "");
  const need = [];
  results.forEach((r, i) => { if (r && !known.has(i)) need.push(i); });
  if (need.length && env.TR_DB) {
    try {
      const keys = await Promise.all(need.map((i) => trRomanKey(target, results[i])));
      const uniq = [...new Set(keys)];
      await genCacheInit(env);
      const ph = uniq.map((_, i) => `?${i + 1}`).join(",");
      const res = await env.TR_DB.prepare(`SELECT k, v FROM gen_cache WHERE k IN (${ph})`).bind(...uniq).all();
      const m = new Map((res.results || []).map((r) => [r.k, r.v]));
      need.forEach((i, j) => { romans[i] = m.get(keys[j]) || ""; });
    } catch { /* کش خراب = بدونِ رومی‌سازی */ }
  }
  return romans;
}

// 🎨 سبکِ ترجمه به فارسی: یک‌دست، محاوره‌ای‌ملایم و محترمانه؛ نه کلمه‌به‌کلمه، نه رسمی/کتابی در یک جمله و محاوره‌ای در جمله‌ی بعد.
function trStyle(target) {
  if (target !== "fa") return "";
  return (
    "Style for Persian: natural, fluent, everyday spoken Persian of Iran (polite colloquial, e.g. «چطوری؟»، «خوبه»، «می‌کنم»), " +
    "used consistently in every sentence — do not mix stiff bookish forms with colloquial ones, and never translate word for word. " +
    "Pay attention to the exact meaning of every word (e.g. \"together\" = «با هم», \"a little\" = «یه کم / کمی»). "
  );
}

// 🔎 بازبینیِ ترجمه با مدل‌های رایگان/ارزان: «درست و طبیعی است؟ همان را برگردان؛ وگرنه اصلاحش کن».
//   AI_PROVIDER_REVIEW (پیش‌فرض groq,cerebras,llm7,kilocode) و <NAME>_MODEL_REVIEW برای مدلِ بازبین.
//   حداکثر دو بازبین امتحان می‌شود؛ هر مشکلی (خطا، تایم‌اوت، خروجیِ مشکوک) = ترجمه‌ی اول بدونِ تغییر.
const REVIEW_DEFAULT_CHAIN = "groq,cerebras,llm7,kilocode";
function reviewSetup(env) {
  const raw = String(env.AI_PROVIDER_REVIEW || REVIEW_DEFAULT_CHAIN).toLowerCase();
  const chain = raw.split(",").map((p) => p.trim()).filter((p) => VALID_PROVIDERS.includes(p));
  const e = { ...env };
  for (const v of TR_MODEL_VARS) {
    if (env[v + "_REVIEW"]) e[v] = env[v + "_REVIEW"];
  }
  return { chain, env: e };
}

async function trReviewFree(env, text, out, label, target, maxTokens, leftMs, level = "", context = "") {
  const { chain, env: rEnv } = reviewSetup(env);
  const timeoutMs = Math.min(numVar(env, "TR_REVIEW_TIMEOUT_MS", 3500), leftMs);
  let tried = 0;
  for (const provider of chain) {
    if (tried >= 2) break;
    if (cbOpen(provider)) continue;
    tried++;
    try {
      const rev = await trReviewOnce(provider, rEnv, text, out, label, target, timeoutMs, maxTokens, level, context);
      cbOk(provider);
      return rev;
    } catch {
      cbFail(env, provider);
    }
  }
  return out;
}

// خطای پرووایدر (تایم‌اوت، بدونِ کلید، …) را پرتاب می‌کند؛ خروجیِ مشکوک = همان out.
async function trReviewOnce(provider, rEnv, text, out, label, target, timeoutMs, maxTokens, level = "", context = "") {
  const rp =
    `You are a strict ${label} translation reviewer.\n` +
    `Source text: ${text}\n` + ctxLine(context) +
    `Proposed ${label} translation: ${out}\n` +
    `If the translation is accurate, complete and sounds natural to a native ${label} speaker, output it exactly unchanged. ` +
    (isBeginner(level)
      ? BEGINNER_REVIEW
      : `Otherwise output a corrected ${label} translation (by meaning; idioms and slang rendered naturally, never word for word). `) +
    trStyle(target) +
    `Output ONLY the final ${label} text — no quotes, no explanation, nothing else.`;
  const raw = await withTimeout(callProvider(provider, rp, maxTokens, rEnv), timeoutMs, provider);
  const rev = sanitizeAiText(raw).trim().replace(/^["“”«»]+|["“”«»]+$/g, "").trim();
  if (!rev || badAiOutputReason(rev, rp)) return out;
  if (!trScriptOk(target, text, rev)) return out;
  if (rev.length > out.length * 3 + 60) return out;
  if (rev.length < out.length * 0.4) return out; // بازبین نباید ترجمه را به‌شدت کوتاه کند (حذفِ محتوا)
  return rev;
}

// 🧠 زنجیره و مدل‌های «قوی‌تر» برای /api/translate-text.
//   AI_PROVIDER_TRANSLATE = ترتیبِ پرووایدرها (ست‌نشده = همان AI_PROVIDER قبلی)
//   <NAME>_MODEL_TRANSLATE = مدلِ قوی‌ترِ همان پرووایدر فقط برای ترجمه (مثلاً GEMINI_MODEL_TRANSLATE)
// هر پرووایدری که خطا بدهد/کلید نداشته باشد رد می‌شود و بعدی امتحان می‌شود (همان رفتارِ قبلی).
const TR_MODEL_VARS = [
  "GEMINI_MODEL", "MISTRAL_MODEL", "GROQ_MODEL", "NVIDIA_MODEL", "OPENAI_MODEL", "DEEPSEEK_MODEL",
  "OPENROUTER_MODEL", "GROK_MODEL", "CEREBRAS_MODEL", "COHERE_MODEL", "ZAI_MODEL", "CF_AI_MODEL",
];
function translateSetup(env) {
  let chain = null;
  if (env.AI_PROVIDER_TRANSLATE) {
    const c = String(env.AI_PROVIDER_TRANSLATE).toLowerCase().split(",").map((p) => p.trim()).filter((p) => VALID_PROVIDERS.includes(p));
    if (c.length) chain = c;
  }
  const e = { ...env };
  let overridden = false;
  for (const v of TR_MODEL_VARS) {
    if (env[v + "_TRANSLATE"]) { e[v] = env[v + "_TRANSLATE"]; overridden = true; }
  }
  return { chain: chain || getProviderChain(env), env: e, strong: !!chain || overridden };
}

// --- کشِ مشترکِ D1 برای /api/generate (مثال‌ساز و ...) ---------------------
// اگر binding با نام TR_DB تنظیم نشده باشد، همه‌ی این توابع بی‌صدا هیچ‌کاری نمی‌کنند.
// ⏳ دیگر TTLِ زمانی روی «خواندن» نیست: ترجمه تا وقتی متن همان است (کلیدِ هشِ متن) معتبر می‌ماند.
// این عدد فقط برای پاک‌سازیِ ردیف‌های یتیم (cron هفتگی، scheduled پایین) است.
const GEN_CACHE_PURGE_MS = 3 * 365 * 24 * 60 * 60 * 1000; // ۳ سال

// 🔖 نسخه‌ی مدل/پرامپتِ ترجمه (env.TR_MODEL_VERSION). "1" = کلیدِ قدیمی (ردیف‌های فعلیِ D1 معتبر می‌مانند)؛
// هر مقدارِ دیگر (مثلاً "2") کلیدِ همه‌ی ترجمه‌ها را عوض می‌کند → همه دوباره از AI گرفته می‌شوند.
async function trCacheKey(env, source, target, text) {
  const mv = String((env && env.TR_MODEL_VERSION) || "1").trim() || "1";
  const base = `translate-text|${source}|${target}|${text}`;
  return genCacheKey(mv === "1" ? base : `mv${mv}|${base}`, 0);
}
let genCacheReady = false;

async function genCacheKey(prompt, capped) {
  const data = new TextEncoder().encode(JSON.stringify([prompt, capped]));
  const digest = await crypto.subtle.digest("SHA-256", data);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function genCacheInit(env) {
  if (genCacheReady) return;
  await env.TR_DB.prepare(
    "CREATE TABLE IF NOT EXISTS gen_cache (k TEXT PRIMARY KEY, v TEXT NOT NULL, provider TEXT, created INTEGER NOT NULL)"
  ).run();
  genCacheReady = true;
}

async function genCacheGet(env, key) {
  if (!env.TR_DB) return null;
  try {
    await genCacheInit(env);
    const row = await env.TR_DB.prepare("SELECT v, created, provider FROM gen_cache WHERE k = ?1").bind(key).first();
    // ✅ بدونِ انقضای زمانی: کلید = هشِ متن (+ نسخه‌ی مدل)، پس متنِ عوض‌شده خودبه‌خود miss می‌شود
    if (!row) return null;
    return row.v;
  } catch {
    return null;
  }
}

// 🔁 سقفِ بازتولیدِ «ردِ کاربر» برای هر ترجمه (همه‌ی کاربرها با هم): TR_REJECT_MAX بار در ۲۴ ساعت. true = اجازه دارد.
async function rejectBudget(env, cacheKey) {
  if (!env.TR_DB) return true;
  try {
    await genCacheInit(env);
    const k = await genCacheKey(`reject|${cacheKey}`, 0);
    const row = await env.TR_DB.prepare("SELECT v, created FROM gen_cache WHERE k = ?1").bind(k).first();
    const fresh = !!row && Date.now() - row.created < 24 * 60 * 60 * 1000;
    const n = fresh ? parseInt(row.v, 10) || 0 : 0;
    if (n >= numVar(env, "TR_REJECT_MAX", 2)) return false;
    await env.TR_DB.prepare("INSERT OR REPLACE INTO gen_cache (k, v, provider, created) VALUES (?1, ?2, ?3, ?4)")
      .bind(k, String(n + 1), "reject", fresh ? row.created : Date.now()).run();
    return true;
  } catch {
    return true; // خطای کش نباید ↻ را بشکند
  }
}

async function genCachePut(env, key, text, provider) {
  if (!env.TR_DB || !text) return;
  try {
    await genCacheInit(env);
    await env.TR_DB.prepare(
      "INSERT OR REPLACE INTO gen_cache (k, v, provider, created) VALUES (?1, ?2, ?3, ?4)"
    ).bind(key, text, provider, Date.now()).run();
  } catch {
    // خطای کش نباید جواب را خراب کند
  }
}

// 🤝 ادغامِ درخواست‌های هم‌زمان «بین isolateها» (Coalescing با قفلِ D1) -------------------------------
// مشکل: TT_INFLIGHT فقط داخلِ «یک» isolate کار می‌کند؛ ۱۰۰۰ کاربرِ هم‌زمان روی چند isolate پخش می‌شوند و هرکدام AI را صدا می‌زنند.
// راه‌حل: قبل از صدا زدنِ AI، برای هر کلیدِ کش‌نشده یک «اجاره» (ردیف در جدولِ tr_lock) می‌گیریم.
//   • اجاره را گرفتی = رهبر: AI را صدا بزن، در کش بنویس، بعد اجاره را آزاد کن.
//   • اجاره دستِ دیگری است = منتظر بمان و کش را poll کن (بدونِ AI، بدونِ مصرفِ سهمیه).
//   • قفل پرید/رهبر شکست خورد = منتظرها بی‌صدا null می‌گیرند (اپ می‌رود سراغ ML Kit/تلاشِ بعدی).
// ایمن در برابرِ خطا (fail-open): هر خطای D1 یعنی «همه را خودم دارم» → رفتارِ قبلی.
// تنظیم (اختیاری، در wrangler.toml):  TR_COALESCE="0" خاموش | TR_LOCK_TTL_MS (پیش‌فرض ۳۰۰۰۰) | TR_LOCK_WAIT_MS (پیش‌فرض ۱۵۰۰۰)
let trLockReady = false;
const trSleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function trLockInit(env) {
  if (trLockReady) return;
  await env.TR_DB.prepare(
    "CREATE TABLE IF NOT EXISTS tr_lock (k TEXT PRIMARY KEY, ts INTEGER NOT NULL)"
  ).run();
  trLockReady = true;
}

/** @returns {{owned:Set<string>, ts:number, active:boolean}} */
async function trLeaseAcquire(env, keys) {
  const now = Date.now();
  const all = new Set(keys);
  if (!env.TR_DB || !keys.length || String(env.TR_COALESCE ?? "1") === "0") return { owned: all, ts: now, active: false };
  try {
    await trLockInit(env);
    const ttl = numVar(env, "TR_LOCK_TTL_MS", 30000);
    const uniq = [...all];
    // قفلِ منقضی‌شده (رهبرِ مرده) بازپس‌گرفته می‌شود؛ قفلِ زنده changes=0 می‌دهد
    const res = await env.TR_DB.batch(uniq.map((k) =>
      env.TR_DB.prepare(
        "INSERT INTO tr_lock (k, ts) VALUES (?1, ?2) ON CONFLICT(k) DO UPDATE SET ts = excluded.ts WHERE tr_lock.ts < ?3"
      ).bind(k, now, now - ttl)
    ));
    const got = new Set();
    uniq.forEach((k, i) => { if ((res[i]?.meta?.changes ?? 1) > 0) got.add(k); });
    return { owned: got, ts: now, active: true };
  } catch {
    return { owned: all, ts: now, active: false };
  }
}

async function trLeaseRelease(env, lease) {
  if (!lease || !lease.active || !lease.owned.size) return;
  try {
    await env.TR_DB.batch([...lease.owned].map((k) =>
      env.TR_DB.prepare("DELETE FROM tr_lock WHERE k = ?1 AND ts = ?2").bind(k, lease.ts)
    ));
  } catch { /* منقضی می‌شود */ }
}

/** منتظرِ ظاهرشدنِ کلیدها در gen_cache می‌ماند. Map(key→value) برای آن‌هایی که رسیدند. */
async function trWaitCache(env, keys) {
  const got = new Map();
  let left = [...new Set(keys)];
  if (!env.TR_DB || !left.length) return got;
  const end = Date.now() + numVar(env, "TR_LOCK_WAIT_MS", 15000);
  let delay = 350;
  while (left.length && Date.now() < end) {
    await trSleep(delay + Math.random() * 150);
    delay = Math.min(Math.round(delay * 1.4), 1200);
    try {
      const ph = left.map((_, i) => `?${i + 1}`).join(",");
      // ترتیب مهم است: اول قفل‌ها، بعد کش. رهبر «اول کش را می‌نویسد، بعد قفل را آزاد می‌کند»؛ پس اگر قفل نبود، کش حتماً (اگر موفق بوده) پر است.
      const lk = await env.TR_DB.prepare(`SELECT k FROM tr_lock WHERE k IN (${ph})`).bind(...left).all();
      const held = new Set((lk.results || []).map((r) => r.k));
      const ch = await env.TR_DB.prepare(`SELECT k, v FROM gen_cache WHERE k IN (${ph})`).bind(...left).all();
      for (const r of ch.results || []) if (r.v) got.set(r.k, r.v);
      left = left.filter((k) => !got.has(k) && held.has(k)); // قفلِ آزادشده و بدونِ کش = رهبر شکست خورد → دیگر منتظر نمان
    } catch {
      break;
    }
  }
  return got;
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

// --- زیرنویسِ واقعیِ یوتیوب -----------------------------------------------
// چند کلاینتِ innertube (ANDROID / ANDROID_VR / IOS / TV-embed) + صفحه‌ی watch هم‌زمان امتحان می‌شن؛
// اولین کسی که زیرنویسِ واقعی بده برنده‌ست. اگه همه شکست بخورن، دلیلِ واقعیِ هر کدوم تو پیام میاد.
const YT_CLIENTS = {
  ANDROID: {
    id: "3", version: "20.10.38",
    ua: "com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip",
    client: { clientName: "ANDROID", clientVersion: "20.10.38", androidSdkVersion: 30, osName: "Android", osVersion: "11" },
  },
  ANDROID_VR: {
    id: "28", version: "1.62.27",
    ua: "com.google.android.apps.youtube.vr.oculus/1.62.27 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip",
    client: { clientName: "ANDROID_VR", clientVersion: "1.62.27", deviceMake: "Oculus", deviceModel: "Quest 3", androidSdkVersion: 32, osName: "Android", osVersion: "12L" },
  },
  IOS: {
    id: "5", version: "20.10.4",
    ua: "com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)",
    client: { clientName: "IOS", clientVersion: "20.10.4", deviceMake: "Apple", deviceModel: "iPhone16,2", osName: "iPhone", osVersion: "18.3.2.22D82" },
  },
  TV: {
    id: "85", version: "2.0",
    ua: "Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36",
    client: { clientName: "TVHTML5_SIMPLY_EMBEDDED_PLAYER", clientVersion: "2.0" },
  },
};

function ytErr(msg, noCaptions) {
  const e = new Error(msg);
  e.noCaptions = !!noCaptions;
  return e;
}

async function fetchYoutubeCaptions(videoId, wantLang, env) {
  // 🗄️ اول D1 (ماندگار و مشترک بین همه‌ی کاربرها)؛ اگر TR_DB نبود/نیافت، همان Cache API قبلی
  const d1Key = env && env.TR_DB ? await genCacheKey(`yt-captions|${videoId}|${wantLang}`, 0) : null;
  if (d1Key) {
    const raw = await genCacheGet(env, d1Key);
    if (raw) {
      try {
        return JSON.parse(raw);
      } catch {}
    }
  }
  const cache = typeof caches !== "undefined" ? caches.default : null;
  const cacheKey = new Request(`https://cache.phrasebook.local/yt-captions/${encodeURIComponent(videoId)}/${encodeURIComponent(wantLang)}`);
  if (cache) {
    const hit = await cache.match(cacheKey).catch(() => null);
    if (hit) return await hit.json();
  }

  const attempts = [
    captionsViaClient("ANDROID", videoId, wantLang, 0),
    captionsViaClient("ANDROID_VR", videoId, wantLang, 0),
    captionsViaClient("IOS", videoId, wantLang, 300),
    captionsViaClient("TV", videoId, wantLang, 600),
    captionsViaWatchPage(videoId, wantLang, 900),
  ];
  let result;
  try {
    result = await Promise.any(attempts);
  } catch (agg) {
    const errs = (agg && agg.errors) || [agg];
    const noCaptions = errs.filter((e) => e && e.noCaptions).length >= 2;
    const msg = errs.map((e) => (e && e.message) || String(e)).join(" · ").slice(0, 400);
    throw ytErr(noCaptions ? "این ویدیو زیرنویس ندارد" : msg, noCaptions);
  }

  const resultJson = JSON.stringify(result);
  if (d1Key && resultJson.length < 1500000) await genCachePut(env, d1Key, resultJson, "yt");
  if (cache) {
    await cache
      .put(cacheKey, new Response(resultJson, { headers: { "Content-Type": "application/json", "Cache-Control": "public, max-age=21600" } }))
      .catch(() => {});
  }
  return result;
}

async function captionsViaClient(name, videoId, wantLang, delayMs) {
  if (delayMs) await new Promise((r) => setTimeout(r, delayMs));
  const c = YT_CLIENTS[name];
  const label = name.toLowerCase();
  const body = {
    videoId,
    contentCheckOk: true,
    racyCheckOk: true,
    context: { client: { hl: "en", gl: "US", ...c.client } },
  };
  if (name === "TV") body.context.thirdParty = { embedUrl: `https://www.youtube.com/watch?v=${videoId}` };
  const res = await fetch("https://www.youtube.com/youtubei/v1/player?prettyPrint=false", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "User-Agent": c.ua,
      "X-YouTube-Client-Name": c.id,
      "X-YouTube-Client-Version": c.version,
      Origin: "https://www.youtube.com",
      "Accept-Language": "en-US,en;q=0.9",
    },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw ytErr(`${label}: player HTTP ${res.status}`);
  const data = await res.json();
  return await captionsFromPlayerResponse(data, label, c.ua, wantLang, videoId);
}

async function captionsViaWatchPage(videoId, wantLang, delayMs) {
  if (delayMs) await new Promise((r) => setTimeout(r, delayMs));
  const ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";
  const res = await fetch(`https://www.youtube.com/watch?v=${videoId}&hl=en&has_verified=1&bpctr=9999999999`, {
    headers: { "User-Agent": ua, "Accept-Language": "en-US,en;q=0.9", Cookie: "CONSENT=YES+1; SOCS=CAI" },
  });
  if (!res.ok) throw ytErr(`watch: HTTP ${res.status}`);
  const html = await res.text();
  const jsonStr = extractJsonAfter(html, "ytInitialPlayerResponse");
  if (!jsonStr) throw ytErr("watch: player response not found");
  return await captionsFromPlayerResponse(JSON.parse(jsonStr), "watch", ua, wantLang, videoId);
}

async function captionsFromPlayerResponse(data, label, ua, wantLang, videoId) {
  const status = data?.playabilityStatus?.status || "";
  if (status !== "OK") {
    const reason = String(data?.playabilityStatus?.reason || "").slice(0, 70);
    throw ytErr(`${label}: ${status || "no playability"}${reason ? ` (${reason})` : ""}`);
  }
  const tracks = data?.captions?.playerCaptionsTracklistRenderer?.captionTracks;
  if (!tracks || !tracks.length) throw ytErr(`${label}: no caption tracks`, true);

  const track = pickCaptionTrack(tracks, wantLang);
  const clean = track.baseUrl.replace(/[&?]fmt=[^&]*/g, "");
  let cues = [];
  let why = "";
  for (const url of [`${clean}&fmt=json3`, clean]) {
    const capRes = await fetch(url, { headers: { "User-Agent": ua, "Accept-Language": "en-US,en;q=0.9" } });
    if (!capRes.ok) { why = `timedtext HTTP ${capRes.status}`; continue; }
    const text = await capRes.text();
    if (!text.trim()) { why = "timedtext empty (needs PO token?)"; continue; }
    cues = parseCaptionBody(text);
    if (cues.length) break;
    why = "timedtext unparsable";
  }
  if (!cues.length) throw ytErr(`${label}: ${why}`);

  return {
    ok: true,
    videoId,
    lang: track.languageCode,
    isAuto: track.kind === "asr",
    availableLangs: tracks.map((t) => ({
      code: t.languageCode,
      name: (t.name && t.name.simpleText) || t.languageCode,
      auto: t.kind === "asr",
    })),
    cues,
  };
}

function decodeXmlEntities(s) {
  let out = s;
  for (let i = 0; i < 2 && out.includes("&"); i++) {
    out = out
      .replace(/&#x([0-9a-fA-F]+);/g, (_, h) => String.fromCodePoint(parseInt(h, 16)))
      .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(parseInt(d, 10)))
      .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"')
      .replace(/&apos;/g, "'").replace(/&nbsp;/g, " ").replace(/&amp;/g, "&");
  }
  return out;
}

// json3 یا XML (srv1: <text start dur>، srv3: <p t d>)
function parseCaptionBody(text) {
  const t = text.trim();
  if (t.startsWith("{")) {
    try {
      const j = JSON.parse(t);
      return (j.events || [])
        .filter((e) => e.segs && e.segs.length)
        .map((e) => ({
          start: Math.round(e.tStartMs || 0) / 1000,
          end: Math.round((e.tStartMs || 0) + (e.dDurationMs || 0)) / 1000,
          text: e.segs.map((s) => s.utf8 || "").join("").replace(/\n/g, " ").trim(),
        }))
        .filter((c) => c.text);
    } catch {
      /* می‌افتیم رو XML */
    }
  }
  const out = [];
  const clean = (raw) => decodeXmlEntities(raw.replace(/<[^>]+>/g, "")).replace(/\n/g, " ").trim();
  let m;
  const v3 = /<p\s+t="(\d+)"(?:\s+d="(\d+)")?[^>]*>([\s\S]*?)<\/p>/g;
  while ((m = v3.exec(t))) {
    const st = parseInt(m[1], 10), du = m[2] ? parseInt(m[2], 10) : 0, tx = clean(m[3]);
    if (tx) out.push({ start: st / 1000, end: (st + du) / 1000, text: tx });
  }
  if (out.length) return out;
  const v1 = /<text\s+start="([\d.]+)"(?:\s+dur="([\d.]+)")?[^>]*>([\s\S]*?)<\/text>/g;
  while ((m = v1.exec(t))) {
    const st = parseFloat(m[1]), du = m[2] ? parseFloat(m[2]) : 0, tx = clean(m[3]);
    if (tx) out.push({ start: st, end: st + du, text: tx });
  }
  return out;
}

function extractJsonAfter(html, marker) {
  const idx = html.indexOf(marker);
  if (idx === -1) return null;
  const start = html.indexOf("{", idx);
  if (start === -1) return null;
  let depth = 0;
  let inStr = false;
  let strCh = "";
  let esc = false;
  for (let i = start; i < html.length; i++) {
    const ch = html[i];
    if (inStr) {
      if (esc) esc = false;
      else if (ch === "\\") esc = true;
      else if (ch === strCh) inStr = false;
      continue;
    }
    if (ch === '"' || ch === "'") {
      inStr = true;
      strCh = ch;
      continue;
    }
    if (ch === "{") depth++;
    else if (ch === "}") {
      depth--;
      if (depth === 0) return html.slice(start, i + 1);
    }
  }
  return null;
}

function pickCaptionTrack(tracks, wantLang) {
  const norm = (s) => (s || "").toLowerCase().split("-")[0];
  const want = norm(wantLang);
  // 🌍 "auto": زبانِ اصلیِ ویدیو. ترکِ خودکار (asr) همیشه به زبانِ گفتارِ ویدیو ساخته می‌شه؛
  // اگه ترکِ دستی هم به همون زبان بود اون، وگرنه خودِ asr؛ اگه asr نبود، اولین ترکِ دستی.
  if (want === "auto") {
    const asr = tracks.find((t) => t.kind === "asr");
    if (asr) {
      const spoken = norm(asr.languageCode);
      return tracks.find((t) => t.kind !== "asr" && norm(t.languageCode) === spoken) || asr;
    }
    return tracks.find((t) => t.kind !== "asr") || tracks[0];
  }
  return (
    tracks.find((t) => norm(t.languageCode) === want && t.kind !== "asr") ||
    tracks.find((t) => norm(t.languageCode) === want) ||
    tracks.find((t) => t.kind !== "asr") ||
    tracks[0]
  );
}

// --- ترجمه‌ی chunk به chunk‌ِ زیرنویس (برای حالت یوتیوبِ حباب) --------------
// ورودی: { subtitles: [متنِ هر خط], context_before: [...], context_after: [...],
//          content_title, source_language, target_language, translation_tone }
// خروجی: { ok: true, translations: [...] } — دقیقاً به تعدادِ subtitles.
// جمله‌های همسایه فقط برای فهمیدنِ معنی داده می‌شن و ترجمه نمی‌شن؛ همین باعث
// می‌شه ترجمه‌ی خط‌های نیمه‌کاره (که یوتیوب وسطِ جمله می‌بره) دقیق‌تر بشه.
async function translateSubtitleChunk(body, env, ctx, gateFn) {
  const subs = Array.isArray(body?.subtitles)
    ? body.subtitles.map((s) => (typeof s === "string" ? s : String(s?.text ?? "")).slice(0, 500))
    : [];
  if (!subs.length) throw new Error("subtitles (array) is required");
  if (subs.length > 30) throw new Error("too many subtitles in one chunk");

  const cleanList = (a) =>
    (Array.isArray(a) ? a : []).map((s) => String(s ?? "").slice(0, 300)).filter(Boolean).slice(0, 6);
  const before = cleanList(body.context_before);
  const after = cleanList(body.context_after);
  const srcName = String(body.source_language || "the source language").slice(0, 40);
  const tgtName = String(body.target_language || "").slice(0, 40);
  if (!tgtName) throw new Error("target_language is required");
  const title = String(body.content_title || "").slice(0, 160);
  const tone = String(body.translation_tone || "neutral").toLowerCase();

  let toneRule = "Use natural, neutral spoken language.";
  if (tone === "formal") toneRule = "Use a formal, polite register.";
  else if (tone === "casual") toneRule = "Use a casual, everyday spoken register.";

  const prompt =
    `You are a professional subtitle translator. Translate every subtitle line from ${srcName} to ${tgtName}.\n` +
    `Rules:\n` +
    `- Output ONLY a JSON array of exactly ${subs.length} strings, in the same order as the input. No markdown, no commentary.\n` +
    `- Item N of the output is the translation of item N of the input. Never merge or split lines, even if a sentence continues on the next line.\n` +
    `- ${toneRule}\n` +
    `- The context lines are ONLY for understanding the meaning; do NOT translate or output them.\n` +
    (title ? `\nVideo title: ${title}\n` : "\n") +
    (before.length ? `Context before (do not translate): ${JSON.stringify(before)}\n` : "") +
    `Subtitle lines to translate: ${JSON.stringify(subs)}\n` +
    (after.length ? `Context after (do not translate): ${JSON.stringify(after)}\n` : "");

  const maxTokens = Math.min(Math.max(600, subs.join("").length * 4 + 300), 4000);

  // ⚡ کشِ سمتِ سرور: همین جمله‌ها + همین زبان‌ها + همین لحن = همان ترجمه (بین همه‌ی کاربرها مشترک).
  // زمینه (جمله‌های قبل/بعد) عمداً در کلید نیست تا شانسِ hit بیشتر شود.
  // 🗄️ اول D1 (ماندگار)؛ اگر TR_DB نبود/نیافت، همان Cache API قبلی
  const cache = typeof caches !== "undefined" ? caches.default : null;
  let cacheReq = null;
  let d1Key = null;
  if (env.TR_DB) {
    try {
      d1Key = await genCacheKey(`sub-tr|${String(env.TR_MODEL_VERSION || "1") === "1" ? "" : "mv" + env.TR_MODEL_VERSION + "|"}${JSON.stringify([srcName, tgtName, tone, subs])}`, 0);
      const raw = await genCacheGet(env, d1Key);
      if (raw) {
        const arr0 = JSON.parse(raw);
        if (Array.isArray(arr0) && arr0.length === subs.length) {
          return { ok: true, provider: "cache", cached: true, translations: arr0 };
        }
      }
    } catch {}
  }
  if (cache) {
    try {
      const keyStr = JSON.stringify([srcName, tgtName, tone, subs]);
      const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(keyStr));
      const hex = [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
      cacheReq = new Request(`https://cache.phrasebook.local/sub-tr/${hex}`);
      const hit = await cache.match(cacheReq).catch(() => null);
      if (hit) {
        const j = await hit.json();
        if (Array.isArray(j.translations) && j.translations.length === subs.length) {
          return { ok: true, provider: "cache", cached: true, translations: j.translations };
        }
      }
    } catch {
      cacheReq = null;
    }
  }

  // ⚖️ کش جواب نداشت و واقعاً به AI می‌رود → سقفِ سراسریِ روزانه
  let degraded = false;
  if (gateFn) {
    const g = await gateFn();
    if (g && g.deny) {
      const err = new Error("global daily cap");
      err.gateResponse = g.deny;
      throw err;
    }
    degraded = !!(g && g.degraded); // 🪙 امتیازِ ماهانه تمام شده → فقط مدل‌های رایگان (بی‌صدا)
  }

  // ⚡ به‌جای امتحانِ ترتیبیِ ~۲۰ پرووایدر (هر خرابی = چند ثانیه تأخیر)، «hedged»: اولی شروع می‌شود؛
  // اگر خطا داد، فوراً بعدی؛ اگر تا hedgeMs جواب نداد، بعدی هم‌زمان (حداکثر ۳ تا هم‌زمان). اولین جوابِ معتبر برنده است.
  const chain = degraded ? getFreeChainFor(env, "ytsub") : getProviderChain(env);
  const { provider, value: arr } = await hedgedProviders(chain, prompt, maxTokens, env, (raw) => {
    const a = parseJsonStringArray(raw);
    if (!a || a.length !== subs.length) throw new Error(`bad shape (${a ? a.length : "no array"} vs ${subs.length})`);
    return a;
  });

  if (d1Key && !degraded) {
    const d1put = genCachePut(env, d1Key, JSON.stringify(arr), provider);
    if (ctx && typeof ctx.waitUntil === "function") ctx.waitUntil(d1put);
    else await d1put;
  }
  if (cache && cacheReq && !degraded) {
    const put = cache
      .put(
        cacheReq,
        new Response(JSON.stringify({ translations: arr }), {
          headers: { "Content-Type": "application/json", "Cache-Control": "public, max-age=2592000" },
        })
      )
      .catch(() => {});
    if (ctx && typeof ctx.waitUntil === "function") ctx.waitUntil(put);
  }
  return { ok: true, provider, translations: arr };
}

// اولین پرووایدرِ موفق برنده است؛ بقیه‌ی درخواست‌های در حالِ اجرا نادیده گرفته می‌شوند.
function hedgedProviders(chain, prompt, maxTokens, env, validate, hedgeMs = 2500, maxInflight = 3) {
  return new Promise((resolve, reject) => {
    const errors = [];
    let next = 0;
    let inflight = 0;
    let settled = false;
    let timer = null;

    const finishFail = () => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      reject(new Error(errors.join(" | ") || "no provider available"));
    };

    const arm = () => {
      clearTimeout(timer);
      if (settled || next >= chain.length) return;
      timer = setTimeout(() => {
        if (!settled && inflight < maxInflight && next < chain.length) launch();
      }, hedgeMs);
    };

    const launch = () => {
      if (settled) return;
      if (next >= chain.length) {
        if (inflight === 0) finishFail();
        return;
      }
      const provider = chain[next++];
      inflight++;
      Promise.resolve()
        .then(() => callProvider(provider, prompt, maxTokens, env))
        .then((raw) => validate(raw))
        .then((value) => {
          if (settled) return;
          settled = true;
          clearTimeout(timer);
          resolve({ provider, value });
        })
        .catch((e) => {
          errors.push(`${provider}: ${(e && e.message) || e}`);
        })
        .finally(() => {
          inflight--;
          if (settled) return;
          if (next < chain.length) launch();
          else if (inflight === 0) finishFail();
        });
      arm();
    };

    launch();
  });
}

function parseJsonStringArray(raw) {
  if (typeof raw !== "string") return null;
  const a = raw.indexOf("[");
  const b = raw.lastIndexOf("]");
  if (a === -1 || b <= a) return null;
  try {
    const arr = JSON.parse(raw.slice(a, b + 1));
    if (!Array.isArray(arr)) return null;
    return arr.map((x) => (typeof x === "string" ? x.trim() : String(x ?? "").trim()));
  } catch {
    return null;
  }
}

// --- پیدا کردنِ آی‌دیِ ویدیو از روی عنوان (جست‌وجوی innertube) -----------------
async function resolveYoutubeVideoId(title, channel, durationSec) {
  const INNERTUBE_KEY = "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8";
  const res = await fetch(`https://www.youtube.com/youtubei/v1/search?key=${INNERTUBE_KEY}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      query: channel ? `${title} ${channel}` : title,
      context: { client: { clientName: "WEB", clientVersion: "2.20240401.01.00", hl: "en", gl: "US" } },
    }),
  });
  if (!res.ok) throw new Error(`search status ${res.status}`);
  const data = await res.json();

  const found = [];
  const walk = (node, depth) => {
    if (!node || depth > 14 || found.length > 40) return;
    if (Array.isArray(node)) {
      for (const n of node) walk(n, depth + 1);
      return;
    }
    if (typeof node !== "object") return;
    if (node.videoRenderer && node.videoRenderer.videoId) found.push(node.videoRenderer);
    for (const k of Object.keys(node)) walk(node[k], depth + 1);
  };
  walk(data, 0);
  if (!found.length) throw new Error("no search results");

  const norm = (s) => String(s || "").toLowerCase().replace(/[^\p{L}\p{N}]+/gu, " ").trim();
  const wantTitle = norm(title);
  const wantChannel = norm(channel);
  const toSec = (t) => {
    const parts = String(t || "").split(":").map((x) => parseInt(x, 10));
    if (!parts.length || parts.some((n) => Number.isNaN(n))) return 0;
    return parts.reduce((acc, n) => acc * 60 + n, 0);
  };

  let best = null;
  let bestScore = -1;
  for (const v of found) {
    const vTitle = norm((v.title?.runs || []).map((r) => r.text).join("") || v.title?.simpleText);
    const vChannel = norm((v.ownerText?.runs || []).map((r) => r.text).join(""));
    const vSec = toSec(v.lengthText?.simpleText);
    let score = 0;
    if (vTitle === wantTitle) score += 6;
    else if (vTitle && (vTitle.includes(wantTitle) || wantTitle.includes(vTitle))) score += 3;
    if (wantChannel && vChannel && (vChannel === wantChannel || vChannel.includes(wantChannel) || wantChannel.includes(vChannel))) score += 2;
    if (durationSec > 0 && vSec > 0) {
      const diff = Math.abs(vSec - durationSec);
      if (diff <= 2) score += 5;
      else if (diff <= 6) score += 2;
      else score -= 3;
    }
    if (score > bestScore) {
      bestScore = score;
      best = v;
    }
  }
  // بدونِ هیچ نشانه‌ی قابل‌اعتمادی (عنوان یا مدت) حدس نمی‌زنیم؛ زیرنویسِ ویدیوی اشتباه بدتر از بی‌زیرنویسیه.
  if (!best || bestScore < 3) throw new Error("could not confidently match the video");
  return {
    ok: true,
    videoId: best.videoId,
    title: (best.title?.runs || []).map((r) => r.text).join("") || best.title?.simpleText || "",
    score: bestScore,
  };
}

// --- Hugging Face TTS (فارسی/عربی) -------------------------------------------
function hfTtsModelFor(lang, env) {
  if (lang === "fa") return env.HF_TTS_MODEL_FA || "facebook/mms-tts-fas";
  if (lang === "ar") return env.HF_TTS_MODEL_AR || "facebook/mms-tts-ara";
  return null;
}

function hfTtsSpaceUrlFor(lang, env) {
  if (lang === "fa") return env.HF_TTS_SPACE_FA_URL || "";
  if (lang === "ar") return env.HF_TTS_SPACE_AR_URL || "";
  return "";
}

function hfTtsConfigStatus(env, lang) {
  const spaceUrl = hfTtsSpaceUrlFor(lang, env);
  if (spaceUrl) return { mode: "custom-space", url: spaceUrl };
  if (env.HF_API_KEY) return { mode: "hf-inference", model: hfTtsModelFor(lang, env) };
  return { mode: "none (HF_API_KEY not set)" };
}

async function fetchHuggingFaceTtsAudio(text, lang, env) {
  const sanitized = String(text).slice(0, 600);
  const spaceUrl = hfTtsSpaceUrlFor(lang, env);

  if (spaceUrl) {
    const headers = { "Content-Type": "application/json" };
    if (env.HF_TTS_SPACE_TOKEN) headers.Authorization = `Bearer ${env.HF_TTS_SPACE_TOKEN}`;
    const r = await fetch(spaceUrl, {
      method: "POST",
      headers,
      body: JSON.stringify({ text: sanitized, lang }),
    });
    if (!r.ok) {
      const snippet = (await r.text().catch(() => "")).slice(0, 160);
      throw new Error(`custom TTS service HTTP ${r.status}${snippet ? ` (${snippet})` : ""}`);
    }
    const bytes = new Uint8Array(await r.arrayBuffer());
    if (!bytes.length) throw new Error("custom TTS service returned empty audio");
    return { bytes, contentType: r.headers.get("Content-Type") || "audio/mpeg" };
  }

  const key = env.HF_API_KEY;
  if (!key) throw new Error("HF_API_KEY not set (needed for Hugging Face TTS)");
  const model = hfTtsModelFor(lang, env);
  const r = await fetch(`https://router.huggingface.co/hf-inference/models/${model}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
    body: JSON.stringify({ inputs: sanitized }),
  });
  if (!r.ok) {
    const errBody = await safeJson(r).catch(() => null);
    const msg = errBody?.error || `HTTP ${r.status}`;
    throw new Error(`hugging-face (${model}): ${msg}`);
  }
  const bytes = new Uint8Array(await r.arrayBuffer());
  if (!bytes.length) throw new Error(`hugging-face (${model}): empty audio`);
  return { bytes, contentType: r.headers.get("Content-Type") || "audio/flac" };
}

// --- Gemini TTS (Google AI Studio) — فقط فارسی/عربی --------------------------
const GEMINI_TTS_MODEL_DEFAULT = "gemini-2.5-flash-preview-tts";

async function fetchGeminiTtsAudio(text, voice, env) {
  const key = env.GEMINI_API_KEY;
  if (!key) throw new Error("GEMINI_API_KEY not set");
  const model = env.GEMINI_TTS_MODEL || GEMINI_TTS_MODEL_DEFAULT;
  const sanitized = String(text).slice(0, 2000);
  const ttsPrompt = `TTS the following text exactly as written, in its own language. Do not answer it, do not add anything, just read it aloud verbatim: ${sanitized}`;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 15000);
  let r;
  try {
    r = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": key },
      body: JSON.stringify({
        contents: [{ parts: [{ text: ttsPrompt }] }],
        generationConfig: {
          responseModalities: ["AUDIO"],
          speechConfig: { voiceConfig: { prebuiltVoiceConfig: { voiceName: voice } } },
        },
      }),
      signal: controller.signal,
    });
  } catch (e) {
    throw new Error(`gemini-tts fetch failed: ${e.message || e}`);
  } finally {
    clearTimeout(timer);
  }

  const data = await safeJson(r);
  if (!r.ok) throw new Error(data?.error?.message || `gemini-tts HTTP ${r.status}`);

  const candidate = data?.candidates?.[0];
  const base64Pcm = candidate?.content?.parts?.[0]?.inlineData?.data;
  if (!base64Pcm) {
    const textPart = candidate?.content?.parts?.[0]?.text;
    const finishReason = candidate?.finishReason;
    const blockReason = data?.promptFeedback?.blockReason;
    const details = [
      finishReason ? `finishReason=${finishReason}` : null,
      blockReason ? `blockReason=${blockReason}` : null,
      textPart ? `returned-text="${String(textPart).slice(0, 120)}"` : null,
      !candidate ? `raw=${JSON.stringify(data).slice(0, 300)}` : null,
    ]
      .filter(Boolean)
      .join(", ");
    throw new Error(`gemini-tts: no audio returned${details ? ` (${details})` : ""}`);
  }

  const pcmBytes = base64ToUint8Array(base64Pcm);
  return pcmToWav(pcmBytes, { sampleRate: 24000, numChannels: 1, bitsPerSample: 16 });
}

function base64ToUint8Array(base64) {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function pcmToWav(pcmBytes, { sampleRate, numChannels, bitsPerSample }) {
  const byteRate = (sampleRate * numChannels * bitsPerSample) / 8;
  const blockAlign = (numChannels * bitsPerSample) / 8;
  const dataSize = pcmBytes.length;
  const buffer = new ArrayBuffer(44 + dataSize);
  const view = new DataView(buffer);

  const writeString = (offset, str) => {
    for (let i = 0; i < str.length; i++) view.setUint8(offset + i, str.charCodeAt(i));
  };

  writeString(0, "RIFF");
  view.setUint32(4, 36 + dataSize, true);
  writeString(8, "WAVE");
  writeString(12, "fmt ");
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, numChannels, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, byteRate, true);
  view.setUint16(32, blockAlign, true);
  view.setUint16(34, bitsPerSample, true);
  writeString(36, "data");
  view.setUint32(40, dataSize, true);

  const wavBytes = new Uint8Array(buffer);
  wavBytes.set(pcmBytes, 44);
  return wavBytes;
}

// --- Edge/Azure Neural TTS proxy ---------------------------------------------
const EDGE_TTS_TRUSTED_TOKEN = "6A5AA1D4EAFF4E9FB37E23D68491D6F4";

function edgeTtsUuid() {
  return crypto.randomUUID().replace(/-/g, "");
}

function edgeTtsEscapeXml(s) {
  return (s || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

async function edgeTtsSecMsGec() {
  const WIN_EPOCH = 11644473600;
  let ticks = Math.floor(Date.now() / 1000) + WIN_EPOCH;
  ticks -= ticks % 300;
  const ticksStr = String(Math.round(ticks * 1e7));
  const strToHash = ticksStr + EDGE_TTS_TRUSTED_TOKEN;
  const enc = new TextEncoder().encode(strToHash);
  const hashBuf = await crypto.subtle.digest("SHA-256", enc);
  return Array.from(new Uint8Array(hashBuf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("")
    .toUpperCase();
}

// ⛔ غیرفعال: این مسیر غیررسمی است و در حجمِ بالا خطرِ بن‌شدنِ IP دارد. برای فعال‌کردنِ دوباره false را true کن.
const EDGE_TTS_ENABLED = false;

async function fetchEdgeTtsAudio(text, voice) {
  if (!EDGE_TTS_ENABLED) throw new Error("edge-tts disabled");
  const sanitized = String(text).slice(0, 600);
  const gec = await edgeTtsSecMsGec();
  const connId = edgeTtsUuid();
  const wsUrl =
    "https://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1" +
    `?TrustedClientToken=${EDGE_TTS_TRUSTED_TOKEN}` +
    `&Sec-MS-GEC=${gec}` +
    `&Sec-MS-GEC-Version=1-131.0.2903.99` +
    `&ConnectionId=${connId}`;

  const resp = await fetch(wsUrl, {
    headers: {
      Upgrade: "websocket",
      Origin: "chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold",
      "User-Agent":
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0",
    },
  });
  const ws = resp.webSocket;
  if (!ws) throw new Error("edge-tts: upstream didn't upgrade to websocket");
  ws.accept();

  return new Promise((resolve, reject) => {
    const audioParts = [];
    let settled = false;

    const finishOk = () => {
      if (settled) return;
      settled = true;
      clearTimeout(timeoutId);
      try {
        ws.close();
      } catch (e) {}
      if (!audioParts.length) {
        reject(new Error("edge-tts: no audio returned"));
        return;
      }
      let total = 0;
      for (const p of audioParts) total += p.length;
      const merged = new Uint8Array(total);
      let offset = 0;
      for (const p of audioParts) {
        merged.set(p, offset);
        offset += p.length;
      }
      resolve(merged);
    };
    const finishFail = (err) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeoutId);
      try {
        ws.close();
      } catch (e) {}
      reject(err || new Error("edge-tts: failed"));
    };
    const timeoutId = setTimeout(() => finishFail(new Error("edge-tts: timeout")), 15000);

    ws.addEventListener("message", (evt) => {
      if (typeof evt.data === "string") {
        if (evt.data.indexOf("Path:turn.end") !== -1) finishOk();
        return;
      }
      try {
        const buf = new Uint8Array(evt.data);
        if (buf.length < 2) return;
        const headerLen = (buf[0] << 8) | buf[1];
        const headerStr = new TextDecoder("utf-8").decode(buf.slice(2, 2 + headerLen));
        if (headerStr.indexOf("Path:audio") !== -1) {
          const audioData = buf.slice(2 + headerLen);
          if (audioData.length) audioParts.push(audioData);
        }
      } catch (e) {}
    });
    ws.addEventListener("close", () => finishOk());
    ws.addEventListener("error", () => finishFail(new Error("edge-tts: websocket error")));

    try {
      const now = new Date().toISOString();
      ws.send(
        `X-Timestamp:${now}\r\n` +
          "Content-Type:application/json; charset=utf-8\r\n" +
          "Path:speech.config\r\n\r\n" +
          JSON.stringify({
            context: {
              synthesis: {
                audio: {
                  metadataoptions: { sentenceBoundaryEnabled: false, wordBoundaryEnabled: false },
                  outputFormat: "audio-24khz-48kbitrate-mono-mp3",
                },
              },
            },
          })
      );
      const ssml =
        `<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='en-US'>` +
        `<voice name='${voice}'><prosody rate='+0%'>${edgeTtsEscapeXml(sanitized)}</prosody></voice>` +
        `</speak>`;
      ws.send(
        `X-RequestId:${edgeTtsUuid()}\r\n` +
          "Content-Type:application/ssml+xml\r\n" +
          `X-Timestamp:${now}\r\n` +
          "Path:ssml\r\n\r\n" +
          ssml
      );
    } catch (e) {
      finishFail(e);
    }
  });
}

async function safeJson(r) {
  const raw = await r.text();
  try {
    return JSON.parse(raw);
  } catch {
    const snippet = raw.trim().slice(0, 120) || `HTTP ${r.status}`;
    throw new Error(`non-JSON response (${snippet})`);
  }
}

function withTimeout(promise, ms, label) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(`timeout after ${ms}ms`)), ms);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

// <think>…</think> و برچسب‌های مشابه را برمی‌دارد.
function sanitizeAiText(text) {
  return String(text || "")
    .replace(/<think(ing)?>[\s\S]*?<\/think(ing)?>/gi, "")
    .replace(/<think(ing)?>[\s\S]*$/gi, "")
    .trim();
}

// دلیلِ «این جواب نیست» — یا null اگر سالم است.
function badAiOutputReason(text, prompt) {
  const t = String(text || "").trim();
  if (!t) return "empty";
  if (/^\s*(user\s+|assistant\s+)?safety\s*:/im.test(t) || /^\s*(safe|unsafe)\s*$/im.test(t)) return "guard";
  if (/(thinking process|here'?s a thinking|analy[sz]e the (request|text|input|user)|\*\*\s*analy[sz]e|the user (wants|asks|is asking) |let me (read|think|analy[sz]e|re-?read)|<\/?think(ing)?>|^\s*(we need to|we should|we must|let'?s (craft|produce|compose|draft)))/im.test(t)) return "reasoning";
  // خودِ پرامپت برگشته؟ (۶۰ کاراکترِ اولِ پرامپت عیناً در جواب)
  const head = String(prompt || "").trim().slice(0, 60);
  if (head.length >= 40 && t.includes(head)) return "prompt-echo";
  return null;
}

const VALID_PROVIDERS = [
  "huggingface", "groq", "gemini", "deepseek", "openai", "avalai", "grok", "openrouter", "mistral", "cerebras",
  "aionlabs", "cohere", "zai", "cloudflareai", "kilocode", "llm7", "modelscope", "nvidianim", "ollamacloud", "ovhcloud", "siliconflow",
];
function getProviderChain(env) {
  const raw = (
    env.AI_PROVIDER ||
    "deepseek,kilocode,llm7,ovhcloud,groq,nvidianim,ollamacloud,cloudflareai,mistral,cohere,zai,aionlabs,modelscope,siliconflow,openrouter,cerebras,grok,gemini,huggingface"
  ).toLowerCase();
  const chain = raw
    .split(",")
    .map((p) => p.trim())
    .filter((p) => VALID_PROVIDERS.includes(p));
  return chain.length ? chain : ["openrouter"];
}

// 🎚️ زنجیره بر اساسِ نوعِ کار: story → AI_PROVIDER_STRONG، بقیه → AI_PROVIDER_LIGHT.
// متغیرِ ست‌نشده/نامعتبر = همان getProviderChain (بدونِ تغییرِ رفتار).
function getProviderChainFor(env, feature) {
  // ⚡ ویدیو کال: زنجیره‌ی جدا با مدل‌های کوچک و سریع (AI_PROVIDER_CALL)؛ ست‌نشده/نامعتبر
  // = همان زنجیره‌ی سبکِ قبلی (بدونِ تغییرِ رفتار).
  if (feature === "videocall" && env.AI_PROVIDER_CALL) {
    const chain = String(env.AI_PROVIDER_CALL)
      .toLowerCase()
      .split(",")
      .map((p) => p.trim())
      .filter((p) => VALID_PROVIDERS.includes(p));
    if (chain.length) return chain;
  }
  const raw = feature === "story" ? env.AI_PROVIDER_STRONG : env.AI_PROVIDER_LIGHT;
  if (raw) {
    const chain = String(raw)
      .toLowerCase()
      .split(",")
      .map((p) => p.trim())
      .filter((p) => VALID_PROVIDERS.includes(p));
    if (chain.length) return chain;
  }
  return getProviderChain(env);
}

// 🆓 زنجیره‌ی «مدل‌های رایگان» — وقتی امتیازِ ماهانه‌ی کاربر تمام شده (بی‌صدا؛ کاربر چیزی نمی‌فهمد).
// AI_PROVIDER_FREE = زنجیره‌ی عمومی (چت/داستان/گرامر/مثال/زیرنویس)، AI_PROVIDER_FREE_CALL = ویدیوکال (کوچک و سریع).
// عمداً فقط پرووایدرهای رایگان؛ deepseek/gemini/openai/... هرگز در این زنجیره نیستند.
const FREE_DEFAULT = "groq,cerebras,llm7,kilocode,ovhcloud,cloudflareai";
const FREE_DEFAULT_CALL = "cerebras,groq,llm7,kilocode,ovhcloud,cloudflareai";
function getFreeChainFor(env, feature) {
  const raw = (feature === "videocall" ? env.AI_PROVIDER_FREE_CALL : "") || env.AI_PROVIDER_FREE ||
    (feature === "videocall" ? FREE_DEFAULT_CALL : FREE_DEFAULT);
  const chain = String(raw).toLowerCase().split(",").map((p) => p.trim()).filter((p) => VALID_PROVIDERS.includes(p));
  return chain.length ? chain : FREE_DEFAULT.split(",");
}

async function callProvider(provider, prompt, maxTokens, env) {
  if (provider === "huggingface") return callHuggingFace(prompt, maxTokens, env);
  if (provider === "groq") return callGroq(prompt, maxTokens, env);
  if (provider === "gemini") return callGemini(prompt, maxTokens, env);
  if (provider === "deepseek") return callDeepSeek(prompt, maxTokens, env);
  if (provider === "openai") return callOpenAI(prompt, maxTokens, env);
  if (provider === "avalai") return callAvalAI(prompt, maxTokens, env);
  if (provider === "grok") return callGrok(prompt, maxTokens, env);
  if (provider === "openrouter") return callOpenRouter(prompt, maxTokens, env);
  if (provider === "mistral") return callMistral(prompt, maxTokens, env);
  if (provider === "cerebras") return callCerebras(prompt, maxTokens, env);
  if (provider === "aionlabs") return callAionLabs(prompt, maxTokens, env);
  if (provider === "cohere") return callCohere(prompt, maxTokens, env);
  if (provider === "zai") return callZai(prompt, maxTokens, env);
  if (provider === "cloudflareai") return callCloudflareAI(prompt, maxTokens, env);
  if (provider === "kilocode") return callKiloCode(prompt, maxTokens, env);
  if (provider === "llm7") return callLLM7(prompt, maxTokens, env);
  if (provider === "modelscope") return callModelScope(prompt, maxTokens, env);
  if (provider === "nvidianim") return callNvidiaNim(prompt, maxTokens, env);
  if (provider === "ollamacloud") return callOllamaCloud(prompt, maxTokens, env);
  if (provider === "ovhcloud") return callOvhCloud(prompt, maxTokens, env);
  if (provider === "siliconflow") return callSiliconFlow(prompt, maxTokens, env);
  throw new Error(`Unknown provider "${provider}"`);
}

async function callAionLabs(prompt, maxTokens, env) {
  const key = env.AIONLABS_API_KEY;
  if (!key) throw new Error("AIONLABS_API_KEY not set");
  const r = await fetch("https://api.aionlabs.ai/v1/chat/completions", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
    body: JSON.stringify({
      model: env.AIONLABS_MODEL || "aion-labs/aion-3.0-mini",
      messages: [{ role: "user", content: prompt }],
      max_tokens: maxTokens,
    }),
  });
  const data = await safeJson(r);
  if (!r.ok) throw new Error(data?.error?.message || data?.error || `Aion Labs HTTP ${r.status}`);
  const text = data.choices?.[0]?.message?.content || "";
  if (!text) throw new Error("Aion Labs returned empty response");
  return text;
}

async function callCohere(prompt, maxTokens, env) {
  const key = env.COHERE_API_KEY;
  if (!key) throw new Error("COHERE_API_KEY not set");
  const r = await fetch("https://api.cohere.com/v2/chat", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
    body: JSON.stringify({
      model: env.COHERE_MODEL || "command-r7b-12-2024",
      messages: [{ role: "user", content: prompt }],
      max_tokens: maxTokens,
    }),
  });
  const data = await safeJson(r);
  if (!r.ok) throw new Error(data?.message || `Cohere HTTP ${r.status}`);
  const parts = data?.message?.content || [];
  const text = parts.map((p) => p.text || "").join("").trim();
  if (!text) throw new Error("Cohere returned empty response");
  return text;
}

async function callZai(prompt, maxTokens, env) {
  const key = env.ZAI_API_KEY;
  if (!key) throw new Error("ZAI_API_KEY not set");
  const r = await fetch("https://api.z.ai/api/paas/v4/chat/completions", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
    body: JSON.stringify({
      model: env.ZAI_MODEL || "glm-4.7-flash",
      messages: [{ role: "user", content: prompt }],
      max_tokens: maxTokens,
    }),
  });
  const data = await safeJson(r);
  if (!r.ok) throw new Error(data?.error?.message || data?.error || `Z AI HTTP ${r.status}`);
  const text = data.choices?.[0]?.message?.content || "";
  if (!text) throw new Error("Z AI returned empty response");
  return text;
}

async function callCloudflareAI(prompt, maxTokens, env) {
  const token = env.CF_API_TOKEN;
  const accountId = env.CF_ACCOUNT_ID;
  if (!token || !accountId) throw new Error("CF_API_TOKEN/CF_ACCOUNT_ID not set");
  const model = env.CF_AI_MODEL || "@cf/openai/gpt-oss-120b";
  const r = await fetch(
    `https://api.cloudflare.com/client/v4/accounts/${accountId}/ai/run/${model}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
      body: JSON.stringify({
        messages: [{ role: "user", content: prompt }],
        max_tokens: maxTokens,
      }),
    }
  );
  const data = await safeJson(r);
  if (!r.ok || data?.success === false) {
    const errMsg = (data?.errors || []).map((e) => e.message).join("; ");
    throw new Error(errMsg || `Cloudflare Workers AI HTTP ${r.status}`);
  }
  const text = data?.result?.response || "";
  if (!text) throw new Error("Cloudflare Workers AI returned empty response");
  return text;
}

async function callKiloCode(prompt, maxTokens, env) {
  const headers = { "Content-Type": "application/json" };
  if (env.KILOCODE_API_KEY) headers.Authorization = `Bearer ${env.KILOCODE_API_KEY}`;
  const r = await fetch("https://api.kilo.ai/api/gateway/v1/chat/completions", {
    method: "POST",
    headers,
    body: JSON.stringify({
      model: env.KILOCODE_MODEL || "openrouter/free",
      messages: [{ role: "user", content: prompt }],
      max_tokens: maxTokens,
    }),
  });
  const data = await safeJson(r);
  if (!r.ok) throw new Error(data?.error?.message || data?.error || `Kilo Code HTTP ${r.status}`);
  const text = data.choices?.[0]?.message?.content || "";
  if (!text) throw new Error("Kilo Code returned empty response");
  return text;
}

async function callLLM7(prompt, maxTokens, env) {
  const headers = { "Content-Type": "application/json" };
  if (env.LLM7_API_KEY) headers.Authorization = `Bearer ${env.LLM7_API_KEY}`;
  const r = await fetch("https://api.llm7.io/v1/chat/completions", {
    method: "POST",
    headers,
    body: JSON.stringify({
      model: env.LLM7_MODEL || "gpt-oss:20b",
      messages: [{ role: "user", content: prompt }],
      max_tokens: maxTokens,
    }),
  });
  const data = await safeJson(r);
  if (!r.ok) throw new Error(data?.error?.message || data?.error || `LLM7.io HTTP ${r.status}`);
  const text = data.choices?.[0]?.message?.content || "";
  if (!text) throw new Error("LLM7.io returned empty response");
  return text;
}

async function callModelScope(prompt, maxTokens, env) {
  const key = env.MODELSCOPE_API_KEY;
  if (!key) throw new Error("MODELSCOPE_API_KEY not set");
  const r = await fetch("https://api-inference.modelscope.cn/v1/chat/completions", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
    body: JSON.stringify({
      model: env.MODELSCOPE_MODEL || "Qwen/Qwen3.5-35B-A3B",
      messages: [{ role: "user", content: prompt }],
      max_tokens: maxTokens,
    }),
  });
  const data = await safeJson(r);
  if (!r.ok) throw new Error(data?.error?.message || data?.error || `ModelScope HTTP ${r.status}`);
  const text = data.choices?.[0]?.message?.content || "";
  if (!text) throw new Error("ModelScope returned empty response");
  return text;
}

async function callNvidiaNim(prompt, maxTokens, env) {
  const key = env.NVIDIA_API_KEY;
  if (!key) throw new Error("NVIDIA_API_KEY not set");
  const r = await fetch("https://integrate.api.nvidia.com/v1/chat/completions", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
    body: JSON.stringify({
      model: env.NVIDIA_MODEL || "meta/llama-3.3-70b-instruct",
      messages: [{ role: "user", content: prompt }],
      max_tokens: maxTokens,
    }),
  });
  const data = await safeJson(r);
  if (!r.ok) throw new Error(data?.error?.message || data?.error || `NVIDIA NIM HTTP ${r.status}`);
  const text = data.choices?.[0]?.message?.content || "";
  if (!text) throw new Error("NVIDIA NIM returned empty response");
  return text;
}

async function callOllamaCloud(prompt, maxTokens, env) {
  const key = env.OLLAMA_API_KEY;
  if (!key) throw new Error("OLLAMA_API_KEY not set");
  const r = await fetch("https://ollama.com/v1/chat/completions", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
    body: JSON.stringify({
      model: env.OLLAMA_MODEL || "gpt-oss:120b",
      messages: [{ role: "user", content: prompt }],
      max_tokens: maxTokens,
    }),
  });
  const data = await safeJson(r);
  if (!r.ok) throw new Error(data?.error?.message || data?.error || `Ollama Cloud HTTP ${r.status}`);
  const text = data.choices?.[0]?.message?.content || "";
  if (!text) throw new Error("Ollama Cloud returned empty response");
  return text;
}

async function callOvhCloud(prompt, maxTokens, env) {
  const headers = { "Content-Type": "application/json" };
  if (env.OVHCLOUD_API_KEY) headers.Authorization = `Bearer ${env.OVHCLOUD_API_KEY}`;
  const r = await fetch("https://oai.endpoints.kepler.ai.cloud.ovh.net/v1/chat/completions", {
    method: "POST",
    headers,
    body: JSON.stringify({
      model: env.OVHCLOUD_MODEL || "gpt-oss-120b",
      messages: [{ role: "user", content: prompt }],
      max_tokens: maxTokens,
    }),
  });
  const data = await safeJson(r);
  if (!r.ok) throw new Error(data?.error?.message || data?.error || `OVHcloud HTTP ${r.status}`);
  const text = data.choices?.[0]?.message?.content || "";
  if (!text) throw new Error("OVHcloud returned empty response");
  return text;
}

async function callSiliconFlow(prompt, maxTokens, env) {
  const key = env.SILICONFLOW_API_KEY;
  if (!key) throw new Error("SILICONFLOW_API_KEY not set");
  const r = await fetch("https://api.siliconflow.cn/v1/chat/completions", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
    body: JSON.stringify({
      model: env.SILICONFLOW_MODEL || "Qwen/Qwen3-8B",
      messages: [{ role: "user", content: prompt }],
      max_tokens: maxTokens,
    }),
  });
  const data = await safeJson(r);
  if (!r.ok) throw new Error(data?.error?.message || data?.error || `SiliconFlow HTTP ${r.status}`);
  const text = data.choices?.[0]?.message?.content || "";
  if (!text) throw new Error("SiliconFlow returned empty response");
  return text;
}

async function callHuggingFace(prompt, maxTokens, env) {
  const key = env.HF_API_KEY;
  if (!key) throw new Error("HF_API_KEY not set");
  const model = env.HF_MODEL || "openai/gpt-oss-120b";
  const r = await fetch("https://router.huggingface.co/v1/chat/completions", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
    body: JSON.stringify({
      model,
      messages: [{ role: "user", content: prompt }],
      max_tokens: maxTokens,
    }),
  });
  const data = await safeJson(r);
  if (!r.ok) throw new Error(data?.error?.message || data?.error || `Hugging Face HTTP ${r.status}`);
  const text = data.choices?.[0]?.message?.content || "";
  if (!text) throw new Error("Hugging Face returned empty response");
  return text.trim();
}

async function callGroq(prompt, maxTokens, env) {
  const key = env.GROQ_API_KEY;
  if (!key) throw new Error("GROQ_API_KEY not set");
  const r = await fetch("https://api.groq.com/openai/v1/chat/completions", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
    body: JSON.stringify({
      model: env.GROQ_MODEL || "openai/gpt-oss-120b",
      messages: [{ role: "user", content: prompt }],
      max_tokens: maxTokens,
      // gpt-oss «فکر» می‌کند و فکرش از سقفِ توکن و زمان کم می‌کند → حداقل
      ...((env.GROQ_MODEL || "openai/gpt-oss-120b").includes("gpt-oss")
        ? { reasoning_effort: "low", include_reasoning: false }
        : {}),
    }),
  });
  const data = await safeJson(r);
  if (!r.ok) throw new Error(data?.error?.message || `Groq HTTP ${r.status}`);
  const text = data.choices?.[0]?.message?.content || "";
  if (!text) throw new Error("Groq returned empty response");
  return text;
}

async function callGemini(prompt, maxTokens, env) {
  const key = env.GEMINI_API_KEY;
  if (!key) throw new Error("GEMINI_API_KEY not set");
  const model = env.GEMINI_MODEL || "gemini-3.6-flash";
  const r = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${key}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: { maxOutputTokens: maxTokens },
      }),
    }
  );
  const data = await safeJson(r);
  if (!r.ok) throw new Error(data?.error?.message || `Gemini HTTP ${r.status}`);
  const text = (data.candidates?.[0]?.content?.parts || []).map((p) => p.text || "").join("");
  if (!text) throw new Error("Gemini returned empty response");
  return text;
}

async function callDeepSeek(prompt, maxTokens, env) {
  const key = env.DEEPSEEK_API_KEY;
  if (!key) throw new Error("DEEPSEEK_API_KEY not set");
  const baseUrl = env.DEEPSEEK_BASE_URL || "https://api.deepseek.com";
  const r = await fetch(`${baseUrl}/chat/completions`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
    body: JSON.stringify({
      model: env.DEEPSEEK_MODEL || "deepseek-v4.1-flash",
      messages: [{ role: "user", content: prompt }],
      max_tokens: maxTokens,
    }),
  });
  const data = await safeJson(r);
  if (!r.ok) throw new Error(data?.error?.message || `DeepSeek HTTP ${r.status}`);
  const text = data.choices?.[0]?.message?.content || "";
  if (!text) throw new Error("DeepSeek returned empty response");
  return text;
}

async function callOpenAI(prompt, maxTokens, env) {
  const key = env.OPENAI_API_KEY;
  if (!key) throw new Error("OPENAI_API_KEY not set");
  const r = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
    body: JSON.stringify({
      model: env.OPENAI_MODEL || "gpt-4o-mini",
      messages: [{ role: "user", content: prompt }],
      max_tokens: maxTokens,
    }),
  });
  const data = await safeJson(r);
  if (!r.ok) throw new Error(data?.error?.message || `OpenAI HTTP ${r.status}`);
  const text = data.choices?.[0]?.message?.content || "";
  if (!text) throw new Error("OpenAI returned empty response");
  return text;
}

async function callGrok(prompt, maxTokens, env) {
  const key = env.GROK_API_KEY || env.XAI_API_KEY;
  if (!key) throw new Error("GROK_API_KEY not set");
  const r = await fetch("https://api.x.ai/v1/chat/completions", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
    body: JSON.stringify({
      model: env.GROK_MODEL || "grok-3-mini",
      messages: [{ role: "user", content: prompt }],
      max_tokens: maxTokens,
    }),
  });
  const data = await safeJson(r);
  if (!r.ok) throw new Error(data?.error?.message || data?.error || `Grok HTTP ${r.status}`);
  const text = data.choices?.[0]?.message?.content || "";
  if (!text) throw new Error("Grok returned empty response");
  return text;
}

async function callOpenRouter(prompt, maxTokens, env) {
  const key = env.OPENROUTER_API_KEY;
  if (!key) throw new Error("OPENROUTER_API_KEY not set");
  const r = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${key}`,
      ...(env.OPENROUTER_SITE_URL ? { "HTTP-Referer": env.OPENROUTER_SITE_URL } : {}),
      "X-Title": "LingoLearn",
    },
    body: JSON.stringify({
      model: env.OPENROUTER_MODEL || "deepseek/deepseek-chat",
      messages: [{ role: "user", content: prompt }],
      max_tokens: maxTokens,
    }),
  });
  const data = await safeJson(r);
  if (!r.ok) throw new Error(data?.error?.message || `OpenRouter HTTP ${r.status}`);
  const text = data.choices?.[0]?.message?.content || "";
  if (!text) throw new Error("OpenRouter returned empty response");
  return text;
}

async function callMistral(prompt, maxTokens, env) {
  const key = env.MISTRAL_API_KEY;
  if (!key) throw new Error("MISTRAL_API_KEY not set");
  const r = await fetch("https://api.mistral.ai/v1/chat/completions", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
    body: JSON.stringify({
      model: env.MISTRAL_MODEL || "mistral-small-latest",
      messages: [{ role: "user", content: prompt }],
      max_tokens: maxTokens,
    }),
  });
  const data = await safeJson(r);
  if (!r.ok) throw new Error(data?.error?.message || `Mistral HTTP ${r.status}`);
  const text = data.choices?.[0]?.message?.content || "";
  if (!text) throw new Error("Mistral returned empty response");
  return text;
}

async function callCerebras(prompt, maxTokens, env) {
  const key = env.CEREBRAS_API_KEY;
  if (!key) throw new Error("CEREBRAS_API_KEY not set");
  const r = await fetch("https://api.cerebras.ai/v1/chat/completions", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
    body: JSON.stringify({
      model: env.CEREBRAS_MODEL || "llama3.1-8b",
      messages: [{ role: "user", content: prompt }],
      max_tokens: maxTokens,
    }),
  });
  const data = await safeJson(r);
  if (!r.ok) throw new Error(data?.error?.message || `Cerebras HTTP ${r.status}`);
  const text = data.choices?.[0]?.message?.content || "";
  if (!text) throw new Error("Cerebras returned empty response");
  return text;
}

async function callAvalAI(prompt, maxTokens, env) {
  const key = env.AVALAI_API_KEY;
  if (!key) throw new Error("AVALAI_API_KEY not set");
  const r = await fetch("https://api.avalai.ir/v1/chat/completions", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
    body: JSON.stringify({
      model: env.AVALAI_MODEL || "deepseek-chat",
      messages: [{ role: "user", content: prompt }],
      max_tokens: maxTokens,
    }),
  });
  const data = await safeJson(r);
  if (!r.ok) throw new Error(data?.error?.message || `AvalAI HTTP ${r.status}`);
  const text = data.choices?.[0]?.message?.content || "";
  if (!text) throw new Error("AvalAI returned empty response");
  return text;
}
