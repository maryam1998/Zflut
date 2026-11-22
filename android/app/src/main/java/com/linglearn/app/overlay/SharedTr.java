package com.linglearn.app.overlay;

import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.TimeUnit;

import okhttp3.MediaType;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;
import okhttp3.ResponseBody;

/**
 * 🗄️ کشِ مشترکِ ترجمه بین همه‌ی کاربرها (Worker: /api/tr-share) برای بخشِ بومی (ذره‌بین).
 * همتای SharedTranslations.dart. هیچ‌وقت exception نمی‌دهد؛ هر خطا = «چیزی پیدا نشد».
 *  • get: فقط از ترد پس‌زمینه صدا بزن (بلاک می‌شود).
 *  • put: غیرهمزمان (fire-and-forget) — فقط ترجمه‌ی تأییدشده‌ی AI/اصلاح‌شده را بفرست.
 * بدونِ توکنِ لاگین (مهمان) هیچ درخواستی نمی‌رود.
 */
final class SharedTr {
    private static final String TAG = "SharedTr";
    // همان WORKER_BASE در BubbleService (آنجا private است)
    private static final String URL = BackendConfig.BASE + "/api/tr-share";
    private static final MediaType JSON_MT = MediaType.get("application/json; charset=utf-8");
    private static final int MAX_CHARS = 300;
    private static final Set<String> LANGS = new HashSet<>(Arrays.asList(
            "fa", "en", "it", "hi", "tr", "ar", "es", "de", "fr", "zh", "ko", "ru", "ja"));

    private static final OkHttpClient HTTP = new OkHttpClient.Builder()
            .connectTimeout(3, TimeUnit.SECONDS)
            .readTimeout(4, TimeUnit.SECONDS)
            .writeTimeout(3, TimeUnit.SECONDS)
            .build();

    private static final ExecutorService IO = Executors.newSingleThreadExecutor(new ThreadFactory() {
        @Override public Thread newThread(Runnable r) {
            Thread t = new Thread(r, "shared-tr");
            t.setDaemon(true);
            return t;
        }
    });

    // مواردی که در این اجرا در کشِ مشترک نبودند؛ دوباره نپرس
    private static final Set<String> MISSED = new LinkedHashSet<>();
    private static int fails = 0;
    private static long pausedUntil = 0;

    private SharedTr() {}

    private static String key(String text, String src, String tgt) {
        return (src == null || src.isEmpty() ? "auto" : src) + ">" + tgt + "|" + text.trim();
    }

    private static boolean eligible(String text, String src, String tgt) {
        if (text == null || tgt == null) return false;
        String t = text.trim();
        if (t.isEmpty() || t.length() > MAX_CHARS) return false;
        if (!LANGS.contains(tgt)) return false;
        if (src != null && !src.isEmpty() && !"auto".equals(src) && !LANGS.contains(src)) return false;
        if (src != null && src.equals(tgt)) return false;
        boolean letter = false;
        for (int i = 0; i < t.length(); i++) if (Character.isLetter(t.charAt(i))) { letter = true; break; }
        return letter;
    }

    private static synchronized boolean paused() {
        return System.currentTimeMillis() < pausedUntil;
    }

    private static synchronized void good() { fails = 0; }

    private static synchronized void bad() {
        if (++fails >= 2) {                       // سرور/شبکه پشتِ‌هم خراب بود → چند دقیقه صدا نزن
            pausedUntil = System.currentTimeMillis() + 2 * 60 * 1000L;
            fails = 0;
        }
    }

    private static Request build(JSONObject body) {
        return WorkerAuthNative.sign(new Request.Builder()
                .url(URL)
                .post(RequestBody.create(body.toString().getBytes(StandardCharsets.UTF_8), JSON_MT)), URL)
                .build();
    }

    /** ترجمه‌ی مشترک، یا null اگر نبود/نشد. فقط از ترد پس‌زمینه. */
    static String get(String text, String src, String tgt) {
        try {
            if (!eligible(text, src, tgt) || paused()) return null;
            if (WorkerAuthNative.token().isEmpty()) return null;       // مهمان / هنوز لاگین نشده
            final String t = text.trim();
            final String k = key(t, src, tgt);
            synchronized (MISSED) { if (MISSED.contains(k)) return null; }

            JSONObject body = new JSONObject();
            body.put("op", "get");
            body.put("source_lang_code", src == null || src.isEmpty() ? "auto" : src);
            body.put("target_lang_code", tgt);
            body.put("items", new JSONArray().put(new JSONObject().put("text", t)));
            try (Response r = HTTP.newCall(build(body)).execute()) {
                if (!r.isSuccessful()) { bad(); return null; }
                ResponseBody rb = r.body();
                JSONArray arr = new JSONObject(rb == null ? "{}" : rb.string()).optJSONArray("results");
                good();
                String v = (arr == null || arr.length() == 0 || arr.isNull(0)) ? "" : arr.optString(0, "").trim();
                if (v.isEmpty() || v.equalsIgnoreCase(t)) {
                    synchronized (MISSED) {
                        if (MISSED.size() > 2000) MISSED.clear();
                        MISSED.add(k);
                    }
                    return null;
                }
                return v;
            }
        } catch (Throwable e) {
            Log.d(TAG, "get failed: " + e);
            bad();
            return null;
        }
    }

    /** ذخیره‌ی ترجمه‌ی تأییدشده برای بقیه (fire-and-forget). */
    static void put(final String text, final String src, final String tgt, final String translation) {
        try {
            if (!eligible(text, src, tgt) || translation == null || paused()) return;
            final String t = text.trim(), tr = translation.trim();
            if (tr.isEmpty() || tr.length() > 1200 || tr.equalsIgnoreCase(t)) return;
            if (WorkerAuthNative.token().isEmpty()) return;
            synchronized (MISSED) { MISSED.remove(key(t, src, tgt)); }
            IO.execute(new Runnable() {
                @Override public void run() {
                    try {
                        JSONObject body = new JSONObject();
                        body.put("op", "put");
                        body.put("source_lang_code", src == null || src.isEmpty() ? "auto" : src);
                        body.put("target_lang_code", tgt);
                        body.put("text", t);
                        body.put("translation", tr);
                        try (Response r = HTTP.newCall(build(body)).execute()) {
                            int c = r.code();
                            if (c >= 200 && c < 300) good();
                            else if (c >= 500 || c == 401) bad();
                        }
                    } catch (Throwable e) {
                        Log.d(TAG, "put failed: " + e);
                        bad();
                    }
                }
            });
        } catch (Throwable ignored) { }
    }
}
