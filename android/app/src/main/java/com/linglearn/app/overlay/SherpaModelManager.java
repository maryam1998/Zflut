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
    private static final class TtsSpec {
        final String repo;         // مخزن HuggingFace
        final String modelFile;    // فایل .onnx داخل مخزن
        final String tokensFile;   // فایل tokens.txt
        final String dataDirName;  // نام پوشه espeak-ng-data
        TtsSpec(String repo, String modelFile, String tokensFile, String dataDirName) {
            this.repo = repo;
            this.modelFile = modelFile;
            this.tokensFile = tokensFile;
            this.dataDirName = dataDirName;
        }
    }

    private static final Map<String, TtsSpec> TTS_SPECS;
    static {
        Map<String, TtsSpec> m = new LinkedHashMap<>();

        m.put("en", new TtsSpec(
                "csukuangfj/vits-piper-en_US-ryan-medium",
                "en_US-ryan-medium.onnx", "tokens.txt", "espeak-ng-data"));
        m.put("fa", new TtsSpec(
                "csukuangfj/vits-piper-fa_IR-gyro-medium",
                "fa_IR-gyro-medium.onnx", "tokens.txt", "espeak-ng-data"));
        m.put("ar", new TtsSpec(
                "csukuangfj/vits-piper-ar_JO-kareem-medium",
                "ar_JO-kareem-medium.onnx", "tokens.txt", "espeak-ng-data"));
        m.put("tr", new TtsSpec(
                "csukuangfj/vits-piper-tr_TR-fahrettin-medium",
                "tr_TR-fahrettin-medium.onnx", "tokens.txt", "espeak-ng-data"));
        m.put("de", new TtsSpec(
                "csukuangfj/vits-piper-de_DE-thorsten_emotional-medium",
                "de_DE-thorsten_emotional-medium.onnx", "tokens.txt", "espeak-ng-data"));
        m.put("fr", new TtsSpec(
                "csukuangfj/vits-piper-fr_FR-miro-high",
                "fr_FR-miro-high.onnx", "tokens.txt", "espeak-ng-data"));
        m.put("es", new TtsSpec(
                "csukuangfj/vits-piper-es_ES-miro-high",
                "es_ES-miro-high.onnx", "tokens.txt", "espeak-ng-data"));
        m.put("it", new TtsSpec(
                "csukuangfj/vits-piper-it_IT-miro-high",
                "it_IT-miro-high.onnx", "tokens.txt", "espeak-ng-data"));
        m.put("ru", new TtsSpec(
                "csukuangfj/vits-piper-ru_RU-irina-medium",
                "ru_RU-irina-medium.onnx", "tokens.txt", "espeak-ng-data"));
        m.put("zh", new TtsSpec(
                "csukuangfj/vits-piper-zh_CN-huayan-medium",
                "zh_CN-huayan-medium.onnx", "tokens.txt", "espeak-ng-data"));
        m.put("hi", new TtsSpec(
                "csukuangfj/vits-piper-hi_IN-rohan-medium",
                "hi_IN-rohan-medium.onnx", "tokens.txt", "espeak-ng-data"));
        // he (عبری), ja (ژاپنی), ko (کره‌ای): بسته Piper رسمی ندارن؛
        // اگه پیدا کردی همینجا اضافه کن.

        TTS_SPECS = Collections.unmodifiableMap(m);
    }

    // ============ چند صدا برای هر زبان ============
    // هر زبان یک صدای پیش‌فرض (همان TTS_SPECS) + چند صدای اضافه‌ی Piper (تک‌گوینده) دارد.
    // کاربر از تنظیمات هر کدام را دانلود/انتخاب می‌کند. شناسه‌ی صدا = نام Piper (مثلاً en_US-amy-medium).
    // صدای پیش‌فرض همان پوشه‌ی قدیمی tts/<lang> را نگه می‌دارد (بسته‌های قبلاً دانلودشده سالم می‌مانند)؛
    // بقیه در tts/<lang>__<id> ذخیره می‌شوند و صدای فعال در فایل tts/<lang>.active ثبت می‌شود
    // (فایل، چون TtsService در پردازه‌ی جدا اجرا می‌شود و SharedPreferences بین پردازه‌ها مطمئن نیست).
    static final class TtsVoice {
        final String id;
        final String label;
        final TtsSpec spec;
        final boolean isDefault;
        TtsVoice(String id, String label, TtsSpec spec, boolean isDefault) {
            this.id = id; this.label = label; this.spec = spec; this.isDefault = isDefault;
        }
    }

    private static final Map<String, List<TtsVoice>> TTS_VOICES;
    static {
        Map<String, List<TtsVoice>> vm = new LinkedHashMap<>();
        for (Map.Entry<String, TtsSpec> e : TTS_SPECS.entrySet()) {
            List<TtsVoice> list = new ArrayList<>();
            String pid = piperIdOf(e.getValue());
            list.add(new TtsVoice(pid, voiceLabel(pid), e.getValue(), true));
            vm.put(e.getKey(), list);
        }
        String[][] extra = {
            {"en", "en_US-amy-medium", "en_US-amy-low", "en_US-lessac-high", "en_US-lessac-medium",
                    "en_US-lessac-low", "en_US-hfc_female-medium", "en_US-hfc_male-medium",
                    "en_US-joe-medium", "en_US-john-medium", "en_US-kristin-medium", "en_US-norman-medium",
                    "en_US-ryan-high", "en_US-ryan-low", "en_US-danny-low", "en_US-kathleen-low",
                    "en_US-ljspeech-high", "en_US-ljspeech-medium",
                    "en_GB-alba-medium", "en_GB-alan-medium", "en_GB-alan-low", "en_GB-jenny_dioco-medium",
                    "en_GB-northern_english_male-medium", "en_GB-southern_english_female-low", "en_GB-cori-high",
                    "en_GB-cori-medium"},
            {"de", "de_DE-thorsten-high", "de_DE-thorsten-medium", "de_DE-thorsten-low", "de_DE-eva_k-x_low",
                    "de_DE-ramona-low", "de_DE-kerstin-low", "de_DE-karlsson-low", "de_DE-pavoque-low"},
            {"fr", "fr_FR-siwis-medium", "fr_FR-siwis-low", "fr_FR-tom-medium", "fr_FR-gilles-low"},
            {"es", "es_ES-davefx-medium", "es_ES-carlfm-x_low", "es_MX-ald-medium", "es_MX-claude-high",
                    "es_AR-daniela-high"},
            {"it", "it_IT-paola-medium", "it_IT-riccardo-x_low"},
            {"ru", "ru_RU-denis-medium", "ru_RU-dmitri-medium", "ru_RU-ruslan-medium"},
            {"tr", "tr_TR-dfki-medium", "tr_TR-fettah-medium"},
            {"ar", "ar_JO-kareem-low"},
            {"fa", "fa_IR-amir-medium", "fa_IR-ganji-medium", "fa_IR-ganji_adabi-medium",
                    "fa_IR-reza_ibrahim-medium"},
            {"hi", "hi_IN-pratham-medium", "hi_IN-priyamvada-medium"},
            {"zh", "zh_CN-xiao_ya-medium", "zh_CN-chaowen-medium", "zh_CN-huayan-x_low"},
        };
        for (String[] row : extra) {
            List<TtsVoice> list = vm.get(row[0]);
            if (list == null) continue;
            for (int i = 1; i < row.length; i++) {
                final String pid = row[i];
                boolean dup = false;
                for (TtsVoice v : list) if (v.id.equals(pid)) { dup = true; break; }
                if (dup) continue;
                list.add(new TtsVoice(pid, voiceLabel(pid), new TtsSpec(
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

    private static File ttsDirFor(Context ctx, String l, TtsVoice v) {
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
        File dir = ttsDirFor(ctx, l, v);
        File model = new File(dir, "model.onnx");
        File tokens = new File(dir, "tokens.txt");
        if (!model.isFile() || model.length() == 0) return false;
        if (!tokens.isFile() || tokens.length() == 0) return false;
        return isEspeakReady(ctx);
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

    static File getTtsModelDir(Context ctx, String lang) {
        String l = normalize(lang);
        TtsSpec s = l == null ? null : TTS_SPECS.get(l);
        if (s == null) return null;
        TtsVoice v = activeVoice(ctx, l);
        if (voiceFilesReady(ctx, l, v)) return ttsDirFor(ctx, l, v);
        // صدای انتخاب‌شده سالم نیست (مثلاً ناقص/حذف‌شده) → به صدای پیش‌فرض برگرد تا خوانش قطع نشود
        List<TtsVoice> all = TTS_VOICES.get(l);
        if (all != null && !all.isEmpty() && all.get(0) != v && voiceFilesReady(ctx, l, all.get(0))) {
            return ttsDirFor(ctx, l, all.get(0));
        }
        return null;
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
                    // دانلودِ کامل شد → همین صدا صدای فعالِ زبان می‌شود
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
        if (!dir.isDirectory() && !dir.mkdirs()) throw new java.io.IOException("cannot create " + dir);

        // ۱. tokens.txt (کوچیکه)
        checkCancel(l);
        File tokensTarget = new File(dir, "tokens.txt");
        if (!tokensTarget.isFile() || tokensTarget.length() == 0) {
            downloadFile(HF_BASE + s.repo + "/resolve/main/" + s.tokensFile, tokensTarget, cb, l);
        }

        // ۲. model.onnx (بزرگ‌ترین فایل؛ از همین‌جا پیشرفت دیده می‌شه و از نقطه‌ی توقف ادامه پیدا می‌کنه)
        checkCancel(l);
        File modelTarget = new File(dir, "model.onnx");
        if (!modelTarget.isFile() || modelTarget.length() == 0) {
            downloadFile(HF_BASE + s.repo + "/resolve/main/" + s.modelFile, modelTarget, cb, l);
        }

        // ۳. espeak-ng-data مشترک (فقط یک بار؛ زبان‌های دیگه همین‌جا صبر می‌کنن، ولی با امکانِ توقف)
        if (!isEspeakReady(app)) {
            while (!ESPEAK_LOCK.tryLock(500, TimeUnit.MILLISECONDS)) {
                checkCancel(l);
                if (isEspeakReady(app)) break;
            }
            if (ESPEAK_LOCK.isHeldByCurrentThread()) {
                try {
                    if (!isEspeakReady(app)) downloadEspeakData(app, s.repo, cb, l);
                } finally {
                    ESPEAK_LOCK.unlock();
                }
            }
        }
    }

    /**
     * پوشه‌ی espeak-ng-data رو از HuggingFace (لیستِ فایل‌ها با API) دانلود می‌کنه.
     * فقط وقتی کامل شد فایلِ marker ساخته می‌شه.
     */
    private static void downloadEspeakData(Context app, String repo, ProgressCallback cb, String l) throws Exception {
        final String prefix = "espeak-ng-data/";
        File root = getEspeakDataDir(app);
        if (!root.isDirectory() && !root.mkdirs()) throw new java.io.IOException("cannot create " + root);

        // لیست فایل‌ها (با صفحه‌بندی)
        List<String> paths = new ArrayList<>();
        List<Long> sizes = new ArrayList<>();
        String next = HF_BASE + "api/models/" + repo + "/tree/main/espeak-ng-data?recursive=true";
        int guard = 0;
        while (next != null && guard++ < 20) {
            checkCancel(l);
            Request req = new Request.Builder().url(next).build();
            try (Response r = HTTP.newCall(req).execute()) {
                if (!r.isSuccessful() || r.body() == null) {
                    throw new java.io.IOException("HTTP " + r.code() + " listing espeak-ng-data");
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
        if (paths.isEmpty()) throw new java.io.IOException("espeak-ng-data list is empty");

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
        File marker = espeakMarker(app);
        if (!marker.exists() && !marker.createNewFile()) throw new java.io.IOException("cannot create marker");
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
        deleteRecursive(ttsDirFor(ctx, l, v));
        if (active != null && active.id.equals(v.id) && !v.isDefault) setActiveVoice(ctx, l, null);
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
