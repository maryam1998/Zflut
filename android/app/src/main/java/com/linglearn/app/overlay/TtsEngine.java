package com.linglearn.app.overlay;

import android.content.Context;
import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioTrack;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.Process;
import android.os.SystemClock;
import android.util.Log;
import android.widget.Toast;

import com.k2fsa.sherpa.onnx.OfflineTts;
import com.k2fsa.sherpa.onnx.OfflineTtsConfig;
import com.k2fsa.sherpa.onnx.OfflineTtsKokoroModelConfig;
import com.k2fsa.sherpa.onnx.OfflineTtsModelConfig;
import com.k2fsa.sherpa.onnx.OfflineTtsVitsModelConfig;

import java.io.File;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.PriorityBlockingQueue;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * موتور TTS (Piper/VITS) — نسخه‌ی سریع:
 *  - پخشِ استریم: همین‌که اولین تکه‌ی صدا ساخته شد پخش شروع می‌شه (منتظرِ ساختنِ کلِ جمله نمی‌مونه)
 *  - AudioTrack هم‌زمان با تولیدِ صدا ساخته می‌شه (نه بعد از اون)
 *  - prefetch: جمله‌ی بعدی پیش‌پیش، موقعِ پخشِ جمله‌ی فعلی ساخته و کش می‌شه
 *  - کشِ صدا: تکرارِ یه جمله (یا A-B) فوری و بدونِ محاسبه‌ی دوباره پخش می‌شه
 *  - warmUp: اولین inference (که کنده) قبل از اولین تپ انجام می‌شه
 */
final class TtsEngine {

    private static final String TAG = "TtsEngine";

    // 🔎 تشخیصِ موقت: زمان‌های ساخت صدا را روی صفحه (Toast) نشان می‌دهد. بعد از پیدا شدن مشکل false کن.
    private static final boolean DEBUG_TOAST = true;
    private static volatile Context dbgCtx;
    private static final Handler DBG_MAIN = new Handler(Looper.getMainLooper());
    private static void dbg(final String msg) {
        Log.i(TAG, msg);
        final Context c = dbgCtx;
        if (!DEBUG_TOAST || c == null) return;
        DBG_MAIN.post(() -> { try { Toast.makeText(c, msg, Toast.LENGTH_SHORT).show(); } catch (Throwable ignored) {} });
    }
    volatile int threadsUsed = 0;
    private static final int CACHE_MAX = 16;
    private static final short[] END = new short[0];

    /** نتیجه‌ی پخش: ok=false یعنی شکستِ واقعی (برای fallback)؛ لغو شدن ok=true حساب می‌شه. */
    interface DoneCallback { void onDone(boolean ok); }

    private interface Sink { boolean accept(float[] samples); } // false → توقفِ تولید

    // true → به‌جای generateWithCallback از generate() ی ساده استفاده می‌شه (اگه مسیرِ callback کرش می‌کرد)
    volatile boolean plain = false;

    /** متن رو برای espeak-ng تمیز می‌کنه (علائمِ عربی/فارسی، نیم‌فاصله، ارقام، کاراکترهای کنترلی). */
    static String sanitize(String lang, String t) {
        if (t == null) return "";
        StringBuilder sb = new StringBuilder(t.length());
        for (int i = 0; i < t.length(); i++) {
            char c = t.charAt(i);
            switch (c) {
                case '\u060C': sb.append(','); break;          // ،
                case '\u061B': sb.append(';'); break;          // ؛
                case '\u061F': sb.append('?'); break;          // ؟
                case '\u066B': sb.append('.'); break;
                case '\u066C': sb.append(','); break;
                case '\u200C': case '\u200D': case '\u200E': case '\u200F':
                case '\u202A': case '\u202B': case '\u202C': case '\u202D': case '\u202E':
                case '\u2066': case '\u2067': case '\u2068': case '\u2069':
                case '\uFEFF': case '\u0640':
                    sb.append(c == '\u0640' ? "" : " "); break;
                case '\u201C': case '\u201D': case '\u00AB': case '\u00BB': sb.append('"'); break;
                case '\u2018': case '\u2019': sb.append('\''); break;
                case '\u2026': sb.append("..."); break;
                default:
                    if (c >= '\u06F0' && c <= '\u06F9') sb.append((char) ('0' + (c - '\u06F0')));
                    else if (c >= '\u0660' && c <= '\u0669') sb.append((char) ('0' + (c - '\u0660')));
                    else if (c < 32 && c != '\n' && c != '\t') sb.append(' ');
                    else if (c >= '\u064B' && c <= '\u065F') { /* اعراب */ }
                    else sb.append(c);
            }
        }
        String r = sb.toString().replaceAll("\\s+", " ").trim();
        // جداکننده‌ی هزارگان (75,000 → 75000): ویرگول مکث حساب می‌شد و عدد درهم خوانده می‌شد
        r = r.replaceAll("(?<=\\d),(?=\\d{3}(?!\\d))", "");
        return r;
    }

    // پارامترهای VITS: کمتر از پیش‌فرض (0.667 / 0.8) → صدای تمیزتر، کمتر خش‌دار/دماغی و ریتمِ یکنواخت‌تر
    // Supertonic: تعدادِ گام‌های حذفِ نویز؛ کمتر = سریع‌تر (شروعِ خوانش زودتر). برای کیفیتِ بیشتر ۴ یا ۵ بگذار.
    private static final int SUPERTONIC_STEPS = 4;   // ۳ → صدای ناپایدار/نوسان‌دار؛ ۵ باکیفیت‌تر ولی کندتر

    private static final float NOISE_SCALE = 0.60f;
    private static final float NOISE_SCALE_W = 0.80f;

    private static void setVitsFloat(Object cfg, String setter, float v) {
        try {
            cfg.getClass().getMethod(setter, float.class).invoke(cfg, v);
        } catch (Throwable ignored) {}
    }

    // true = فارسیِ بدون espeak: متن قبل از Sherpa با PersianG2P به نمادهای مدل تبدیل می‌شود
    volatile boolean charFrontend = false;
    private String feed(String t) {
        return charFrontend ? PersianG2P.toModelInput(t) : t;
    }

    private final OfflineTts tts;
    private final int sampleRate;
    private final String lang;
    // شناسه‌ی گوینده (sid) و — فقط Supertonic — زبانِ سنتز که با GenerationConfig.extra["lang"] می‌رود
    private volatile int sid;
    // 🔁 گوینده/زبانِ «همین درخواست». یک موتور (Supertonic / Kokoro) بینِ چند زبان مشترک است و
    // نباید برای هر زبان دوباره لود شود؛ پس sid و زبان با هر کار روی thread ی تولید (تک‌نخی) ست می‌شود.
    private volatile int curSid;
    private volatile String curLang;
    private final String genLang;   // null = از generate()/generateWithCallback() ی ساده استفاده می‌شود
    private final boolean useCfg;

    // موتور/بسته‌ی صدایی که این نمونه برایش ساخته شده (برای تعویضِ سریعِ گوینده بدون لودِ دوباره)
    private volatile String engineKind = null;
    private volatile String pkgId = null;

    private volatile boolean released = false;
    private volatile long lastUsed = SystemClock.uptimeMillis();
    private volatile AudioTrack currentTrack = null;
    private volatile String inflightPrefetchKey = null;
    private final AtomicBoolean warmed = new AtomicBoolean(false);
    // با هر stop()/speak ی جدید بالا می‌ره؛ پخش‌های قدیمی خودشون رو متوقف می‌کنن
    private final AtomicInteger epoch = new AtomicInteger(0);
    // با هر speak ی غیرِ هم‌کلید بالا می‌ره؛ prefetch های در صف/در حالِ اجرا کنسل می‌شن
    private final AtomicInteger pfAbort = new AtomicInteger(0);

    private final LinkedHashMap<String, float[]> cache =
            new LinkedHashMap<String, float[]>(16, 0.75f, true) {
                @Override protected boolean removeEldestEntry(Map.Entry<String, float[]> e) {
                    return size() > CACHE_MAX;
                }
            };

    // کدِ native (espeak-ng / onnxruntime) حالتِ سراسری داره و thread-safe نیست؛ پس تولیدِ صدای «همه‌ی»
    // زبان‌ها روی «یک» thread ی مشترک انجام می‌شه (قبلاً هر موتور thread ی خودش رو داشت و دو زبان هم‌زمان
    // وارد native می‌شدن → کرشِ تصادفی). NATIVE_LOCK هم ساختنِ موتور رو با تولید هم‌زمان نمی‌ذاره.
    private static final Object NATIVE_LOCK = new Object();
    // ⚡ اولویتِ threadهای «تولیدِ صدا» (و threadهای ONNX که ازش ارث می‌برن). قبلاً URGENT_AUDIO بود و
    // باعث می‌شد با هر جمله، تولیدِ صدا CPU رو از UI/WebView بگیره و هایلایت و اسکرول لگ کنن.
    // پخشِ صدا (tts-play) همچنان با اولویتِ AUDIO اجرا می‌شه. اگه صدا قطع‌وصل شد، این رو
    // به Process.THREAD_PRIORITY_FOREGROUND (یا بالاتر) برگردون.
    private static final int GEN_PRIORITY = Process.THREAD_PRIORITY_FOREGROUND;
    // ⚡ صفِ تولیدِ صدا «اولویت‌دار» است: خوانشِ جمله‌ی فعلی (PRIO_SPEAK) همیشه جلوتر از prefetch (PRIO_PREFETCH)
    // اجرا می‌شود. قبلاً صف FIFO بود و اگر prefetchِ جمله‌ی بعد در حالِ ساخت بود، دو prefetchِ بعدی هم
    // قبل از خوانشِ جمله‌ی فعلی اجرا می‌شدند → بینِ جمله‌ها چند ثانیه سکوتِ غیرطبیعی می‌افتاد.
    private static final int PRIO_PREFETCH = 0;
    private static final int PRIO_SPEAK = 10;

    private static final class GenTask implements Runnable, Comparable<GenTask> {
        private static final AtomicLong SEQ = new AtomicLong();
        final Runnable r;
        final int prio;
        final long seq = SEQ.incrementAndGet();
        GenTask(Runnable r, int prio) { this.r = r; this.prio = prio; }
        @Override public void run() { r.run(); }
        @Override public int compareTo(GenTask o) {
            if (prio != o.prio) return prio > o.prio ? -1 : 1;
            return Long.compare(seq, o.seq);
        }
    }

    private static final ThreadPoolExecutor genPool = new ThreadPoolExecutor(
            1, 1, 0L, TimeUnit.MILLISECONDS, new PriorityBlockingQueue<Runnable>(),
            r -> {
                Thread t = new Thread(() -> {
                    try { Process.setThreadPriority(GEN_PRIORITY); } catch (Throwable ignored) {}
                    r.run();
                }, "tts-gen");
                t.setDaemon(true);
                return t;
            });

    private static void gen(Runnable r, int prio) {
        genPool.execute(new GenTask(r, prio));
    }

    /**
     * ⚡ تعدادِ درخواست‌های «خوانش» که به سرویس رسیده‌اند ولی کارِ تولیدشان هنوز در صفِ gen ننشسته
     * (در حالِ پیدا کردن/لودِ موتور). prefetchِ جمله‌ی بعد تا آن موقع کنار می‌ایستد؛ وگرنه روی thread ی
     * تولید (که تک‌نخی است) زودتر از خوانشِ واقعی شروع می‌شد و خوانش تا تمام شدنِ آن (~۱ ثانیه) معطل می‌ماند.
     */
    static final AtomicInteger speakPending = new AtomicInteger(0);

    /** آیا کارِ تولیدِ یک «خوانش» (اولویتِ بالا) در صف منتظر است؟ */
    private static boolean speakQueued() {
        try {
            for (Runnable r : genPool.getQueue()) {
                if (r instanceof GenTask && ((GenTask) r).prio >= PRIO_SPEAK) return true;
            }
        } catch (Throwable ignored) {}
        return false;
    }

    private TtsEngine(OfflineTts tts, int sampleRate, String lang, int sid, String genLang) {
        this.tts = tts;
        this.sampleRate = sampleRate;
        this.lang = lang;
        this.sid = sid;
        this.curSid = sid;
        this.curLang = genLang;
        this.genLang = genLang;
        this.useCfg = genLang != null;
    }

    // ================= کمکی‌های reflection (APIهای جدیدِ Sherpa: Supertonic / GenerationConfig) =================
    // با reflection تا اگر نامِ کلاس/متدی در نسخه‌ی AAR فرق کرد، بیلد نشکند و خطای واضح در لاگ بیاید.
    private static Object newSherpa(String cls) throws Exception {
        return Class.forName("com.k2fsa.sherpa.onnx." + cls).getDeclaredConstructor().newInstance();
    }

    private static boolean argMatches(Class<?> p, Object v) {
        if (v == null) return !p.isPrimitive();
        if (p.isInstance(v)) return true;
        if (p == float.class) return v instanceof Float;
        if (p == int.class) return v instanceof Integer;
        if (p == boolean.class) return v instanceof Boolean;
        return false;
    }

    private static void setReq(Object o, String name, Object v) throws Exception {
        for (java.lang.reflect.Method m : o.getClass().getMethods()) {
            Class<?>[] pt = m.getParameterTypes();
            if (m.getName().equals(name) && pt.length == 1 && argMatches(pt[0], v)) {
                m.invoke(o, v);
                return;
            }
        }
        throw new NoSuchMethodException(o.getClass().getSimpleName() + "." + name);
    }

    private static void setOpt(Object o, String name, Object v) {
        try { setReq(o, name, v); } catch (Throwable ignored) {}
    }

    private static Throwable unwrap(Throwable t) {
        while (t instanceof java.lang.reflect.InvocationTargetException && t.getCause() != null) t = t.getCause();
        return t;
    }

    private interface SampleCb { int on(float[] samples); }   // 1 = ادامه، 0 = توقف

    private Object makeGenConfig(float sp) throws Exception {
        Object g = newSherpa("GenerationConfig");
        setOpt(g, "setSid", curSid);
        setOpt(g, "setSpeed", sp);
        setOpt(g, "setNumSteps", SUPERTONIC_STEPS);
        java.util.HashMap<String, String> ex = new java.util.HashMap<>();
        final String gl = curLang != null ? curLang : genLang;
        ex.put("lang", gl);
        try {
            setReq(g, "setExtra", ex);
        } catch (NoSuchMethodException e) {
            setReq(g, "setExtra", "{\"lang\": \"" + gl + "\"}");
        }
        return g;
    }

    /** کلِ جمله را یک‌جا می‌سازد. */
    private com.k2fsa.sherpa.onnx.GeneratedAudio genFull(String t, float sp) {
        t = feed(t);
        if (!useCfg) return tts.generate(t, curSid, sp);
        try {
            Object cfg = makeGenConfig(sp);
            java.lang.reflect.Method m = tts.getClass().getMethod("generateWithConfig", String.class, cfg.getClass());
            return (com.k2fsa.sherpa.onnx.GeneratedAudio) m.invoke(tts, t, cfg);
        } catch (Throwable e) {
            throw new RuntimeException("generateWithConfig failed", unwrap(e));
        }
    }

    /** تکه‌تکه می‌سازد؛ callback باید 1 (ادامه) یا 0 (توقف) برگرداند. */
    private void genStream(String t, float sp, final SampleCb cb) {
        t = feed(t);
        if (!useCfg) {
            tts.generateWithCallback(t, curSid, sp, samples -> cb.on(samples));
            return;
        }
        try {
            Object cfg = makeGenConfig(sp);
            java.lang.reflect.Method cm = null;
            for (java.lang.reflect.Method m : tts.getClass().getMethods()) {
                Class<?>[] pt = m.getParameterTypes();
                if (m.getName().equals("generateWithConfigAndCallback") && pt.length == 3
                        && pt[0] == String.class && pt[1].isInstance(cfg) && pt[2].isInterface()) {
                    cm = m;
                    break;
                }
            }
            if (cm == null) {
                // نسخه‌ی AAR متدِ استریم ندارد → کلِ جمله ساخته و یک‌جا داده می‌شود
                com.k2fsa.sherpa.onnx.GeneratedAudio ga = genFull(t, sp);
                float[] all = ga == null ? null : ga.getSamples();
                if (all != null && all.length > 0) cb.on(all);
                return;
            }
            Class<?> cbType = cm.getParameterTypes()[2];
            Object proxy = java.lang.reflect.Proxy.newProxyInstance(
                    cbType.getClassLoader(), new Class<?>[]{cbType},
                    (p, method, args) -> {
                        if ("invoke".equals(method.getName()) && args != null && args.length == 1
                                && args[0] instanceof float[]) {
                            return cb.on((float[]) args[0]);
                        }
                        Class<?> rt = method.getReturnType();
                        if (rt == int.class) return 0;
                        if (rt == boolean.class) return false;
                        return null;
                    });
            cm.invoke(tts, t, cfg, proxy);
        } catch (Throwable e) {
            throw new RuntimeException("generateWithConfigAndCallback failed", unwrap(e));
        }
    }

    String lang() { return lang; }

    void bindVoice(String engineKind, String pkgId) {
        this.engineKind = engineKind;
        this.pkgId = pkgId;
    }

    /** صدای جدید از «همین بسته‌ی مشترک» است (فقط شماره‌ی گوینده فرق دارد) → بدون لودِ دوباره قابل‌تعویض است. */
    boolean canReuseFor(SherpaModelManager.TtsVoice v) {
        return !released && v != null && v.spec.pkg != null
                && v.spec.pkg.id.equals(pkgId) && v.spec.engine.equals(engineKind);
    }

    /** تعویضِ گوینده روی موتورِ لودشده (فوری؛ بدون لودِ چندثانیه‌ایِ مدل). */
    void setSid(int newSid) {
        if (sid == newSid) return;
        sid = newSid;
        curSid = newSid;
        pfAbort.incrementAndGet();                 // prefetchِ در حالِ ساخت با گوینده‌ی قبلی کنسل شود
        synchronized (cache) { cache.clear(); }    // کلیدِ کش به گوینده وابسته نیست → صدای قبلی نباید پخش شود
    }

    boolean isReleased() { return released; }
    long lastUsed() { return lastUsed; }
    void touch() { lastUsed = SystemClock.uptimeMillis(); }

    /**
     * قبل از لودِ native فایل‌ها رو بررسی می‌کنه (فایلِ خراب/ناقص باعثِ exit() یا abort ی native می‌شه).
     * اگه مشکلی باشه متنِ خطا رو برمی‌گردونه و فایلِ خراب رو پاک می‌کنه تا دوباره دانلود بشه.
     */
    private static String validateFiles(Context ctx, File dir, String lang, SherpaModelManager.TtsVoice voice) {
        final String eng = voice.spec.engine;
        if (voice.spec.pkg != null) {
            // بسته‌ی مشترک (Supertonic / Kokoro): همه‌ی فایل‌ها باید باشند؛ وگرنه marker پاک می‌شود تا دوباره دانلود شود
            for (String n : voice.spec.pkg.files) {
                File f = new File(dir, n);
                if (!f.isFile() || f.length() == 0) {
                    SherpaModelManager.invalidatePackage(ctx, voice.spec.pkg);
                    return "package file missing: " + n;
                }
                if (n.endsWith(".onnx")) {
                    try (java.io.FileInputStream in = new java.io.FileInputStream(f)) {
                        int b = in.read();
                        if (f.length() < 1_000_000L || b == '<' || b == '{' || b == 'v' || b == ' ' || b == '\n' || b == '\r') {
                            f.delete();
                            SherpaModelManager.invalidatePackage(ctx, voice.spec.pkg);
                            return n + " is not a valid ONNX file";
                        }
                    } catch (Throwable e) {
                        return "cannot read " + n;
                    }
                }
            }
            if (SherpaModelManager.ENG_KOKORO.equals(eng)) {
                File es = SherpaModelManager.getEspeakDataDir(ctx);
                String[] need = {"phontab", "phonindex", "phondata", "intonations", "en_dict"};
                for (String n : need) {
                    File f = new File(es, n);
                    if (!f.isFile() || f.length() == 0) {
                        SherpaModelManager.invalidateEspeak(ctx);
                        return "espeak-ng-data incomplete: " + n;
                    }
                }
                String[] dd = new File(dir, "dict").list();
                if (dd == null || dd.length == 0) {
                    SherpaModelManager.invalidatePackage(ctx, voice.spec.pkg);
                    return "kokoro dict folder missing";
                }
            }
            return null;
        }
        File model = new File(dir, "model.onnx");
        if (model.length() < 2_000_000L) {
            model.delete();
            return "model.onnx too small (corrupt download)";
        }
        try (java.io.FileInputStream in = new java.io.FileInputStream(model)) {
            int b = in.read();
            // HTML / JSON / متن (مثلاً صفحه‌ی خطای آینه یا pointer ی git-lfs) → بسته نیست
            if (b == '<' || b == '{' || b == 'v' || b == ' ' || b == '\n' || b == '\r') {
                model.delete();
                return "model.onnx is not an ONNX file";
            }
        } catch (Throwable e) {
            return "cannot read model.onnx";
        }
        if (voice.spec.charFrontend) return null;   // فارسیِ بدون espeak: داده‌ی espeak لازم نیست
        File es = SherpaModelManager.getEspeakDataDir(ctx);
        String[] need = {"phontab", "phonindex", "phondata", "intonations", lang + "_dict"};
        for (String n : need) {
            File f = new File(es, n);
            if (!f.isFile() || f.length() == 0) {
                SherpaModelManager.invalidateEspeak(ctx);
                return "espeak-ng-data incomplete: " + n;
            }
        }
        return null;
    }

    /** آخرین خطای لود (برای گزارش به کاربر)؛ فقط توی پردازه‌ی TTS معنی داره. */
    static volatile String lastCreateError = null;

    /** تعدادِ هسته‌هایی که فرکانسشان ≥ ۷۰٪ بیشینه است؛ اگر خوانده نشد -1. */
    private static int fastCoreCount() {
        try {
            int n = Runtime.getRuntime().availableProcessors();
            long[] f = new long[n];
            long max = 0;
            for (int i = 0; i < n; i++) {
                File ff = new File("/sys/devices/system/cpu/cpu" + i + "/cpufreq/cpuinfo_max_freq");
                if (!ff.canRead()) return -1;
                try (java.io.BufferedReader br = new java.io.BufferedReader(new java.io.FileReader(ff))) {
                    f[i] = Long.parseLong(br.readLine().trim());
                }
                if (f[i] > max) max = f[i];
            }
            if (max <= 0) return -1;
            int c = 0;
            for (long x : f) if (x >= max * 0.7) c++;
            return c;
        } catch (Throwable t) {
            return -1;
        }
    }

    static TtsEngine create(Context ctx, String lang) {
        lastCreateError = null;
        dbgCtx = ctx.getApplicationContext();
        final SherpaModelManager.TtsVoice voice = SherpaModelManager.getReadyVoice(ctx, lang);
        final File dir = voice == null ? null : SherpaModelManager.voiceDir(ctx, lang, voice);
        if (dir == null) {
            Log.w(TAG, "TTS model not found for " + lang);
            lastCreateError = "model not found";
            return null;
        }
        String bad = validateFiles(ctx, dir, lang, voice);
        if (bad != null) {
            Log.e(TAG, "invalid TTS files for " + lang + ": " + bad);
            lastCreateError = bad;
            return null;
        }
        int oldPrio = Process.THREAD_PRIORITY_DEFAULT;
        boolean prioChanged = false;
        try {
            long t0 = SystemClock.uptimeMillis();
            TtsCrumb.mark("create:" + lang);
            // threadهای ONNX Runtime اولویتِ threadی رو که می‌سازتشون به ارث می‌برن
            try {
                oldPrio = Process.getThreadPriority(Process.myTid());
                Process.setThreadPriority(GEN_PRIORITY);
                prioChanged = true;
            } catch (Throwable ignored) {}

            final String eng = voice.spec.engine;
            int cores = Runtime.getRuntime().availableProcessors();
            int threads = Math.max(2, Math.min(4, cores / 2));
            // Supertonic چهار مدل پشت‌سرهم دارد؛ نخ‌های بیشتر = تأخیر کمتر
            if (SherpaModelManager.ENG_SUPERTONIC.equals(eng)) threads = Math.max(2, Math.min(4, cores - 2));   // بیشتر از ۴ نخ روی هسته‌های ضعیف کندتر می‌شود

            // ⚡ فقط هسته‌های «قوی» (big/prime): نخِ ONNX روی هسته‌ی ضعیف کلِ محاسبه را کند می‌کند
            int fastCores = fastCoreCount();
            if (fastCores > 0) threads = Math.max(2, Math.min(4, fastCores));

            OfflineTtsModelConfig modelConfig = new OfflineTtsModelConfig();
            OfflineTtsConfig config = new OfflineTtsConfig();

            if (SherpaModelManager.ENG_SUPERTONIC.equals(eng)) {
                // Supertonic 3 (بدون espeak): چهار مدل + tts.json + unicode_indexer + voice.bin
                Object st = newSherpa("OfflineTtsSupertonicModelConfig");
                setReq(st, "setDurationPredictor", new File(dir, "duration_predictor.int8.onnx").getAbsolutePath());
                setReq(st, "setTextEncoder", new File(dir, "text_encoder.int8.onnx").getAbsolutePath());
                setReq(st, "setVectorEstimator", new File(dir, "vector_estimator.int8.onnx").getAbsolutePath());
                setReq(st, "setVocoder", new File(dir, "vocoder.int8.onnx").getAbsolutePath());
                setReq(st, "setTtsJson", new File(dir, "tts.json").getAbsolutePath());
                setReq(st, "setUnicodeIndexer", new File(dir, "unicode_indexer.bin").getAbsolutePath());
                setReq(st, "setVoiceStyle", new File(dir, "voice.bin").getAbsolutePath());
                setReq(modelConfig, "setSupertonic", st);
            } else if (SherpaModelManager.ENG_KOKORO.equals(eng)) {
                // Kokoro multi-lang v1.0 (انگلیسی + چینی). espeak-ng-data فقط برای کلماتِ خارج از لغت‌نامه است.
                OfflineTtsKokoroModelConfig k = new OfflineTtsKokoroModelConfig();
                k.setModel(new File(dir, "model.onnx").getAbsolutePath());
                k.setVoices(new File(dir, "voices.bin").getAbsolutePath());
                k.setTokens(new File(dir, "tokens.txt").getAbsolutePath());
                k.setDataDir(SherpaModelManager.getEspeakDataDir(ctx).getAbsolutePath());
                setOpt(k, "setDictDir", new File(dir, "dict").getAbsolutePath());
                setOpt(k, "setLexicon", new File(dir, "lexicon-us-en.txt").getAbsolutePath()
                        + "," + new File(dir, "lexicon-zh.txt").getAbsolutePath());
                modelConfig.setKokoro(k);
                setOpt(config, "setRuleFsts", new File(dir, "date-zh.fst").getAbsolutePath()
                        + "," + new File(dir, "number-zh.fst").getAbsolutePath());
            } else {
                // فارسی (Piper/VITS + espeak-ng) — بدون تغییر
                OfflineTtsVitsModelConfig vitsConfig = new OfflineTtsVitsModelConfig();
                vitsConfig.setModel(new File(dir, "model.onnx").getAbsolutePath());
                vitsConfig.setTokens(new File(dir, "tokens.txt").getAbsolutePath());
                if (voice.spec.charFrontend) {
                    // فارسیِ Mana بدون espeak-ng: نیازی به dataDir نیست
                    PersianG2P.configure(ctx, new File(dir, "tokens.txt"));
                } else {
                    // espeak-ng-dataِ مشترک (یک بار دانلود می‌شه)
                    vitsConfig.setDataDir(SherpaModelManager.getEspeakDataDir(ctx).getAbsolutePath());
                }
                // 🎙 صدای پایدارتر و کم‌خش‌تر: نویز کمتر = لحنِ یکنواخت‌تر و مکثِ کمتر پرش‌دار.
                // با reflection تا اگه نسخه‌ی کتابخانه این setter را نداشت build/اجرا خراب نشه.
                setVitsFloat(vitsConfig, "setNoiseScale", NOISE_SCALE);
                setVitsFloat(vitsConfig, "setNoiseScaleW", NOISE_SCALE_W);
                modelConfig.setVits(vitsConfig);
            }
            modelConfig.setNumThreads(threads);
            modelConfig.setDebug(false);
            config.setModel(modelConfig);

            OfflineTts engine;
            int sr;
            synchronized (NATIVE_LOCK) {
                engine = new OfflineTts(null, config);
                // نرخ نمونه‌برداری رو از خودِ بسته بخون (بسته‌های Piper همه ۲۲۰۵۰ نیستن)
                sr = engine.sampleRate();
            }
            if (sr <= 0) sr = 22050;
            Log.i(TAG, "TTS loaded for " + lang + ", sampleRate=" + sr + ", threads=" + threads
                    + ", loadMs=" + (SystemClock.uptimeMillis() - t0));
            TtsCrumb.mark("idle");
            TtsEngine created = new TtsEngine(engine, sr, lang, voice.sid,
                    SherpaModelManager.ENG_SUPERTONIC.equals(eng) ? lang : null);
            created.bindVoice(eng, voice.spec.pkg == null ? null : voice.spec.pkg.id);
            created.charFrontend = voice.spec.charFrontend;
            created.threadsUsed = threads;
            dbg("TTS لود شد: " + lang + " " + eng + " thr=" + threads + " load=" + (SystemClock.uptimeMillis() - t0) + "ms");
            return created;
        } catch (Throwable e) {
            Log.e(TAG, "Failed to load TTS for " + lang, e);
            lastCreateError = String.valueOf(e);
            TtsCrumb.mark("idle");
            return null;
        } finally {
            if (prioChanged) {
                try { Process.setThreadPriority(oldPrio); } catch (Throwable ignored) {}
            }
        }
    }

    /** یک inference کوچیکِ بی‌صدا تا اولین تپِ واقعی کند نباشه. یک‌بار اجرا می‌شه. */
    void warmUp() {
        if (released || !warmed.compareAndSet(false, true)) return;
        final String w;
        switch (lang == null ? "" : lang) {
            case "fa": w = "سلام"; break;
            case "ar": w = "مرحبا"; break;
            case "ru": w = "привет"; break;
            case "zh": w = "你好"; break;
            case "hi": w = "नमस्ते"; break;
            case "ja": w = "こんにちは"; break;
            case "ko": w = "안녕하세요"; break;
            case "de": w = "Hallo."; break;
            case "fr": w = "Bonjour."; break;
            case "es": w = "Hola."; break;
            case "it": w = "Ciao."; break;
            case "tr": w = "Merhaba."; break;
            default:   w = "Hello."; break;
        }
        // ⚡ اگه تا نوبتِ این گرم‌کردن، خوانشِ واقعی (یا stop) رسید، گرم‌کردن رد می‌شود؛ خودِ خوانش موتور را گرم می‌کند
        final int warmEpoch = epoch.get();
        try {
            gen(() -> {
                if (released || epoch.get() != warmEpoch) return;
                curSid = sid; curLang = genLang;
                try {
                    long t0 = SystemClock.uptimeMillis();
                    TtsCrumb.mark("warm:" + lang);
                    synchronized (NATIVE_LOCK) { genFull(w, 1.0f); }
                    TtsCrumb.mark("idle");
                    Log.i(TAG, "warmUp " + lang + " ms=" + (SystemClock.uptimeMillis() - t0));
                } catch (Throwable e) {
                    Log.w(TAG, "warmUp failed", e);
                }
            }, PRIO_PREFETCH);
        } catch (Throwable ignored) {}
    }

    // ================= کش =================
    // سرعتِ کاربر با time-stretch موقعِ پخش اعمال می‌شود (نه با ساختنِ دوباره‌ی صدا)؛ پس کش به سرعت وابسته نیست
    // و تغییرِ سرعت فوری و بدون پرش/تأخیر است. فقط اگر دستگاه setPlaybackParams را نپذیرفت کلید سرعت دارد.
    private volatile boolean stretchOk = true;
    private String keyOf(String t, float sp, int rs, String rl) { return (stretchOk ? 1.0f : sp) + "|" + rs + "|" + rl + "|" + t; }

    private float[] cacheGet(String key) {
        synchronized (cache) { return cache.get(key); }
    }
    private boolean cacheHas(String key) {
        synchronized (cache) { return cache.containsKey(key); }
    }
    private void cachePut(String key, float[] v) {
        if (v == null || v.length == 0) return;
        synchronized (cache) { cache.put(key, v); }
    }

    private static short[] toPcm16(float[] samples) {
        short[] pcm = new short[samples.length];
        for (int i = 0; i < samples.length; i++) {
            float s = samples[i];
            if (s > 1f) s = 1f; else if (s < -1f) s = -1f;
            pcm[i] = (short) (s * 32767);
        }
        return pcm;
    }

    /**
     * سکوتِ زیادِ اول/آخرِ هر تکه را کوتاه می‌کند ولی نه آن‌قدر که صدا «بریده‌بریده و تند» شود:
     * ~۴۰ms اول و ~۱۰۰ms آخر می‌ماند + محوِ نرمِ لبه‌ها (بدون تَق‌تَق).
     */
    private static float[] trimSilence(float[] x, int sr) {
        return trimSilence(x, sr, false);
    }

    /** longText=true (جمله‌ی بلند/چندجمله‌ای): مکثِ آخر و مکثِ وسطِ صدا کمی کوتاه‌تر می‌شود. */
    private static float[] trimSilence(float[] x, int sr, boolean longText) {
        if (x == null || x.length == 0 || sr <= 0) return x;
        final float th = 0.015f;
        int first = -1, last = -1;
        for (int i = 0; i < x.length; i++) {
            float v = x[i] < 0 ? -x[i] : x[i];
            if (v > th) { if (first < 0) first = i; last = i; }
        }
        if (first < 0) return x;                       // کاملاً سکوت: دست نزن
        int from = Math.max(0, first - sr * 20 / 1000);
        int to = Math.min(x.length, last + 1 + sr * (longText ? 50 : 70) / 1000);
        float[] y = (from == 0 && to == x.length) ? x : java.util.Arrays.copyOfRange(x, from, to);
        y = capInnerSilence(y, sr, longText);
        edgeFade(y, sr);
        return y;
    }

    /** تکه‌ی کاملاً بی‌صدا؟ (همان آستانه‌ی trimSilence) */
    private static boolean isSilent(float[] x) {
        if (x == null) return true;
        for (int i = 0; i < x.length; i++) {
            float v = x[i] < 0 ? -x[i] : x[i];
            if (v > 0.015f) return false;
        }
        return true;
    }

    /** محوِ بسیار کوتاه (۶ms اول / ۱۲ms آخر) تا اتصالِ تکه‌ها صدای «تِق» نده. */
    private static void edgeFade(float[] y, int sr) {
        if (y == null || y.length < 8) return;
        int fin = Math.min(y.length / 2, Math.max(1, sr * 6 / 1000));
        int fout = Math.min(y.length / 2, Math.max(1, sr * 12 / 1000));
        for (int i = 0; i < fin; i++) y[i] *= (float) i / fin;
        for (int i = 0; i < fout; i++) y[y.length - 1 - i] *= (float) i / fout;
    }

    /**
     * مکثِ «وسطِ» صدا (بعد از ویرگول/نقطه/…) را سقف می‌زند، ولی به اندازه‌ی طبیعی:
     * سکوتِ بلندتر از ~۳۰۰ms (جمله‌ی بلند: ~۲۲۰ms) کوتاه می‌شود (با محوِ نرم در دو سرِ برش).
     * مدل‌های Piper گاهی بعد از علائمِ نگارشی مکثِ چند‌ثانیه‌ای می‌سازند؛ قبلاً سقف فقط ۸۰–۱۵۰ms بود
     * و همین باعث می‌شد صدا «تند و بدون نفس» به‌نظر برسد.
     */
    private static float[] capInnerSilence(float[] x, int sr, boolean longText) {
        final float th = 0.015f;
        final int maxGap = sr * (longText ? 220 : 300) / 1000;
        final int minRun = maxGap + sr * 60 / 1000;   // فقط سکوتِ واقعاً بلند دست می‌خورد
        final int fade = Math.max(1, sr * 10 / 1000);
        float[] out = new float[x.length];
        int o = 0, i = 0, n = x.length;
        while (i < n) {
            float v = x[i] < 0 ? -x[i] : x[i];
            if (v > th) { out[o++] = x[i++]; continue; }
            int j = i;
            while (j < n) {
                float w = x[j] < 0 ? -x[j] : x[j];
                if (w > th) break;
                j++;
            }
            int run = j - i;
            if (run >= minRun) {
                int half = maxGap / 2;
                int f = Math.min(fade, half);
                for (int k = 0; k < half; k++) {
                    float g = k >= half - f ? (float) (half - k) / f : 1f;      // محوِ خروجی
                    out[o++] = x[i + k] * g;
                }
                for (int k = run - half; k < run; k++) {
                    int kk = k - (run - half);
                    float g = kk < f ? (float) kk / f : 1f;                      // محوِ ورودی
                    out[o++] = x[i + k] * g;
                }
            } else {
                for (int k = 0; k < run; k++) out[o++] = x[i + k];
            }
            i = j;
        }
        return o == n ? x : java.util.Arrays.copyOf(out, o);
    }

    // سرعتِ پایه‌ی صداهای Piper: در سرعتِ ۱× کمی کندتر از پیش‌فرضِ مدل بخون (مدل‌ها تند می‌خونن).
    // اگه هنوز تنده عدد رو کمتر کن (مثلاً 0.80)، اگه خیلی کنده بیشتر (مثلاً 0.92).
    // (کشیدنِ زیادِ طولِ واجها در VITS باعثِ «لرزش» می‌شد؛ پایه نزدیک به طبیعی نگه داشته شد)
    private static final float BASE_SPEED = 0.94f;

    /** سرعتِ ساختِ صدا در مدل: وقتی time-stretch فعاله ثابت است، وگرنه مثلِ قبل به سرعتِ کاربر وابسته. */
    private float effectiveSpeed(float sp) {
        if (sp <= 0f) sp = 1.0f;
        float e = stretchOk ? 1.0f : sp;
        e *= BASE_SPEED;
        return Math.max(0.2f, Math.min(3.0f, e));
    }

    // ================= پردازشِ صدا (کاهشِ حالتِ دماغی/تو‌دماغی + نرم‌کردن) =================
    /**
     * فیلترِ ملایم (biquad) روی خروجیِ مدل:
     *  - کمی تقویتِ بَم (~۱۸۰Hz) → صدا پُرتر و گرم‌تر
     *  - کمی کاهشِ ناحیه‌ی دماغی (~۱.۲kHz)
     *  - کمی کاهشِ زیرِ بسیار بالا (~۷kHz) → کمتر «سیس/خش»
     * وضعیتِ فیلتر بینِ تکه‌های یک جمله حفظ می‌شود (بدون ناپیوستگی).
     */
    private static final class VoiceEq {
        private static final float LOW_SHELF_DB = 0.5f;     // ~150Hz (قبلاً ۱.۵؛ صدا را گرفته می‌کرد)
        private static final float NASAL_CUT_DB = 2.0f;     // ~2800Hz: تقویتِ وضوحِ کلمات (قبلاً ۳- در ۱.۲kHz)
        private static final float AIR_CUT_DB = -6.0f;      // ~6500Hz: کاهشِ خشِ مدل‌های Piper

        private final double[][] c = new double[3][5];      // b0 b1 b2 a1 a2 (نرمال‌شده)
        private final double[][] z = new double[3][2];
        private final boolean on;

        VoiceEq(int sr) {
            on = sr >= 16000;
            if (!on) return;
            lowShelf(c[0], sr, 150.0, LOW_SHELF_DB, 0.8);
            peaking(c[1], sr, 2800.0, 0.9, NASAL_CUT_DB);
            highShelf(c[2], sr, Math.min(6500.0, sr * 0.42), AIR_CUT_DB, 0.8);
        }

        private static void put(double[] o, double b0, double b1, double b2, double a0, double a1, double a2) {
            o[0] = b0 / a0; o[1] = b1 / a0; o[2] = b2 / a0; o[3] = a1 / a0; o[4] = a2 / a0;
        }

        private static void peaking(double[] o, int sr, double f0, double q, double db) {
            double A = Math.pow(10, db / 40.0);
            double w = 2 * Math.PI * f0 / sr, cs = Math.cos(w), al = Math.sin(w) / (2 * q);
            put(o, 1 + al * A, -2 * cs, 1 - al * A, 1 + al / A, -2 * cs, 1 - al / A);
        }

        private static void lowShelf(double[] o, int sr, double f0, double db, double s) {
            double A = Math.pow(10, db / 40.0);
            double w = 2 * Math.PI * f0 / sr, cs = Math.cos(w), sn = Math.sin(w);
            double al = sn / 2 * Math.sqrt((A + 1 / A) * (1 / s - 1) + 2);
            double sq = 2 * Math.sqrt(A) * al;
            put(o, A * ((A + 1) - (A - 1) * cs + sq), 2 * A * ((A - 1) - (A + 1) * cs),
                    A * ((A + 1) - (A - 1) * cs - sq),
                    (A + 1) + (A - 1) * cs + sq, -2 * ((A - 1) + (A + 1) * cs), (A + 1) + (A - 1) * cs - sq);
        }

        private static void highShelf(double[] o, int sr, double f0, double db, double s) {
            double A = Math.pow(10, db / 40.0);
            double w = 2 * Math.PI * f0 / sr, cs = Math.cos(w), sn = Math.sin(w);
            double al = sn / 2 * Math.sqrt((A + 1 / A) * (1 / s - 1) + 2);
            double sq = 2 * Math.sqrt(A) * al;
            put(o, A * ((A + 1) + (A - 1) * cs + sq), -2 * A * ((A - 1) + (A + 1) * cs),
                    A * ((A + 1) + (A - 1) * cs - sq),
                    (A + 1) - (A - 1) * cs + sq, 2 * ((A - 1) - (A + 1) * cs), (A + 1) - (A - 1) * cs - sq);
        }

        /** درجا روی x اعمال می‌شود (و یک محدودکننده‌ی نرم برای جلوگیری از clip). */
        void process(float[] x) {
            if (!on || x == null) return;
            for (int n = 0; n < x.length; n++) {
                double v = x[n];
                for (int s = 0; s < 3; s++) {
                    double[] k = c[s];
                    double[] st = z[s];
                    double y = k[0] * v + st[0];
                    st[0] = k[1] * v - k[3] * y + st[1];
                    st[1] = k[2] * v - k[4] * y;
                    v = y;
                }
                // محدودکننده‌ی نرم: زیرِ ۰.۸ دست‌نخورده، بالاتر به‌آرامی به ۱ نزدیک می‌شود
                double a = v < 0 ? -v : v;
                if (a > 0.8) {
                    double t = 0.8 + 0.2 * Math.tanh((a - 0.8) / 0.2);
                    v = v < 0 ? -t : t;
                }
                x[n] = (float) v;
            }
        }
    }

    // ================= تکه‌تکه‌کردنِ جمله (شروعِ سریع‌تر + مکثِ طبیعی) =================
    private static final class Clause {
        final String text;
        final int pauseMs;     // مکثِ بعد از این تکه
        Clause(String text, int pauseMs) { this.text = text; this.pauseMs = pauseMs; }
    }

    private static int wordCount(CharSequence s) {
        int n = 0;
        boolean in = false;
        for (int i = 0; i < s.length(); i++) {
            boolean w = !Character.isWhitespace(s.charAt(i));
            if (w && !in) n++;
            in = w;
        }
        return n;
    }

    /**
     * جمله را سرِ ویرگول / نقطه‌ویرگول / دونقطه / خط‌تیره به تکه‌های ≥۴ کلمه‌ای می‌شکند.
     * مزیت: پخش بعد از ساختنِ «تکه‌ی اول» شروع می‌شود (نه کلِ جمله) و مکثِ بینِ تکه‌ها دقیقاً کنترل می‌شود.
     * اعداد مثل 1,5 (بدون فاصله بعد از ویرگول) شکسته نمی‌شوند.
     */
    private static java.util.List<Clause> splitClauses(String t) {
        java.util.ArrayList<Clause> out = new java.util.ArrayList<>();
        if (t == null) return out;
        int start = 0;
        final int n = t.length();
        for (int i = 0; i < n - 1; i++) {
            char c = t.charAt(i);
            int pause;
            if (c == ',') pause = 170;
            else if (c == ';') pause = 230;
            else if (c == ':') pause = 230;
            else if (c == '\u2014' || c == '\u2013') pause = 190;
            else continue;
            if (!Character.isWhitespace(t.charAt(i + 1))) continue;
            String head = t.substring(start, i + 1).trim();
            String rest = t.substring(i + 1).trim();
            if (wordCount(head) < 4 || wordCount(rest) < 3) continue;
            out.add(new Clause(head, pause));
            start = i + 1;
        }
        String tail = t.substring(start).trim();
        if (!tail.isEmpty()) out.add(new Clause(tail, 0));
        if (out.isEmpty()) out.add(new Clause(t, 0));
        return out;
    }

    /** تکه‌های بیش از maxWords کلمه را به تکه‌های ~chunk کلمه‌ای می‌شکند (بدون مکثِ اضافه). */
    private static java.util.List<Clause> chunkLong(java.util.List<Clause> in, int maxWords, int chunk) {
        java.util.ArrayList<Clause> out = new java.util.ArrayList<>();
        for (Clause c : in) {
            String[] w = c.text.trim().split("\\s+");
            if (w.length <= maxWords) { out.add(c); continue; }
            int i = 0;
            while (i < w.length) {
                int end = Math.min(w.length, i + chunk);
                if (w.length - end < 4) end = w.length;      // ته‌مانده‌ی خیلی کوتاه به تکه‌ی قبلی بچسبد
                StringBuilder sb = new StringBuilder();
                for (int k = i; k < end; k++) { if (k > i) sb.append(' '); sb.append(w[k]); }
                out.add(new Clause(sb.toString(), end >= w.length ? c.pauseMs : 0));
                i = end;
            }
        }
        return out;
    }

    /** تولیدِ یک تکه؛ sink برای هر بخشِ صدا زده می‌شود. false = لغو. */
    private float[] synthClause(String t, float sp, boolean pl, boolean longText, VoiceEq eq, final Sink sink) {
        if (pl) {
            com.k2fsa.sherpa.onnx.GeneratedAudio ga;
            synchronized (NATIVE_LOCK) { ga = genFull(t, sp); }
            float[] all = ga == null ? null : ga.getSamples();
            if (all == null || all.length == 0) return new float[0];
            all = trimSilence(all, sampleRate, longText);
            eq.process(all);
            if (!sink.accept(all)) return null;
            return all;
        }
        final ArrayList<float[]> parts = new ArrayList<>();
        final boolean[] heard = {false};   // تا صدای واقعی نیامده، تکه‌های کاملاً بی‌صدای ابتدای خوانش دور ریخته می‌شوند
        final boolean[] aborted = {false};
        final Throwable[] err = {null};
        synchronized (NATIVE_LOCK) {
            genStream(t, sp, samples -> {
                // هیچ exception ی نباید از callback به native برگرده: JNI بعدش FindClass صدا می‌زنه
                // و ART با exceptionِ معلق کلِ پردازه رو abort می‌کنه (SIGABRT / status=6).
                try {
                    if (samples == null || samples.length == 0) return 1;
                    if (!heard[0]) {
                        if (isSilent(samples)) return 1;   // سکوتِ ابتدای خوانش → رد شو
                        heard[0] = true;
                    }
                    float[] copy = trimSilence(samples.clone(), sampleRate, longText);
                    eq.process(copy);
                    parts.add(copy);
                    if (!sink.accept(copy)) {
                        aborted[0] = true;
                        return 0;
                    }
                    return 1;
                } catch (Throwable e) {
                    err[0] = e;
                    aborted[0] = true;
                    return 0;
                }
            });
        }
        if (err[0] != null) throw new RuntimeException("synth callback failed", err[0]);
        if (aborted[0]) return null;
        int total = 0;
        for (float[] p : parts) total += p.length;
        float[] merged = new float[total];
        int off = 0;
        for (float[] p : parts) {
            System.arraycopy(p, 0, merged, off, p.length);
            off += p.length;
        }
        return merged;
    }

    /** تولیدِ استریم؛ sink برای هر تکه صدا زده می‌شه. اگه sink false بده، null برمی‌گرده (لغو). */
    private float[] synth(String t, float spUser, boolean pl, final Sink sink) {
        final float sp = effectiveSpeed(spUser);
        // متنِ بلند / چندجمله‌ای (نه لغتِ تکی و اسلنگ) → مکث‌های کمی کوتاه‌تر
        final boolean longText = wordCount(t) > 4;
        // EQ ی «ضدِ خش» مخصوصِ Piper (۲۲kHz) است؛ روی Supertonic (۴۴kHz) صدا را خفه و «ته‌چاهی» می‌کرد
        final boolean skipEq = SherpaModelManager.ENG_SUPERTONIC.equals(engineKind);
        final VoiceEq eq = new VoiceEq(skipEq ? 0 : sampleRate);
        java.util.List<Clause> clauses = splitClauses(t);
        // جمله‌ی بلند بدون ویرگول: تکه‌تکه ساخته شود تا پخش زودتر شروع شود (Supertonic استریم نمی‌کند)
        clauses = chunkLong(clauses, 14, 10);   // همه‌ی موتورها: تکه‌های کوتاه → شروعِ زودترِ پخش
        final ArrayList<float[]> all = new ArrayList<>();
        int total = 0;
        for (int ci = 0; ci < clauses.size(); ci++) {
            Clause cl = clauses.get(ci);
            float[] a = synthClause(cl.text, sp, pl, longText, eq, sink);
            if (a == null) return null;
            all.add(a);
            total += a.length;
            if (cl.pauseMs > 0 && ci < clauses.size() - 1 && a.length > 0) {
                float[] gap = new float[sampleRate * cl.pauseMs / 1000];
                if (!sink.accept(gap)) return null;
                all.add(gap);
                total += gap.length;
            }
        }
        if (all.size() == 1) return all.get(0);
        float[] merged = new float[total];
        int off = 0;
        for (float[] p : all) {
            System.arraycopy(p, 0, merged, off, p.length);
            off += p.length;
        }
        return merged;
    }

    // ================= prefetch =================
    /** صدای این متن رو پیش‌پیش می‌سازه و کش می‌کنه (برای جمله‌ی بعدی). */
    void prefetch(String text, float speed) { prefetch(text, speed, sid, genLang != null ? genLang : lang); }

    void prefetch(String text, float speed, final int reqSid, final String reqLang) {
        if (released || text == null || text.trim().isEmpty()) return;
        final String t = sanitize(lang, text);
        if (t.isEmpty()) return;
        final float sp = (speed <= 0f) ? 1.0f : speed;
        final String key = keyOf(t, sp, reqSid, reqLang);
        if (cacheHas(key)) return;
        final int g = pfAbort.get();
        try {
            final Runnable[] self = new Runnable[1];
            self[0] = () -> {
                if (released || pfAbort.get() != g || cacheHas(key)) return;
                // ⚡ خوانشِ واقعی در راه است: کوتاه صبر کن تا کارش وارد صف شود، بعد خودت را «پشتِ» او بگذار
                if (speakPending.get() > 0) {
                    long until = SystemClock.uptimeMillis() + 500;
                    while (speakPending.get() > 0 && SystemClock.uptimeMillis() < until) {
                        try { Thread.sleep(3); } catch (InterruptedException ie) { break; }
                    }
                    if (released || pfAbort.get() != g || cacheHas(key)) return;
                }
                if (speakQueued()) {
                    try { gen(self[0], PRIO_PREFETCH); } catch (Throwable ignored) {}
                    return;
                }
                curSid = reqSid; curLang = reqLang;
                inflightPrefetchKey = key;
                final boolean pl = plain; // یک‌بار بخون تا بینِ crumb و synth عوض نشه
                try {
                    TtsCrumb.mark((pl ? "prefetchp:" : "prefetch:") + lang + ":" + t.length() + ":" + TtsCrumb.brief(t));
                    float[] audio = synth(t, sp, pl, s -> !released && pfAbort.get() == g);
                    TtsCrumb.mark("idle");
                    if (audio != null) cachePut(key, audio);
                } catch (Throwable e) {
                    Log.w(TAG, "prefetch failed", e);
                } finally {
                    inflightPrefetchKey = null;
                }
            };
            gen(self[0], PRIO_PREFETCH);
        } catch (Throwable ignored) {}
    }

    // ================= پخش =================
    /**
     * خواندن متن؛ cb دقیقاً یک‌بار، بعد از تمام‌شدنِ واقعیِ پخش (یا شکست/لغو) صدا زده می‌شه.
     */
    void speakAsync(String text, float speed, final DoneCallback cb) {
        speakAsync(text, speed, sid, genLang != null ? genLang : lang, cb);
    }

    void speakAsync(String text, float speed, final int reqSid, final String reqLang, final DoneCallback cb) {
        if (text == null || text.trim().isEmpty()) {
            if (cb != null) cb.onDone(true);
            return;
        }
        if (released) {
            if (cb != null) cb.onDone(false);
            return;
        }
        final String t = sanitize(lang, text);
        if (t.isEmpty()) {
            if (cb != null) cb.onDone(true);
            return;
        }
        final float sp = (speed <= 0f) ? 1.0f : speed;
        final String key = keyOf(t, sp, reqSid, reqLang);
        touch();

        // اگه prefetchِ در حالِ اجرا مالِ همین متن نیست (و خودِ این متن هم از قبل ساخته نشده)، کنسلش کن
        // تا این پخش معطل نشه. اگه کش شده باشه لازم نیست prefetchِ جمله‌های بعدی هدر بره.
        if (!key.equals(inflightPrefetchKey) && !cacheHas(key)) pfAbort.incrementAndGet();
        haltPlayback();
        final int myEpoch = epoch.get();

        final LinkedBlockingQueue<short[]> q = new LinkedBlockingQueue<>();
        final AtomicBoolean genFailed = new AtomicBoolean(false);
        final AtomicBoolean gotAudio = new AtomicBoolean(false);
        final AtomicBoolean fired = new AtomicBoolean(false);
        final DoneCallback once = ok -> {
            if (fired.compareAndSet(false, true) && cb != null) cb.onDone(ok);
        };

        final float rateF = Math.max(0.25f, Math.min(2.0f, sp));
        // پلیر اول شروع می‌شه: ساختنِ AudioTrack هم‌زمان با تولیدِ صدا انجام می‌شه
        Thread player = new Thread(() -> runPlayer(q, myEpoch, rateF, genFailed, gotAudio, once), "tts-play");
        player.setDaemon(true);
        player.start();

        // 🚀 جمله از قبل ساخته شده: مستقیم و بدونِ انتظار برای صفِ تولید (که ممکنه مشغولِ prefetchِ بعدی باشه)
        final float[] hit = cacheGet(key);
        if (hit != null && hit.length > 0) {
            gotAudio.set(true);
            q.add(toPcm16(hit));
            q.add(END);
            return;
        }

        try {
            gen(() -> {
                curSid = reqSid; curLang = reqLang;
                runGenerate(t, sp, key, myEpoch, q, genFailed, gotAudio);
            }, PRIO_SPEAK);
        } catch (Throwable e) {
            genFailed.set(true);
            q.add(END);
        }
    }

    // نسخه‌ی قدیمی (سازگاری با کدهای قبلی مثل BubbleService)
    void speak(String text, float speed, final Runnable onDone) {
        speakAsync(text, speed, ok -> { if (onDone != null) onDone.run(); });
    }

    void speak(String text, float speed) {
        speakAsync(text, speed, null);
    }

    private void runGenerate(String t, float sp, String key, final int myEpoch,
                             final LinkedBlockingQueue<short[]> q,
                             AtomicBoolean genFailed, final AtomicBoolean gotAudio) {
        try {
            if (released || epoch.get() != myEpoch) return;
            float[] cached = cacheGet(key);
            if (cached != null) {
                if (cached.length > 0) {
                    gotAudio.set(true);
                    q.add(toPcm16(cached));
                }
                return;
            }
            long t0 = SystemClock.uptimeMillis();
            final boolean[] first = {true};
            final boolean pl = plain; // یک‌بار بخون تا بینِ crumb و synth عوض نشه
            TtsCrumb.mark((pl ? "genp:" : "gen:") + lang + ":" + t.length() + ":" + TtsCrumb.brief(t));
            final long[] firstMs = {-1};
            float[] audio = synth(t, sp, pl, s -> {
                if (released || epoch.get() != myEpoch) return false;
                if (first[0]) {
                    first[0] = false;
                    firstMs[0] = SystemClock.uptimeMillis() - t0;
                    Log.i(TAG, "first audio after ms=" + firstMs[0]);
                }
                gotAudio.set(true);
                q.add(toPcm16(s));
                return true;
            });
            TtsCrumb.mark("idle");
            if (audio != null) {
                cachePut(key, audio);
                dbg("ساخت " + curLang + " " + engineKind + " thr=" + threadsUsed + " | " + t.length()
                        + " حرف | اولین صدا=" + firstMs[0] + "ms | کل=" + (SystemClock.uptimeMillis() - t0)
                        + "ms | طول صدا=" + String.format(java.util.Locale.US, "%.1f", audio.length / (float) sampleRate) + "s");
            }
        } catch (Throwable e) {
            Log.e(TAG, "TTS generate failed", e);
            TtsCrumb.mark("idle");
            genFailed.set(true);
        } finally {
            q.add(END);
        }
    }

    private AudioTrack buildTrack() {
        int minBuf = AudioTrack.getMinBufferSize(
                sampleRate, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT);
        int bufSize = Math.max(minBuf, sampleRate * 2); // حدود ۱ ثانیه
        AudioTrack.Builder b = new AudioTrack.Builder()
                .setAudioAttributes(new AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build())
                .setAudioFormat(new AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(sampleRate)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build())
                .setBufferSizeInBytes(bufSize)
                .setTransferMode(AudioTrack.MODE_STREAM);
        if (Build.VERSION.SDK_INT >= 26) {
            // ⚠️ LOW_LATENCY مسیرِ «fast mixer» را باز می‌کند که صدای ۲۲٫۰۵kHz را با ریسمپلرِ ضعیف
            // به ۴۸kHz می‌برد (صدای نازک/دماغی). برای گفتار تأخیرِ کم لازم نیست؛ مسیرِ عادیِ باکیفیت.
            b.setPerformanceMode(AudioTrack.PERFORMANCE_MODE_NONE);
        }
        return b.build();
    }

    /** سرعتِ کاربر را با time-stretch (حفظِ زیر و بمی) روی AudioTrack اعمال می‌کند. */
    private void applyRate(AudioTrack track, float rate) {
        if (!stretchOk || track == null) return;
        // سرعتِ عادی (۱×): بدونِ PlaybackParams → مسیرِ time-stretch فعال نمی‌شود (بدونِ تأخیر و سکوتِ ابتدایی)
        if (Math.abs(rate - 1.0f) < 0.01f) return;
        try {
            android.media.PlaybackParams pp = new android.media.PlaybackParams();
            pp.setSpeed(rate);
            pp.setPitch(1.0f);
            pp.setAudioFallbackMode(android.media.PlaybackParams.AUDIO_FALLBACK_MODE_DEFAULT);
            track.setPlaybackParams(pp);
        } catch (Throwable e) {
            Log.w(TAG, "setPlaybackParams failed; falling back to model speed", e);
            stretchOk = false;
        }
    }

    private void runPlayer(LinkedBlockingQueue<short[]> q, int myEpoch, final float rateNow,
                           AtomicBoolean genFailed, AtomicBoolean gotAudio, DoneCallback once) {
        try { Process.setThreadPriority(Process.THREAD_PRIORITY_AUDIO); } catch (Throwable ignored) {}
        AudioTrack track = null;
        boolean ok = true;
        boolean cancelled = false;
        boolean started = false;
        long frames = 0;
        try {
            track = buildTrack();
            if (epoch.get() != myEpoch || released) {
                cancelled = true;
            } else {
                currentTrack = track;
            }
            // ⚠️ نوشتنِ تکه‌ی بلند (مثلاً جمله‌ی کش‌شده‌ی چندثانیه‌ای) یک‌جا قبل از play() در حالتِ STREAM
            // وقتی از بافرِ ~۱ثانیه‌ای بزرگ‌تر بود می‌توانست write() را برای همیشه بلاک کند (جمله «خوانده نمی‌شد»).
            // حالا تکه‌ها ریز ریز نوشته می‌شوند و به‌محضِ جمع‌شدنِ مقدارِ کمی صدا play() زده می‌شود.
            final int slice = Math.max(512, sampleRate / 10);          // ~۱۰۰ms
            final long startFrames = Math.max(1, sampleRate * 12L / 100); // ~۱۲۰ms پیش‌بافر
            loop:
            while (!cancelled) {
                if (epoch.get() != myEpoch || released) { cancelled = true; break; }
                short[] c = q.poll(40, TimeUnit.MILLISECONDS);
                if (c == null) continue;
                if (c == END) break;
                int off = 0;
                while (off < c.length) {
                    if (epoch.get() != myEpoch || released) { cancelled = true; break loop; }
                    int n = track.write(c, off, Math.min(slice, c.length - off));
                    if (n < 0) { ok = false; break loop; }
                    if (n == 0) {
                        // بافر پر است: اگر هنوز play نشده، همین حالا شروع کن تا خالی شود
                        if (!started) { applyRate(track, rateNow); track.play(); started = true; }
                        else Thread.sleep(5);
                        continue;
                    }
                    off += n;
                    frames += n;
                    if (!started && frames >= startFrames) {
                        applyRate(track, rateNow);
                        track.play();
                        started = true;
                    }
                }
            }
            if (!started && frames > 0 && !cancelled && ok) {
                applyRate(track, rateNow);
                track.play();
                started = true;
            }
            // رفعِ باگِ «لغات و جمله‌های کوتاه خونده نمی‌شن»:
            // توی AudioTrack حالتِ MODE_STREAM، پخش تا وقتی بافر کاملاً پر نشده شروع نمی‌شه
            // (بافرِ ما ~۱ ثانیه‌ست). هر صدایی که کوتاه‌تر از اون باشه (لغت‌ها و جمله‌های کوتاه)
            // هیچ‌وقت شروع نمی‌شد و آخرِ کار با flush() دور ریخته می‌شد، ولی onDone(ok) هم
            // صدا زده می‌شد، پس بی‌صدا رد می‌شد. راهِ درست: بعد از نوشتنِ آخرین تکه stop() می‌زنیم؛
            // توی حالتِ STREAM یعنی «هرچی تو بافره تا آخر پخش بشه» (drain).
            if (!cancelled && ok && started) {
                try { track.stop(); } catch (Throwable ignored) {}
                long deadline = SystemClock.uptimeMillis() + (long) (frames * 1000L / sampleRate / Math.max(0.25f, rateNow)) + 400;
                while (SystemClock.uptimeMillis() < deadline) {
                    if (epoch.get() != myEpoch || released) { cancelled = true; break; }
                    long head = track.getPlaybackHeadPosition() & 0xFFFFFFFFL;
                    if (head >= frames) break;
                    Thread.sleep(15);
                }
                // head یعنی «به mixer رسید»، نه «از بلندگو درآمد»؛ چند ده میلی‌ثانیه صبر می‌کنیم
                // تا ته‌ِ صدا با pause()/flush() آخرِ finally بریده نشه.
                if (!cancelled) {
                    long until = SystemClock.uptimeMillis() + 45;
                    while (SystemClock.uptimeMillis() < until) {
                        if (epoch.get() != myEpoch || released) { cancelled = true; break; }
                        Thread.sleep(10);
                    }
                }
            }
            if (!cancelled && ok && !gotAudio.get()) {
                Log.w(TAG, "Generated audio is empty");
                ok = false;
            }
        } catch (Throwable e) {
            Log.e(TAG, "playback failed", e);
            ok = false;
        } finally {
            if (track != null) {
                if (currentTrack == track) currentTrack = null;
                try { track.pause(); } catch (Throwable ignored) {}
                try { track.flush(); } catch (Throwable ignored) {}
                try { track.stop(); } catch (Throwable ignored) {}
                try { track.release(); } catch (Throwable ignored) {}
            }
            once.onDone(cancelled || ok);
        }
    }

    /** پخشِ فعلی رو فوراً قطع می‌کنه (آزادسازیِ track رو خودِ thread پلیر انجام می‌ده). */
    private void haltPlayback() {
        epoch.incrementAndGet();
        AudioTrack t = currentTrack;
        if (t != null) {
            try { t.pause(); } catch (Throwable ignored) {}
            try { t.flush(); } catch (Throwable ignored) {}
        }
    }

    void stop() {
        haltPlayback();
    }

    void release() {
        if (released) return;
        released = true;
        haltPlayback();
        try {
            // release رو بعد از تولیدِ در حالِ اجرا انجام بده (وگرنه کرشِ native)
            gen(() -> { try { synchronized (NATIVE_LOCK) { tts.release(); } } catch (Throwable ignored) {} }, PRIO_SPEAK);
        } catch (Throwable e) {
            try { tts.release(); } catch (Throwable ignored) {}
        }
    }
}
