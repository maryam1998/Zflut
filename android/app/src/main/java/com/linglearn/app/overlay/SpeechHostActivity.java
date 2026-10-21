package com.linglearn.app.overlay;

import android.app.Activity;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.WindowManager;

/**
 * پشتیبان: صفحه‌ی نامرئی که GoogleAsr را اجرا می‌کند. فقط وقتی استفاده می‌شود که گوگل از داخلِ سرویس
 * جواب ندهد (روی بعضی گوشی‌ها اجازه‌ی صدا فقط به برنامه‌ی «پیش‌زمینه» داده می‌شود).
 * بدونِ فوکوس و بدونِ لمس و کاملاً شفاف است تا ویدیو/اپِ زیرش قفل نشود.
 */
public class SpeechHostActivity extends Activity {

    static final String EXTRA_LANG_TAG = "lang_tag";

    private static volatile SpeechHostActivity current;

    private final Handler main = new Handler(Looper.getMainLooper());
    private GoogleAsr asr;
    private boolean intentionalFinish = false;

    /** از BubbleService صدا زده می‌شه؛ اگه در حالِ اجراست می‌بندتش (بدونِ اینکه asrClosed بزنه). */
    static void finishIfRunning() {
        final SpeechHostActivity a = current;
        if (a == null) return;
        a.intentionalFinish = true;
        a.main.post(a::finish);
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        current = this;
        try {
            // شفاف + بدونِ فوکوس + لمس‌ها رد شوند. alpha ≤ ۰٫۸ شرطِ اندروید ۱۲+ است تا لمس به اپِ زیرش برسد.
            WindowManager.LayoutParams lp = getWindow().getAttributes();
            lp.alpha = 0f;
            lp.flags |= WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                    | WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                    | WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL;
            getWindow().setAttributes(lp);
        } catch (Throwable ignored) {}

        String tag = getIntent() != null ? getIntent().getStringExtra(EXTRA_LANG_TAG) : null;
        asr = new GoogleAsr(this, tag, new GoogleAsr.Host() {
            @Override public void onFatal() { intentionalFinish = true; BubbleService.asrFallback(); finish(); }
            @Override public void onNeedsPermission() { intentionalFinish = true; BubbleService.asrNeedsPermission(); finish(); }
            @Override public void onHostUnsupported() { intentionalFinish = true; BubbleService.asrFallback(); finish(); }
        });
        asr.start();
    }

    @Override
    protected void onDestroy() {
        main.removeCallbacksAndMessages(null);
        if (asr != null) { asr.stop(); asr = null; }
        if (current == this) current = null;
        boolean unexpected = !intentionalFinish && !isChangingConfigurations();
        super.onDestroy();
        if (unexpected) BubbleService.asrClosed();
    }
}
