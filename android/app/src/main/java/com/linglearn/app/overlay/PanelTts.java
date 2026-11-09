package com.linglearn.app.overlay;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;

import java.util.concurrent.atomic.AtomicInteger;

/**
 * 🔊 خواندنِ جمله/لغت در پنلِ شناور — دقیقاً همان منطقِ خوانشِ اپ (nativeSpeak):
 * اول Piper (اگر بسته‌ی آن زبان دانلود شده و کرش‌نکرده)، وگرنه/در صورت شکست، TTS خودِ گوشی.
 * با هر پخشِ تازه، پخشِ قبلی قطع می‌شود؛ onEnd همیشه روی thread اصلی صدا زده می‌شود.
 */
final class PanelTts {

    interface End { void onEnd(boolean ok); }

    private static final Handler MAIN = new Handler(Looper.getMainLooper());
    private static final AtomicInteger SEQ = new AtomicInteger(0);

    private PanelTts() {}

    /**
     * همان گزینه‌ی تنظیماتِ اپ («خواندن ترجمه‌ها در پس‌زمینه»، کلیدِ zflut-read-trans-bg) — حباب و ذره‌بین
     * همیشه روی برنامه‌های دیگرند، پس همین گزینه تعیین می‌کند ترجمه‌ی زبانِ مبدأ بعد از متن خوانده شود یا نه.
     */
    static boolean readTransBg(Context ctx) {
        try {
            return ctx.getApplicationContext()
                    .getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    .getBoolean("flutter.zflut-read-trans-bg", true);
        } catch (Throwable t) { return false; }
    }

    static void stop(Context ctx) {
        SEQ.incrementAndGet();
        try { TtsClient.stop(); } catch (Throwable ignored) {}
        try { BubblePlugin.sys(ctx).stop(); } catch (Throwable ignored) {}
    }

    static void speak(final Context ctx0, final String text, final String lang0, final float speed, final End end) {
        final Context ctx = ctx0.getApplicationContext();
        if (text == null || text.trim().isEmpty()) { if (end != null) end.onEnd(false); return; }
        final String lang = (lang0 == null || lang0.isEmpty() || "auto".equals(lang0)) ? "en" : lang0;
        // پخشِ قبلی را قطع کن
        try { TtsClient.stop(); } catch (Throwable ignored) {}
        try { BubblePlugin.sys(ctx).stop(); } catch (Throwable ignored) {}
        final int my = SEQ.incrementAndGet();

        final String piperLang = SherpaModelManager.normalize(lang);
        boolean piper = piperLang != null
                && SherpaModelManager.getTtsModelDir(ctx, piperLang) != null
                && !TtsClient.isBlocked(piperLang);
        if (piper) {
            try {
                TtsClient.initIfNeeded(ctx);
                final String id = "panel-" + System.nanoTime();
                TtsClient.speakWith(piperLang, text, speed, id, (l, t, i, ok) -> {
                    if (my != SEQ.get()) return;                 // پخشِ تازه‌تری شروع شده
                    if (ok) done(end, true);
                    else systemSpeak(ctx, text, lang, speed, my, end);   // Piper شکست خورد → TTS گوشی
                });
                return;
            } catch (Throwable t) { /* می‌افتیم روی TTS گوشی */ }
        }
        systemSpeak(ctx, text, lang, speed, my, end);
    }

    private static void systemSpeak(final Context ctx, final String text, final String lang,
                                    final float speed, final int my, final End end) {
        new Thread(() -> {
            if (my != SEQ.get()) return;
            try {
                BubblePlugin.sys(ctx).speak(text, lang, speed, "panel-sys-" + System.nanoTime(), ok -> {
                    if (my != SEQ.get()) return;
                    done(end, ok);
                });
            } catch (Throwable t) { done(end, false); }
        }, "panel-sys-tts").start();
    }

    private static void done(final End end, final boolean ok) {
        if (end == null) return;
        MAIN.post(() -> end.onEnd(ok));
    }
}
