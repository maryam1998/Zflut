package com.linglearn.app.overlay;

import android.content.Context;
import android.util.Log;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;

/**
 * تبدیل متن فارسی → دنباله‌ی نمادهای مدل Mana، بدون espeak-ng.
 *
 * مسیر کار:
 *   متن → PersianNormalizer → بخش‌بندی با علائم نگارشی → G2P
 *        (۱) مدل Homo-GE2PE (ONNX، دانلودی)  ← اگر آماده بود
 *        (۲) قواعد ساده‌ی داخلی               ← اگر مدل نبود/خطا داد/تعداد کلمات نخواند
 *   → نمادهای GE2PE به IPA → فقط نمادهایی که در tokens.txt ی Mana هست → «^ _ p _ p _ … $»
 *   رشته‌ی نهایی به Sherpa داده می‌شود (frontend=characters: هر کاراکتر = یک token).
 */
final class PersianG2P {
    private static final String TAG = "PersianG2P";

    // ======================= تنظیمات (اگر آدرس/نام فایل‌ها فرق داشت فقط همین‌جا را عوض کن) =======================
    private static final String G2P_BASE = "https://huggingface.co/MahtaFetrat/Homo-GE2PE-Persian/resolve/main/";
    /** {نام محلی, مسیر داخل مخزن} */
    private static final String[][] G2P_FILES = {
            {"encoder_model.onnx", "onnx/encoder_model.onnx"},
            {"decoder_model.onnx", "onnx/decoder_model.onnx"},
    };
    /** اگر مدل ورودی را با پیشوند خاصی می‌خواهد اینجا بگذار. */
    private static final String INPUT_PREFIX = "";
    private static final int MAX_NEW_TOKENS_FACTOR = 4;

    // تنظیم Piper: ^ شروع، $ پایان، _ پد بین نمادها
    private static final String BOS = "^", EOS = "$", PAD = "_";

    private PersianG2P() {}

    // ======================= وضعیت =======================
    private static volatile File g2pDir = null;
    private static volatile Set<Integer> tokenSet = new HashSet<>();
    private static final Object LOAD_LOCK = new Object();
    private static Object ort = null;     // Ge2pe
    private static boolean ortTried = false;
    private static final Set<String> WARNED = new HashSet<>();
    private static final Map<String, List<String>> CACHE = new LinkedHashMap<String, List<String>>(64, 0.75f, true) {
        @Override protected boolean removeEldestEntry(Map.Entry<String, List<String>> e) { return size() > 256; }
    };

    /** TtsEngine.create() صدا می‌زند. */
    static void configure(Context ctx, File tokensFile) {
        g2pDir = new File(new File(ctx.getApplicationContext().getFilesDir(), "tts"), "fa-g2p");
        Set<Integer> set = new HashSet<>();
        try {
            String all = readText(tokensFile);
            for (String line : all.split("\n")) {
                if (line.isEmpty()) continue;
                int sp = line.lastIndexOf(' ');
                if (sp < 0) continue;
                String sym = line.substring(0, sp);
                if (sym.codePointCount(0, sym.length()) == 1) set.add(sym.codePointAt(0));
            }
        } catch (Throwable e) {
            Log.e(TAG, "cannot read tokens", e);
        }
        tokenSet = set;
        Log.i(TAG, "tokens loaded: " + set.size() + " (g2p model ready=" + isModelReady(ctx) + ")");
    }

    // ======================= دانلود مدل G2P =======================
    static boolean isModelReady(Context ctx) {
        File d = new File(new File(ctx.getApplicationContext().getFilesDir(), "tts"), "fa-g2p");
        for (String[] f : G2P_FILES) {
            File x = new File(d, f[0]);
            if (!x.isFile() || x.length() < 100_000L) return false;
        }
        return new File(d, "ready.ok").isFile();
    }

    /** دانلودِ مدل (غیرِ بلاک‌کننده برای صدا: اگر شکست خورد قواعد داخلی کار را ادامه می‌دهند). */
    static void downloadModel(Context ctx, SherpaModelManager.ProgressCallback cb, String lang) throws Exception {
        if (isModelReady(ctx)) return;
        File d = new File(new File(ctx.getApplicationContext().getFilesDir(), "tts"), "fa-g2p");
        if (!d.isDirectory() && !d.mkdirs()) throw new java.io.IOException("cannot create " + d);
        new File(d, "ready.ok").delete();
        OkHttpClient http = new OkHttpClient();
        for (String[] f : G2P_FILES) {
            File target = new File(d, f[0]);
            if (target.isFile() && target.length() >= 100_000L) continue;
            File part = new File(d, f[0] + ".part");
            Request req = new Request.Builder().url(G2P_BASE + f[1]).build();
            try (Response r = http.newCall(req).execute()) {
                if (!r.isSuccessful() || r.body() == null) throw new java.io.IOException("HTTP " + r.code() + " " + f[1]);
                String ct = r.header("Content-Type");
                if (ct != null && ct.toLowerCase().startsWith("text/html")) throw new java.io.IOException("HTML instead of " + f[1]);
                long total = r.body().contentLength(), done = 0;
                try (InputStream in = r.body().byteStream(); OutputStream out = new FileOutputStream(part, false)) {
                    byte[] buf = new byte[64 * 1024];
                    int n;
                    while ((n = in.read(buf)) > 0) {
                        out.write(buf, 0, n);
                        done += n;
                        if (cb != null) cb.onProgress(lang, done, total);
                    }
                }
                if (total > 0 && part.length() != total) { part.delete(); throw new java.io.IOException("incomplete " + f[1]); }
            }
            if (target.exists()) target.delete();
            if (!part.renameTo(target)) throw new java.io.IOException("rename failed " + f[0]);
        }
        if (!new File(d, "ready.ok").createNewFile()) throw new java.io.IOException("cannot create ready.ok");
    }

    // ======================= API اصلی =======================
    /** متنِ فارسی (هر چیزی) → رشته‌ای که مستقیم به Sherpa داده می‌شود. */
    static String toModelInput(String text) {
        String norm = PersianNormalizer.normalize(text);
        if (norm.isEmpty()) return "";
        StringBuilder ipa = new StringBuilder();
        Matcher m = Pattern.compile("[^,.;:!?]+|[,.;:!?]").matcher(norm);
        while (m.find()) {
            String seg = m.group().trim();
            if (seg.isEmpty()) continue;
            if (seg.length() == 1 && ",.;:!?".indexOf(seg.charAt(0)) >= 0) {
                if (ipa.length() > 0 && ipa.charAt(ipa.length() - 1) == ' ') ipa.setLength(ipa.length() - 1);
                ipa.append(seg).append(' ');
                continue;
            }
            for (String w : phonemizeSegment(seg)) {
                if (w.isEmpty()) continue;
                ipa.append(w).append(' ');
            }
        }
        return build(ipa.toString().trim());
    }

    /** IPA (با فاصله بین کلمات) → «^ _ p _ p … $» فقط با نمادهای موجود در tokens.txt. */
    private static String build(String ipa) {
        Set<Integer> ts = tokenSet;
        boolean pad = ts.contains((int) PAD.charAt(0));
        StringBuilder sb = new StringBuilder();
        if (ts.contains((int) BOS.charAt(0))) sb.append(BOS);
        for (int i = 0; i < ipa.length(); ) {
            int cp = ipa.codePointAt(i);
            i += Character.charCount(cp);
            int use = pick(cp, ts);
            if (use < 0) continue;
            sb.appendCodePoint(use);
            if (pad) sb.append(PAD);
        }
        if (ts.contains((int) EOS.charAt(0))) sb.append(EOS);
        return sb.toString();
    }

    private static final Map<Integer, int[]> SUBS = new HashMap<>();
    static {
        SUBS.put((int) '\u0261', new int[]{'g'});                 // ɡ
        SUBS.put((int) 'g', new int[]{0x0261});
        SUBS.put((int) '\u027E', new int[]{'r'});                 // ɾ
        SUBS.put((int) '\u0262', new int[]{0x0263, 'q', 0x0261, 'g'}); // ɢ
        SUBS.put((int) '\u0263', new int[]{0x0262, 'q', 0x0261});  // ɣ
        SUBS.put((int) 'q', new int[]{0x0262, 0x0263});
        SUBS.put((int) '\u00E6', new int[]{'a', 0x025B});          // æ
        SUBS.put((int) '\u0251', new int[]{'a', 0x0252});          // ɑ
        SUBS.put((int) '\u0252', new int[]{0x0251, 'a'});          // ɒ
        SUBS.put((int) '\u0292', new int[]{0x0283});               // ʒ
        SUBS.put((int) 'x', new int[]{'h', 'k'});
        SUBS.put((int) '\u0294', new int[]{});                     // ʔ  (اگر نبود حذف)
        SUBS.put((int) '\u02D0', new int[]{});                     // ː  (اگر نبود حذف)
    }

    private static int pick(int cp, Set<Integer> ts) {
        if (ts.contains(cp)) return cp;
        int[] alt = SUBS.get(cp);
        if (alt != null) for (int a : alt) if (ts.contains(a)) return a;
        if (cp != ' ') warnOnce("no token for U+" + Integer.toHexString(cp).toUpperCase() + " '" + new String(Character.toChars(cp)) + "'");
        return -1;
    }

    private static void warnOnce(String s) {
        synchronized (WARNED) { if (WARNED.add(s)) Log.w(TAG, s); }
    }

    // ======================= یک بخش (بین دو علامت نگارشی) =======================
    private static List<String> phonemizeSegment(String seg) {
        synchronized (CACHE) { List<String> c = CACHE.get(seg); if (c != null) return c; }
        String[] words = seg.split(" +");
        List<String> out = null;
        Ge2pe g = loadModel();
        if (g != null) {
            try {
                String raw = g.run(INPUT_PREFIX + seg);
                String[] ph = raw.trim().split("\\s+");
                if (ph.length == words.length) {
                    out = new ArrayList<>();
                    for (String p : ph) out.add(ge2peToIpa(p));
                } else {
                    warnOnce("g2p word count mismatch: in=" + words.length + " out=" + ph.length + " seg=" + seg + " raw=" + raw);
                }
            } catch (Throwable e) {
                Log.w(TAG, "g2p model failed, using rules", e);
            }
        }
        if (out == null) {
            out = new ArrayList<>();
            for (String w : words) out.add(ruleWord(w));
        }
        synchronized (CACHE) { CACHE.put(seg, out); }
        return out;
    }

    // ======================= جدول تبدیل نمادهای Homo-GE2PE → IPA (حدسی؛ با لاگ اصلاح می‌شود) =======================
    // نتیجه IPA به سبک espeak-ng فارسی است؛ مرحله‌ی pick() بعداً با tokens.txt ی Mana تطبیقش می‌دهد.
    private static final Map<Character, String> GE2PE = new HashMap<>();
    static {
        // واکه‌ها
        GE2PE.put('a', "\u00E6");          // æ  (زبر)
        GE2PE.put('A', "\u0251\u02D0");    // ɑː (الف)
        GE2PE.put('e', "e");               // زیر
        GE2PE.put('i', "i\u02D0");         // iː
        GE2PE.put('o', "o");               // پیش
        GE2PE.put('u', "u\u02D0");         // uː
        // همخوان‌ها
        GE2PE.put('b', "b");  GE2PE.put('p', "p");  GE2PE.put('t', "t");  GE2PE.put('d', "d");
        GE2PE.put('k', "k");  GE2PE.put('g', "\u0261");  GE2PE.put('f', "f");  GE2PE.put('v', "v");
        GE2PE.put('s', "s");  GE2PE.put('z', "z");  GE2PE.put('x', "x");  GE2PE.put('h', "h");
        GE2PE.put('m', "m");  GE2PE.put('n', "n");  GE2PE.put('l', "l");
        GE2PE.put('r', "\u027E");          // ɾ
        GE2PE.put('y', "j");
        GE2PE.put('S', "\u0283");          // ʃ
        GE2PE.put('Z', "\u0292");          // ʒ
        GE2PE.put('C', "t\u0283");         // tʃ
        GE2PE.put('J', "d\u0292");         // dʒ
        GE2PE.put('q', "\u0262");          // ɢ  (ق/غ)
        GE2PE.put('G', "\u0262");
        GE2PE.put('?', "\u0294");          // ʔ  همزه/عین
        GE2PE.put('\'', "\u0294");
        // نمادهای خاص (حدسی — اگر تلفظ اشتباه بود لاگ بفرست)
        GE2PE.put('@', "\u0294");          // ʔ
        GE2PE.put('/', "");                // مرز/نشانه‌ی ساختاری → نادیده
        GE2PE.put('$', "");                // نادیده
        GE2PE.put('-', "");
        GE2PE.put('_', "");
        GE2PE.put(' ', " ");
    }

    static String ge2peToIpa(String p) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < p.length(); i++) {
            char c = p.charAt(i);
            String m = GE2PE.get(c);
            if (m != null) sb.append(m);
            else if (c > 127) sb.append(c);              // خودش IPA بود
            else warnOnce("unmapped GE2PE symbol '" + c + "' in " + p);
        }
        return sb.toString();
    }

    // ======================= قواعد ساده (پشتیبان) =======================
    private static final Map<Character, String> CONS = new HashMap<>();
    static {
        String[][] t = {
                {"ب", "b"}, {"پ", "p"}, {"ت", "t"}, {"ث", "s"}, {"ج", "d\u0292"}, {"چ", "t\u0283"},
                {"ح", "h"}, {"خ", "x"}, {"د", "d"}, {"ذ", "z"}, {"ر", "\u027E"}, {"ز", "z"},
                {"ژ", "\u0292"}, {"س", "s"}, {"ش", "\u0283"}, {"ص", "s"}, {"ض", "z"}, {"ط", "t"},
                {"ظ", "z"}, {"ع", "\u0294"}, {"غ", "\u0262"}, {"ف", "f"}, {"ق", "\u0262"},
                {"ک", "k"}, {"گ", "\u0261"}, {"ل", "l"}, {"م", "m"}, {"ن", "n"}, {"ه", "h"},
                {"ء", "\u0294"}, {"ئ", "\u0294"}, {"ؤ", "\u0294"},
        };
        for (String[] e : t) CONS.put(e[0].charAt(0), e[1]);
    }

    private static boolean isVowelLetter(char c) { return c == 'ا' || c == 'آ' || c == 'و' || c == 'ی'; }
    private static boolean isCons(char c) { return CONS.containsKey(c); }

    static String ruleWord(String w) {
        StringBuilder out = new StringBuilder();
        for (String part : w.split(String.valueOf(PersianNormalizer.ZWNJ))) {
            if (!part.isEmpty()) out.append(rulePart(part));
        }
        return out.toString();
    }

    private static String rulePart(String w) {
        char[] c = w.toCharArray();
        int n = c.length;
        StringBuilder o = new StringBuilder();
        int vowels = 0;
        for (int i = 0; i < n; i++) {
            char ch = c[i];
            char nx = i + 1 < n ? c[i + 1] : 0;
            char pv = i > 0 ? c[i - 1] : 0;
            if (ch == 'آ') { o.append(i == 0 ? "\u0294\u0251\u02D0" : "\u0251\u02D0"); vowels++; }
            else if (ch == 'ا') {
                if (i == 0) {
                    if (nx == 'ی') { o.append("\u0294i\u02D0"); i++; vowels++; }
                    else if (nx == 'و') { o.append("\u0294u\u02D0"); i++; vowels++; }
                    else { o.append("\u0294e"); vowels++; }
                } else { o.append("\u0251\u02D0"); vowels++; }
            } else if (ch == 'و') {
                if (i == 0 || nx == 'ا' || nx == 'ی' || nx == 'آ') o.append('v');
                else if (isCons(pv) && (i == n - 1 || isCons(nx))) { o.append("u\u02D0"); vowels++; }
                else o.append('v');
            } else if (ch == 'ی') {
                if (i == 0 || pv == 'ا' || pv == 'آ' || pv == 'و' || nx == 'ا' || nx == 'آ') o.append('j');
                else { o.append("i\u02D0"); vowels++; }
            } else if (ch == 'ه') {
                if (i == n - 1 && isCons(pv)) { o.append('e'); vowels++; }
                else o.append('h');
            } else if (isCons(ch)) {
                o.append(CONS.get(ch));
                // بین دو همخوان (و نه در پایان) واکه‌ی ناپیدا اضافه کن
                if (isCons(nx) && i + 2 < n) {
                    o.append(vowels == 0 ? (i == 0 ? "e" : "\u00E6") : "e");
                    vowels++;
                }
            }
        }
        return o.toString();
    }

    // ======================= اجرای مدل ONNX (ByT5-مانند) =======================
    private static Ge2pe loadModel() {
        synchronized (LOAD_LOCK) {
            if (ort != null) return (Ge2pe) ort;
            if (ortTried) return null;
            File d = g2pDir;
            if (d == null || !new File(d, "ready.ok").isFile()) return null;   // هنوز دانلود نشده؛ دفعه‌ی بعد دوباره بررسی می‌شود
            ortTried = true;
            try {
                Ge2pe g = new Ge2pe(new File(d, G2P_FILES[0][0]), new File(d, G2P_FILES[1][0]));
                ort = g;
                Log.i(TAG, "GE2PE ONNX model loaded");
                return g;
            } catch (Throwable e) {
                Log.e(TAG, "cannot load GE2PE model → rule-based fallback", e);
                return null;
            }
        }
    }

    /** Encoder-decoder بایت‌محور (ByT5): شناسه = بایت UTF-8 + 3؛ 0=pad، 1=eos. حریصانه (greedy) بدون KV-cache. */
    private static final class Ge2pe {
        private final ai.onnxruntime.OrtEnvironment env;
        private final ai.onnxruntime.OrtSession enc, dec;

        Ge2pe(File encFile, File decFile) throws Exception {
            env = ai.onnxruntime.OrtEnvironment.getEnvironment();
            ai.onnxruntime.OrtSession.SessionOptions so = new ai.onnxruntime.OrtSession.SessionOptions();
            so.setIntraOpNumThreads(2);
            enc = env.createSession(encFile.getAbsolutePath(), so);
            dec = env.createSession(decFile.getAbsolutePath(), so);
        }

        synchronized String run(String text) throws Exception {
            byte[] b = text.getBytes(StandardCharsets.UTF_8);
            long[][] ids = new long[1][b.length + 1];
            long[][] mask = new long[1][b.length + 1];
            for (int i = 0; i < b.length; i++) { ids[0][i] = (b[i] & 0xff) + 3; mask[0][i] = 1; }
            ids[0][b.length] = 1; mask[0][b.length] = 1;

            try (ai.onnxruntime.OnnxTensor tIds = ai.onnxruntime.OnnxTensor.createTensor(env, ids);
                 ai.onnxruntime.OnnxTensor tMask = ai.onnxruntime.OnnxTensor.createTensor(env, mask)) {
                Map<String, ai.onnxruntime.OnnxTensor> ei = new HashMap<>();
                for (String name : enc.getInputNames()) {
                    if (name.contains("mask")) ei.put(name, tMask); else ei.put(name, tIds);
                }
                try (ai.onnxruntime.OrtSession.Result er = enc.run(ei)) {
                    ai.onnxruntime.OnnxTensor hidden = (ai.onnxruntime.OnnxTensor) er.get(0);
                    int maxNew = Math.min(512, b.length * MAX_NEW_TOKENS_FACTOR + 8);
                    long[] gen = new long[maxNew + 1];
                    gen[0] = 0;
                    int len = 1;
                    java.io.ByteArrayOutputStream bo = new java.io.ByteArrayOutputStream();
                    for (int step = 0; step < maxNew; step++) {
                        long[][] dIds = new long[1][len];
                        System.arraycopy(gen, 0, dIds[0], 0, len);
                        try (ai.onnxruntime.OnnxTensor tDec = ai.onnxruntime.OnnxTensor.createTensor(env, dIds)) {
                            Map<String, ai.onnxruntime.OnnxTensor> di = new HashMap<>();
                            for (String name : dec.getInputNames()) {
                                if (name.contains("encoder_hidden")) di.put(name, hidden);
                                else if (name.contains("mask")) di.put(name, tMask);
                                else di.put(name, tDec);
                            }
                            try (ai.onnxruntime.OrtSession.Result dr = dec.run(di)) {
                                float[][][] logits = (float[][][]) ((ai.onnxruntime.OnnxTensor) dr.get(0)).getValue();
                                float[] last = logits[0][len - 1];
                                int best = 0;
                                for (int k = 1; k < last.length; k++) if (last[k] > last[best]) best = k;
                                if (best == 1) break;                  // eos
                                gen[len++] = best;
                                if (best >= 3 && best - 3 < 256) bo.write(best - 3);
                            }
                        }
                    }
                    return new String(bo.toByteArray(), StandardCharsets.UTF_8);
                }
            }
        }
    }

    private static String readText(File f) throws Exception {
        try (java.io.FileInputStream in = new java.io.FileInputStream(f)) {
            java.io.ByteArrayOutputStream bo = new java.io.ByteArrayOutputStream();
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) > 0) bo.write(buf, 0, n);
            return bo.toString("UTF-8");
        }
    }
}
