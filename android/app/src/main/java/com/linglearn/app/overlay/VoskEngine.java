package com.linglearn.app.overlay;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import org.json.JSONObject;
import org.vosk.LibVosk;
import org.vosk.LogLevel;
import org.vosk.Model;
import org.vosk.Recognizer;

import java.io.File;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;

/**
 * موتور تشخیص گفتارِ «سریع و سبک» (Vosk) برای فرانسوی/آلمانی/اسپانیایی.
 * جریانی است (مثل SherpaEngine): متنِ در حال گفتن را به‌صورت partial و جمله‌ی تمام‌شده را به‌صورت final
 * به BubbleService می‌دهد. رمزگشایی در نخِ جدا انجام می‌شود تا ضبط/UI بلاک نشود.
 */
final class VoskEngine implements PcmSink {

    private static final String TAG = "VoskEngine";
    private static final float SAMPLE_RATE = 16000f;

    private static final Handler MAIN = new Handler(Looper.getMainLooper());

    private final Object lock = new Object();
    private Model model;
    private Recognizer recognizer;
    private volatile boolean released = false;
    private volatile boolean failed = false;
    private String lastPartial = "";
    private final LinkedBlockingQueue<byte[]> queue = new LinkedBlockingQueue<>(500);
    private Thread worker;

    private VoskEngine(Model m, Recognizer r) {
        this.model = m;
        this.recognizer = r;
        worker = new Thread(this::runWorker, "vosk-decode");
        worker.setDaemon(true);
        worker.start();
    }

    static boolean isAvailable(Context ctx, String lang) {
        return VoskModelManager.getModelDir(ctx, lang) != null;
    }

    static VoskEngine create(Context ctx, String lang) {
        File dir = VoskModelManager.getModelDir(ctx, lang);
        if (dir == null) return null;
        Model m = null;
        Recognizer r = null;
        try {
            try { LibVosk.setLogLevel(LogLevel.WARNINGS); } catch (Throwable ignored) {}
            m = new Model(dir.getAbsolutePath());
            r = new Recognizer(m, SAMPLE_RATE);
            Log.i(TAG, "vosk model loaded from " + dir);
            return new VoskEngine(m, r);
        } catch (Throwable e) {
            Log.e(TAG, "cannot load vosk model for " + lang, e);
            if (r != null) { try { r.close(); } catch (Throwable ignored) {} }
            if (m != null) { try { m.close(); } catch (Throwable ignored) {} }
            return null;
        }
    }

    @Override
    public void accept(byte[] pcm16k, int len) {
        if (pcm16k == null || len < 2 || released || failed) return;
        byte[] copy = new byte[len];
        System.arraycopy(pcm16k, 0, copy, 0, len);
        if (!queue.offer(copy)) { queue.poll(); queue.offer(copy); }   // موتور عقب افتاد → قدیمی‌ترین تکه دور ریخته می‌شود
    }

    private void runWorker() {
        try { android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_URGENT_AUDIO); } catch (Throwable ignored) {}
        while (!released && !failed) {
            byte[] chunk;
            try { chunk = queue.poll(100, TimeUnit.MILLISECONDS); }
            catch (InterruptedException e) { return; }
            if (chunk == null) continue;
            String partialToSend = null, finalToSend = null;
            boolean fail = false;
            synchronized (lock) {
                if (released || failed || recognizer == null) return;
                try {
                    boolean endpoint = recognizer.acceptWaveForm(chunk, chunk.length);
                    if (endpoint) {
                        String text = field(recognizer.getResult(), "text");
                        lastPartial = "";
                        if (!text.isEmpty()) finalToSend = text;
                    } else {
                        String text = field(recognizer.getPartialResult(), "partial");
                        if (!text.isEmpty() && !text.equals(lastPartial)) {
                            lastPartial = text;
                            partialToSend = text;
                        }
                    }
                } catch (Throwable e) {
                    Log.e(TAG, "decode failed", e);
                    failed = true;
                    fail = true;
                }
            }
            if (finalToSend != null) { final String t = finalToSend; MAIN.post(() -> BubbleService.asrFinal(t)); }
            else if (partialToSend != null) { final String t = partialToSend; MAIN.post(() -> BubbleService.asrPartial(t)); }
            if (fail) MAIN.post(BubbleService::asrFallback);
        }
    }

    private static String field(String json, String key) {
        if (json == null || json.isEmpty()) return "";
        try {
            return new JSONObject(json).optString(key, "").trim();
        } catch (Throwable t) {
            return "";
        }
    }

    @Override
    public void release() {
        synchronized (lock) {
            if (released) return;
            released = true;
            try { if (recognizer != null) recognizer.close(); } catch (Throwable e) { Log.w(TAG, "recognizer close", e); }
            try { if (model != null) model.close(); } catch (Throwable e) { Log.w(TAG, "model close", e); }
            recognizer = null;
            model = null;
            lastPartial = "";
        }
        queue.clear();
        Thread w = worker;
        if (w != null) w.interrupt();
    }
}
