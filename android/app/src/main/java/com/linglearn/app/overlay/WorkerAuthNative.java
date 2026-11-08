package com.linglearn.app.overlay;

import android.content.Context;
import android.content.SharedPreferences;

import okhttp3.Request;

/**
 * 🔐 توکنِ نشستِ Worker برای بخشِ بومی (حبابِ ترجمه‌ی زنده، زیرنویس، ترانه).
 * توکن را Flutter بعد از لاگین می‌گیرد و در SharedPreferences می‌گذارد
 * (فایلِ FlutterSharedPreferences، کلیدِ flutter.worker_token)؛ اینجا فقط خوانده می‌شود.
 */
final class WorkerAuthNative {

    private WorkerAuthNative() {}

    static final String WORKER_HOST_PREFIX = "https://phrasebook-api.";

    private static volatile Context appCtx;

    static void init(Context c) {
        if (c != null) appCtx = c.getApplicationContext();
    }

    private static Context ctx() {
        Context c = appCtx;
        if (c != null) return c;
        try {                                   // اگر هنوز init نشده بود (مثلاً از یک رشته‌ی کمکی)
            Object app = Class.forName("android.app.ActivityThread").getMethod("currentApplication").invoke(null);
            if (app instanceof Context) { appCtx = (Context) app; return appCtx; }
        } catch (Throwable ignored) {}
        return null;
    }

    static String token() {
        try {
            Context c = ctx();
            if (c == null) return "";
            SharedPreferences sp = c.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE);
            String t = sp.getString("flutter.worker_token", "");
            return t == null ? "" : t;
        } catch (Throwable e) {
            return "";
        }
    }

    /** فقط برای آدرسِ Workerِ خودمان هدرِ X-App-Token اضافه می‌شود. */
    static Request.Builder sign(Request.Builder b, String url) {
        if (url != null && url.startsWith(WORKER_HOST_PREFIX)) {
            String t = token();
            if (!t.isEmpty()) b.header("X-App-Token", t);
        }
        return b;
    }
}
