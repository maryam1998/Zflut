package com.linglearn.app.overlay;

import android.content.Context;
import android.os.Bundle;
import android.speech.tts.TextToSpeech;
import android.speech.tts.UtteranceProgressListener;
import android.util.Log;

import java.util.Locale;
import java.util.concurrent.ConcurrentHashMap;

/**
 * TTS خودِ گوشی (android.speech.tts.TextToSpeech).
 * داخل WebView، speechSynthesis معمولاً صدایی نداره؛ این کلاس مستقیم از موتور سیستم می‌خونه.
 */
final class SystemTts {

    interface Done { void onDone(boolean ok); }

    private static final String TAG = "SystemTts";

    private final Context app;
    private TextToSpeech tts;
    private volatile boolean ready = false;
    private volatile boolean initFailed = false;
    private final Object lock = new Object();
    private final ConcurrentHashMap<String, Done> callbacks = new ConcurrentHashMap<>();

    // ⚡ کش: زبان/صدا/سرعتی که آخرین‌بار روی موتور ست شد. قبلاً با هر جمله setLanguage +
    // getVoice/getVoices (چند ده تا چند صد میلی‌ثانیه) تکرار می‌شد؛ حالا فقط وقتی زبان عوض شود.
    private String curLangKey = null;
    private float curRate = -1f;
    private final java.util.HashMap<String, android.speech.tts.Voice> bestVoice = new java.util.HashMap<>();

    SystemTts(Context ctx) {
        this.app = ctx.getApplicationContext();
    }

    private void ensureInit() {
        synchronized (lock) {
            if (tts != null || initFailed) return;
            try {
                tts = new TextToSpeech(app, status -> {
                    synchronized (lock) {
                        if (status == TextToSpeech.SUCCESS) {
                            ready = true;
                        } else {
                            initFailed = true;
                        }
                        lock.notifyAll();
                    }
                });
                tts.setOnUtteranceProgressListener(new UtteranceProgressListener() {
                    @Override public void onStart(String id) {}
                    @Override public void onDone(String id) { finish(id, true); }
                    @Override public void onError(String id) { finish(id, false); }
                    @Override public void onError(String id, int code) { finish(id, false); }
                    @Override public void onStop(String id, boolean interrupted) { finish(id, true); }
                });
            } catch (Throwable t) {
                Log.w(TAG, "init failed", t);
                initFailed = true;
                tts = null;
            }
        }
    }

    private void finish(String id, boolean ok) {
        Done d = id == null ? null : callbacks.remove(id);
        if (d != null) d.onDone(ok);
    }

    /** منتظر آماده‌شدنِ موتور می‌مونه (حداکثر چند ثانیه). باید روی نخِ پس‌زمینه صدا زده بشه. */
    private boolean awaitReady() {
        // اگر دفعه‌ی قبل راه‌اندازیِ موتور شکست خورد (مثلاً سرویسِ TTS هنوز بالا
        // نیامده بود)، برای همیشه قفل نماند؛ این بار دوباره امتحان کن.
        if (initFailed) release();
        ensureInit();
        long end = System.currentTimeMillis() + 6000;
        synchronized (lock) {
            while (!ready && !initFailed && System.currentTimeMillis() < end) {
                try { lock.wait(200); } catch (InterruptedException e) { return false; }
            }
        }
        return ready && tts != null;
    }

    private static Locale localeFor(String lang) {
        String l = SherpaModelManager.normalize(lang);
        if (l == null) return Locale.ENGLISH;
        switch (l) {
            case "en": return Locale.US;
            case "zh": return Locale.SIMPLIFIED_CHINESE;
            default: return new Locale(l);
        }
    }

    /** آیا این زبان رو موتورِ گوشی می‌خونه؟ */
    boolean isLanguageAvailable(String lang) {
        if (!awaitReady()) return false;
        try {
            int r = tts.isLanguageAvailable(localeFor(lang));
            return r >= TextToSpeech.LANG_AVAILABLE;
        } catch (Throwable t) {
            return false;
        }
    }

    private static final float BASE_RATE = 0.92f;

    /**
     * بهترین صدای «آفلاین» برای این زبان را انتخاب می‌کند. صداهای شبکه‌ای (که بدونِ اینترنتِ خوب
     * چند ثانیه معطل می‌کنند و کیفیتِ دماغی/رباتی دارند) فقط وقتی انتخاب می‌شوند که آفلاین نباشد.
     * اگه صدای پیش‌فرضِ کاربر همین زبان و آفلاین است، دست نمی‌زنیم.
     */
    private void pickBestVoice(Locale loc) {
        try {
            android.speech.tts.Voice cur = tts.getVoice();
            if (cur != null && cur.getLocale() != null
                    && cur.getLocale().getLanguage().equalsIgnoreCase(loc.getLanguage())
                    && !cur.isNetworkConnectionRequired()) {
                bestVoice.put(loc.toLanguageTag(), cur);
                return;
            }
            java.util.Set<android.speech.tts.Voice> all = tts.getVoices();
            if (all == null) return;
            android.speech.tts.Voice best = null;
            int bestScore = Integer.MIN_VALUE;
            for (android.speech.tts.Voice v : all) {
                Locale vl = v.getLocale();
                if (vl == null || !vl.getLanguage().equalsIgnoreCase(loc.getLanguage())) continue;
                java.util.Set<String> f = v.getFeatures();
                if (f != null && f.contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED)) continue;
                int score = v.getQuality() - v.getLatency() / 10;
                if (!v.isNetworkConnectionRequired()) score += 2000;
                if (loc.getCountry() != null && loc.getCountry().length() > 0
                        && loc.getCountry().equalsIgnoreCase(vl.getCountry())) score += 150;
                if (score > bestScore) { bestScore = score; best = v; }
            }
            if (best != null) {
                tts.setVoice(best);
                bestVoice.put(loc.toLanguageTag(), best);
            }
        } catch (Throwable t) {
            Log.w(TAG, "pickBestVoice failed", t);
        }
    }

    /**
     * 🎭 صدای مرد/زن: صداهای گوگل در اسمشان «male»/«female» دارند (مثلاً en-us-x-sfg#male_1-local).
     * بهترین صدای آفلاینِ همان جنسیت برای این زبان را می‌گذارد؛ true = پیدا شد.
     */
    private boolean pickGenderVoice(Locale loc, String gender, String key) {
        try {
            java.util.Set<android.speech.tts.Voice> all = tts.getVoices();
            if (all == null) return false;
            android.speech.tts.Voice best = null;
            int bestScore = Integer.MIN_VALUE;
            for (android.speech.tts.Voice v : all) {
                Locale vl = v.getLocale();
                if (vl == null || !vl.getLanguage().equalsIgnoreCase(loc.getLanguage())) continue;
                java.util.Set<String> f = v.getFeatures();
                if (f != null && f.contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED)) continue;
                String n = v.getName() == null ? "" : v.getName().toLowerCase(Locale.ROOT);
                boolean female = n.contains("female") || n.contains("#f_") || n.contains("-f-");
                boolean male = !female && (n.contains("male") || n.contains("#m_") || n.contains("-m-"));
                if (gender.equals("male") ? !male : !female) continue;
                int score = v.getQuality() - v.getLatency() / 10;
                if (!v.isNetworkConnectionRequired()) score += 2000;
                if (loc.getCountry() != null && loc.getCountry().length() > 0
                        && loc.getCountry().equalsIgnoreCase(vl.getCountry())) score += 150;
                if (score > bestScore) { bestScore = score; best = v; }
            }
            if (best == null) return false;
            if (tts.setVoice(best) != TextToSpeech.SUCCESS) return false;
            bestVoice.put(key, best);
            return true;
        } catch (Throwable t) {
            Log.w(TAG, "pickGenderVoice failed", t);
            return false;
        }
    }

    void speak(String text, String lang, float speed, String id, Done cb) {
        speak(text, lang, speed, id, null, cb);
    }

    /** gender: "male" / "female" / null (همان صدای پیش‌فرض) */
    void speak(String text, String lang, float speed, String id, String gender, Done cb) {
        if (!awaitReady()) { cb.onDone(false); return; }
        try {
            Locale loc = localeFor(lang);
            if (!"male".equals(gender) && !"female".equals(gender)) gender = null;
            String lk = loc.toLanguageTag() + (gender == null ? "" : "|" + gender);
            if (!lk.equals(curLangKey)) {
                // زبان عوض شده (یا اولین خوانش): اگر صدای انتخاب‌شده‌ی قبلیِ این زبان را داریم همان را بگذار
                boolean applied = false;
                android.speech.tts.Voice cached = bestVoice.get(lk);
                if (cached != null) {
                    try { applied = tts.setVoice(cached) == TextToSpeech.SUCCESS; } catch (Throwable ignored) {}
                }
                float pitch = 1.0f;
                if (!applied) {
                    int r = tts.setLanguage(loc);
                    if (r < TextToSpeech.LANG_AVAILABLE) { curLangKey = null; cb.onDone(false); return; }
                    if (gender == null) {
                        pickBestVoice(loc);
                    } else if (!pickGenderVoice(loc, gender, lk)) {
                        // صدایی با آن جنسیت نیست → همان صدای معمول، فقط زیر/بمِ صدا را کمی عوض کن
                        pickBestVoice(loc);
                        pitch = "male".equals(gender) ? 0.8f : 1.12f;
                    }
                }
                curLangKey = lk;
                try { tts.setPitch(pitch); } catch (Throwable ignored) {}
            }
            // سرعتِ پایه کمی آرام‌تر از پیش‌فرضِ موتور (صدای گوشی در ۱× معمولاً تنده)
            float rate = Math.max(0.25f, Math.min(speed * BASE_RATE, 2.0f));
            if (rate != curRate) {
                tts.setSpeechRate(rate);
                curRate = rate;
            }
            final String uid = id != null ? id : ("sys-" + System.nanoTime());
            callbacks.put(uid, cb);
            int res = tts.speak(text, TextToSpeech.QUEUE_FLUSH, new Bundle(), uid);
            if (res != TextToSpeech.SUCCESS) {
                callbacks.remove(uid);
                curLangKey = null;
                curRate = -1f;
                cb.onDone(false);
            }
        } catch (Throwable t) {
            Log.w(TAG, "speak failed", t);
            cb.onDone(false);
        }
    }

    void stop() {
        try { if (tts != null && ready) tts.stop(); } catch (Throwable ignored) {}
    }

    void release() {
        synchronized (lock) {
            try { if (tts != null) { tts.stop(); tts.shutdown(); } } catch (Throwable ignored) {}
            tts = null; ready = false; initFailed = false;
            curLangKey = null; curRate = -1f; bestVoice.clear();
        }
        callbacks.clear();
    }
}
