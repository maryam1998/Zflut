package com.linglearn.app.overlay;

import android.content.Context;
import android.util.Log;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;

/**
 * بسته‌های تشخیص گفتارِ «سریع و سبک» (فرانسوی / آلمانی / اسپانیایی) — مجوز Apache 2.0.
 * کاملاً جدا از SherpaModelManager و WhisperModelManager. بسته داخل APK نیست؛ کاربر دانلودش می‌کند
 * و توی files/vosk/<lang>/model/ ذخیره می‌شود. دانلود با Range قابل ادامه است.
 */
final class VoskModelManager {

    private static final String TAG = "VoskModelMgr";
    private static final String BASE = "https://alphacephei.com/vosk/models/";

    private VoskModelManager() {}

    interface Callback {
        void onProgress(String lang, long done, long total);
        void onDone(String lang);
        void onError(String lang, Exception e);
    }

    private static final class Spec {
        final String zip;
        final int approxMb;
        Spec(String zip, int approxMb) { this.zip = zip; this.approxMb = approxMb; }
    }

    private static final Map<String, Spec> SPECS;
    static {
        Map<String, Spec> m = new LinkedHashMap<>();
        m.put("fr", new Spec("vosk-model-small-fr-0.22.zip", 41));
        m.put("de", new Spec("vosk-model-small-de-0.15.zip", 45));
        m.put("es", new Spec("vosk-model-small-es-0.42.zip", 39));
        SPECS = Collections.unmodifiableMap(m);
    }

    private static final OkHttpClient HTTP = new OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .build();

    private static final AtomicBoolean DOWNLOADING = new AtomicBoolean(false);
    private static volatile boolean CANCEL = false;
    private static volatile String ACTIVE = null;

    static final class Cancelled extends IOException {
        Cancelled() { super("cancelled"); }
    }

    static boolean isAvailable(String lang) {
        String l = SherpaModelManager.normalize(lang);
        return l != null && SPECS.containsKey(l);
    }
    static boolean isDownloading() { return DOWNLOADING.get(); }
    static String activeLang() { return ACTIVE; }
    static void cancel() { if (DOWNLOADING.get()) CANCEL = true; }
    static int approxMb(String lang) {
        Spec s = SPECS.get(SherpaModelManager.normalize(lang));
        return s == null ? 0 : s.approxMb;
    }

    private static File langDir(Context ctx, String l) {
        return new File(new File(ctx.getFilesDir(), "vosk"), l);
    }

    /** پوشه‌ی مدلِ آماده (که Vosk مستقیم باز می‌کند)، وگرنه null. */
    static File getModelDir(Context ctx, String lang) {
        String l = SherpaModelManager.normalize(lang);
        if (l == null || !SPECS.containsKey(l)) return null;
        File model = new File(langDir(ctx, l), "model");
        File mdl = new File(model, "am/final.mdl");
        return mdl.isFile() && mdl.length() > 0 ? model : null;
    }

    /** بایت‌های نیمه‌تمامِ دانلود (برای نمایش «ادامه»). */
    static long partialBytes(Context ctx, String lang) {
        String l = SherpaModelManager.normalize(lang);
        Spec s = l == null ? null : SPECS.get(l);
        if (s == null) return 0;
        File p = new File(langDir(ctx, l), s.zip + ".part");
        return p.isFile() ? p.length() : 0;
    }

    static void delete(Context ctx, String lang) {
        String l = SherpaModelManager.normalize(lang);
        if (l == null || !SPECS.containsKey(l)) return;
        deleteRecursive(langDir(ctx, l));
    }

    private static void deleteRecursive(File f) {
        if (f == null) return;
        if (f.isDirectory()) {
            File[] fs = f.listFiles();
            if (fs != null) for (File c : fs) deleteRecursive(c);
        }
        f.delete();
    }

    static void download(final Context ctx, final String lang, final Callback cb) {
        final Context app = ctx.getApplicationContext();
        final String l = SherpaModelManager.normalize(lang);
        final Spec s = l == null ? null : SPECS.get(l);
        if (s == null) {
            if (cb != null) cb.onError(String.valueOf(lang), new IllegalArgumentException("no vosk pack for " + lang));
            return;
        }
        if (!DOWNLOADING.compareAndSet(false, true)) {
            if (cb != null) cb.onError(l, new IllegalStateException("another vosk download is running"));
            return;
        }
        CANCEL = false;
        ACTIVE = l;
        Thread t = new Thread(() -> {
            Exception result = null;
            try {
                Exception last = null;
                for (int attempt = 1; attempt <= 3; attempt++) {
                    try {
                        downloadOnce(app, l, s, cb);
                        last = null;
                        break;
                    } catch (Cancelled c) {
                        last = c;
                        break;
                    } catch (Exception e) {
                        last = e;
                        Log.w(TAG, "attempt " + attempt + " failed for " + l, e);
                        if (CANCEL) { last = new Cancelled(); break; }
                        try { Thread.sleep(1500L * attempt); } catch (InterruptedException ie) { break; }
                    }
                }
                result = last;
            } finally {
                // اول وضعیت پاک می‌شود، بعد به UI خبر می‌دهیم (تا دکمه‌ها گیر نکنند)
                ACTIVE = null;
                CANCEL = false;
                DOWNLOADING.set(false);
            }
            if (cb != null) {
                if (result != null) cb.onError(l, result); else cb.onDone(l);
            }
        }, "vosk-download");
        t.setDaemon(true);
        t.start();
    }

    private static void downloadOnce(Context app, String l, Spec s, Callback cb) throws Exception {
        File dir = langDir(app, l);
        if (!dir.isDirectory() && !dir.mkdirs()) throw new IOException("cannot create " + dir);
        if (getModelDir(app, l) != null) return;

        File zip = new File(dir, s.zip);
        File part = new File(dir, s.zip + ".part");

        if (!(zip.isFile() && zip.length() > 0)) {
            long have = part.isFile() ? part.length() : 0;
            Request.Builder rb = new Request.Builder().url(BASE + s.zip);
            if (have > 0) rb.header("Range", "bytes=" + have + "-");
            try (Response r = HTTP.newCall(rb.build()).execute()) {
                if (r.code() == 416) {                        // .part قبلاً کامل بوده
                    if (!part.renameTo(zip)) throw new IOException("rename failed: " + s.zip);
                } else {
                    if (!r.isSuccessful() || r.body() == null) throw new IOException("HTTP " + r.code() + " for " + s.zip);
                    boolean resumed = r.code() == 206 && have > 0;
                    if (!resumed) have = 0;                   // سرور Range را نپذیرفت → از صفر
                    long len = r.body().contentLength();
                    long total = len > 0 ? have + len : -1;
                    long done = have;
                    try (InputStream in = r.body().byteStream();
                         OutputStream out = new FileOutputStream(part, resumed)) {
                        byte[] buf = new byte[64 * 1024];
                        int n;
                        while ((n = in.read(buf)) > 0) {
                            if (CANCEL) throw new Cancelled();
                            out.write(buf, 0, n);
                            done += n;
                            if (cb != null) cb.onProgress(l, done, total);
                        }
                    }
                    if (total > 0 && part.length() != total) throw new IOException("incomplete download: " + s.zip);
                    if (!part.renameTo(zip)) throw new IOException("rename failed: " + s.zip);
                }
            }
        }

        if (CANCEL) throw new Cancelled();
        File tmp = new File(dir, "model.tmp");
        File model = new File(dir, "model");
        deleteRecursive(tmp);
        deleteRecursive(model);
        try {
            unzipStripTop(zip, tmp);
            if (!new File(tmp, "am/final.mdl").isFile()) throw new IOException("bad vosk pack layout");
            if (!tmp.renameTo(model)) throw new IOException("rename failed: model");
        } catch (Exception e) {
            deleteRecursive(tmp);
            zip.delete();                                      // فایل خراب؛ دفعه‌ی بعد از اول گرفته شود
            throw e;
        }
        zip.delete();
    }

    /** zip را باز می‌کند و پوشه‌ی سطحِ بالا (vosk-model-…) را حذف می‌کند. با محافظت در برابر zip-slip. */
    private static void unzipStripTop(File zip, File destDir) throws IOException {
        if (!destDir.isDirectory() && !destDir.mkdirs()) throw new IOException("cannot create " + destDir);
        String destCanon = destDir.getCanonicalPath() + File.separator;
        try (ZipInputStream zin = new ZipInputStream(new FileInputStream(zip))) {
            ZipEntry e;
            byte[] buf = new byte[64 * 1024];
            while ((e = zin.getNextEntry()) != null) {
                if (CANCEL) throw new Cancelled();
                String name = e.getName().replace('\\', '/');
                int slash = name.indexOf('/');
                if (slash < 0) continue;                       // فایلِ بیرون از پوشه‌ی اصلی
                String rel = name.substring(slash + 1);
                if (rel.isEmpty()) continue;
                File out = new File(destDir, rel);
                if (!out.getCanonicalPath().startsWith(destCanon)) throw new IOException("bad zip entry: " + name);
                if (e.isDirectory()) {
                    if (!out.isDirectory() && !out.mkdirs()) throw new IOException("cannot create " + out);
                    continue;
                }
                File parent = out.getParentFile();
                if (parent != null && !parent.isDirectory() && !parent.mkdirs()) throw new IOException("cannot create " + parent);
                try (OutputStream os = new FileOutputStream(out)) {
                    int n;
                    while ((n = zin.read(buf)) > 0) os.write(buf, 0, n);
                }
            }
        }
    }
}
