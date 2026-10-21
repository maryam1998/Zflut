package com.linglearn.app.overlay;

import android.Manifest;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.media.AudioFormat;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.ParcelFileDescriptor;
import android.speech.RecognitionListener;
import android.speech.RecognizerIntent;
import android.speech.SpeechRecognizer;
import android.util.Log;

import java.util.ArrayList;

/**
 * یک نشستِ SpeechRecognizerِ گوگل که صدا را از PcmFeed (صدای پخش‌شده‌ی سیستم) می‌گیرد، نه میکروفون.
 * مستقل از «میزبان» است: می‌تواند داخلِ BubbleService (بدونِ هیچ صفحه‌ای؛ ویدیو/اپِ زیرش دست‌نخورده می‌ماند)
 * یا داخلِ SpeechHostActivity (پشتیبان برای گوشی‌هایی که گوگل از سرویس صدا نمی‌گیرد) اجرا شود.
 * همه‌ی متدها باید روی thread اصلی صدا زده شوند.
 */
final class GoogleAsr {

    interface Host {
        /** کارِ گوگل ممکن نیست (آفلاین/زبان/سرور/نبودنِ سرویس) → موتورِ آفلاین. */
        void onFatal();
        /** مجوزِ میکروفونِ برنامه داده نشده. */
        void onNeedsPermission();
        /** میزبانِ فعلی اجازه‌ی کار با گوگل را ندارد (مثلاً چون برنامه «در پیش‌زمینه» حساب نمی‌شود). */
        void onHostUnsupported();
    }

    private static final String TAG = "GoogleAsr";
    private static final int MAX_CONSECUTIVE_ERRORS = 6;

    private final Context ctx;
    private final String langTag;
    private final Host host;
    private final Handler main = new Handler(Looper.getMainLooper());
    private SpeechRecognizer recognizer;
    private ParcelFileDescriptor readSide;
    private boolean destroyed = false;
    private int consecutiveErrors = 0;

    GoogleAsr(Context ctx, String langTag, Host host) {
        this.ctx = ctx;
        this.langTag = (langTag == null || langTag.isEmpty()) ? "en-US" : langTag;
        this.host = host;
    }

    void start() {
        if (Build.VERSION.SDK_INT < 33) { host.onFatal(); return; }
        if (ctx.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            host.onNeedsPermission();
            return;
        }
        if (!SpeechRecognizer.isRecognitionAvailable(ctx)) { host.onFatal(); return; }
        try {
            recognizer = SpeechRecognizer.createSpeechRecognizer(ctx);
            recognizer.setRecognitionListener(listener);
        } catch (Throwable e) {
            Log.w(TAG, "cannot create recognizer", e);
            host.onFatal();
            return;
        }
        startSession();
    }

    void stop() {
        destroyed = true;
        main.removeCallbacksAndMessages(null);
        SpeechRecognizer r = recognizer;
        recognizer = null;
        if (r != null) {
            try { r.cancel(); } catch (Throwable ignored) {}
            try { r.destroy(); } catch (Throwable ignored) {}
        }
        closeReadSide();
    }

    private void startSession() {
        if (destroyed || recognizer == null) return;
        try {
            startSession33();
        } catch (Throwable e) {
            Log.w(TAG, "startSession failed", e);
            fatal();
        }
    }

    @android.annotation.TargetApi(33)
    private void startSession33() throws Exception {
        closeReadSide();
        readSide = PcmFeed.newSession();
        Intent i = new Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH);
        i.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM);
        i.putExtra(RecognizerIntent.EXTRA_LANGUAGE, langTag);
        i.putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true);
        i.putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1);
        i.putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, ctx.getPackageName());
        i.putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, readSide);
        i.putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, 1);
        i.putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING, AudioFormat.ENCODING_PCM_16BIT);
        i.putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, 16000);
        recognizer.startListening(i);
    }

    private void restartSoon(long delayMs) {
        main.postDelayed(() -> {
            if (destroyed || recognizer == null) return;
            try { recognizer.cancel(); } catch (Throwable ignored) {}
            startSession();
        }, delayMs);
    }

    private void fatal() {
        if (destroyed) return;
        host.onFatal();
    }

    private void closeReadSide() {
        ParcelFileDescriptor p = readSide;
        readSide = null;
        if (p != null) {
            try { p.close(); } catch (Throwable ignored) {}
        }
    }

    private static String first(Bundle b) {
        if (b == null) return null;
        ArrayList<String> list = b.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);
        if (list == null || list.isEmpty()) return null;
        String s = list.get(0);
        return (s == null || s.trim().isEmpty()) ? null : s.trim();
    }

    private final RecognitionListener listener = new RecognitionListener() {
        @Override public void onReadyForSpeech(Bundle params) {}
        @Override public void onBeginningOfSpeech() {}
        @Override public void onRmsChanged(float rmsdB) {}
        @Override public void onBufferReceived(byte[] buffer) {}
        @Override public void onEndOfSpeech() {}
        @Override public void onEvent(int eventType, Bundle params) {}

        @Override
        public void onPartialResults(Bundle partialResults) {
            String t = first(partialResults);
            if (t != null) {
                consecutiveErrors = 0;
                BubbleService.asrPartial(t);
            }
        }

        @Override
        public void onResults(Bundle results) {
            String t = first(results);
            if (t != null) {
                consecutiveErrors = 0;
                BubbleService.asrFinal(t);
            }
            restartSoon(50);
        }

        @Override
        public void onError(int error) {
            if (destroyed) return;
            switch (error) {
                case SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS:
                    host.onHostUnsupported();
                    return;
                case SpeechRecognizer.ERROR_NETWORK:
                case SpeechRecognizer.ERROR_NETWORK_TIMEOUT:
                case SpeechRecognizer.ERROR_SERVER:
                case SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED:
                case SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE:
                    fatal();
                    return;
                case SpeechRecognizer.ERROR_NO_MATCH:
                case SpeechRecognizer.ERROR_SPEECH_TIMEOUT:
                    restartSoon(50);                       // سکوت/نامفهوم: عادی است
                    return;
                case SpeechRecognizer.ERROR_RECOGNIZER_BUSY:
                    consecutiveErrors++;
                    if (consecutiveErrors > MAX_CONSECUTIVE_ERRORS) { fatal(); return; }
                    restartSoon(400);
                    return;
                default:
                    consecutiveErrors++;
                    if (consecutiveErrors > MAX_CONSECUTIVE_ERRORS) { fatal(); return; }
                    restartSoon(200);
            }
        }
    };
}
