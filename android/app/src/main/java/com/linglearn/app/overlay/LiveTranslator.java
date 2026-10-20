package com.linglearn.app.overlay;

import android.content.Context;
import android.util.Log;

import java.io.IOException;
import java.util.Locale;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.regex.Pattern;

import okhttp3.OkHttpClient;

/**
 * ترجمه‌ی زنده — سریع و بدونِ پرشِ دیدنی:
 *   کش → سرویس‌های رایگان (موازیِ تدریجی، داخلِ FreeTranslator)
 *   اگر نتیجه مشکوک بود (یا سرویس‌ها شکست خوردند یا کند بودند) → «مستقیم» ترجمه‌ی AI، بدونِ مرحله‌ی بازبینیِ جدا.
 *   - اگر رایگان بیش از AI_HEDGE_MS طول کشید، AI «هم‌زمان» شروع می‌شود تا وقتی رایگان مشکوک درآمد، جوابِ AI
 *     از قبل در راه یا آماده باشد (کاربر هیچ‌وقت متنِ مشکوک را نمی‌بیند؛ فقط ترجمه‌ی نهایی می‌آید).
 *   - فقط نتیجه‌ی تأییدشده کش می‌شود (همان‌جا که اپ در IndexedDB کش می‌کند).
 */
final class LiveTranslator {
    private static final String TAG = "LiveTranslator";

    /** اگر ترجمه‌ی رایگان تا این مدت نیامد، ترجمه‌ی AI هم‌زمان شروع می‌شود. */
    private static final long AI_HEDGE_MS = 600;

    private static final ExecutorService POOL = Executors.newCachedThreadPool(new ThreadFactory() {
        @Override public Thread newThread(Runnable r) {
            Thread t = new Thread(r, "live-translate");
            t.setDaemon(true);
            return t;
        }
    });

    /** پشتیبانِ AI (ورکرِ خودِ اپ) — فقط وقتی لازم شود صدا زده می‌شود. */
    interface Ai {
        String translate(String text, String tgt) throws Exception;
        /** (دیگر در مسیرِ زنده استفاده نمی‌شود؛ ترجمه‌ی مستقیمِ AI سریع‌تر است.) */
        String verify(String text, String tgt, String draft) throws Exception;
    }

    private LiveTranslator() {}

    static String translate(Context ctx, OkHttpClient http, final String text, String src, final String tgt, final Ai ai) throws Exception {
        if (text == null) throw new IllegalArgumentException("no text");
        final String t = text.trim();
        if (t.isEmpty()) return "";
        final String s = (src == null || src.isEmpty()) ? "auto" : src;
        if (s.equals(tgt)) return t;

        final TransCache cache = TransCache.get(ctx);
        final String cached = cache.get(s, tgt, t);
        if (cached != null) {
            if (!looksLikelyMistranslated(t, cached, tgt, s)) return cached;
            cache.remove(s, tgt, t);                       // کشِ قدیمیِ مشکوک: نادیده + پاک
        }

        final OkHttpClient client = http;
        final Future<String> freeF = POOL.submit(new Callable<String>() {
            @Override public String call() throws Exception { return FreeTranslator.translate(client, t, s, tgt); }
        });
        Future<String> aiF = null;
        String out = null;
        Exception last = null;

        try {
            out = freeF.get(ai != null ? AI_HEDGE_MS : 60_000, TimeUnit.MILLISECONDS);
        } catch (TimeoutException te) {
            // رایگان کند است → AI را هم‌زمان شروع کن و منتظرِ رایگان هم بمان
            aiF = submitAi(ai, t, tgt);
            try { out = freeF.get(); }
            catch (ExecutionException ee) { last = asException(ee); }
        } catch (ExecutionException ee) {
            last = asException(ee);
            Log.d(TAG, "free translators failed: " + last);
        }

        if (out != null && looksLikelyMistranslated(t, out, tgt, s)) out = null;   // غلط را نه نشان بده نه کش کن

        if (out == null && ai != null) {
            if (aiF == null) aiF = submitAi(ai, t, tgt);
            try {
                String r = aiF.get();
                if (r != null) {
                    r = cleanQuotes(r.trim());
                    if (!r.isEmpty() && !looksLikelyMistranslated(t, r, tgt, s)) out = r;
                }
            } catch (ExecutionException ee) { last = asException(ee); }
        } else if (aiF != null) {
            aiF.cancel(true);                                // رایگانِ سالم رسید؛ AI لازم نیست
        }

        if (out == null) throw last != null ? last : new IOException("translation failed");
        cache.put(s, tgt, t, out);
        return out;
    }

    private static Future<String> submitAi(final Ai ai, final String t, final String tgt) {
        if (ai == null) return null;
        return POOL.submit(new Callable<String>() {
            @Override public String call() throws Exception { return ai.translate(t, tgt); }
        });
    }

    private static Exception asException(ExecutionException ee) {
        Throwable c = ee.getCause();
        return c instanceof Exception ? (Exception) c : new IOException(String.valueOf(c));
    }

    private static String cleanQuotes(String s) {
        return s.replaceAll("^[\"'«»]+|[\"'«».\\s]+$", "").trim();
    }

    // ───────── looksLikelyMistranslated (همتای app.jsx) ─────────

    private static final Pattern REASONING = Pattern.compile(
            "(thinking process|here'?s a thinking|analy[sz]e the (request|text|input)|\\*\\*\\s*analy[sz]e|\\bconstraint\\s*:|the user wants me to|let me (read|think|analy[sz]e|re-?read)|</?think(ing)?>)",
            Pattern.CASE_INSENSITIVE);

    private static Pattern scriptRangeFor(String lang) {
        switch (lang) {
            case "fa": case "ar": return Pattern.compile("[\\u0600-\\u06FF]");
            case "ru": return Pattern.compile("[\\u0400-\\u04FF]");
            case "zh": return Pattern.compile("[\\u4E00-\\u9FFF]");
            case "ja": return Pattern.compile("[\\u3040-\\u30FF\\u4E00-\\u9FFF]");
            case "ko": return Pattern.compile("[\\uAC00-\\uD7AF]");
            case "hi": return Pattern.compile("[\\u0900-\\u097F]");
            default: return null;
        }
    }

    static boolean looksLikelyMistranslated(String sourceText, String draft, String targetLang, String sourceLang) {
        final String src = sourceText == null ? "" : sourceText.trim();
        final String out = draft == null ? "" : draft.trim();
        if (out.isEmpty()) return true;
        // AI گاهی به‌جای ترجمه «فرایندِ فکر کردنش» را می‌نویسد؛ آن را ترجمه حساب نکن
        if (REASONING.matcher(out).find()) return true;
        // مبدأ و مقصد فرق دارند ولی خروجی عیناً همان متنِ مبدأ است → ترجمه نشده
        if (sourceLang != null && !"auto".equals(sourceLang) && !sourceLang.equals(targetLang)
                && out.toLowerCase(Locale.ROOT).equals(src.toLowerCase(Locale.ROOT))) return true;
        // رسم‌الخطِ زبانِ مقصد مشخص است ولی اثری از آن در خروجی نیست
        Pattern re = scriptRangeFor(targetLang);
        if (re != null && src.length() > 1 && !re.matcher(out).find()) return true;
        // نسبتِ طولِ غیرعادی (برای زبان‌های CJK که فشرده‌اند حدِ پایین سخت‌گیرانه‌تر نیست)
        boolean cjk = "zh".equals(targetLang) || "ja".equals(targetLang) || "ko".equals(targetLang);
        double ratio = out.length() / (double) Math.max(src.length(), 1);
        double lo = cjk ? 0.08 : 0.25;
        if (src.length() > 3 && (ratio < lo || ratio > 3.5)) return true;
        // یک کلمه‌ی تکراریِ پشتِ‌سرهم (نشانه‌ی خرابیِ سرویس)
        if (out.length() > 20 && out.matches("(?s).*\\b(\\p{L}{2,})(\\s+\\1){4,}\\b.*")) return true;

        // ── بررسی‌های تازه (ترجمه‌ی غلط/نیمه‌کاره‌ای که از فیلترهای بالا رد می‌شد) ──
        // پیامِ خطای سرویس / HTML / JSON / توضیحِ AI به‌جای ترجمه
        if (SERVICE_JUNK.matcher(out).find() && !SERVICE_JUNK.matcher(src).find()) return true;
        // عدد در مبدأ هست (۲ رقم یا بیشتر) ولی هیچ رقمی در خروجی نیست
        if (MULTI_DIGIT.matcher(src).find() && !ANY_DIGIT.matcher(out).find() && out.length() < src.length() * 2) return true;
        boolean tgtLatin = isLatinTarget(targetLang);
        boolean srcHasForeign = FOREIGN_SCRIPT.matcher(src).find();
        // رسم‌الخطِ بی‌ربط در خروجی (مثلاً چینی/سیریلیک/هانگول وسطِ ترجمه‌ی فارسی)
        if (!srcHasForeign && FOREIGN_SCRIPT.matcher(out).find()
                && !"zh".equals(targetLang) && !"ja".equals(targetLang) && !"ko".equals(targetLang) && !"ru".equals(targetLang)) return true;
        // مقصد غیرلاتین ولی بخشِ بزرگی از خروجی هنوز لاتین است = ترجمه‌نشده/نیمه‌ترجمه
        if (!tgtLatin && src.length() > 12) {
            int latin = 0, letters = 0;
            for (int i = 0; i < out.length(); i++) {
                char c = out.charAt(i);
                if (!Character.isLetter(c)) continue;
                letters++;
                if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')) latin++;
            }
            if (letters >= 8 && latin / (double) letters > 0.45) return true;
        }
        // مقصدِ لاتین: بیشترِ کلمه‌های خروجی عیناً همان کلمه‌های مبدأ است = ترجمه نشده
        if (tgtLatin && sourceLang != null && !sourceLang.equals(targetLang)) {
            String[] sw = src.toLowerCase(Locale.ROOT).split("[^\\p{L}\\p{N}']+");
            String[] ow = out.toLowerCase(Locale.ROOT).split("[^\\p{L}\\p{N}']+");
            if (sw.length >= 5 && ow.length >= 5) {
                java.util.HashSet<String> set = new java.util.HashSet<>(java.util.Arrays.asList(sw));
                int same = 0;
                for (String w : ow) if (set.contains(w)) same++;
                if (same / (double) ow.length >= 0.85) return true;
            }
        }
        return false;
    }

    private static final Pattern SERVICE_JUNK = Pattern.compile(
            "(<\\s*/?\\s*(html|body|div|br)\\b|\\{\\s*\"|\\bhttp error\\b|\\bquota\\b|\\brequest failed\\b|here'?s the translation|here is the translation"
                    + "|\\btranslation\\s*:|\\bas an ai\\b|\\bi (cannot|can'?t|am unable to) translate\\b|\\bsorry,? i\\b|MYMEMORY WARNING|PLEASE SELECT)",
            Pattern.CASE_INSENSITIVE);
    private static final Pattern MULTI_DIGIT = Pattern.compile("\\d{2,}");
    private static final Pattern ANY_DIGIT = Pattern.compile("[0-9\\u06F0-\\u06F9\\u0660-\\u0669]");
    private static final Pattern FOREIGN_SCRIPT = Pattern.compile("[\\u0400-\\u04FF\\u3040-\\u30FF\\u4E00-\\u9FFF\\uAC00-\\uD7AF\\u0E00-\\u0E7F]");

    private static boolean isLatinTarget(String lang) {
        return scriptRangeFor(lang == null ? "" : lang) == null;
    }

    /**
     * ترجمه‌ی «مستقیم با AI» برای جمله‌ای که ترجمه‌ی موجودش مشکوک است (بدونِ مرحله‌ی رایگان).
     * فقط نتیجه‌ی سالم برمی‌گردد و کش می‌شود؛ وگرنه استثنا پرتاب می‌شود.
     */
    static String aiOnly(Context ctx, String text, String src, String tgt, Ai ai) throws Exception {
        if (ai == null) throw new IOException("no ai");
        final String t = text == null ? "" : text.trim();
        if (t.isEmpty()) return "";
        final String s = (src == null || src.isEmpty()) ? "auto" : src;
        String r = ai.translate(t, tgt);
        if (r == null) throw new IOException("ai empty");
        r = cleanQuotes(r.trim());
        if (r.isEmpty() || looksLikelyMistranslated(t, r, tgt, s)) throw new IOException("ai result rejected");
        TransCache.get(ctx).put(s, tgt, t, r);
        return r;
    }
}
