package com.linglearn.app.overlay;

import android.app.Service;
import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.IBinder;
import android.os.Looper;
import android.os.Message;
import android.os.Messenger;
import android.os.RemoteException;
import android.util.Log;

import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * موتورِ Piper توی یک پردازه‌ی جدا (android:process=":tts").
 * اگه کدِ native (sherpa-onnx / onnxruntime / espeak) کرش کنه یا exit() صدا بزنه،
 * فقط همین پردازه می‌میره و خودِ اپ باز می‌مونه؛ BubblePlugin خطا رو می‌گیره و fallback می‌ره.
 */
public class TtsService extends Service {

    private static final String TAG = "TtsService";

    // پیام‌های کلاینت → سرویس
    static final int MSG_SPEAK = 1;
    static final int MSG_STOP = 2;
    static final int MSG_PREFETCH = 3;
    static final int MSG_PRELOAD = 4;
    static final int MSG_RELEASE_ALL = 5;
    static final int MSG_RELEASE_LANG = 6;
    // پیام‌های سرویس → کلاینت
    static final int REPLY_DONE = 100;

    private static final int MAX_ENGINES = 3;   // VITS(فارسی) + Supertonic(چند زبان) + Kokoro(en/zh)

    private final ConcurrentHashMap<String, TtsEngine> engines = new ConcurrentHashMap<>();
    private volatile TtsEngine shared;
    private final AtomicInteger speakSeq = new AtomicInteger(0);
    private volatile Messenger client;

    private HandlerThread ctlThread;
    private Messenger messenger;
    // لودِ موتور (چند ثانیه) روی این thread انجام می‌شه تا thread ی کنترل هیچ‌وقت بلاک نشه
    private final ExecutorService loader = Executors.newSingleThreadExecutor(r -> {
        Thread t = new Thread(r, "tts-loader");
        t.setDaemon(true);
        return t;
    });
    // ⚡ خوانش (speak) صفِ جدا دارد: قبلاً پشتِ preload/prefetch/لودِ موتورِ زبانِ دیگر در همان صفِ loader
    // می‌ماند و چند ثانیه (تا ~۱۰ ثانیه) دیر شروع می‌شد.
    private final ExecutorService speaker = Executors.newSingleThreadExecutor(r -> {
        Thread t = new Thread(r, "tts-speaker");
        t.setDaemon(true);
        return t;
    });
    // با هر release (تعویضِ صدا/حذفِ زبان) بالا می‌رود؛ موتورِ در حالِ ساخت با صدای قدیمی دور ریخته می‌شود
    private final AtomicInteger releaseGen = new AtomicInteger(0);
    private final ConcurrentHashMap<String, Object> createLocks = new ConcurrentHashMap<>();

    @Override
    public void onCreate() {
        super.onCreate();
        TtsCrumb.init(this);
        final Thread.UncaughtExceptionHandler prev = Thread.getDefaultUncaughtExceptionHandler();
        Thread.setDefaultUncaughtExceptionHandler((t, e) -> {
            TtsCrumb.mark("java-crash:" + TtsCrumb.brief(String.valueOf(e)));
            if (prev != null) prev.uncaughtException(t, e);
        });
        ctlThread = new HandlerThread("tts-ctl");
        ctlThread.start();
        messenger = new Messenger(new Handler(ctlThread.getLooper(), this::handle));
    }

    @Override
    public IBinder onBind(Intent intent) {
        return messenger.getBinder();
    }

    @Override
    public void onDestroy() {
        try {
            for (TtsEngine e : engines.values()) {
                try { e.release(); } catch (Throwable ignored) {}
            }
            engines.clear();
        } catch (Throwable ignored) {}
        try { loader.shutdownNow(); } catch (Throwable ignored) {}
        try { speaker.shutdownNow(); } catch (Throwable ignored) {}
        try { if (ctlThread != null) ctlThread.quit(); } catch (Throwable ignored) {}
        super.onDestroy();
    }

    // ---------------------------------------------------------------

    private boolean handle(Message m) {
        if (m.replyTo != null) client = m.replyTo;
        Bundle b = m.getData();
        if (b == null) b = new Bundle();
        try {
            switch (m.what) {
                case MSG_SPEAK: {
                    final String text = b.getString("text", "");
                    final String lang = b.getString("lang", "en");
                    final String id = b.getString("id", "");
                    final float speed = b.getFloat("speed", 1.0f);
                    final boolean plain = b.getBoolean("plain", false);
                    final String voice = b.getString("voice", "");
                    final int mySeq = speakSeq.incrementAndGet();
                    // ⚡ prefetch ها تا وارد صف شدنِ کارِ این خوانش جلو نیفتند (TtsEngine.speakPending)
                    TtsEngine.speakPending.incrementAndGet();
                    try {
                        speaker.execute(() -> {
                            try {
                                doSpeak(text, lang, speed, id, mySeq, plain, voice);
                            } finally {
                                TtsEngine.speakPending.decrementAndGet();
                            }
                        });
                    } catch (Throwable t) {
                        TtsEngine.speakPending.decrementAndGet();
                        replyDone(lang, id, false, String.valueOf(t));
                    }
                    return true;
                }
                case MSG_STOP:
                    speakSeq.incrementAndGet();
                    for (TtsEngine e : engines.values()) {
                        try { e.stop(); } catch (Throwable ignored) {}
                    }
                    return true;
                case MSG_PREFETCH: {
                    String text = b.getString("text", "");
                    String lang = b.getString("lang", "en");
                    final float speed = b.getFloat("speed", 1.0f);
                    final boolean plainPf = b.getBoolean("plain", false);
                    final String voicePf = b.getString("voice", "");
                    final String langPf = lang;
                    final int seqPf = speakSeq.get();
                    // متنِ دوزبانه → هر تکه روی موتورِ زبانِ خودش (دقیقاً همون تکه‌بندیِ موقعِ پخش، تا کش بخوره)
                    final java.util.List<TtsSegmenter.Seg> segsPf = TtsSegmenter.split(text, lang);
                    try {
                        loader.execute(() -> {
                            for (TtsSegmenter.Seg s : segsPf) {
                                try {
                                    if (seqPf != speakSeq.get()) return;   // بینِ راه speak/stop ی جدید اومد
                                    TtsEngine e = obtainEngine(s.lang, false);
                                    if (e != null && !e.isReleased()) {
                                        e.plain = plainPf;
                                        e.prefetch(s.text, speed, sidFor(s.lang, langPf, voicePf), s.lang);
                                    }
                                } catch (Throwable ignored) {}
                            }
                        });
                    } catch (Throwable ignored) {}
                    return true;
                }
                case MSG_PRELOAD: {
                    final String lang = b.getString("lang", "");
                    loader.execute(() -> {
                        try {
                            TtsEngine e = obtainEngine(lang, false);
                            if (e != null) e.warmUp();
                        } catch (Throwable ignored) {}
                    });
                    return true;
                }
                case MSG_RELEASE_LANG: {
                    String lang = b.getString("lang", "");
                    synchronized (this) {
                        TtsEngine cur = engines.get(lang);
                        if (cur != null) {
                            // فقط گوینده عوض شده (همان بسته‌ی مشترکِ Supertonic/Kokoro) → مدل دوباره لود نشود
                            SherpaModelManager.TtsVoice nv = SherpaModelManager.getReadyVoice(getApplicationContext(), lang);
                            if (nv != null && cur.canReuseFor(nv)) {
                                cur.setSid(nv.sid);
                                return true;
                            }
                            releaseGen.incrementAndGet();
                            engines.remove(lang);
                            cur.release();
                            if (shared == cur) shared = null;
                        }
                        // ⚡ موتورِ مشترک (کلیدِ pkg:…) با تعویضِ گوینده آزاد نمی‌شود (sid با هر خوانش می‌رسد)؛
                        // قبلاً releaseGen همیشه بالا می‌رفت و لودِ در حالِ انجام دور ریخته و از نو لود می‌شد → کندیِ چندثانیه‌ای
                    }
                    return true;
                }
                case MSG_RELEASE_ALL:
                    releaseGen.incrementAndGet();
                    synchronized (this) {
                        for (TtsEngine e : engines.values()) {
                            try { e.release(); } catch (Throwable ignored) {}
                        }
                        engines.clear();
                        shared = null;
                    }
                    return true;
                default:
                    return false;
            }
        } catch (Throwable e) {
            Log.e(TAG, "handle failed", e);
            return true;
        }
    }

    /**
     * متن رو به تکه‌های تک‌زبانه می‌شکنه (فارسی ↔ انگلیسی و …) و هر تکه رو با مدلِ «زبانِ خودش» پشتِ‌سرهم می‌خونه
     * (همون کاری که TTS خودِ گوشی خودکار می‌کنه). اگه مدلِ یکی از زبان‌ها دانلود نشده باشه، قبل از شروع ok=false
     * برمی‌گرده تا سمتِ اپ به TTS گوشی (که دوزبانه رو بلده) برگرده.
     */
    private void doSpeak(String text, String lang, float speed, String id, int mySeq, boolean plain, String voice) {
        try {
            java.util.List<TtsSegmenter.Seg> segs = TtsSegmenter.split(text, lang);
            for (TtsSegmenter.Seg s : segs) {
                if (SherpaModelManager.getTtsModelDir(getApplicationContext(), s.lang) == null) {
                    replyDone(lang, id, false, "no TTS model for " + s.lang);
                    return;
                }
            }
            speakSegment(segs, 0, lang, speed, id, mySeq, plain, voice);
        } catch (Throwable e) {
            Log.e(TAG, "doSpeak failed", e);
            replyDone(lang, id, false, String.valueOf(e));
        }
    }

    private void speakSegment(final java.util.List<TtsSegmenter.Seg> segs, final int i, final String reqLang,
                              final float speed, final String id, final int mySeq, final boolean plain,
                              final String voice) {
        try {
            // وسطِ لود/پخش، stop() یا speak ی جدید اومده، یا همه‌ی تکه‌ها تموم شد
            if (mySeq != speakSeq.get() || i >= segs.size()) {
                replyDone(reqLang, id, true, null);
                return;
            }
            final TtsSegmenter.Seg s = segs.get(i);
            TtsEngine engine = obtainEngine(s.lang, true);
            if (engine == null) {
                String err = TtsEngine.lastCreateError;
                replyDone(reqLang, id, false, err == null ? "failed to load TTS engine" : err);
                return;
            }
            engine.plain = plain;
            if (mySeq != speakSeq.get()) {
                replyDone(reqLang, id, true, null);
                return;
            }
            // صدای موتورهای «زبانِ دیگه» هم‌زمان پخش نشه
            for (TtsEngine e : engines.values()) {
                if (e != engine) { try { e.stop(); } catch (Throwable ignored) {} }
            }
            // تکه‌ی بعدی (اگه هست) پیش‌پیش ساخته بشه تا بینِ دو زبان وقفه نیفته
            if (i + 1 < segs.size()) {
                final TtsSegmenter.Seg nx = segs.get(i + 1);
                try {
                    loader.execute(() -> {
                        try {
                            if (mySeq != speakSeq.get()) return;
                            TtsEngine ne = obtainEngine(nx.lang, false);
                            if (ne != null && !ne.isReleased()) { ne.plain = plain; ne.prefetch(nx.text, speed, sidFor(nx.lang, reqLang, voice), nx.lang); }
                        } catch (Throwable ignored) {}
                    });
                } catch (Throwable ignored) {}
            }
            engine.speakAsync(s.text, speed, sidFor(s.lang, reqLang, voice), s.lang, ok -> {
                if (!ok) { replyDone(reqLang, id, false, null); return; }
                if (i + 1 >= segs.size()) { replyDone(reqLang, id, true, null); return; }
                // لودِ موتورِ تکه‌ی بعد ممکنه کند باشه → روی thread ی loader (نه thread ی پلیر)
                try {
                    speaker.execute(() -> speakSegment(segs, i + 1, reqLang, speed, id, mySeq, plain, voice));
                } catch (Throwable t) {
                    replyDone(reqLang, id, false, String.valueOf(t));
                }
            });
        } catch (Throwable e) {
            Log.e(TAG, "speakSegment failed", e);
            replyDone(reqLang, id, false, String.valueOf(e));
        }
    }

    /** کلیدِ موتور: زبان‌های یک «بسته‌ی مشترک» (Supertonic / Kokoro) یک موتور دارند، نه هر زبان یکی. */
    private String poolKey(String lang) {
        try {
            SherpaModelManager.TtsVoice v = SherpaModelManager.getReadyVoice(getApplicationContext(), lang);
            if (v != null && v.spec.pkg != null) return "pkg:" + v.spec.pkg.id;
        } catch (Throwable ignored) {}
        return lang;
    }

    /** sid برای تکه‌ای از زبانِ segLang؛ اگر voice داده شده و تکه هم‌زبانِ درخواست است، همان گوینده. */
    private int sidFor(String segLang, String reqLang, String voice) {
        if (voice != null && !voice.isEmpty() && segLang != null && segLang.equals(reqLang)) {
            int sid = SherpaModelManager.sidForVoice(getApplicationContext(), segLang, voice);
            if (sid >= 0) return sid;
        }
        return sidFor(segLang);
    }

    private int sidFor(String lang) {
        try {
            SherpaModelManager.TtsVoice v = SherpaModelManager.getReadyVoice(getApplicationContext(), lang);
            return v == null ? 0 : v.sid;
        } catch (Throwable t) {
            return 0;
        }
    }

    /** موتورِ این زبان رو برمی‌گردونه (اگه لود نیست، لودش می‌کنه). */
    private TtsEngine obtainEngine(String lang, boolean forSpeak) {
        final String key = poolKey(lang);
        final Object lk = createLocks.computeIfAbsent(key, k -> new Object());
        for (int attempt = 0; attempt < 2; attempt++) {
            synchronized (this) {
                TtsEngine e = engines.get(key);
                if (e != null && e.isReleased()) { engines.remove(key); e = null; }
                if (e != null) return reuseLoaded(e, key, lang, forSpeak);
            }
            synchronized (lk) {
                final int gen0;
                synchronized (this) {
                    TtsEngine e = engines.get(key);
                    if (e != null && e.isReleased()) { engines.remove(key); e = null; }
                    if (e != null) return reuseLoaded(e, key, lang, forSpeak);
                    if (!forSpeak && engines.size() >= MAX_ENGINES) return null;
                    gen0 = releaseGen.get();
                }
                TtsEngine ne = TtsEngine.create(getApplicationContext(), lang);
                if (ne == null) return null;
                boolean stale = false;
                synchronized (this) {
                    if (releaseGen.get() != gen0) {
                        stale = true;
                    } else {
                        engines.put(key, ne);
                        while (engines.size() > MAX_ENGINES) {
                            String vk = null;
                            TtsEngine victim = null;
                            for (java.util.Map.Entry<String, TtsEngine> en : engines.entrySet()) {
                                TtsEngine x = en.getValue();
                                if (x == ne || x == shared) continue;
                                if (victim == null || x.lastUsed() < victim.lastUsed()) { victim = x; vk = en.getKey(); }
                            }
                            if (victim == null) break;
                            engines.remove(vk);
                            victim.release();
                        }
                        if (forSpeak) {
                            ne.touch();
                            shared = ne;
                        }
                    }
                }
                if (!stale) return ne;
                try { ne.release(); } catch (Throwable ignored) {}
            }
        }
        return null;
    }

    /** (داخلِ synchronized(this)) موتورِ لودشده هنوز معتبر است؟ */
    private TtsEngine reuseLoaded(TtsEngine e, String key, String lang, boolean forSpeak) {
        SherpaModelManager.TtsVoice av = SherpaModelManager.getReadyVoice(getApplicationContext(), lang);
        if (av == null) {
            engines.remove(key);
            if (shared == e) shared = null;
            e.release();
            return null;
        }
        if (forSpeak) {
            e.touch();
            shared = e;
        }
        return e;
    }

    private void replyDone(String lang, String id, boolean ok, String err) {
        Messenger c = client;
        if (c == null) return;
        try {
            Message r = Message.obtain(null, REPLY_DONE);
            Bundle b = new Bundle();
            b.putString("lang", lang);
            b.putString("id", id);
            b.putBoolean("ok", ok);
            if (err != null) b.putString("err", err);
            r.setData(b);
            c.send(r);
        } catch (RemoteException ignored) {
        } catch (Throwable t) {
            Log.w(TAG, "reply failed", t);
        }
    }
}
