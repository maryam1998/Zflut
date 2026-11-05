package com.linglearn.app.overlay;

import android.content.Context;
import android.util.Log;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.locks.ReentrantLock;

import org.json.JSONArray;
import org.json.JSONObject;

import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;

final class SherpaModelManager {

    private static final String TAG = "SherpaModelMgr";
    private static final String HF_BASE = "https://hf-mirror.com/";

    private SherpaModelManager() {}

    interface ProgressCallback {
        void onProgress(String lang, long done, long total);
        void onDone(String lang);
        void onError(String lang, Exception e);
    }

    // ============ STT (تشخیص گفتار) ============
    private static final class Spec {
        final String repo;
        final String encoder, decoder, joiner, tokens;
        Spec(String repo, String encoder, String decoder, String joiner, String tokens) {
            this.repo = repo; this.encoder = encoder; this.decoder = decoder;
            this.joiner = joiner; this.tokens = tokens;
        }
        String[] files() { return new String[]{encoder, decoder, joiner, tokens}; }
    }

    private static final Map<String, Spec> SPECS;
    static {
        Map<String, Spec> m = new HashMap<>();
        m.put("en", new Spec(
                "csukuangfj/sherpa-onnx-streaming-zipformer-en-2023-06-26",
                "encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx",
                "decoder-epoch-99-avg-1-chunk-16-left-128.onnx",
                "joiner-epoch-99-avg-1-chunk-16-left-128.int8.onnx",
                "tokens.txt"));
        m.put("zh", new Spec(
                "csukuangfj/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20",
                "encoder-epoch-99-avg-1.int8.onnx",
                "decoder-epoch-99-avg-1.onnx",
                "joiner-epoch-99-avg-1.int8.onnx",
                "tokens.txt"));
        // کره‌ای: Zipformer جریانی رسمی k2-fsa (encoder/joiner به‌صورت int8؛ decoder فول)
        m.put("ko", new Spec(
                "k2-fsa/sherpa-onnx-streaming-zipformer-korean-2024-06-16",
                "encoder-epoch-99-avg-1.int8.onnx",
                "decoder-epoch-99-avg-1.onnx",
                "joiner-epoch-99-avg-1.int8.onnx",
                "tokens.txt"));
        // روسی: Zipformer کوچکِ جریانیِ Vosk (فایل‌ها fp32 هستن، حدود ۹۵ مگ)
        m.put("ru", new Spec(
                "csukuangfj/sherpa-onnx-streaming-zipformer-small-ru-vosk-2025-08-16",
                "encoder.onnx", "decoder.onnx", "joiner.onnx", "tokens.txt"));
        // فرانسوی / آلمانی / اسپانیایی: بسته‌های جریانی Kroko (Zipformer2)
        m.put("fr", new Spec(
                "csukuangfj/sherpa-onnx-streaming-zipformer-fr-kroko-2025-08-06",
                "encoder.onnx", "decoder.onnx", "joiner.onnx", "tokens.txt"));
        m.put("de", new Spec(
                "csukuangfj/sherpa-onnx-streaming-zipformer-de-kroko-2025-08-06",
                "encoder.onnx", "decoder.onnx", "joiner.onnx", "tokens.txt"));
        m.put("es", new Spec(
                "csukuangfj/sherpa-onnx-streaming-zipformer-es-kroko-2025-08-06",
                "encoder.onnx", "decoder.onnx", "joiner.onnx", "tokens.txt"));
        SPECS = Collections.unmodifiableMap(m);
    }

    // ============ TTS (تبدیل متن به گفتار) ============
    // موتورها:
    //   • فارسی: Piper/VITS (مدل Mana) + espeak-ng — بدون تغییر
    //   • Supertonic 3 (بسته‌ی مشترک، بدون espeak): de fr es it ru tr ar hi ko ja
    //   • Kokoro multi-lang v1.0 (بسته‌ی مشترک): en zh  (خودِ sherpa برای کلماتِ خارج از لغت‌نامه به espeak-ng-data نیاز دارد)
    static final String ENG_VITS = "vits";
    static final String ENG_SUPERTONIC = "supertonic";
    static final String ENG_KOKORO = "kokoro";

    /** بسته‌ی مشترکِ چندزبانه: یک بار دانلود می‌شود و برای چند زبان کار می‌کند. */
    static final class Pkg {
        final String id, repo;
        final String[] files;      // فایل‌های ریشه‌ی مخزن
        final String[] dirs;       // پوشه‌هایی که کاملاً از مخزن کپی می‌شوند
        final long approxBytes;    // فقط برای نوار پیشرفت
        Pkg(String id, String repo, String[] files, String[] dirs, long approxBytes) {
            this.id = id; this.repo = repo; this.files = files; this.dirs = dirs; this.approxBytes = approxBytes;
        }
    }

    static final Pkg PKG_SUPERTONIC = new Pkg(
            "supertonic3",
            "csukuangfj2/sherpa-onnx-supertonic-3-tts-int8-2026-05-11",
            new String[]{"duration_predictor.int8.onnx", "text_encoder.int8.onnx",
                    "vector_estimator.int8.onnx", "vocoder.int8.onnx",
                    "tts.json", "unicode_indexer.bin", "voice.bin"},
            new String[0],
            146_000_000L);

    static final Pkg PKG_KOKORO = new Pkg(
            "kokoro-multi-lang-v1_0",
            "csukuangfj/kokoro-multi-lang-v1_0",
            new String[]{"model.onnx", "voices.bin", "tokens.txt",
                    "lexicon-us-en.txt", "lexicon-zh.txt", "date-zh.fst", "number-zh.fst"},
            new String[]{"dict"},
            420_000_000L);

    static final class TtsSpec {
        final String repo;         // مخزن HuggingFace
        final String modelFile;    // فایل .onnx داخل مخزن (فقط VITS)
        final String tokensFile;   // فایل tokens.txt (فقط VITS)
        final String dataDirName;  // نام پوشه espeak-ng-data (فقط VITS)
        // true = مخزن فقط فایل خام Piper (.onnx + .onnx.json) دارد (بدون tokens.txt و metadata سازگار با Sherpa)؛
        // tokens.txt از json ساخته و metadata به خود onnx اضافه می‌شود. espeak-ng-data هم از مخزن دیگری می‌آید.
        final boolean rawPiper;
        final String engine;       // ENG_*
        final Pkg pkg;             // != null → بسته‌ی مشترک (Supertonic / Kokoro)
        TtsSpec(String repo, String modelFile, String tokensFile, String dataDirName) {
            this(repo, modelFile, tokensFile, dataDirName, false);
        }
        TtsSpec(String repo, String modelFile, String tokensFile, String dataDirName, boolean rawPiper) {
            this.repo = repo;
            this.modelFile = modelFile;
            this.tokensFile = tokensFile;
            this.dataDirName = dataDirName;
            this.rawPiper = rawPiper;
            this.engine = ENG_VITS;
            this.pkg = null;
        }
        TtsSpec(Pkg pkg, String engine) {
            this.repo = pkg.repo;
            this.modelFile = null;
            this.tokensFile = null;
            this.dataDirName = null;
            this.rawPiper = false;
            this.engine = engine;
            this.pkg = pkg;
        }
    }

    private static final Map<String, TtsSpec> TTS_SPECS;
    static {
        Map<String, TtsSpec> m = new LinkedHashMap<>();

        // فارسی: Mana (مجوز MIT) — مخزنش فایل خام Piper است، پس rawPiper. (بدون تغییر؛ نیازمند espeak-ng)
        m.put("fa", new TtsSpec(
                "MahtaFetrat/Mana-Persian-Piper",
                "fa_IR-mana-medium.onnx", "tokens.txt", "espeak-ng-data", true));

        // انگلیسی و چینی: Kokoro multi-lang v1.0 (Apache-2.0)
        m.put("en", new TtsSpec(PKG_KOKORO, ENG_KOKORO));
        m.put("zh", new TtsSpec(PKG_KOKORO, ENG_KOKORO));

        // ده زبانِ دیگر: Supertonic 3 (مجوز OpenRAIL-M)
        for (String lg : new String[]{"de", "fr", "es", "it", "ru", "tr", "ar", "hi", "ko", "ja"}) {
            m.put(lg, new TtsSpec(PKG_SUPERTONIC, ENG_SUPERTONIC));
        }

        TTS_SPECS = Collections.unmodifiableMap(m);
    }

    // ============ چند صدا برای هر زبان ============
    // فارسی: صدای پیش‌فرض (Mana) + چند صدای اضافه‌ی Piper، مثل قبل (پوشه‌ی tts/fa و tts/fa__<id>).
    // Supertonic: ۱۰ گوینده (sid ۰..۹) داخل همان بسته‌ی مشترک؛ Kokoro: چند گوینده‌ی منتخب.
    // صدای فعال در فایل tts/<lang>.active ثبت می‌شود (TtsService در پردازه‌ی جدا اجرا می‌شود).
    static final class TtsVoice {
        final String id;
        final String label;
        final TtsSpec spec;
        final boolean isDefault;
        final int sid;
        TtsVoice(String id, String label, TtsSpec spec, boolean isDefault) {
            this(id, label, spec, isDefault, 0);
        }
        TtsVoice(String id, String label, TtsSpec spec, boolean isDefault, int sid) {
            this.id = id; this.label = label; this.spec = spec; this.isDefault = isDefault; this.sid = sid;
        }
    }

    // {id, برچسب, sid}  — ترتیبِ sid در Kokoro v1.0 (۵۳ گوینده، الفبایی). پیش‌فرض = اولی.
    private static final String[][] KOKORO_EN = {
            {"af_heart", "Heart · US · F", "3"}, {"af_bella", "Bella · US · F", "2"},
            {"af_nicole", "Nicole · US · F", "6"}, {"af_sarah", "Sarah · US · F", "9"},
            {"am_michael", "Michael · US · M", "16"}, {"am_adam", "Adam · US · M", "11"},
            {"bf_emma", "Emma · UK · F", "21"}, {"bm_george", "George · UK · M", "26"},
    };
    private static final String[][] KOKORO_ZH = {
            {"zf_xiaoxiao", "Xiaoxiao · F", "47"}, {"zf_xiaobei", "Xiaobei · F", "45"},
            {"zf_xiaoni", "Xiaoni · F", "46"}, {"zf_xiaoyi", "Xiaoyi · F", "48"},
            {"zm_yunxi", "Yunxi · M", "50"}, {"zm_yunjian", "Yunjian · M", "49"},
            {"zm_yunyang", "Yunyang · M", "52"},
    };
    private static final int SUPERTONIC_VOICES = 10;

    private static final Map<String, List<TtsVoice>> TTS_VOICES;
    static {
        Map<String, List<TtsVoice>> vm = new LinkedHashMap<>();
        for (Map.Entry<String, TtsSpec> e : TTS_SPECS.entrySet()) {
            String lg = e.getKey();
            TtsSpec sp = e.getValue();
            List<TtsVoice> list = new ArrayList<>();
            if (sp.pkg == null) {
                String pid = piperIdOf(sp);
                list.add(new TtsVoice(pid, voiceLabel(pid), sp, true));
            } else if (ENG_KOKORO.equals(sp.engine)) {
                String[][] vs = "zh".equals(lg) ? KOKORO_ZH : KOKORO_EN;
                for (int i = 0; i < vs.length; i++) {
                    list.add(new TtsVoice(vs[i][0], vs[i][1], sp, i == 0, Integer.parseInt(vs[i][2])));
                }
            } else {
                for (int i = 0; i < SUPERTONIC_VOICES; i++) {
                    list.add(new TtsVoice("st-" + i, "Supertonic · " + (i + 1), sp, i == 0, i));
                }
            }
            vm.put(lg, list);
        }
        // صداهای اضافه‌ی فارسی (Piper) — بدون تغییر
        String[] faExtra = {"fa_IR-amir-medium", "fa_IR-ganji-medium", "fa_IR-ganji_adabi-medium",
                "fa_IR-reza_ibrahim-medium"};
        List<TtsVoice> fa = vm.get("fa");
        if (fa != null) {
            for (final String pid : faExtra) {
                boolean dup = false;
                for (TtsVoice v : fa) if (v.id.equals(pid)) { dup = true; break; }
                if (dup) continue;
                fa.add(new TtsVoice(pid, voiceLabel(pid), new TtsSpec(
                        "csukuangfj/vits-piper-" + pid, pid + ".onnx", "tokens.txt", "espeak-ng-data"), false));
            }
        }
        for (Map.Entry<String, List<TtsVoice>> e : vm.entrySet()) {
            e.setValue(Collections.unmodifiableList(e.getValue()));
        }
        TTS_VOICES = Collections.unmodifiableMap(vm);
    }

    private static String piperIdOf(TtsSpec s) {
        String f = s.modelFile;
        if (f == null) return s.pkg != null ? s.pkg.id : "";
        return f.endsWith(".onnx") ? f.substring(0, f.length() - 5) : f;
    }

    /** en_US-amy-medium → «amy · US · medium» */
    private static String voiceLabel(String pid) {
        try {
            String[] p = pid.split("-");
            if (p.length < 3) return pid;
            String loc = p[0];
            int u = loc.indexOf('_');
            String region = u >= 0 ? loc.substring(u + 1) : loc;
            StringBuilder name = new StringBuilder();
            for (int i = 1; i < p.length - 1; i++) {
                if (name.length() > 0) name.append('-');
                name.append(p[i]);
            }
            return name.toString().replace('_', ' ') + " · " + region + " · " + p[p.length - 1].replace('_', ' ');
        } catch (Throwable t) {
            return pid;
        }
    }

    static List<TtsVoice> ttsVoices(String lang) {
        String l = normalize(lang);
        List<TtsVoice> v = l == null ? null : TTS_VOICES.get(l);
        return v == null ? Collections.<TtsVoice>emptyList() : v;
    }

    private static TtsVoice findVoice(String l, String vid) {
        List<TtsVoice> list = TTS_VOICES.get(l);
        if (list == null || list.isEmpty()) return null;
        if (vid != null && !vid.isEmpty()) {
            for (TtsVoice v : list) if (v.id.equals(vid)) return v;
        }
        return null;
    }

    private static File ttsRoot(Context ctx) {
        return new File(ctx.getFilesDir(), "tts");
    }

    private static File pkgDir(Context ctx, Pkg p) {
        return new File(new File(ttsRoot(ctx), "_pkg"), p.id);
    }

    // ---- غیرفعال‌سازیِ «یک زبان» از بسته‌ی مشترک (Supertonic / Kokoro) ----
    // پاک‌کردنِ یک زبان نباید فایل‌های مشترکِ بسته را پاک کند (زبان‌های دیگر همان‌ها را می‌خوانند).
    // پس فقط یک marker (tts/<lang>.off) ساخته می‌شود و آن زبان «دانلودنشده» حساب می‌شود.
    private static File langOffMarker(Context ctx, String l) {
        return new File(ttsRoot(ctx), l + ".off");
    }

    private static boolean isLangOff(Context ctx, String l) {
        return l != null && langOffMarker(ctx, l).isFile();
    }

    private static void setLangOff(Context ctx, String l, boolean off) {
        if (l == null) return;
        try {
            File f = langOffMarker(ctx, l);
            if (off) {
                File root = ttsRoot(ctx);
                if (!root.isDirectory()) root.mkdirs();
                if (!f.isFile()) f.createNewFile();
            } else if (f.isFile()) {
                f.delete();
            }
        } catch (Throwable t) {
            Log.w(TAG, "setLangOff failed", t);
        }
    }

    /** بسته‌ی مشترک کامل دانلود شده؟ (marker + همه‌ی فایل‌ها و پوشه‌ها) */
    private static boolean pkgReady(Context ctx, Pkg p) {
        File d = pkgDir(ctx, p);
        if (!new File(d, "ready.ok").isFile()) return false;
        for (String f : p.files) {
            File x = new File(d, f);
            if (!x.isFile() || x.length() == 0) return false;
        }
        for (String sub : p.dirs) {
            String[] ch = new File(d, sub).list();
            if (ch == null || ch.length == 0) return false;
        }
        return true;
    }

    /** فایلِ خراب پیدا شد: marker پاک می‌شود تا دانلودِ بعدی کم‌وکسرها را دوباره بگیرد. */
    static void invalidatePackage(Context ctx, Pkg p) {
        try { new File(pkgDir(ctx, p), "ready.ok").delete(); } catch (Throwable ignored) {}
    }

    static File voiceDir(Context ctx, String lang, TtsVoice v) {
        return ttsDirFor(ctx, normalize(lang), v);
    }

    private static File ttsDirFor(Context ctx, String l, TtsVoice v) {
        if (v != null && v.spec.pkg != null) return pkgDir(ctx, v.spec.pkg);
        return v == null || v.isDefault
                ? new File(ttsRoot(ctx), l)
                : new File(ttsRoot(ctx), l + "__" + v.id);
    }

    /** صدای فعالِ این زبان (اگر انتخابی ثبت نشده یا نامعتبر باشد = صدای پیش‌فرض). */
    static TtsVoice activeVoice(Context ctx, String lang) {
        String l = normalize(lang);
        List<TtsVoice> list = l == null ? null : TTS_VOICES.get(l);
        if (list == null || list.isEmpty()) return null;
        try {
            File f = new File(ttsRoot(ctx), l + ".active");
            if (f.isFile() && f.length() > 0 && f.length() < 200) {
                byte[] b = new byte[(int) f.length()];
                try (java.io.FileInputStream in = new java.io.FileInputStream(f)) {
                    int off = 0, n;
                    while (off < b.length && (n = in.read(b, off, b.length - off)) > 0) off += n;
                }
                TtsVoice v = findVoice(l, new String(b, "UTF-8").trim());
                if (v != null) return v;
            }
        } catch (Throwable ignored) {}
        return list.get(0);
    }

    static void setActiveVoice(Context ctx, String lang, String vid) {
        String l = normalize(lang);
        if (l == null || !TTS_VOICES.containsKey(l)) return;
        try {
            File root = ttsRoot(ctx);
            if (!root.isDirectory()) root.mkdirs();
            File f = new File(root, l + ".active");
            TtsVoice v = findVoice(l, vid);
            if (v == null || v.isDefault) { f.delete(); return; }   // پیش‌فرض = بدون فایل
            try (FileOutputStream out = new FileOutputStream(f, false)) {
                out.write(v.id.getBytes("UTF-8"));
            }
        } catch (Throwable t) {
            Log.w(TAG, "setActiveVoice failed", t);
        }
    }

    private static boolean voiceFilesReady(Context ctx, String l, TtsVoice v) {
        if (v == null) return false;
        if (v.spec.pkg != null) {
            if (isLangOff(ctx, l)) return false;   // این زبان توسط کاربر پاک شده (بسته‌ی مشترک سر جایش است)
            if (!pkgReady(ctx, v.spec.pkg)) return false;
            // Kokoro برای کلماتِ خارج از لغت‌نامه به espeak-ng-data نیاز دارد
            return !ENG_KOKORO.equals(v.spec.engine) || isEspeakReady(ctx);
        }
        File dir = ttsDirFor(ctx, l, v);
        File model = new File(dir, "model.onnx");
        File tokens = new File(dir, "tokens.txt");
        if (!model.isFile() || model.length() == 0) return false;
        if (!tokens.isFile() || tokens.length() == 0) return false;
        // صدای پیش‌فرضِ en/fa عوض شده؛ فایل‌های قدیمیِ همان پوشه (ryan/gyro) نباید به‌جای صدای جدید حساب شوند
        if (v.isDefault && MIGRATED_LANGS.contains(l) && !v.id.equals(readVoiceMarker(dir))) return false;
        if (v.spec.rawPiper && !new File(dir, "meta.ok").isFile()) return false;
        return isEspeakReady(ctx);
    }

    private static final Set<String> MIGRATED_LANGS =
            Collections.unmodifiableSet(new java.util.HashSet<>(java.util.Arrays.asList("en", "fa", "fr")));

    /** espeak-ng-data برای مدل‌هایی که مخزنشان آن را ندارد (rawPiper) از این مخزن گرفته می‌شود. */
    private static final String ESPEAK_FALLBACK_REPO = "csukuangfj/vits-piper-en_US-amy-low";

    private static String readVoiceMarker(File dir) {
        try {
            File f = new File(dir, "voice.id");
            if (!f.isFile() || f.length() == 0 || f.length() > 200) return "";
            byte[] b = new byte[(int) f.length()];
            try (java.io.FileInputStream in = new java.io.FileInputStream(f)) {
                int off = 0, n;
                while (off < b.length && (n = in.read(b, off, b.length - off)) > 0) off += n;
            }
            return new String(b, "UTF-8").trim();
        } catch (Throwable t) {
            return "";
        }
    }

    private static void writeVoiceMarker(File dir, String id) {
        try (FileOutputStream out = new FileOutputStream(new File(dir, "voice.id"), false)) {
            out.write(id.getBytes("UTF-8"));
        } catch (Throwable t) {
            Log.w(TAG, "writeVoiceMarker failed", t);
        }
    }

    /** این صدا (نه لزوماً فعال) کامل دانلود شده؟ */
    static boolean isTtsVoiceInstalled(Context ctx, String lang, String vid) {
        String l = normalize(lang);
        if (l == null) return false;
        TtsVoice v = vid == null || vid.isEmpty() ? activeVoice(ctx, l) : findVoice(l, vid);
        return voiceFilesReady(ctx, l, v);
    }

    /** صدایی که الان برای این زبان در حال دانلود است (null = هیچ). */
    private static final Map<String, String> TTS_DL_VOICE = new ConcurrentHashMap<>();

    static String downloadingVoiceId(String lang) {
        String l = normalize(lang);
        return l == null ? null : TTS_DL_VOICE.get(l);
    }

    static long getTtsPartialBytes(Context ctx, String lang, String vid) {
        String l = normalize(lang);
        if (l == null) return 0;
        TtsVoice v = vid == null || vid.isEmpty() ? activeVoice(ctx, l) : findVoice(l, vid);
        if (v == null) return 0;
        if (v.spec.pkg != null) {
            if (pkgReady(ctx, v.spec.pkg)) return 0;
            long sum = 0;
            File[] fs = pkgDir(ctx, v.spec.pkg).listFiles();
            if (fs != null) for (File f : fs) if (f.isFile() && !f.getName().equals("ready.ok")) sum += f.length();
            return sum;
        }
        File part = new File(ttsDirFor(ctx, l, v), "model.onnx.part");
        return part.isFile() ? part.length() : 0;
    }

    private static final OkHttpClient HTTP = new OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(25, TimeUnit.SECONDS)
            .build();
    private static final AtomicBoolean DOWNLOADING = new AtomicBoolean(false);
    private static volatile boolean DOWNLOADING_STATE = false;
    // دانلودِ TTS برای هر زبان مستقله؛ چند زبان می‌تونن هم‌زمان دانلود بشن
    private static final Set<String> TTS_ACTIVE = ConcurrentHashMap.newKeySet();
    // espeak-ng-data بینِ همه‌ی زبان‌ها مشترکه؛ فقط یک نخ دانلودش می‌کنه، بقیه صبر می‌کنن
    private static final ReentrantLock ESPEAK_LOCK = new ReentrantLock();
    // زبان‌هایی که کاربر «توقف» رو زده؛ فایل .part نگه داشته می‌شه تا دفعه‌ی بعد ادامه پیدا کنه
    private static final Set<String> TTS_CANCEL = ConcurrentHashMap.newKeySet();

    /** پرتاب می‌شه وقتی کاربر دانلود رو متوقف کرده. */
    static final class DownloadCancelled extends java.io.IOException {
        DownloadCancelled() { super("cancelled"); }
    }

    static void cancelTtsDownload(String lang) {
        String l = normalize(lang);
        if (l != null && TTS_ACTIVE.contains(l)) TTS_CANCEL.add(l);
    }

    static void cancelAllTtsDownloads() {
        TTS_CANCEL.addAll(TTS_ACTIVE);
    }

    private static void checkCancel(String l) throws DownloadCancelled {
        if (l != null && TTS_CANCEL.contains(l)) throw new DownloadCancelled();
    }

    /** حجمِ بخشِ دانلودشده‌ی ناتمامِ بسته‌ی یه زبان (برای دکمه‌ی «ادامه»). */
    static long getTtsPartialBytes(Context ctx, String lang) {
        return getTtsPartialBytes(ctx, lang, null);
    }
    // آخرین مقدارِ پیشرفتِ هر زبان (بایت) — برای نوتیفیکیشنِ سرویسِ دانلود
    private static final Map<String, Long> TTS_BYTES = new ConcurrentHashMap<>();

    static long getTtsDownloadedBytes() {
        long sum = 0;
        for (Long v : TTS_BYTES.values()) if (v != null) sum += v;
        return sum;
    }

    // ============ متدهای مشترک ============
    static String normalize(String lang) {
        if (lang == null) return null;
        String l = lang.trim().toLowerCase(Locale.ROOT);
        int i = l.indexOf('-');
        if (i < 0) i = l.indexOf('_');
        if (i > 0) l = l.substring(0, i);
        return l.isEmpty() ? null : l;
    }

    // ============ STT ============
    static boolean isAvailable(String lang) {
        String l = normalize(lang);
        return l != null && SPECS.containsKey(l);
    }

    static boolean isDownloading() { return DOWNLOADING_STATE; }

    private static File sttDirFor(Context ctx, String l) {
        return new File(new File(ctx.getFilesDir(), "sherpa"), l);
    }

    static File getModelDir(Context ctx, String lang) {
        String l = normalize(lang);
        Spec s = l == null ? null : SPECS.get(l);
        if (s == null) return null;
        File dir = sttDirFor(ctx, l);
        for (String f : s.files()) {
            File x = new File(dir, f);
            if (!x.isFile() || x.length() == 0) return null;
        }
        return dir;
    }

    static String encoderFile(String lang) { Spec s = SPECS.get(normalize(lang)); return s == null ? null : s.encoder; }
    static String decoderFile(String lang) { Spec s = SPECS.get(normalize(lang)); return s == null ? null : s.decoder; }
    static String joinerFile(String lang)  { Spec s = SPECS.get(normalize(lang)); return s == null ? null : s.joiner; }
    static String tokensFile(String lang)  { Spec s = SPECS.get(normalize(lang)); return s == null ? null : s.tokens; }

    // ============ TTS ============
    static boolean isTtsAvailable(String lang) {
        String l = normalize(lang);
        return l != null && TTS_SPECS.containsKey(l);
    }

    /** زبان‌هایی که بسته TTS آفلاین دارن (به ترتیب تعریف). */
    static List<String> ttsLanguages() {
        return new ArrayList<>(TTS_SPECS.keySet());
    }

    /** زبان‌هایی که بسته TTS‌شون همین الان در حال دانلوده. */
    static List<String> getTtsDownloadingLangs() {
        return new ArrayList<>(TTS_ACTIVE);
    }

    static boolean isTtsDownloading() { return !TTS_ACTIVE.isEmpty(); }

    static boolean isTtsDownloading(String lang) {
        String l = normalize(lang);
        return l != null && TTS_ACTIVE.contains(l);
    }

    /** espeak-ng-data مشترکِ همه‌ی بسته‌های Piper (یک بار دانلود می‌شه). */
    static File getEspeakDataDir(Context ctx) {
        return new File(new File(ctx.getFilesDir(), "tts"), "espeak-ng-data");
    }

    private static File espeakMarker(Context ctx) {
        return new File(new File(ctx.getFilesDir(), "tts"), "espeak-ng-data.ok");
    }

    private static boolean isEspeakReady(Context ctx) {
        return espeakMarker(ctx).isFile() && getEspeakDataDir(ctx).isDirectory();
    }

    /** espeak-ng-data ناقص/خراب بود: marker رو پاک کن تا دانلودِ بعدی فایل‌های کم‌وکسر رو دوباره بگیره. */
    static void invalidateEspeak(Context ctx) {
        try { espeakMarker(ctx).delete(); } catch (Throwable ignored) {}
    }

    /** صدایی که الان آماده‌ی استفاده است (فعال؛ اگر سالم نبود پیش‌فرض)، یا null. */
    static TtsVoice getReadyVoice(Context ctx, String lang) {
        String l = normalize(lang);
        if (l == null || !TTS_SPECS.containsKey(l)) return null;
        cleanupLegacyTts(ctx);
        TtsVoice v = activeVoice(ctx, l);
        if (voiceFilesReady(ctx, l, v)) return v;
        // صدای انتخاب‌شده سالم نیست (مثلاً ناقص/حذف‌شده) → به صدای پیش‌فرض برگرد تا خوانش قطع نشود
        List<TtsVoice> all = TTS_VOICES.get(l);
        if (all != null && !all.isEmpty() && all.get(0) != v && voiceFilesReady(ctx, l, all.get(0))) {
            return all.get(0);
        }
        return null;
    }

    static File getTtsModelDir(Context ctx, String lang) {
        String l = normalize(lang);
        TtsVoice v = getReadyVoice(ctx, lang);
        return v == null ? null : ttsDirFor(ctx, l, v);
    }

    // ============ پاک‌سازیِ صداهای قدیمیِ Piper (غیرِ فارسی) ============
    // فقط یک بار: پوشه‌های tts/<lang> و tts/<lang>__* و فایل‌های <lang>.active زبان‌هایی که حالا Supertonic/Kokoro دارند.
    // فارسی، espeak-ng-data و بسته‌های جدید (_pkg) دست‌نخورده می‌مانند.
    private static volatile boolean LEGACY_DONE = false;
    private static final String[] LEGACY_PIPER_LANGS =
            {"en", "es", "de", "fr", "it", "hi", "tr", "ar", "zh", "ru", "ko", "ja", "he"};

    static void cleanupLegacyTts(Context ctx) {
        if (LEGACY_DONE) return;
        LEGACY_DONE = true;
        try {
            File root = ttsRoot(ctx);
            if (!root.isDirectory()) return;
            File marker = new File(root, "legacy-piper-removed.v1");
            if (marker.isFile()) return;
            File[] fs = root.listFiles();
            if (fs != null) {
                for (File f : fs) {
                    String n = f.getName();
                    for (String lg : LEGACY_PIPER_LANGS) {
                        if (n.equals(lg) || n.startsWith(lg + "__") || n.equals(lg + ".active")) {
                            deleteRecursive(f);
                            break;
                        }
                    }
                }
            }
            try { marker.createNewFile(); } catch (Throwable ignored) {}
        } catch (Throwable t) {
            Log.w(TAG, "cleanupLegacyTts failed", t);
        }
    }

    // ============ دانلود STT ============
    // توقف/ادامه مثلِ دانلودِ صدا: فایل‌های .part نگه داشته می‌شن و دانلودِ بعدی با Range ادامه پیدا می‌کنه.
    private static volatile boolean STT_CANCEL = false;
    private static volatile String STT_ACTIVE = null;

    /** توقفِ دانلودِ بسته‌ی تشخیص گفتار (بخشِ دانلودشده می‌مونه). */
    static void cancelDownload() { if (DOWNLOADING.get()) STT_CANCEL = true; }

    /** زبانی که همین الان بسته‌اش دانلود می‌شه (یا null). */
    static String activeDownloadLang() { return STT_ACTIVE; }

    /** حجمِ بخشِ دانلودشده‌ی ناتمامِ بسته‌ی یه زبان (برای دکمه‌ی «ادامه»). */
    static long getSttPartialBytes(Context ctx, String lang) {
        String l = normalize(lang);
        Spec s = l == null ? null : SPECS.get(l);
        if (s == null) return 0;
        long sum = 0;
        File dir = sttDirFor(ctx, l);
        for (String f : s.files()) {
            File p = new File(dir, f + ".part");
            if (p.isFile()) sum += p.length();
        }
        return sum;
    }

    static void downloadModel(final Context ctx, final String lang, final ProgressCallback cb) {
        final Context app = ctx.getApplicationContext();
        final String l = normalize(lang);
        final Spec s = l == null ? null : SPECS.get(l);
        if (s == null) {
            if (cb != null) cb.onError(String.valueOf(lang), new IllegalArgumentException("no model for " + lang));
            return;
        }
        if (!DOWNLOADING.compareAndSet(false, true)) {
            if (cb != null) cb.onError(l, new IllegalStateException("another download is running"));
            return;
        }
        DOWNLOADING_STATE = true;
        STT_CANCEL = false;
        STT_ACTIVE = l;
        Thread t = new Thread(() -> {
            Exception failure = null;
            try {
                File dir = sttDirFor(app, l);
                if (!dir.isDirectory() && !dir.mkdirs()) throw new java.io.IOException("cannot create " + dir);
                long[] done = {0};
                for (String name : s.files()) {
                    if (STT_CANCEL) throw new DownloadCancelled();
                    File target = new File(dir, name);
                    if (target.isFile() && target.length() > 0) { done[0] += target.length(); continue; }
                    downloadSttFile(HF_BASE + s.repo + "/resolve/main/" + name, target, cb, l, done);
                }
            } catch (Exception e) {
                if (!(e instanceof DownloadCancelled)) Log.w(TAG, "STT download failed for " + l, e);
                failure = e;
            } finally {
                // اول وضعیت رو پاک کن، بعد به JS خبر بده — وگرنه JS موقعِ refresh هنوز «در حال دانلود» می‌بینه
                STT_ACTIVE = null;
                STT_CANCEL = false;
                DOWNLOADING.set(false);
                DOWNLOADING_STATE = false;
            }
            if (cb != null) {
                if (failure == null) cb.onDone(l); else cb.onError(l, failure);
            }
        }, "sherpa-download");
        t.setDaemon(true);
        t.start();
    }

    /** یک فایلِ بسته‌ی STT رو با امکانِ ادامه (Range) و توقفِ کاربر می‌گیره. done[0] = مجموعِ بایت‌های همه‌ی فایل‌ها. */
    private static void downloadSttFile(String url, File target, ProgressCallback cb, String l, long[] done) throws Exception {
        File part = new File(target.getParentFile(), target.getName() + ".part");
        long existing = part.isFile() ? part.length() : 0;
        Request.Builder rb = new Request.Builder().url(url);
        if (existing > 0) rb.header("Range", "bytes=" + existing + "-");
        try (Response r = HTTP.newCall(rb.build()).execute()) {
            if (r.code() == 416) {
                // بخشِ قبلی با فایلِ سرور نمی‌خونه؛ از اول می‌گیریم
                part.delete();
                downloadSttFile(url, target, cb, l, done);
                return;
            }
            if (!r.isSuccessful() || r.body() == null) {
                throw new java.io.IOException("HTTP " + r.code() + " for " + target.getName());
            }
            String ctype = r.header("Content-Type");
            if (ctype != null && ctype.toLowerCase(Locale.ROOT).startsWith("text/html")) {
                part.delete();
                throw new java.io.IOException("server returned HTML instead of " + target.getName());
            }
            boolean resumed = r.code() == 206 && existing > 0;
            long base = resumed ? existing : 0;
            long len = r.body().contentLength();
            long total = len > 0 ? base + len : -1;
            done[0] += base;
            long lastEmit = 0;
            try (InputStream in = r.body().byteStream();
                 OutputStream out = new FileOutputStream(part, resumed)) {
                byte[] buf = new byte[64 * 1024];
                int n;
                while ((n = in.read(buf)) > 0) {
                    if (STT_CANCEL) throw new DownloadCancelled();
                    out.write(buf, 0, n);
                    done[0] += n;
                    if (cb != null) {
                        long now = System.currentTimeMillis();
                        if (now - lastEmit > 300) { lastEmit = now; cb.onProgress(l, done[0], -1); }
                    }
                }
            }
            if (cb != null) cb.onProgress(l, done[0], -1);
            if (total > 0 && part.length() != total) throw new java.io.IOException("incomplete download: " + target.getName());
        }
        if (target.exists()) target.delete();
        if (!part.renameTo(target)) throw new java.io.IOException("rename failed: " + target.getName());
    }

    // ============ دانلود TTS ============
    // هر زبان توی نخِ خودش دانلود می‌شه، پس می‌شه همه‌ی زبان‌ها رو هم‌زمان زد.
    static void downloadTtsModel(final Context ctx, final String lang, final ProgressCallback cb) {
        downloadTtsModel(ctx, lang, null, cb);
    }

    /** vid = شناسه‌ی صدا (null = صدای فعالِ همین زبان). بعد از دانلودِ کامل، همین صدا فعال می‌شود. */
    static void downloadTtsModel(final Context ctx, final String lang, final String vid, final ProgressCallback cb) {
        final Context app = ctx.getApplicationContext();
        final String l = normalize(lang);
        final TtsVoice voice = l == null ? null
                : (vid == null || vid.isEmpty() ? activeVoice(app, l) : findVoice(l, vid));
        final TtsSpec s = voice == null ? null : voice.spec;
        if (s == null) {
            if (cb != null) cb.onError(String.valueOf(lang), new IllegalArgumentException("no TTS for " + lang));
            return;
        }
        if (!TTS_ACTIVE.add(l)) {
            // همین زبان همین الان در حال دانلوده؛ دوباره شروعش نمی‌کنیم
            return;
        }
        TTS_DL_VOICE.put(l, voice.id);
        TTS_CANCEL.remove(l);
        Thread t = new Thread(() -> {
            try {
                Exception last = null;
                for (int attempt = 1; attempt <= 3; attempt++) {
                    try {
                        downloadTtsOnce(app, l, s, ttsDirFor(app, l, voice), new ProgressCallback() {
                            @Override public void onProgress(String lg, long done, long total) {
                                TTS_BYTES.put(l, done);
                                if (cb != null) cb.onProgress(lg, done, total);
                            }
                            @Override public void onDone(String lg) {}
                            @Override public void onError(String lg, Exception e) {}
                        });
                        last = null;
                        break;
                    } catch (DownloadCancelled dc) {
                        last = dc;
                        break;
                    } catch (Exception e) {
                        last = e;
                        Log.w(TAG, "TTS download attempt " + attempt + " failed for " + l, e);
                        if (TTS_CANCEL.contains(l)) { last = new DownloadCancelled(); break; }
                        try { Thread.sleep(1500L * attempt); } catch (InterruptedException ie) { break; }
                    }
                }
                if (last != null) {
                    if (cb != null) {
                        if (last instanceof DownloadCancelled) cb.onError(l, last);
                        else cb.onError(l, new Exception(last.getClass().getSimpleName() + ": " + last.getMessage(), last));
                    }
                } else {
                    // دانلودِ کامل شد → اگر این زبان قبلاً پاک شده بود دوباره فعال شود، و همین صدا صدای فعالِ زبان می‌شود
                    if (voice.spec.pkg != null) setLangOff(app, l, false);
                    setActiveVoice(app, l, voice.id);
                    if (cb != null) cb.onDone(l);
                }
            } finally {
                TTS_DL_VOICE.remove(l);
                TTS_BYTES.remove(l);
                TTS_CANCEL.remove(l);
                TTS_ACTIVE.remove(l);
            }
        }, "sherpa-tts-download-" + l);
        t.setDaemon(true);
        t.start();
    }

    private static void downloadTtsOnce(Context app, String l, TtsSpec s, File dir, ProgressCallback cb) throws Exception {
        if (s.pkg != null) {
            downloadPackage(app, l, s, cb);
            return;
        }
        if (!dir.isDirectory() && !dir.mkdirs()) throw new java.io.IOException("cannot create " + dir);

        // فایل‌های صدای قدیمی (مثلاً ryan/gyro که پیش‌فرض بودند) پاک می‌شوند تا با صدای جدید قاطی نشوند
        final String vid = piperIdOf(s);
        if (MIGRATED_LANGS.contains(l) && dir.getName().equals(l) && !vid.equals(readVoiceMarker(dir))) {
            new File(dir, "model.onnx").delete();
            new File(dir, "model.onnx.part").delete();
            new File(dir, "tokens.txt").delete();
            new File(dir, "tokens.txt.part").delete();
            new File(dir, "model.json").delete();
            new File(dir, "meta.ok").delete();
        }

        if (s.rawPiper) {
            // ۱. فایل پیکربندی Piper → tokens.txt
            checkCancel(l);
            File cfg = new File(dir, "model.json");
            if (!cfg.isFile() || cfg.length() == 0) {
                downloadFile(HF_BASE + s.repo + "/resolve/main/" + s.modelFile + ".json", cfg, cb, l);
            }
            File tokensTarget = new File(dir, "tokens.txt");
            if (!tokensTarget.isFile() || tokensTarget.length() == 0) {
                writeTokensFromPiperJson(cfg, tokensTarget);
            }
        } else {
            // ۱. tokens.txt (کوچیکه)
            checkCancel(l);
            File tokensTarget = new File(dir, "tokens.txt");
            if (!tokensTarget.isFile() || tokensTarget.length() == 0) {
                downloadFile(HF_BASE + s.repo + "/resolve/main/" + s.tokensFile, tokensTarget, cb, l);
            }
        }

        // ۲. model.onnx (بزرگ‌ترین فایل؛ از همین‌جا پیشرفت دیده می‌شه و از نقطه‌ی توقف ادامه پیدا می‌کنه)
        checkCancel(l);
        File modelTarget = new File(dir, "model.onnx");
        if (!modelTarget.isFile() || modelTarget.length() == 0) {
            downloadFile(HF_BASE + s.repo + "/resolve/main/" + s.modelFile, modelTarget, cb, l);
        }

        // ۲.۵ فایل خام Piper: metadata موردنیاز Sherpa را به انتهای onnx اضافه کن (فقط یک بار)
        if (s.rawPiper) {
            File ok = new File(dir, "meta.ok");
            if (!ok.isFile()) {
                appendSherpaMetadata(modelTarget, new File(dir, "model.json"));
                if (!ok.createNewFile()) throw new java.io.IOException("cannot create meta.ok");
            }
        }

        // ۳. espeak-ng-data مشترک (فقط یک بار؛ زبان‌های دیگه همین‌جا صبر می‌کنن، ولی با امکانِ توقف)
        if (!isEspeakReady(app)) {
            while (!ESPEAK_LOCK.tryLock(500, TimeUnit.MILLISECONDS)) {
                checkCancel(l);
                if (isEspeakReady(app)) break;
            }
            if (ESPEAK_LOCK.isHeldByCurrentThread()) {
                try {
                    if (!isEspeakReady(app)) {
                        downloadEspeakData(app, s.rawPiper ? ESPEAK_FALLBACK_REPO : s.repo, cb, l);
                    }
                } finally {
                    ESPEAK_LOCK.unlock();
                }
            }
        }

        // ۴. همه‌چیز کامل شد → این پوشه مالِ همین صداست
        writeVoiceMarker(dir, vid);
    }

    // ============ دانلودِ بسته‌ی مشترک (Supertonic / Kokoro) ============
    // چند زبان یک بسته را مشترک دارند؛ قفلِ هر بسته جلوی دانلودِ هم‌زمانِ دوباره را می‌گیرد.
    private static final Map<String, ReentrantLock> PKG_LOCKS = new ConcurrentHashMap<>();

    private static ProgressCallback offsetCb(final ProgressCallback cb, final long base, final long total) {
        return new ProgressCallback() {
            @Override public void onProgress(String lg, long d, long t) {
                if (cb != null) cb.onProgress(lg, Math.min(base + d, total), total);
            }
            @Override public void onDone(String lg) {}
            @Override public void onError(String lg, Exception e) {}
        };
    }

    private static void downloadPackage(Context app, String l, TtsSpec s, ProgressCallback cb) throws Exception {
        final Pkg p = s.pkg;
        ReentrantLock lock = PKG_LOCKS.get(p.id);
        if (lock == null) {
            PKG_LOCKS.putIfAbsent(p.id, new ReentrantLock());
            lock = PKG_LOCKS.get(p.id);
        }
        while (!lock.tryLock(500, TimeUnit.MILLISECONDS)) {
            checkCancel(l);
            if (pkgReady(app, p)) break;
        }
        try {
            if (!pkgReady(app, p)) {
                File dir = pkgDir(app, p);
                if (!dir.isDirectory() && !dir.mkdirs()) throw new java.io.IOException("cannot create " + dir);
                new File(dir, "ready.ok").delete();
                long done = 0;
                for (String name : p.files) {
                    checkCancel(l);
                    File target = new File(dir, name);
                    if (!target.isFile() || target.length() == 0) {
                        downloadFile(HF_BASE + p.repo + "/resolve/main/" + name, target,
                                offsetCb(cb, done, p.approxBytes), l);
                    }
                    done += target.length();
                    if (cb != null) cb.onProgress(l, Math.min(done, p.approxBytes), p.approxBytes);
                }
                for (String sub : p.dirs) {
                    checkCancel(l);
                    done += downloadRepoDir(p.repo, sub, new File(dir, sub), offsetCb(cb, done, p.approxBytes), l);
                }
                File ok = new File(dir, "ready.ok");
                if (!ok.exists() && !ok.createNewFile()) throw new java.io.IOException("cannot create ready.ok");
            }
        } finally {
            if (lock.isHeldByCurrentThread()) lock.unlock();
        }
        // Kokoro: espeak-ng-data مشترک (همان که فارسی هم دارد)
        if (ENG_KOKORO.equals(s.engine)) ensureEspeak(app, ESPEAK_FALLBACK_REPO, cb, l);
    }

    private static void ensureEspeak(Context app, String repo, ProgressCallback cb, String l) throws Exception {
        if (isEspeakReady(app)) return;
        while (!ESPEAK_LOCK.tryLock(500, TimeUnit.MILLISECONDS)) {
            checkCancel(l);
            if (isEspeakReady(app)) break;
        }
        if (ESPEAK_LOCK.isHeldByCurrentThread()) {
            try {
                if (!isEspeakReady(app)) downloadEspeakData(app, repo, cb, l);
            } finally {
                ESPEAK_LOCK.unlock();
            }
        }
    }

    /** tokens.txt ی Sherpa را از phoneme_id_map فایل json ی Piper می‌سازد («نماد id» در هر خط). */
    private static void writeTokensFromPiperJson(File cfg, File out) throws Exception {
        String json = readAll(cfg);
        JSONObject map = new JSONObject(json).getJSONObject("phoneme_id_map");
        File tmp = new File(out.getParentFile(), "tokens.txt.part");
        try (java.io.Writer w = new java.io.OutputStreamWriter(new FileOutputStream(tmp, false), "UTF-8")) {
            java.util.Iterator<String> it = map.keys();
            while (it.hasNext()) {
                String sym = it.next();
                JSONArray ids = map.getJSONArray(sym);
                if (ids.length() == 0) continue;
                w.write(sym + " " + ids.getInt(0) + "\n");
            }
        }
        if (out.exists()) out.delete();
        if (!tmp.renameTo(out)) throw new java.io.IOException("rename failed: tokens.txt");
    }

    /**
     * Sherpa-ONNX برای مدل‌های Piper چند کلید metadata داخل خود onnx می‌خواهد (model_type, comment=piper, voice, ...).
     * فایل خام Piper آن‌ها را ندارد. ModelProto.metadata_props فیلدِ شماره‌ی ۱۴ (repeated) است و در protobuf
     * اضافه کردنِ بایت‌های یک فیلدِ تکرارشونده به انتهای فایل معتبر است؛ پس همین‌جا به انتهای فایل می‌چسبانیم.
     */
    private static void appendSherpaMetadata(File onnx, File cfg) throws Exception {
        JSONObject c = new JSONObject(readAll(cfg));
        int sampleRate = c.getJSONObject("audio").optInt("sample_rate", 22050);
        int nSpeakers = c.optInt("num_speakers", 1);
        String voice = c.has("espeak") ? c.getJSONObject("espeak").optString("voice", "fa") : "fa";
        java.io.ByteArrayOutputStream bo = new java.io.ByteArrayOutputStream();
        putMeta(bo, "model_type", "vits");
        putMeta(bo, "comment", "piper");
        putMeta(bo, "language", "Persian");
        putMeta(bo, "voice", voice);
        putMeta(bo, "has_espeak", "1");
        putMeta(bo, "n_speakers", String.valueOf(nSpeakers));
        putMeta(bo, "sample_rate", String.valueOf(sampleRate));
        try (FileOutputStream out = new FileOutputStream(onnx, true)) {
            out.write(bo.toByteArray());
        }
    }

    private static void putMeta(java.io.ByteArrayOutputStream bo, String key, String value) throws Exception {
        byte[] k = key.getBytes("UTF-8");
        byte[] v = value.getBytes("UTF-8");
        java.io.ByteArrayOutputStream entry = new java.io.ByteArrayOutputStream();
        entry.write(0x0A); writeVarint(entry, k.length); entry.write(k);       // StringStringEntryProto.key
        entry.write(0x12); writeVarint(entry, v.length); entry.write(v);       // .value
        bo.write(0x72);                                                         // ModelProto.metadata_props (14, len-delimited)
        writeVarint(bo, entry.size());
        bo.write(entry.toByteArray());
    }

    private static void writeVarint(java.io.ByteArrayOutputStream o, int v) {
        while ((v & ~0x7F) != 0) { o.write((v & 0x7F) | 0x80); v >>>= 7; }
        o.write(v);
    }

    private static String readAll(File f) throws Exception {
        try (java.io.FileInputStream in = new java.io.FileInputStream(f)) {
            java.io.ByteArrayOutputStream bo = new java.io.ByteArrayOutputStream();
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) > 0) bo.write(buf, 0, n);
            return bo.toString("UTF-8");
        }
    }

    /** پوشه‌ی espeak-ng-data رو از HuggingFace می‌گیره؛ فقط وقتی کامل شد فایلِ marker ساخته می‌شه. */
    private static void downloadEspeakData(Context app, String repo, ProgressCallback cb, String l) throws Exception {
        downloadRepoDir(repo, "espeak-ng-data", getEspeakDataDir(app), cb, l);
        File marker = espeakMarker(app);
        if (!marker.exists() && !marker.createNewFile()) throw new java.io.IOException("cannot create marker");
    }

    /**
     * یک زیرپوشه‌ی مخزنِ HuggingFace (لیستِ فایل‌ها با API) را داخلِ root کپی می‌کند.
     * خروجی: مجموعِ بایت‌های پوشه.
     */
    private static long downloadRepoDir(String repo, String sub, File root, ProgressCallback cb, String l) throws Exception {
        final String prefix = sub + "/";
        if (!root.isDirectory() && !root.mkdirs()) throw new java.io.IOException("cannot create " + root);

        // لیست فایل‌ها (با صفحه‌بندی)
        List<String> paths = new ArrayList<>();
        List<Long> sizes = new ArrayList<>();
        String next = HF_BASE + "api/models/" + repo + "/tree/main/" + sub + "?recursive=true";
        int guard = 0;
        while (next != null && guard++ < 20) {
            checkCancel(l);
            Request req = new Request.Builder().url(next).build();
            try (Response r = HTTP.newCall(req).execute()) {
                if (!r.isSuccessful() || r.body() == null) {
                    throw new java.io.IOException("HTTP " + r.code() + " listing " + sub);
                }
                String body = r.body().string();
                JSONArray arr = new JSONArray(body);
                for (int i = 0; i < arr.length(); i++) {
                    JSONObject o = arr.getJSONObject(i);
                    if (!"file".equals(o.optString("type"))) continue;
                    String p = o.optString("path");
                    if (p.startsWith(prefix)) {
                        paths.add(p);
                        sizes.add(o.optLong("size", 0));
                    }
                }
                next = fixHost(parseNextLink(r.header("Link")));
            }
        }
        if (paths.isEmpty()) throw new java.io.IOException(sub + " list is empty");

        // فایل‌ها رو چندتا چندتا هم‌زمان می‌گیریم (صدها فایل کوچیکه؛ یکی‌یکی خیلی کند بود)
        final AtomicLong done = new AtomicLong(0);
        final long totalBytes = sumSizes(sizes);
        ExecutorService ex = Executors.newFixedThreadPool(6);
        try {
            List<Future<Void>> futures = new ArrayList<>();
            for (int i = 0; i < paths.size(); i++) {
                final String p = paths.get(i);
                final String rel = p.substring(prefix.length());
                final File target = new File(root, rel);
                final long expected = sizes.get(i);
                File parent = target.getParentFile();
                if (parent != null && !parent.isDirectory() && !parent.mkdirs()) {
                    throw new java.io.IOException("cannot create " + parent);
                }
                if (target.isFile() && (expected <= 0 || target.length() == expected)) {
                    done.addAndGet(target.length());
                    continue;
                }
                final String url = HF_BASE + repo + "/resolve/main/" + p;
                futures.add(ex.submit(new Callable<Void>() {
                    @Override public Void call() throws Exception {
                        checkCancel(l);
                        downloadFile(url, target, null, l);
                        long now = done.addAndGet(target.length());
                        if (cb != null) cb.onProgress(l, now, totalBytes);
                        return null;
                    }
                }));
            }
            for (Future<Void> f : futures) {
                try {
                    f.get();
                } catch (ExecutionException ee) {
                    Throwable c = ee.getCause();
                    if (c instanceof Exception) throw (Exception) c;
                    throw ee;
                }
            }
        } finally {
            ex.shutdownNow();
        }
        return done.get();
    }

    private static long sumSizes(List<Long> sizes) {
        long t = 0;
        for (Long v : sizes) if (v != null) t += v;
        return t;
    }

    /** لینکِ صفحه‌ی بعدیِ API ممکنه به huggingface.co اشاره کنه؛ همون مسیر رو روی آینه‌ی خودمون می‌خونیم. */
    private static String fixHost(String url) {
        if (url == null) return null;
        int i = url.indexOf("/api/");
        if (i < 0) return url;
        return HF_BASE + url.substring(i + 1);
    }

    /** از هدرِ Link مقدارِ rel="next" رو درمیاره (یا null). */
    private static String parseNextLink(String link) {
        if (link == null) return null;
        for (String part : link.split(",")) {
            if (part.contains("rel=\"next\"")) {
                int a = part.indexOf('<');
                int b = part.indexOf('>');
                if (a >= 0 && b > a) return part.substring(a + 1, b).trim();
            }
        }
        return null;
    }

    /** دانلودِ فایل با امکانِ ادامه از نقطه‌ی توقف (Range) و توقفِ کاربر. */
    private static void downloadFile(String url, File target, ProgressCallback cb, String l) throws Exception {
        File part = new File(target.getParentFile(), target.getName() + ".part");
        long existing = part.isFile() ? part.length() : 0;
        Request.Builder rb = new Request.Builder().url(url);
        if (existing > 0) rb.header("Range", "bytes=" + existing + "-");
        try (Response r = HTTP.newCall(rb.build()).execute()) {
            if (r.code() == 416) {
                // بخشِ قبلی با فایلِ سرور نمی‌خونه؛ از اول می‌گیریم
                part.delete();
                downloadFile(url, target, cb, l);
                return;
            }
            if (!r.isSuccessful() || r.body() == null) {
                throw new java.io.IOException("HTTP " + r.code() + " for " + target.getName());
            }
            // صفحه‌ی خطای آینه (HTML) به‌جای فایل → خرابِ بی‌صدا؛ همین‌جا ردش کن
            String ctype = r.header("Content-Type");
            if (ctype != null && ctype.toLowerCase(Locale.ROOT).startsWith("text/html")) {
                part.delete();
                throw new java.io.IOException("server returned HTML instead of " + target.getName());
            }
            boolean resumed = r.code() == 206 && existing > 0;
            long base = resumed ? existing : 0;
            long len = r.body().contentLength();
            long total = len > 0 ? base + len : -1;
            long done = base;
            long lastEmit = 0;
            try (InputStream in = r.body().byteStream();
                 OutputStream out = new FileOutputStream(part, resumed)) {
                byte[] buf = new byte[64 * 1024];
                int n;
                while ((n = in.read(buf)) > 0) {
                    checkCancel(l);
                    out.write(buf, 0, n);
                    done += n;
                    if (cb != null) {
                        long now = System.currentTimeMillis();
                        if (now - lastEmit > 300) { lastEmit = now; cb.onProgress(l, done, total); }
                    }
                }
            }
            if (cb != null) cb.onProgress(l, done, total);
            if (total > 0 && part.length() != total) throw new java.io.IOException("incomplete download");
            if (target.getName().endsWith(".onnx") && part.length() < 2_000_000L) {
                part.delete();
                throw new java.io.IOException("model file too small: " + part.length());
            }
        }
        if (target.exists()) target.delete();
        if (!part.renameTo(target)) throw new java.io.IOException("rename failed: " + target.getName());
    }

    // ============ حذف ============
    static void deleteModel(Context ctx, String lang) {
        String l = normalize(lang);
        if (l == null) return;
        File dir = sttDirFor(ctx, l);
        deleteRecursive(dir);
    }

    static void deleteTtsModel(Context ctx, String lang) {
        deleteTtsModel(ctx, lang, null);
    }

    /** vid = null → صدای فعالِ این زبان. اگر صدای فعال پاک شود، انتخاب به صدای پیش‌فرض برمی‌گردد. */
    static void deleteTtsModel(Context ctx, String lang, String vid) {
        String l = normalize(lang);
        if (l == null) return;
        TtsVoice active = activeVoice(ctx, l);
        TtsVoice v = vid == null || vid.isEmpty() ? active : findVoice(l, vid);
        if (v == null) return;
        if (v.spec.pkg != null) {
            // بسته‌ی مشترک (Supertonic/Kokoro): فقط «همین زبان» غیرفعال می‌شود، نه فایل‌های مشترک
            deletePkgLanguage(ctx, l, v.spec.pkg);
            return;
        }
        deleteRecursive(ttsDirFor(ctx, l, v));
        if (active != null && active.id.equals(v.id) && !v.isDefault) setActiveVoice(ctx, l, null);
    }

    /**
     * پاک‌کردنِ یک زبان از بسته‌ی مشترک: زبان غیرفعال می‌شود و فایل‌های مشترک دست‌نخورده می‌مانند.
     * فقط وقتی «هیچ زبانِ دیگری» از همین بسته باقی نمانده باشد، فایل‌های بسته برای آزادشدنِ فضا پاک می‌شوند.
     */
    private static void deletePkgLanguage(Context ctx, String l, Pkg p) {
        setLangOff(ctx, l, true);
        try { new File(ttsRoot(ctx), l + ".active").delete(); } catch (Throwable ignored) {}
        for (Map.Entry<String, TtsSpec> e : TTS_SPECS.entrySet()) {
            if (e.getValue().pkg != p || e.getKey().equals(l)) continue;
            if (!isLangOff(ctx, e.getKey()) || TTS_ACTIVE.contains(e.getKey())) return;   // زبانِ دیگری هنوز از بسته استفاده می‌کند
        }
        deleteRecursive(pkgDir(ctx, p));
    }

    private static void deleteRecursive(File f) {
        if (f == null) return;
        if (f.isDirectory()) {
            File[] fs = f.listFiles();
            if (fs != null) for (File c : fs) deleteRecursive(c);
        }
        f.delete();
    }
}
