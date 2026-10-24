package com.linglearn.app.overlay;

import android.animation.ValueAnimator;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ServiceInfo;
import android.content.res.Configuration;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.PixelFormat;
import android.graphics.Rect;
import android.graphics.RectF;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.Icon;
import android.hardware.display.DisplayManager;
import android.hardware.display.VirtualDisplay;
import android.media.Image;
import android.media.ImageReader;
import android.media.projection.MediaProjection;
import android.media.projection.MediaProjectionManager;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.provider.Settings;
import android.text.SpannableString;
import android.text.Spanned;
import android.text.TextUtils;
import android.util.DisplayMetrics;
import android.util.Log;
import android.util.TypedValue;
import android.view.Display;
import android.view.Gravity;
import android.view.HapticFeedbackConstants;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewConfiguration;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.widget.FrameLayout;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.SeekBar;
import android.widget.TextView;
import android.widget.Toast;

import com.google.mlkit.vision.common.InputImage;
import com.google.mlkit.vision.text.Text;
import com.google.mlkit.vision.text.TextRecognition;
import com.google.mlkit.vision.text.TextRecognizer;
import com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions;
import com.google.mlkit.vision.text.latin.TextRecognizerOptions;

import org.json.JSONObject;

import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

import okhttp3.OkHttpClient;

/**
 * 🔍 حبابِ ذره‌بین: یک ذره‌بینِ حلقه‌ای که کاربر روی متنِ هر اپی می‌کشد و رها می‌کند.
 * رها که شد: از صفحه عکس گرفته می‌شود (MediaProjection)، متنِ زیرِ ذره‌بین با ML Kit خوانده (OCR)،
 * هایلایت می‌شود و ترجمه‌اش به همه‌ی زبان‌های انتخابی در یک کادر می‌آید.
 * ضربه روی یک لغت (یا کشیدنِ انگشت روی چند لغت) کادرِ «ذخیره برای داستان بعدی / گرامر / لایتنر» را باز می‌کند.
 * خروج: ذره‌بین را بکش روی ✕ی پایینِ صفحه (مثلِ حبابِ ترجمه‌ی زنده) یا «بستن» در اعلان.
 *
 * کادرِ ترجمه مثلِ کادرِ ترجمه‌ی زنده: 🌐 تغییرِ زبان · Aa نوعِ فونت · A−/A+ اندازه‌ی متن ·
 * نوارِ دستگیره (کشیدنِ عمودی = ارتفاع، افقی = جابه‌جایی) · کشیدنِ سربرگ = جابه‌جایی (رها روی ✕ = بستنِ کادر).
 *
 * زبان‌ها از همان SharedPreferencesِ حبابِ ترجمه‌ی زنده خوانده می‌شود
 * (source = «زبان صدا»، targets = زبان‌های مقصد).
 */
public class MagnifierService extends Service {

    private static final String TAG = "MagnifierService";
    public static final String ACTION_START = "com.linglearn.app.overlay.MAG_START";
    public static final String ACTION_STOP = "com.linglearn.app.overlay.MAG_STOP";
    public static final String EXTRA_RESULT_CODE = "resultCode";
    public static final String EXTRA_DATA = "data";
    /** true = از مجوزِ ضبطِ مشترک با ترجمه‌ی زنده (ProjectionHolder) استفاده کن؛ پنجره‌ی اندروید لازم نیست. */
    public static final String EXTRA_REUSE = "reuse";

    static volatile boolean running = false;

    private static final String PREFS = "bubble_prefs";   // همان فایلِ تنظیماتِ BubbleService
    private static final String CHANNEL_ID = "magnifier_channel";
    private static final int NOTIF_ID = 4720;
    private static final int COLOR_INK = Color.parseColor("#1C2541");
    private static final int COLOR_GOLD = Color.parseColor("#C9A227");
    private static final int COLOR_REC = Color.parseColor("#E53935");
    private static final Set<String> LATIN = new HashSet<>(Arrays.asList(
            "en", "de", "fr", "es", "it", "pt", "nl", "tr"));

    // اندازه‌ی ذره‌بین (dp): هم‌اندازه‌ی حبابِ ترجمه‌ی زنده (60)؛ مرکزِ شیشه در (26,26) با شعاعِ 20
    private static final float LENS_SIZE = 60f, LENS_C = 26f, LENS_R = 20f;

    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final OkHttpClient http = new OkHttpClient.Builder()
            .connectTimeout(8, TimeUnit.SECONDS)
            .readTimeout(12, TimeUnit.SECONDS)
            .build();

    private WindowManager wm;
    private MediaProjection projection;
    private boolean projectionRetained = false;
    private boolean projectionLost = false;
    private final Runnable projectionStopListener = () -> main.post(() -> onProjectionLost());
    private VirtualDisplay vd;
    private ImageReader reader;
    private int capW, capH, dpiVal;
    private final Object frameLock = new Object();
    private Image lastImage;

    private LensView lens;
    private WindowManager.LayoutParams lensLp;
    private CloseTargetView closeView;
    private boolean overTarget = false;
    private boolean lensMode = false;      // true = حلقه‌ی شفاف (موقعِ کشیدن/رها)؛ false = حبابِ کنارِ صفحه
    private boolean docked = true;
    private ValueAnimator dockAnim;
    private final Runnable dockRun = () -> dockLens();
    private boolean busy = false;

    private TextRecognizer latinRec, devaRec;

    // انتخابِ فعلی
    private static final class ElemInfo {
        final Rect r; String t;
        ElemInfo(Rect r, String t) { this.r = r; this.t = t; }
    }
    private SelView selView;
    private WindowManager.LayoutParams selLp;
    private LinearLayout popup;
    private WindowManager.LayoutParams popupLp;
    private RectF selBox;
    private String selSrc = "en", selOrig = "";

    // کادرِ سورمه‌ای (هم‌سبکِ پنلِ حبابِ ترجمه‌ی زنده)
    private static final int REPEAT_INF = -1;                 // همان مقدارِ حبابِ ترجمه‌ی زنده
    private LinearLayout rowsBox, wordCard, wordRows, opacityRow;
    private LinearLayout langRow, fontRow;
    private TextView tvLangPill, tvFontBtn;
    private SeekBar opacityBar;
    private MaxHScroll bodyScroll;
    private OverlayFonts fonts;
    private final ArrayList<TextView> langChips = new ArrayList<>();
    private final ArrayList<TextView> appFontChips = new ArrayList<>();
    private float popupHFrac = POPUP_H_DEFAULT;      // ارتفاعِ بخشِ متن (کسری از ارتفاعِ صفحه)
    private boolean popupFree = false;               // کاربر کادر را جابه‌جا کرده → دیگر چسبیده به متن نیست
    private int popupFreeX = 0, popupFreeY = 0;
    private boolean popupHot = false;                // کادر الان روی ✕ی بستن است
    private int langSeq = 0;
    private WindowManager.LayoutParams closeLp;
    private static final float POPUP_H_MIN = 0.12f, POPUP_H_MAX = 0.85f, POPUP_H_DEFAULT = 0.35f;
    private TextView cardTerm, termSpeak, wordTerm, wordSpeak, tvRepeat;
    private TextView cardBtnStory, cardBtnGrammar, cardBtnLeitner;
    private GradientDrawable popupBg;
    private float panelAlpha = 1f;
    private String cardWord = "", cardMeaning = "", cardMeaningLang = "fa";
    private boolean cardStoryDone, cardGrammarDone, cardLeitnerDone;
    private int cardSeq = 0;
    private final ArrayList<String[]> wholeResults = new ArrayList<>();   // ترجمه‌ی کلِ متن: {کدِ زبان، متن}
    private TextView speakingBtn;
    private int speakTok = 0;

    // ───────────────────────── چرخه‌ی عمر ─────────────────────────

    @Override public IBinder onBind(Intent intent) { return null; }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        String action = intent != null ? intent.getAction() : null;
        if (ACTION_STOP.equals(action) || !ACTION_START.equals(action)) {
            stopSelf();
            return START_NOT_STICKY;
        }
        try {
            // ⚠ حتماً قبل از هر return: اندروید بعد از startForegroundService انتظار دارد در چند ثانیه startForeground صدا زده شود،
            // وگرنه برنامه کرش می‌کند و ذره‌بین ناگهان از صفحه می‌پرد (مثلاً وقتی سرویس از قبل روشن بود).
            startForeground(NOTIF_ID, buildNotification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION);
        } catch (SecurityException se) {
            // مجوزِ ضبطِ مشترک دیگر معتبر نیست → یک بار پنجره‌ی اندروید را نشان بده
            Log.w(TAG, "projection FGS refused, asking again", se);
            askProjectionAgain();
            return START_NOT_STICKY;
        }
        if (running) {
            // ذره‌بین از قبل روی صفحه است. اگر مجوزِ ضبط قطع شده بود و کاربر دوباره اجازه داد، همان‌جا وصل می‌شود.
            if (projectionLost) {
                try {
                    setupProjection(intent);
                    projectionLost = false;
                    toast(msg("ذره‌بین دوباره آماده است", "Magnifier is ready again"));
                } catch (Exception e) {
                    Log.w(TAG, "re-attach failed", e);
                }
            }
            return START_NOT_STICKY;
        }
        if (!Settings.canDrawOverlays(this)) {
            toast(msg("مجوز نمایش روی برنامه‌های دیگر داده نشده", "Overlay permission is not granted"));
            stopSelf();
            return START_NOT_STICKY;
        }
        try {
            wm = (WindowManager) getSystemService(WINDOW_SERVICE);
            setupProjection(intent);
            addLens();
            running = true;
            toast(msg("ذره‌بین را روی متن بکشید و رها کنید",
                    "Drag the magnifier over a text and release"));
        } catch (Exception e) {
            Log.e(TAG, "start failed", e);
            if (!"projection expired".equals(e.getMessage())) toast("⚠ " + e.getMessage());
            stopSelf();
        }
        return START_NOT_STICKY;
    }

    @Override
    public void onDestroy() {
        running = false;
        main.removeCallbacksAndMessages(null);
        if (dockAnim != null) dockAnim.cancel();
        clearSelection();
        try { if (closeView != null) wm.removeViewImmediate(closeView); } catch (Exception ignored) {}
        closeView = null;
        try { if (lens != null) wm.removeViewImmediate(lens); } catch (Exception ignored) {}
        lens = null;
        synchronized (frameLock) {
            if (lastImage != null) { try { lastImage.close(); } catch (Exception ignored) {} lastImage = null; }
        }
        // VirtualDisplay و مجوزِ ضبط با ترجمه‌ی زنده مشترک‌اند: فقط خروجی‌اش را قطع می‌کنیم و سهمِ خودمان را برمی‌گردانیم
        // (آخرین مصرف‌کننده که برود، مجوز و VirtualDisplay خودکار آزاد می‌شوند).
        try { if (vd != null) vd.setSurface(null); } catch (Exception ignored) {}
        try { if (reader != null) reader.close(); } catch (Exception ignored) {}
        ProjectionHolder.removeStopListener(projectionStopListener);
        if (projectionRetained) { projectionRetained = false; ProjectionHolder.release(); }
        try { if (latinRec != null) latinRec.close(); } catch (Exception ignored) {}
        try { if (devaRec != null) devaRec.close(); } catch (Exception ignored) {}
        worker.shutdownNow();
        super.onDestroy();
    }

    @Override
    public void onConfigurationChanged(Configuration newConfig) {
        super.onConfigurationChanged(newConfig);
        if (vd == null) return;
        try {
            DisplayMetrics dm = realMetrics();
            if (dm.widthPixels == capW && dm.heightPixels == capH) return;
            clearSelection();
            synchronized (frameLock) {
                if (lastImage != null) { try { lastImage.close(); } catch (Exception ignored) {} lastImage = null; }
            }
            ImageReader old = reader;
            capW = dm.widthPixels; capH = dm.heightPixels; dpiVal = dm.densityDpi;
            reader = newReader(capW, capH);
            vd.resize(capW, capH, dpiVal);
            vd.setSurface(reader.getSurface());
            if (old != null) old.close();
            clampLens();
        } catch (Exception e) {
            Log.e(TAG, "rotate failed", e);
        }
    }

    private Notification buildNotification() {
        NotificationManager nm = getSystemService(NotificationManager.class);
        if (nm.getNotificationChannel(CHANNEL_ID) == null) {
            nm.createNotificationChannel(new NotificationChannel(
                    CHANNEL_ID, "Magnifier bubble", NotificationManager.IMPORTANCE_LOW));
        }
        Intent stop = new Intent(this, MagnifierService.class).setAction(ACTION_STOP);
        PendingIntent pi = PendingIntent.getService(this, 1, stop,
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        Notification.Action close = new Notification.Action.Builder(
                Icon.createWithResource(this, android.R.drawable.ic_menu_close_clear_cancel),
                msg("بستن", "Close"), pi).build();
        return new Notification.Builder(this, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_menu_search)
                .setContentTitle("LingoLearn")
                .setContentText(msg("ذره‌بین فعال است", "Magnifier is active"))
                .setOngoing(true)
                .addAction(close)
                .build();
    }

    // ───────────────────────── عکس‌گرفتن از صفحه ─────────────────────────

    @SuppressWarnings("deprecation")
    private DisplayMetrics realMetrics() {
        DisplayMetrics dm = new DisplayMetrics();
        DisplayManager dmg = (DisplayManager) getSystemService(DISPLAY_SERVICE);
        Display d = dmg.getDisplay(Display.DEFAULT_DISPLAY);
        d.getRealMetrics(dm);
        return dm;
    }

    /**
     * مجوزِ ضبطِ صفحه از بیرون قطع شد (قفل‌شدنِ صفحه، دکمه‌ی توقفِ نوارِ وضعیت، سیستم…).
     * قبلاً همین‌جا سرویس بسته می‌شد و ذره‌بین «ناگهان» غیب می‌شد. حالا ذره‌بین روی صفحه می‌ماند و
     * وقتی کاربر دوباره آن را رها کرد، یک بار اجازه گرفته می‌شود.
     */
    private void onProjectionLost() {
        if (projectionLost || !running) return;
        projectionLost = true;
        projectionRetained = false;                     // ProjectionHolder خودش شمارنده را صفر کرده
        ProjectionHolder.removeStopListener(projectionStopListener);
        busy = false;
        if (lens != null) lens.setBusy(false);
        clearSelection();
        synchronized (frameLock) {
            if (lastImage != null) { try { lastImage.close(); } catch (Exception ignored) {} lastImage = null; }
        }
        try { if (reader != null) reader.close(); } catch (Exception ignored) {}
        reader = null; vd = null; projection = null;
        toast(msg("دسترسی ضبط صفحه قطع شد؛ ذره‌بین را رها کنید تا دوباره اجازه بگیرد",
                "Screen access ended — release the magnifier to allow it again"));
    }

    private void requestProjectionAgain() {
        try {
            startActivity(new Intent(this, ProjectionActivity.class)
                    .putExtra(ProjectionActivity.EXTRA_MAGNIFIER, true)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        } catch (Exception e) { Log.e(TAG, "cannot launch ProjectionActivity", e); }
    }

    private void askProjectionAgain() {
        try {
            startActivity(new Intent(this, ProjectionActivity.class)
                    .putExtra(ProjectionActivity.EXTRA_MAGNIFIER, true)
                    .putExtra(ProjectionActivity.EXTRA_FORCE, true)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        } catch (Exception e) { Log.e(TAG, "cannot launch ProjectionActivity", e); }
        stopSelf();
    }

    @SuppressWarnings("deprecation")
    private void setupProjection(Intent intent) {
        int rc = intent.getIntExtra(EXTRA_RESULT_CODE, 0);
        Intent data = intent.getBooleanExtra(EXTRA_REUSE, false) ? null
                : (Build.VERSION.SDK_INT >= 33
                    ? intent.getParcelableExtra(EXTRA_DATA, Intent.class)
                    : (Intent) intent.getParcelableExtra(EXTRA_DATA));
        // مجوزِ مشترک با ترجمه‌ی زنده: اگر زنده است همان، وگرنه از نتیجه‌ی پنجره‌ی اندروید
        projection = ProjectionHolder.obtain(this, rc, data);
        if (projection == null) {
            if (data == null) { askProjectionAgain(); throw new IllegalStateException("projection expired"); }
            throw new IllegalStateException("projection unavailable");
        }
        ProjectionHolder.retain();
        projectionRetained = true;
        ProjectionHolder.addStopListener(projectionStopListener);
        DisplayMetrics dm = realMetrics();
        capW = dm.widthPixels; capH = dm.heightPixels; dpiVal = dm.densityDpi;
        reader = newReader(capW, capH);
        vd = ProjectionHolder.display();
        if (vd == null) {
            vd = projection.createVirtualDisplay("lingo-magnifier", capW, capH, dpiVal,
                    DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, reader.getSurface(), null, main);
            ProjectionHolder.setDisplay(vd);
        } else {
            // اندروید ۱۴+: برای هر مجوز فقط یک VirtualDisplay؛ همان را با اندازه/خروجیِ تازه دوباره استفاده می‌کنیم
            vd.resize(capW, capH, dpiVal);
            vd.setSurface(reader.getSurface());
        }
    }

    private ImageReader newReader(int w, int h) {
        ImageReader r = ImageReader.newInstance(w, h, PixelFormat.RGBA_8888, 3);
        r.setOnImageAvailableListener(rd -> {
            Image im = null;
            try { im = rd.acquireLatestImage(); } catch (Exception ignored) {}
            if (im == null) return;
            synchronized (frameLock) {
                if (lastImage != null) { try { lastImage.close(); } catch (Exception ignored) {} }
                lastImage = im;
            }
        }, main);
        return r;
    }

    /** آخرین فریمِ صفحه به‌شکل Bitmap (null اگه هنوز فریمی نیومده). */
    private Bitmap frameBitmap() {
        synchronized (frameLock) {
            if (lastImage == null) return null;
            try {
                Image.Plane p = lastImage.getPlanes()[0];
                ByteBuffer buf = p.getBuffer();
                int ps = p.getPixelStride(), rs = p.getRowStride();
                int w = lastImage.getWidth(), h = lastImage.getHeight();
                Bitmap full = Bitmap.createBitmap(rs / ps, h, Bitmap.Config.ARGB_8888);
                buf.rewind();
                full.copyPixelsFromBuffer(buf);
                if (full.getWidth() == w) return full;
                Bitmap crop = Bitmap.createBitmap(full, 0, 0, w, h);
                full.recycle();
                return crop;
            } catch (Throwable e) {
                Log.e(TAG, "frame failed", e);
                return null;
            }
        }
    }

    // ───────────────────────── ذره‌بین (کشیدن / رها کردن) ─────────────────────────

    private void addLens() {
        createCloseTarget();
        lens = new LensView(this);
        int size = dp(LENS_SIZE);
        lensLp = new WindowManager.LayoutParams(size, size,
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
                        | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT);
        lensLp.gravity = Gravity.TOP | Gravity.START;
        // شروع: کنارِ راستِ صفحه، نیمه‌پنهان (مثلِ حبابِ ترجمه‌ی زنده)
        lensLp.x = capW - (int) (size * 0.58f);
        lensLp.y = (int) (capH * 0.42f);
        lens.setAlpha(0.62f);
        docked = true;
        lens.setOnTouchListener(new View.OnTouchListener() {
            float dx, dy, startX, startY; boolean moved; boolean wasDocked;
            @Override public boolean onTouch(View v, MotionEvent e) {
                switch (e.getActionMasked()) {
                    case MotionEvent.ACTION_DOWN:
                        main.removeCallbacks(dockRun);
                        if (dockAnim != null) dockAnim.cancel();
                        startX = e.getRawX(); startY = e.getRawY();
                        dx = lensLp.x - startX; dy = lensLp.y - startY;
                        moved = false; wasDocked = docked;
                        lens.setAlpha(1f);
                        return true;
                    case MotionEvent.ACTION_MOVE:
                        if (!moved && Math.hypot(e.getRawX() - startX, e.getRawY() - startY) > dp(8)) {
                            moved = true;
                            docked = false;
                            setLensMode(true);
                            showCloseTarget();
                        }
                        if (moved) {
                            lensLp.x = (int) (e.getRawX() + dx);
                            lensLp.y = (int) (e.getRawY() + dy);
                            clampLens();
                            updateOverTarget();
                        }
                        return true;
                    case MotionEvent.ACTION_UP:
                    case MotionEvent.ACTION_CANCEL:
                        boolean up = e.getActionMasked() == MotionEvent.ACTION_UP;
                        boolean onX = overTarget;
                        hideCloseTarget();
                        if (!up) { scheduleDock(600); return true; }
                        if (moved && onX) {
                            toast(msg("ذره‌بین بسته شد", "Magnifier closed"));
                            stopSelf();
                        } else if (moved) {
                            onLensDropped();
                        } else if (wasDocked) {
                            // ضربه روی حبابِ کنارِ صفحه: بیاید داخلِ صفحه و به ذره‌بین تبدیل شود
                            docked = false;
                            setLensMode(true);
                            lensLp.x = capW - lensLp.width - dp(24);
                            clampLens();
                            toast(msg("ذره‌بین را روی متن بکشید و رها کنید", "Drag the magnifier over a text and release"));
                            scheduleDock(6000);
                        } else {
                            onLensDropped();          // ضربه روی ذره‌بین: دوباره بخوان
                        }
                        return true;
                }
                return false;
            }
        });
        wm.addView(lens, lensLp);
    }

    private void setLensMode(boolean on) {
        lensMode = on;
        if (lens != null) lens.invalidate();
    }

    /** چند لحظه بعد، ذره‌بین به کنارِ نزدیک‌ترین لبه برمی‌گردد (مثلِ حبابِ ترجمه‌ی زنده). */
    private void scheduleDock(long ms) {
        main.removeCallbacks(dockRun);
        main.postDelayed(dockRun, ms);
    }

    private void dockLens() {
        if (lens == null || lensLp == null || busy) return;
        if (dockAnim != null) dockAnim.cancel();
        final boolean left = lensLp.x + lensLp.width / 2 < capW / 2;
        final int target = left ? -(int) (lensLp.width * 0.42f) : capW - (int) (lensLp.width * 0.58f);
        setLensMode(false);
        dockAnim = ValueAnimator.ofInt(lensLp.x, target);
        dockAnim.setDuration(220);
        dockAnim.addUpdateListener(a -> {
            if (lens == null) return;
            lensLp.x = (Integer) a.getAnimatedValue();
            try { wm.updateViewLayout(lens, lensLp); } catch (Exception ignored) {}
        });
        dockAnim.start();
        docked = true;
        lens.setAlpha(0.62f);
    }

    private void clampLens() {
        if (lens == null || lensLp == null) return;
        lensLp.x = Math.max(0, Math.min(capW - lensLp.width, lensLp.x));
        lensLp.y = Math.max(0, Math.min(capH - lensLp.height, lensLp.y));
        try { wm.updateViewLayout(lens, lensLp); } catch (Exception ignored) {}
    }

    private void bringLensToFront() {
        if (lens == null) return;
        try {
            wm.removeViewImmediate(lens);
            wm.addView(lens, lensLp);
        } catch (Exception ignored) {}
    }

    // ✕ی خروج: یک بار (نامرئی) قبل از ذره‌بین ساخته می‌شود تا زیرِ آن بماند؛ هنگامِ کشیدن ظاهر می‌شود.
    private void createCloseTarget() {
        int sz = dp(84);
        closeView = new CloseTargetView(this);
        WindowManager.LayoutParams lp = closeLp = new WindowManager.LayoutParams(sz, sz,
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                        | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                        | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
                        | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT);
        lp.gravity = Gravity.TOP | Gravity.START;
        lp.x = capW / 2 - sz / 2;
        lp.y = capH - dp(120) - sz / 2;
        closeView.setVisibility(View.INVISIBLE);
        try { wm.addView(closeView, lp); } catch (Exception ex) { closeView = null; }
    }

    private void showCloseTarget() {
        if (closeView != null) closeView.setVisibility(View.VISIBLE);
    }

    private void hideCloseTarget() {
        overTarget = false;
        if (closeView == null) return;
        closeView.setHot(false);
        closeView.setVisibility(View.INVISIBLE);
    }

    private void updateOverTarget() {
        if (closeView == null) return;
        double cx = lensLp.x + dp(LENS_C), cy = lensLp.y + dp(LENS_C);
        double tx = capW / 2.0, ty = capH - dp(120);
        boolean hot = Math.hypot(cx - tx, cy - ty) < dp(60);
        if (hot != overTarget) { overTarget = hot; closeView.setHot(hot); }
    }

    // ───────────────────────── رها شدنِ ذره‌بین روی متن ─────────────────────────

    private void onLensDropped() {
        if (busy) return;
        if (projectionLost || reader == null) {
            requestProjectionAgain();                 // مجوز قطع شده؛ بعد از اجازه‌ی کاربر خودکار وصل می‌شود
            scheduleDock(6000);
            return;
        }
        busy = true;
        main.removeCallbacks(dockRun);
        setLensMode(true);
        clearSelection();                         // هایلایت و کادرِ قبلی از فریم محو شود
        if (lens != null) lens.setBusy(true);
        main.postDelayed(() -> {
            Bitmap bmp = frameBitmap();
            if (bmp == null) {
                finish(msg("هنوز تصویری از صفحه نیست؛ دوباره رها کنید", "No screen image yet, try again"));
                return;
            }
            final float cx = lensLp.x + dp(LENS_C), cy = lensLp.y + dp(LENS_C);
            final Bitmap b = bmp;
            runSafe(() -> process(b, cx, cy));
        }, 260);
    }

    private SharedPreferences prefs() { return getSharedPreferences(PREFS, MODE_PRIVATE); }

    // زبانِ متن‌های ذره‌بین = «زبان نرم‌افزار» در تنظیماتِ اپ (نه زبانِ مقصدِ ترجمه)
    private boolean uiFa() { return BubbleService.uiLangIsFa(this); }

    private String msg(String fa, String en) { return NativeI18n.tr(NativeI18n.lang(this), fa, en); }

    private String sourceLang() {
        String s = prefs().getString("source", "en");
        return (s == null || s.isEmpty() || "auto".equals(s)) ? "en" : s;
    }

    private List<String> targets(String src) {
        ArrayList<String> out = new ArrayList<>();
        String csv = prefs().getString("targets", "");
        if (csv != null) {
            for (String t : csv.split(",")) {
                t = t.trim().toLowerCase(Locale.ROOT);
                if (!t.isEmpty() && !out.contains(t)) out.add(t);
            }
        }
        if (out.isEmpty()) {
            String t = prefs().getString("target", "fa");
            if (t != null && !t.isEmpty()) out.add(t);
        }
        if (out.isEmpty()) {
            // هیچ زبانِ مقصدی (غیر از زبانِ خودِ متن) نمانده → زبانِ رابطِ اپ، وگرنه انگلیسی
            String ui = prefs().getString("uiLang", null);
            if (ui == null || ui.isEmpty() || ui.equals(src)) ui = "en".equals(src) ? "fa" : "en";
            out.add(ui);
        }
        return out;
    }

    private TextRecognizer recognizerFor(String src) {
        if ("hi".equals(src)) {
            if (devaRec == null) devaRec = TextRecognition.getClient(new DevanagariTextRecognizerOptions.Builder().build());
            return devaRec;
        }
        if (LATIN.contains(src)) {
            if (latinRec == null) latinRec = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS);
            return latinRec;
        }
        return null;
    }

    /** کارِ پس‌زمینه بدونِ خطرِ کرشِ کلِ برنامه: استثنا (مثلاً کمبودِ حافظه) فقط یک پیام می‌دهد، ذره‌بین نمی‌پرد. */
    private void runSafe(final Runnable r) {
        try {
            worker.execute(() -> {
                try { r.run(); }
                catch (Throwable t) {
                    Log.e(TAG, "worker task failed", t);
                    main.post(() -> finish(msg("خطایی رخ داد؛ دوباره رها کنید", "Something went wrong — try again")));
                }
            });
        } catch (Exception ignored) { /* سرویس در حال بسته شدن است */ }
    }

    private void process(final Bitmap bmp, final float x, final float y) {
        final String src = sourceLang();
        TextRecognizer rec0 = recognizerFor(src);
        if (rec0 == null) rec0 = recognizerFor("en");   // زبانِ ذخیره‌شده OCR ندارد (مثلاً فارسی): با OCR لاتین بخوان و زبانِ واقعیِ متن را خودکار تشخیص بده
        final TextRecognizer rec = rec0;
        rec.process(InputImage.fromBitmap(bmp, 0))
                .addOnSuccessListener(text -> runSafe(() -> handleText(text, src, x, y)))
                .addOnFailureListener(e -> runSafe(() -> handleText(null, src, x, y)));
    }

    private void handleText(Text text, String src, float x, float y) {
        Text.TextBlock best = null;
        double bestD = Double.MAX_VALUE;
        if (text != null) {
            for (Text.TextBlock b : text.getTextBlocks()) {
                Rect r = b.getBoundingBox();
                if (r == null) continue;
                double d = dist(r, x, y);
                if (d < bestD) { bestD = d; best = b; }
            }
        }
        final ArrayList<ElemInfo> elems = new ArrayList<>();
        Rect box = null;
        String orig = "";
        if (best != null && bestD <= dp(40)) {
            List<Text.Line> lines = best.getLines();
            Rect bb = best.getBoundingBox();
            if (best.getText().length() > 500) {          // بلوکِ خیلی بلند: فقط خطِ نزدیک
                Text.Line bl = null; double bd = Double.MAX_VALUE;
                for (Text.Line l : best.getLines()) {
                    Rect lr = l.getBoundingBox();
                    if (lr == null) continue;
                    double d = dist(lr, x, y);
                    if (d < bd) { bd = d; bl = l; }
                }
                if (bl != null) { lines = new ArrayList<>(); lines.add(bl); }
            }
            // ساعتِ پیام (13:22)، تیک‌ها، ایموجی و خرده‌نویسه‌های OCR حذف می‌شوند
            for (Text.Line l : lines) {
                for (Text.Element e : l.getElements()) {
                    Rect er = e.getBoundingBox();
                    if (er != null && !e.getText().trim().isEmpty()) elems.add(new ElemInfo(new Rect(er), e.getText()));
                }
            }
            cleanElems(elems);
            StringBuilder osb = new StringBuilder();
            Rect ub = null;
            for (ElemInfo ei : elems) {
                if (osb.length() > 0) osb.append(' ');
                osb.append(ei.t);
                if (ub == null) ub = new Rect(ei.r); else ub.union(ei.r);
            }
            orig = osb.toString().trim();
            box = ub != null ? ub : bb;
        }

        // 🔍 متنِ دقیقِ صفحه از دسترس‌پذیری: فارسی/عربی (که OCR نمی‌خواند) و اصلاحِ غلط‌خوانیِ OCR
        final SpeedAccessibilityService.ScreenText a = pickScreenText(x, y);
        if (a != null) {
            String at = cleanScreenText(a.t);
            if (!at.isEmpty() && at.length() <= 500) {
                boolean rtl = hasArabicScript(at);
                boolean overlap = box != null && Rect.intersects(box, a.r);
                if (!elems.isEmpty() && overlap && !rtl) {
                    String[] w = at.split("\\s+");
                    if (w.length == elems.size()) {          // هم‌تعداد: هر لغتِ OCR با لغتِ دقیق عوض می‌شود
                        for (int i = 0; i < w.length; i++) elems.get(i).t = w[i];
                        orig = at;
                    }
                } else if (elems.isEmpty() || rtl || !overlap) {
                    elems.clear();
                    elems.add(new ElemInfo(new Rect(a.r), at));
                    orig = at;
                    box = new Rect(a.r);
                }
            }
        }
        // OCR فقط ساعتِ پیام («19:03») را خوانده و متنِ فارسی/عربیِ کنارش را نه: ترجمه‌ی ساعت بی‌معنی است
        // Latin-OCR روی متنِ فارسی/عربی خرده‌نویسه‌ی بی‌معنی می‌دهد («jyoJoai ög»)؛ اگر دسترس‌پذیری متنِ دقیق را نداد، آن را ترجمه نکن
        boolean ocrGarbage = a == null && best != null && ocrLooksGarbage(best, orig);
        boolean ocrOnlyClock = !orig.isEmpty() && TIME_TOK.matcher(orig.trim()).matches() && !hasLetterChar(orig);
        if (elems.isEmpty() || box == null || orig.isEmpty() || ocrGarbage || (ocrOnlyClock && (a == null || !hasLetterChar(cleanScreenText(a.t))))) {
            if (!SpeedAccessibilityService.isEnabled(this)) {
                if (!prefs().getBoolean("a11yAsked", false)) {
                    prefs().edit().putBoolean("a11yAsked", true).apply();
                    SpeedAccessibilityService.openSettings(this);
                }
                finish(msg("برای خواندنِ متنِ فارسی/عربی، سرویسِ «دسترسی‌پذیری» این برنامه را روشن کنید",
                        "To read Persian/Arabic text, turn on this app's Accessibility service"));
            } else {
                finish(msg("زیرِ ذره‌بین متنی پیدا نشد", "No text found under the magnifier"));
            }
            return;
        }

        // زبانِ واقعیِ همین متن (نه فقط زبانِ ذخیره‌شده): «Este sonido…» با مبدأ en غلط ترجمه می‌شد
        try {
            String det = LangDetect.detect(orig);
            if (det != null && !det.equals(src)) src = det;
        } catch (Throwable ignored) { }

        final ArrayList<String[]> results = new ArrayList<>();
        for (String tgt : targets(src)) {
            String tr;
            try { tr = translateOne(orig, src, tgt); }
            catch (Exception ex) { tr = "—"; }
            results.add(new String[]{tgt, (tr == null || tr.trim().isEmpty()) ? "—" : tr.trim()});
        }
        final String fo = orig, fsrc = src;
        final RectF rf = new RectF(box);
        main.post(() -> {
            busy = false;
            if (lens != null) lens.setBusy(false);
            showSelection(rf, elems, fo, fsrc, results);
            scheduleDock(2500);
        });
    }

    private static final java.util.regex.Pattern CAMEL_JUNK = java.util.regex.Pattern.compile("^\\p{Ll}{2,}\\p{Lu}");

    /** نشانه‌های خوانشِ اشتباهِ OCR لاتین از اسکریپتِ دیگر: زبانِ «und» یا لغتِ نیمه‌کوچک/نیمه‌بزرگ مثلِ jyoJoai. */
    private static boolean ocrLooksGarbage(Text.TextBlock b, String orig) {
        int letters = 0;
        for (int i = 0; i < orig.length(); i++) if (Character.isLetter(orig.charAt(i))) letters++;
        if (letters < 6) return false;
        String lang = null;
        try { lang = b.getRecognizedLanguage(); } catch (Throwable ignored) { }
        boolean und = lang == null || lang.isEmpty() || "und".equals(lang);
        boolean camel = false;
        for (String tok : orig.split("\\s+")) if (CAMEL_JUNK.matcher(tok).find()) { camel = true; break; }
        boolean odd = false;                                   // حرفِ لاتینِ دارای نشانه (ö, ğ …) در متنی که زبانش شناخته نشد
        for (int i = 0; i < orig.length(); i++) { char c = orig.charAt(i); if (Character.isLetter(c) && c > 0x7F) { odd = true; break; } }
        return camel || (und && letters >= 10 && odd);
    }

    private static boolean hasArabicScript(String t) {
        for (int i = 0; i < t.length(); ) {
            int cp = t.codePointAt(i);
            i += Character.charCount(cp);
            if (Character.isLetter(cp) && (cp >= 0x0600 && cp <= 0x06FF || cp >= 0x0750 && cp <= 0x077F)) return true;
        }
        return false;
    }

    /** ساعت (۱۳:۲۲ / 13:22)، ایموجی و فاصله‌های اضافه از متنِ دسترس‌پذیری پاک می‌شود. */
    private static String cleanScreenText(String t) {
        if (t == null) return "";
        t = EMOJI_RUN.matcher(t).replaceAll(" ");
        t = t.replaceAll("[,،]?\\s*[\\d\\u06F0-\\u06F9\\u0660-\\u0669]{1,2}[:.][\\d\\u06F0-\\u06F9\\u0660-\\u0669]{2}\\s*([AaPp][Mm])?", " ");
        return t.replaceAll("\\s+", " ").trim();
    }

    /** گرهٔ متنیِ کوچک‌ترِ شامل نقطه‌ی ذره‌بین که بعد از پاک‌کردنِ ساعت/ایموجی هنوز حرف دارد؛ وگرنه نزدیک‌ترین (تا ۴۰dp). */
    private SpeedAccessibilityService.ScreenText pickScreenText(float x, float y) {
        List<SpeedAccessibilityService.ScreenText> all;
        try { all = SpeedAccessibilityService.readScreenText(this); }
        catch (Throwable e) { return null; }
        SpeedAccessibilityService.ScreenText inside = null, near = null;
        long bestArea = Long.MAX_VALUE;
        double bestD = Double.MAX_VALUE;
        for (SpeedAccessibilityService.ScreenText n : all) {
            if (n.r.width() >= capW * 0.98 && n.r.height() >= capH * 0.5) continue;     // کانتینرِ کلِ صفحه
            if (!hasLetterChar(cleanScreenText(n.t))) continue;                          // فقط ساعت/عدد (مثلاً «۱۹:۰۳») نه
            long area = (long) n.r.width() * n.r.height();
            if (n.r.contains((int) x, (int) y)) {
                if (area < bestArea) { bestArea = area; inside = n; }
            } else {
                double d = dist(n.r, x, y);
                if (d <= dp(40) && d < bestD) { bestD = d; near = n; }
            }
        }
        return inside != null ? inside : near;
    }

    private static boolean hasLetterChar(String t) {
        if (t == null) return false;
        for (int i = 0; i < t.length(); i++) if (Character.isLetter(t.charAt(i))) return true;
        return false;
    }

    private static final java.util.regex.Pattern TIME_TOK = java.util.regex.Pattern.compile("^\\d{1,2}[:.]\\d{2}(am|pm|AM|PM)?$");
    private static final java.util.regex.Pattern EMOJI_RUN = java.util.regex.Pattern.compile(
            "[\\x{1F000}-\\x{1FAFF}\\x{2600}-\\x{27BF}\\x{FE0F}\\x{200D}\\x{2B00}-\\x{2BFF}]+");

    /** ساعت/تیکِ پیام‌رسان، ایموجی و خرده‌ی بی‌معنیِ انتهای متن را از المنت‌ها پاک می‌کند. */
    private static void cleanElems(ArrayList<ElemInfo> el) {
        for (ElemInfo e : el) {
            String t = EMOJI_RUN.matcher(e.t).replaceAll("").trim();
            t = t.replaceAll("(?<=\\p{L})(\\d)\\1{2,}$", "");          // ایموجی که OCR «999» خوانده
            e.t = t;
        }
        for (int i = el.size() - 1; i >= 0; i--) if (el.get(i).t.isEmpty()) el.remove(i);
        // انتها: ساعت (13:22 یا 322)، تیک و نمادِ تنها؛ فقط وقتی پیش از آن کلمه‌ی حرف‌دار هست
        while (el.size() > 1) {
            String t = el.get(el.size() - 1).t;
            boolean hasLetter = false;
            for (int k = 0; k < t.length(); k++) if (Character.isLetter(t.charAt(k))) { hasLetter = true; break; }
            boolean junk = !hasLetter && (TIME_TOK.matcher(t).matches() || t.matches("\\d{3,4}")
                    || t.matches("[\\p{Punct}\\s✓✔vV/|\\\\]{1,4}"));
            if (!junk) break;
            el.remove(el.size() - 1);
        }
        // «|» تنها در ابتدا معمولاً «I» است
        if (!el.isEmpty() && el.get(0).t.equals("|")) el.get(0).t = "I";
    }

    /** هم‌زبان (مبدأ = مقصد): همان متنِ پاک‌شده؛ وگرنه ترجمه با یک بارِ تلاشِ دوباره. */
    private String translateOne(String text, String from, String to) throws Exception {
        if (from != null && from.equals(to)) return text;
        try { return FreeTranslator.translate(http, text, from, to); }
        catch (Exception first) { return FreeTranslator.translate(http, text, from, to); }
    }

    // ───────── 🔎 بازبینیِ AI (ترجمه‌ی رایگان فوراً نشان داده می‌شود؛ اصلاحِ AI که برسد جایش را می‌گیرد) ─────────
    private final ExecutorService aiPool = Executors.newFixedThreadPool(3);
    private volatile int reviewSeq;
    private volatile int wordReviewSeq;

    private interface RowFix { void apply(String lang, String text); }

    private void reviewAi(final java.util.function.IntSupplier cur, final int token, final String text,
                          final String from, final List<String[]> rows, final RowFix fix) {
        for (final String[] r : new ArrayList<>(rows)) {
            final String tgt = r[0], draft = r[1];
            if (tgt == null || tgt.isEmpty() || tgt.equals(from)) continue;
            try {
                aiPool.execute(() -> {
                    if (token != cur.getAsInt()) return;
                    String better = null;
                    try {
                        boolean failed = draft == null || draft.isEmpty() || "—".equals(draft) || "…".equals(draft);
                        String out = failed ? BubbleService.aiTranslateStatic(text, from, tgt)
                                            : BubbleService.aiVerifyStatic(text, from, tgt, draft);
                        if (out != null) {
                            out = out.trim().replaceAll("^[\"'“”«»]+|[\"'“”«»]+$", "").trim();
                            boolean ok = out.equalsIgnoreCase("OK") || out.equalsIgnoreCase("OK.");
                            if (!out.isEmpty() && !ok && !out.equals(draft)
                                    && !LiveTranslator.isReasoningLeak(out)
                                    && !LiveTranslator.looksLikelyMistranslated(text, out, tgt, from)) better = out;
                        }
                    } catch (Throwable ignored) { }
                    if (better == null) return;
                    final String fb = better;
                    main.post(() -> { if (token == cur.getAsInt()) fix.apply(tgt, fb); });
                });
            } catch (Exception ignored) { /* سرویس در حال بسته شدن است */ }
        }
    }

    private void startWholeReview(List<String[]> rows) {
        final int token = ++reviewSeq;
        reviewAi(() -> reviewSeq, token, selOrig, selSrc, rows, (lang, t) -> {
            if (popup == null || rowsBox == null) return;
            for (String[] r : wholeResults) if (r[0].equals(lang)) r[1] = t;
            fillRows(rowsBox, wholeResults);
            if (wordCard != null && wordCard.getVisibility() == View.VISIBLE && wordRows != null
                    && cardWord != null && cardWord.equals(selOrig)) {
                fillRows(wordRows, wholeResults);
                adoptMeaning(wholeResults);
            }
            placePopup();
        });
    }

    private void startWordReview(final int cardToken, final String word, final ArrayList<String[]> rows) {
        final int token = ++wordReviewSeq;
        reviewAi(() -> cardSeq == cardToken ? wordReviewSeq : -1, token, word, selSrc, rows, (lang, t) -> {
            if (wordRows == null || cardSeq != cardToken) return;
            for (String[] r : rows) if (r[0].equals(lang)) r[1] = t;
            fillRows(wordRows, rows);
            adoptMeaning(rows);
            placePopup();
        });
    }

    private void finish(final String message) {
        main.post(() -> {
            busy = false;
            if (lens != null) lens.setBusy(false);
            toast(message);
            scheduleDock(2000);
        });
    }

    private static double dist(Rect r, float x, float y) {
        double dx = Math.max(Math.max(r.left - x, 0), x - r.right);
        double dy = Math.max(Math.max(r.top - y, 0), y - r.bottom);
        return Math.hypot(dx, dy);
    }

    // ───────────────────────── هایلایت + کادرِ ترجمه ─────────────────────────

    private void clearSelection() {
        main.removeCallbacks(cardTick);
        main.removeCallbacks(popupTick);
        popupBar = null;
        tvPin = null;
        reviewSeq++;
        cardSeq++;
        stopSpeech();
        if (selView != null) { try { wm.removeViewImmediate(selView); } catch (Exception ignored) {} selView = null; }
        langSeq++;
        popupHot = false;
        if (popup != null) {
            popup.animate().cancel();
            try { wm.removeViewImmediate(popup); } catch (Exception ignored) {}
            popup = null;
        }
        hideCloseTarget();
        rowsBox = null; wordCard = null; wordRows = null; opacityRow = null;
        langRow = null; fontRow = null; tvLangPill = null; tvFontBtn = null; opacityBar = null; bodyScroll = null;
        langChips.clear(); appFontChips.clear();
        cardTerm = null; termSpeak = null; wordTerm = null; wordSpeak = null; tvRepeat = null; popupBg = null;
    }

    private void showSelection(RectF box, ArrayList<ElemInfo> elems, String orig, String src, List<String[]> results) {
        clearSelection();
        selBox = box;
        selSrc = src;
        selOrig = orig;
        wholeResults.clear();
        wholeResults.addAll(results);

        // پنجره‌ی هایلایت: فقط به‌اندازه‌ی متن، تا بقیه‌ی صفحه لمس‌پذیر بماند
        int pad = dp(6);
        selView = new SelView(this, elems, (int) box.left - pad, (int) box.top - pad);
        selLp = new WindowManager.LayoutParams(
                (int) box.width() + 2 * pad, (int) box.height() + 2 * pad,
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
                        | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT);
        selLp.gravity = Gravity.TOP | Gravity.START;
        selLp.x = (int) box.left - pad;
        selLp.y = (int) box.top - pad;
        try { wm.addView(selView, selLp); } catch (Exception ex) { selView = null; }

        popupFree = false;
        buildPopup();
        int w = Math.min(capW - dp(16), dp(640));
        popupLp = new WindowManager.LayoutParams(w, ViewGroup.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
                        | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT);
        popupLp.gravity = Gravity.TOP | Gravity.START;
        try {
            wm.addView(popup, popupLp);
            placePopup();
        } catch (Exception ex) { popup = null; }
        bringLensToFront();
        armPopupTimer();
        startWholeReview(results);
        // کادرِ «ذخیره برای داستان بعدی / گرامر / لایتنر» فقط وقتی باز می‌شود که کاربر روی لغت یا محدوده بزند (یا 📄)
    }

    private void placePopup() {
        if (popup == null || popupLp == null || selBox == null) return;
        int w = popupLp.width;
        popup.measure(View.MeasureSpec.makeMeasureSpec(w, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED));
        int h = popup.getMeasuredHeight();
        int pad = dp(6), gap = dp(8);
        int left, top;
        if (popupFree) {                                   // جای دلخواهِ کاربر
            left = Math.max(0, Math.min(capW - w, popupFreeX));
            top = Math.max(0, Math.min(capH - h, popupFreeY));
        } else {
            left = Math.max(dp(12), Math.min(capW - w - dp(12), (int) (selBox.centerX() - w / 2f)));
            if (selBox.bottom + pad + gap + h <= capH - dp(24)) top = (int) selBox.bottom + pad + gap;
            else top = Math.max(dp(36), (int) selBox.top - pad - gap - h);
        }
        popupLp.x = left;
        popupLp.y = top;
        try { wm.updateViewLayout(popup, popupLp); } catch (Exception ignored) {}
    }

    /** رنگِ کادر (قابلِ تنظیم در اپ، مشترک با حبابِ ترجمه‌ی زنده)؛ پیش‌فرض سورمه‌ای. */
    private int panelRgb() { return prefs().getInt("panelColor", 0x1C2541) & 0xFFFFFF; }

    /** رنگِ کادرِ لغت: همان منطقِ حبابِ ترجمه‌ی زنده. */
    private int wordCardBgColor() {
        int c = panelRgb();
        if (c == 0x1C2541) return Color.parseColor("#26335F");
        int r = (c >> 16) & 0xFF, g = (c >> 8) & 0xFF, b = c & 0xFF;
        r += Math.round((255 - r) * 0.10f); g += Math.round((255 - g) * 0.10f); b += Math.round((255 - b) * 0.10f);
        return 0xFF000000 | (r << 16) | (g << 8) | b;
    }

    private TextView txt(String s, int color, float sp) {
        TextView t = new TextView(this);
        t.setText(s);
        t.setTextColor(color);
        t.setTextSize(sp);
        t.setTextAlignment(View.TEXT_ALIGNMENT_TEXT_START);
        t.setTextDirection(View.TEXT_DIRECTION_FIRST_STRONG);
        return t;
    }

    // ───────── آیکون‌های خطیِ برداری (همان‌هایی که در کادرِ ترجمه‌ی زنده‌ی BubbleService هست) ─────────
    // کدِ ایموجی با setText داده می‌شود و به آیکونِ برداری نگاشت می‌شود؛ رنگِ آیکون = رنگِ متنِ همان View.
    private static final float ICON_STROKE_DP = 1.7f;

    private final class IconText extends TextView {
        private static final int I_PLAY = 4, I_STOP = 6, I_REPLAY = 8, I_DROP = 10,
                I_SPEAKER = 14, I_DOC = 15, I_CLOSE = 16, I_PAUSE = 3, I_PIN = 11, I_TRASH = 12;
        private int icon;
        private String suffix;
        private float iconDp = 18f;
        private final Paint sp = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint tp = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Path p = new Path();
        private final RectF r = new RectF();

        IconText(Context c) {
            super(c);
            sp.setStyle(Paint.Style.STROKE);
            sp.setStrokeCap(Paint.Cap.ROUND);
            sp.setStrokeJoin(Paint.Join.ROUND);
            tp.setStyle(Paint.Style.FILL);
            tp.setTextAlign(Paint.Align.CENTER);
            tp.setTypeface(Typeface.DEFAULT_BOLD);
        }

        void setIconDp(float v) { iconDp = v; requestLayout(); invalidate(); }

        @Override public void setText(CharSequence t, BufferType type) {
            String k = t == null ? "" : t.toString();
            suffix = null;
            icon = iconFor(k);
            super.setText(icon != 0 ? "" : t, type);
            invalidate();
        }

        private int iconFor(String k) {
            if (k.startsWith("\u21BA")) { suffix = k.length() > 1 ? k.substring(1) : null; return I_REPLAY; }
            switch (k) {
                case "\u23F8": return I_PAUSE;
                case "\u25B6": return I_PLAY;
                case "\u23F9": return I_STOP;
                case "\uD83C\uDF13": return I_DROP;
                case "\uD83D\uDD0A": return I_SPEAKER;
                case "\uD83D\uDCC4": return I_DOC;
                case "\u2715": return I_CLOSE;
                case "\uD83D\uDCCC": return I_PIN;
                case "\uD83D\uDDD1": return I_TRASH;
                default: return 0;
            }
        }

        @Override protected void onMeasure(int wSpec, int hSpec) {
            if (icon == 0) { super.onMeasure(wSpec, hSpec); return; }
            int box = dp(iconDp);
            int w = Math.max(getMinWidth(), getPaddingLeft() + getPaddingRight() + box);
            int h = Math.max(getMinHeight(), getPaddingTop() + getPaddingBottom() + box);
            setMeasuredDimension(resolveSize(w, wSpec), resolveSize(h, hSpec));
        }

        @Override protected void onDraw(Canvas cv) {
            if (icon == 0) { super.onDraw(cv); return; }
            float box = dp(iconDp);
            float s = box / 24f;
            float cx = (getPaddingLeft() + getWidth() - getPaddingRight()) / 2f;
            float cy = (getPaddingTop() + getHeight() - getPaddingBottom()) / 2f;
            int col = getCurrentTextColor();
            sp.setColor(col);
            sp.setStrokeWidth(dp(ICON_STROKE_DP) / s);
            tp.setColor(col);
            cv.save();
            cv.translate(cx - box / 2f, cy - box / 2f);
            cv.scale(s, s);
            p.reset();
            switch (icon) {
                case I_PLAY:
                    p.moveTo(8f, 5.5f); p.lineTo(18.5f, 12f); p.lineTo(8f, 18.5f); p.close();
                    break;
                case I_PAUSE:
                    p.moveTo(9f, 6f); p.lineTo(9f, 18f);
                    p.moveTo(15f, 6f); p.lineTo(15f, 18f);
                    break;
                case I_STOP:
                    r.set(6.5f, 6.5f, 17.5f, 17.5f);
                    p.addRoundRect(r, 2f, 2f, Path.Direction.CW);
                    break;
                case I_REPLAY:
                    r.set(5f, 6f, 19f, 20f);
                    p.arcTo(r, -100f, 300f, true);
                    p.moveTo(14.66f, 8.48f); p.lineTo(10.79f, 6.11f); p.lineTo(13.62f, 2.56f);
                    break;
                case I_DROP:
                    p.moveTo(12f, 4f);
                    p.cubicTo(9f, 7.5f, 6.5f, 10.5f, 6.5f, 14f);
                    p.cubicTo(6.5f, 17.3f, 9f, 20f, 12f, 20f);
                    p.cubicTo(15f, 20f, 17.5f, 17.3f, 17.5f, 14f);
                    p.cubicTo(17.5f, 10.5f, 15f, 7.5f, 12f, 4f);
                    p.close();
                    p.moveTo(9.6f, 14.6f); p.quadTo(9.6f, 16.6f, 11.6f, 17.2f);
                    break;
                case I_SPEAKER:
                    p.moveTo(4f, 10f); p.lineTo(8f, 10f); p.lineTo(13f, 6f); p.lineTo(13f, 18f);
                    p.lineTo(8f, 14f); p.lineTo(4f, 14f); p.close();
                    r.set(9.5f, 8.5f, 16.5f, 15.5f);
                    p.arcTo(r, -45f, 90f, true);
                    r.set(6f, 5f, 20f, 19f);
                    p.arcTo(r, -45f, 90f, true);
                    break;
                case I_DOC:
                    p.moveTo(7f, 3.5f); p.lineTo(14f, 3.5f); p.lineTo(18.5f, 8f); p.lineTo(18.5f, 20.5f);
                    p.lineTo(7f, 20.5f); p.close();
                    p.moveTo(14f, 3.5f); p.lineTo(14f, 8f); p.lineTo(18.5f, 8f);
                    p.moveTo(9.5f, 12.5f); p.lineTo(16f, 12.5f);
                    p.moveTo(9.5f, 16f); p.lineTo(16f, 16f);
                    break;
                case I_PIN:
                    p.moveTo(9f, 4f); p.lineTo(15f, 4f);
                    p.moveTo(10f, 4f); p.lineTo(10f, 10f); p.lineTo(7.5f, 13f); p.lineTo(16.5f, 13f);
                    p.lineTo(14f, 10f); p.lineTo(14f, 4f);
                    p.moveTo(12f, 13f); p.lineTo(12f, 20f);
                    break;
                case I_TRASH:
                    p.moveTo(5f, 7f); p.lineTo(19f, 7f);
                    p.moveTo(9.5f, 7f); p.lineTo(9.5f, 4.8f); p.lineTo(14.5f, 4.8f); p.lineTo(14.5f, 7f);
                    p.moveTo(6.5f, 7f); p.lineTo(7.5f, 19f); p.lineTo(16.5f, 19f); p.lineTo(17.5f, 7f);
                    p.moveTo(10f, 10.5f); p.lineTo(10f, 16f);
                    p.moveTo(14f, 10.5f); p.lineTo(14f, 16f);
                    break;
                case I_CLOSE:
                    p.moveTo(6.5f, 6.5f); p.lineTo(17.5f, 17.5f);
                    p.moveTo(17.5f, 6.5f); p.lineTo(6.5f, 17.5f);
                    break;
                default:
                    break;
            }
            cv.drawPath(p, sp);
            if (icon == I_REPLAY && suffix != null) {
                tp.setTextSize("\u221E".equals(suffix) ? 10f : 8.5f);
                cv.drawText(suffix, 12f, "\u221E".equals(suffix) ? 16.4f : 16f, tp);
            }
            cv.restore();
        }
    }

    private TextView headBtn(String s, View.OnClickListener l) {
        // آیکونِ خطیِ برداری (مثلِ کادرِ ترجمه‌ی زنده) — به‌جای ایموجیِ نارنجی
        IconText t = new IconText(this);
        t.setText(s);
        t.setTextColor(Color.WHITE);
        t.setTextSize(17);
        t.setTextAlignment(View.TEXT_ALIGNMENT_TEXT_START);
        t.setTextDirection(View.TEXT_DIRECTION_FIRST_STRONG);
        t.setGravity(Gravity.CENTER);
        t.setMinWidth(dp(40));
        t.setMinHeight(dp(36));
        t.setOnClickListener(l);
        return t;
    }

    private TextView speakBtn() {
        IconText t = (IconText) headBtn("\uD83D\uDD0A", null);
        t.setIconDp(20f);
        return t;
    }

    private LinearLayout.LayoutParams matchWrap(int topDp) {
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.topMargin = dp(topDp);
        return lp;
    }

    private void applyPopupAlpha() {
        if (popupBg == null) return;
        int a = Math.round(Math.max(0f, Math.min(1f, panelAlpha)) * 255f);
        popupBg.setColor((a << 24) | panelRgb());
    }

    private void buildPopup() {
        fonts().load();
        panelAlpha = Math.max(0f, Math.min(1f, prefs().getFloat("panelAlphaV2", 1f)));
        popupHFrac = Math.max(POPUP_H_MIN, Math.min(POPUP_H_MAX, prefs().getFloat("magHFrac", POPUP_H_DEFAULT)));
        popup = new LinearLayout(this) {
            @Override public boolean dispatchTouchEvent(MotionEvent ev) {
                int a = ev.getActionMasked();
                if (a == MotionEvent.ACTION_DOWN || a == MotionEvent.ACTION_UP) armPopupTimer();   // هر لمس شمارش را از نو می‌کند
                return super.dispatchTouchEvent(ev);
            }
        };
        popup.setOrientation(LinearLayout.VERTICAL);
        popupBg = new GradientDrawable();
        popupBg.setCornerRadius(dp(16));
        popupBg.setStroke(dp(1), COLOR_GOLD);
        popup.setBackground(popupBg);
        applyPopupAlpha();
        popup.setPadding(dp(12), dp(4), dp(10), dp(12));
        popup.setClipToPadding(false);               // نوارِ دستگیره تا لبه‌ها (بیرون از padding) کشیده می‌شود
        popup.setClipToOutline(true);                // و گوشه‌های گردِ کادر آن را می‌برد
        popup.setElevation(dp(10));

        // نوارِ ابزار: 🔁 تکرار · 🌓 شفافیت · Aa فونت · 🌐 زبان‌ها · ✕ بستن
        // (فضای خالیِ نوار = دستگیره‌ی جابه‌جایی: بکش تا کادر هرجا خواستی برود)
        LinearLayout bar = new LinearLayout(this);
        bar.setOrientation(LinearLayout.HORIZONTAL);
        bar.setGravity(Gravity.CENTER_VERTICAL);
        bar.setLayoutDirection(View.LAYOUT_DIRECTION_LTR);
        // 🔁 تکرار و Aa فونت به نوارِ پایینِ کادر (کنار A−/A+) رفتند — makeGrip()
        tvRepeat = headBtn("\u21BA", v -> cycleRepeat());
        tvFontBtn = buildFontButton();
        bar.addView(headBtn("\uD83C\uDF13", v -> toggleOpacityRow()));

        // 🌐 «▾ FA / ES» = دکمه‌ی انتخابِ زبان‌های ترجمه (بزن → ردیفِ زبان‌ها باز می‌شود)
        tvLangPill = new TextView(this);
        tvLangPill.setTextColor(COLOR_GOLD);
        tvLangPill.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11);
        tvLangPill.setTypeface(Typeface.DEFAULT_BOLD);
        tvLangPill.setSingleLine(true);
        tvLangPill.setEllipsize(TextUtils.TruncateAt.MIDDLE);
        tvLangPill.setGravity(Gravity.CENTER);
        tvLangPill.setPadding(dp(8), dp(8), dp(8), dp(8));
        tvLangPill.setContentDescription(msg("زبان‌های ترجمه — برای تغییر بزنید",
                "Translation languages — tap to change"));
        tvLangPill.setOnClickListener(v -> toggleRow(langRow));
        LinearLayout langWrap = new LinearLayout(this);
        langWrap.setOrientation(LinearLayout.HORIZONTAL);
        langWrap.setLayoutDirection(View.LAYOUT_DIRECTION_LTR);
        langWrap.setGravity(Gravity.CENTER_VERTICAL);
        langWrap.addView(tvLangPill, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        LinearLayout.LayoutParams wrapLp = new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        wrapLp.setMarginStart(dp(4));
        bar.addView(langWrap, wrapLp);
        bar.addView(headBtn("\u2715", v -> clearSelection()));
        bar.setOnTouchListener(new PopupMover());
        popup.addView(bar);
        updateRepeatButton();

        // ردیف‌های بازشونده (فقط یکی باز می‌ماند): زبان‌ها · فونت · شفافیت
        popup.addView(buildLangRow(), matchWrap(0));
        popup.addView(buildFontRow(), matchWrap(0));

        opacityRow = new LinearLayout(this);
        opacityRow.setOrientation(LinearLayout.HORIZONTAL);
        opacityRow.setGravity(Gravity.CENTER_VERTICAL);
        opacityRow.setLayoutDirection(View.LAYOUT_DIRECTION_LTR);
        opacityRow.setVisibility(View.GONE);
        opacityBar = new SeekBar(this);
        opacityBar.setMax(100);
        opacityBar.setProgress(Math.round(panelAlpha * 100f));
        opacityBar.setProgressTintList(android.content.res.ColorStateList.valueOf(COLOR_GOLD));
        opacityBar.setThumbTintList(android.content.res.ColorStateList.valueOf(COLOR_GOLD));
        final TextView pct = txt(Math.round(panelAlpha * 100f) + "%", Color.WHITE, 12);
        pct.setMinWidth(dp(44));
        pct.setGravity(Gravity.CENTER);
        opacityBar.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override public void onProgressChanged(SeekBar sb, int progress, boolean fromUser) {
                panelAlpha = progress / 100f;
                pct.setText(progress + "%");
                applyPopupAlpha();
            }
            @Override public void onStartTrackingTouch(SeekBar sb) {}
            @Override public void onStopTrackingTouch(SeekBar sb) {
                prefs().edit().putFloat("panelAlphaV2", panelAlpha).apply();
            }
        });
        opacityRow.addView(opacityBar, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        opacityRow.addView(pct);
        popup.addView(opacityRow, matchWrap(0));

        // بدنه‌ی قابلِ اسکرول (ارتفاعش با دستگیره‌ی پایین تنظیم می‌شود): متنِ اصلی + 🔊 و ترجمه‌ها
        bodyScroll = new MaxHScroll(this);
        bodyScroll.setOverScrollMode(View.OVER_SCROLL_NEVER);
        bodyScroll.setVerticalScrollBarEnabled(false);
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);

        LinearLayout head = new LinearLayout(this);
        head.setOrientation(LinearLayout.HORIZONTAL);
        head.setGravity(Gravity.CENTER_VERTICAL);
        cardTerm = txt(selOrig, Color.WHITE, 16);
        fonts().style(cardTerm, 16, true);
        head.addView(cardTerm, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        termSpeak = speakBtn();
        termSpeak.setOnClickListener(v -> toggleSpeak(termSpeak, selOrig, selSrc));
        head.addView(termSpeak);
        body.addView(head, matchWrap(2));

        // ترجمه به همه‌ی زبان‌های انتخابی (هر ردیف 🔊 دارد)
        rowsBox = new LinearLayout(this);
        rowsBox.setOrientation(LinearLayout.VERTICAL);
        body.addView(rowsBox, matchWrap(0));
        fillRows(rowsBox, wholeResults);
        bodyScroll.addView(body, new ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        popup.addView(bodyScroll, matchWrap(2));

        // کادرِ لغت (اول بسته): لغت/محدوده + ترجمه‌ها + «ذخیره برای داستان بعدی / گرامر / لایتنر»
        buildWordCard();
        popup.addView(wordCard);

        TextView hint = txt(msg("روی یک لغت یا محدوده‌ی هایلایت‌شده بزنید (انگشت را روی چند لغت بکشید)",
                "Tap a word, or drag across several words in the highlighted text"),
                Color.parseColor("#8F98B8"), 11);
        popup.addView(hint, matchWrap(8));

        // 🗑 بستن/پاک‌کردنِ کادر و 📌 «باز بمان» — پایین-راستِ کادر (مثلِ کادرِ ترجمه‌ی زنده)
        magKeepOpen = prefs().getBoolean("magKeepOpen2", true);
        LinearLayout pinRow = new LinearLayout(this);
        pinRow.setOrientation(LinearLayout.HORIZONTAL);
        pinRow.setLayoutDirection(View.LAYOUT_DIRECTION_LTR);
        pinRow.setGravity(Gravity.CENTER_VERTICAL);
        pinRow.addView(new View(this), new LinearLayout.LayoutParams(0, 1, 1f));
        TextView tvClear = new IconText(this);
        tvClear.setText("\uD83D\uDDD1");
        tvClear.setTextColor(Color.WHITE);
        tvClear.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        tvClear.setGravity(Gravity.CENTER);
        tvClear.setPadding(dp(8), dp(3), dp(8), dp(3));
        tvClear.setAlpha(0.8f);
        tvClear.setContentDescription(msg("بستنِ کادر", "Close"));
        tvClear.setOnClickListener(v -> clearSelection());
        pinRow.addView(tvClear);
        tvPin = new IconText(this);
        tvPin.setText("\uD83D\uDCCC");
        tvPin.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        tvPin.setGravity(Gravity.CENTER);
        tvPin.setPadding(dp(8), dp(3), dp(8), dp(3));
        tvPin.setContentDescription(msg("باز بماند", "Keep open"));
        tvPin.setOnClickListener(v -> toggleKeepOpen());
        updatePinUi();
        pinRow.addView(tvPin);
        popup.addView(pinRow, matchWrap(2));

        // نوارِ باریکِ طلاییِ شمارشِ بسته‌شدنِ خودکارِ کادر
        popupBar = new View(this);
        GradientDrawable pbg = new GradientDrawable();
        pbg.setColor(COLOR_GOLD);
        pbg.setCornerRadius(dp(2));
        popupBar.setBackground(pbg);
        LinearLayout.LayoutParams pbLp = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(2));
        pbLp.topMargin = dp(6);
        popup.addView(popupBar, pbLp);

        // نوارِ دستگیره (پایینِ کادر): کشیدنِ عمودی = ارتفاع ، افقی = جابه‌جایی ، A−/A+ = اندازه‌ی متن
        View grip = makeGrip();
        LinearLayout.LayoutParams gLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(30));
        gLp.setMargins(-dp(12), dp(8), -dp(10), -dp(12));
        popup.addView(grip, gLp);

        applyScrollMax();
        refreshLangPill();
        refreshFontChips();
        paintFontButton();
    }

    private void toggleOpacityRow() { toggleRow(opacityRow); }

    // 🔁 تکرارِ خوانش: خاموش ← ۲ ← ۳ ← ∞ (همان تنظیمِ حبابِ ترجمه‌ی زنده)
    private int repeatSetting() {
        int v = prefs().getInt("repeatSetting", 0);
        return (v == 2 || v == 3 || v == REPEAT_INF) ? v : 0;
    }

    private void cycleRepeat() {
        int r = repeatSetting();
        r = r == 0 ? 2 : r == 2 ? 3 : r == 3 ? REPEAT_INF : 0;
        prefs().edit().putInt("repeatSetting", r).apply();
        updateRepeatButton();
        toast(r == 0 ? msg("تکرار خاموش", "Repeat off")
                : r == REPEAT_INF ? msg("تکرار ∞ — تا وقتی ⏹ نزنید", "Repeat ∞ — until you press ⏹")
                : msg("هر خوانش " + r + " بار", "Each reading " + r + "×"));
    }

    private void updateRepeatButton() {
        if (tvRepeat == null) return;
        int r = repeatSetting();
        tvRepeat.setText(r == 0 ? "\u21BA" : r == REPEAT_INF ? "\u21BA\u221E" : "\u21BA" + r);
        tvRepeat.setTextColor(r == 0 ? Color.WHITE : COLOR_GOLD);
        tvRepeat.setAlpha(r == 0 ? 0.6f : 1f);
    }

    private TextView cardAction(View.OnClickListener l) {
        TextView b = txt("", Color.WHITE, 12);
        b.setPadding(dp(10), dp(6), dp(10), dp(6));
        b.setOnClickListener(l);
        styleCardAction(b, false);
        return b;
    }

    private void styleCardAction(TextView b, boolean done) {
        GradientDrawable g = new GradientDrawable();
        g.setColor(Color.parseColor("#14FFFFFF"));
        g.setCornerRadius(dp(8));
        g.setStroke(dp(1), done ? COLOR_GOLD : Color.parseColor("#40FFFFFF"));
        b.setBackground(g);
        b.setTextColor(done ? COLOR_GOLD : Color.WHITE);
    }

    // ── ⏳ بستنِ خودکارِ کادرِ لغت: ۶ ثانیه بعد از باز شدن؛ اگر یکی از دکمه‌های افزودن زده شد، ۴ ثانیه بعد از آن.
    //    هر لمس داخلِ کادر شمارش را از نو می‌کند. نوارِ باریکِ طلاییِ پایینِ کادر زمانِ باقی‌مانده را نشان می‌دهد.
    private static final long POPUP_IDLE_CLOSE_MS = 10000;
    private View popupBar;
    private TextView tvPin;
    private boolean magKeepOpen = true;
    private long popupDeadline = 0;

    private void toggleKeepOpen() {
        magKeepOpen = !magKeepOpen;
        prefs().edit().putBoolean("magKeepOpen2", magKeepOpen).apply();
        updatePinUi();
        armPopupTimer();
        toast(magKeepOpen ? msg("کادر باز می‌ماند تا خودت ببندی", "Panel stays open until you close it")
                          : msg("بسته‌شدنِ خودکارِ کادر دوباره فعال شد", "Auto-close is back on"));
    }

    private void updatePinUi() {
        if (tvPin == null) return;
        tvPin.setAlpha(magKeepOpen ? 1f : 0.5f);
        tvPin.setTextColor(magKeepOpen ? COLOR_GOLD : Color.WHITE);
        GradientDrawable bg = new GradientDrawable();
        bg.setCornerRadius(dp(10));
        bg.setColor(magKeepOpen ? Color.parseColor("#55F2C14E") : Color.parseColor("#1AFFFFFF"));
        if (magKeepOpen) bg.setStroke(dp(1), COLOR_GOLD);
        tvPin.setBackground(bg);
    }
    private final Runnable popupTick = new Runnable() {
        @Override public void run() {
            main.removeCallbacks(this);
            if (popup == null) return;
            if (magKeepOpen) {                                      // 📌 سنجاق: بسته نشود
                if (popupBar != null) popupBar.setVisibility(View.INVISIBLE);
                return;
            }
            long now = android.os.SystemClock.uptimeMillis();
            // وسطِ خوانشِ 🔊، یا وقتی کادرِ لغت باز است (تایمرِ خودش را دارد)، یا وسطِ کارِ ذره‌بین نبند
            if (speakingBtn != null || busy || (wordCard != null && wordCard.getVisibility() == View.VISIBLE)) {
                popupDeadline = now + POPUP_IDLE_CLOSE_MS;
                if (popupBar != null) {
                    popupBar.setScaleX(1f); popupBar.setAlpha(1f);
                    // وسطِ خوانش (و تکرارها) نوارِ طلایی دیده نمی‌شود؛ بعد از پایانِ تکرار ظاهر می‌شود و شمارش شروع می‌شود
                    popupBar.setVisibility(speakingBtn != null ? View.INVISIBLE : View.VISIBLE);
                }
                main.postDelayed(this, 100);
                return;
            }
            float left = (popupDeadline - now) / (float) POPUP_IDLE_CLOSE_MS;
            if (left <= 0f) { clearSelection(); return; }
            left = Math.min(1f, left);
            if (popupBar != null) {
                if (popupBar.getVisibility() != View.VISIBLE) popupBar.setVisibility(View.VISIBLE);
                popupBar.setPivotX(popupBar.getWidth() / 2f);
                popupBar.setScaleX(left);
                popupBar.setAlpha(0.55f + 0.45f * left);
            }
            main.postDelayed(this, 33);
        }
    };

    private void armPopupTimer() {
        popupDeadline = android.os.SystemClock.uptimeMillis() + POPUP_IDLE_CLOSE_MS;
        main.removeCallbacks(popupTick);
        if (popupBar != null) {
            popupBar.setVisibility(magKeepOpen ? View.INVISIBLE : View.VISIBLE);
            popupBar.setScaleX(1f); popupBar.setAlpha(1f);
        }
        if (popup != null) main.post(popupTick);
    }

    private static final long CARD_IDLE_CLOSE_MS = 6000;
    private static final long CARD_ACTION_CLOSE_MS = 4000;
    private View cardBar;
    private boolean cardActed = false;
    private long cardDeadline = 0, cardSpan = CARD_IDLE_CLOSE_MS;
    private final Runnable cardTick = new Runnable() {
        @Override public void run() {
            main.removeCallbacks(this);
            if (wordCard == null || wordCard.getVisibility() != View.VISIBLE) return;
            long now = android.os.SystemClock.uptimeMillis();
            if (speakingBtn != null) {                              // وسطِ خوانشِ 🔊 کادر نبند؛ بعد از پایانِ خوانش شمارش از نو
                cardDeadline = now + cardSpan;
                if (cardBar != null) { cardBar.setScaleX(1f); cardBar.setAlpha(1f); cardBar.setVisibility(View.INVISIBLE); }
                main.postDelayed(this, 100);
                return;
            }
            float left = (cardDeadline - now) / (float) Math.max(1L, cardSpan);
            if (left <= 0f) { closeWordCard(); return; }
            left = Math.min(1f, left);
            if (cardBar != null) {
                if (cardBar.getVisibility() != View.VISIBLE) cardBar.setVisibility(View.VISIBLE);
                cardBar.setPivotX(cardBar.getWidth() / 2f);
                cardBar.setScaleX(left);
                cardBar.setAlpha(0.55f + 0.45f * left);
            }
            main.postDelayed(this, 33);
        }
    };

    /** شمارشِ بسته‌شدن را از نو شروع می‌کند (۶ ثانیه؛ بعد از زدنِ یکی از دکمه‌های افزودن ۴ ثانیه). */
    private void armCardTimer() {
        cardSpan = cardActed ? CARD_ACTION_CLOSE_MS : CARD_IDLE_CLOSE_MS;
        cardDeadline = android.os.SystemClock.uptimeMillis() + cardSpan;
        main.removeCallbacks(cardTick);
        if (cardBar != null) { cardBar.setScaleX(1f); cardBar.setAlpha(1f); cardBar.setVisibility(speakingBtn != null ? View.INVISIBLE : View.VISIBLE); }
        if (wordCard != null && wordCard.getVisibility() == View.VISIBLE) main.post(cardTick);
    }

    private void markCardActed() { cardActed = true; armCardTimer(); }

    private void buildWordCard() {
        wordCard = new LinearLayout(this) {
            @Override public boolean dispatchTouchEvent(MotionEvent ev) {
                if (ev.getActionMasked() == MotionEvent.ACTION_DOWN) armCardTimer();   // هر لمسِ داخلِ کارت شمارش را از نو می‌کند
                return super.dispatchTouchEvent(ev);
            }
        };
        wordCard.setOrientation(LinearLayout.VERTICAL);
        wordCard.setPadding(dp(10), dp(6), dp(8), dp(10));
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(wordCardBgColor());
        bg.setCornerRadius(dp(12));
        bg.setStroke(dp(1), COLOR_GOLD);
        wordCard.setBackground(bg);
        wordCard.setVisibility(View.GONE);
        wordCard.setLayoutParams(matchWrap(10));

        LinearLayout top = new LinearLayout(this);
        top.setOrientation(LinearLayout.HORIZONTAL);
        top.setGravity(Gravity.CENTER_VERTICAL);
        wordTerm = txt("", Color.WHITE, 17);
        wordTerm.setTypeface(wordTerm.getTypeface(), android.graphics.Typeface.BOLD);
        top.addView(wordTerm, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        wordSpeak = speakBtn();
        wordSpeak.setOnClickListener(v -> toggleSpeak(wordSpeak, cardWord, selSrc));
        top.addView(wordSpeak);
        TextView cardX = headBtn("\u2715", v -> closeWordCard());
        ((IconText) cardX).setIconDp(13f);
        cardX.setTextSize(12);
        cardX.setMinWidth(dp(26));
        cardX.setMinHeight(dp(26));
        GradientDrawable xbg = new GradientDrawable();
        xbg.setShape(GradientDrawable.OVAL);
        xbg.setColor(Color.parseColor("#1AFFFFFF"));
        xbg.setStroke(dp(1), Color.parseColor("#47FFFFFF"));
        cardX.setBackground(xbg);
        LinearLayout.LayoutParams xlp = new LinearLayout.LayoutParams(dp(26), dp(26));
        xlp.leftMargin = dp(4);
        top.addView(cardX, xlp);
        wordCard.addView(top);

        wordRows = new LinearLayout(this);
        wordRows.setOrientation(LinearLayout.VERTICAL);
        wordCard.addView(wordRows, matchWrap(0));

        cardBtnStory = cardAction(v -> onCardStory());
        cardBtnGrammar = cardAction(v -> onCardGrammar());
        cardBtnLeitner = cardAction(v -> onCardLeitner());
        for (TextView b : new TextView[]{cardBtnStory, cardBtnGrammar, cardBtnLeitner}) {
            LinearLayout.LayoutParams lp = matchWrap(6);
            lp.rightMargin = dp(2);
            wordCard.addView(b, lp);
        }
        // نوارِ باریکِ طلاییِ شمارشِ بسته‌شدنِ خودکار
        cardBar = new View(this);
        GradientDrawable cbg = new GradientDrawable();
        cbg.setColor(COLOR_GOLD);
        cbg.setCornerRadius(dp(2));
        cardBar.setBackground(cbg);
        LinearLayout.LayoutParams cbLp = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(2));
        cbLp.topMargin = dp(8);
        wordCard.addView(cardBar, cbLp);
    }

    /** ✕ی کادرِ لغت: فقط کادرِ «ذخیره برای داستان بعدی / گرامر / لایتنر» را می‌بندد؛ پنجره‌ی ترجمه می‌ماند. */
    private void closeWordCard() {
        main.removeCallbacks(cardTick);
        cardSeq++;
        stopSpeech();
        if (wordCard != null) wordCard.setVisibility(View.GONE);
        applyScrollMax();
        placePopup();
    }

    private void refreshCardButtons() {
        if (cardBtnStory == null) return;
        cardBtnStory.setText(cardStoryDone
                ? msg("\uD83D\uDD16 ذخیره شد برای داستان بعدی", "\uD83D\uDD16 Saved for next story")
                : msg("\uD83D\uDD16 ذخیره برای داستان بعدی", "\uD83D\uDD16 Save for next story"));
        cardBtnGrammar.setText(cardGrammarDone
                ? msg("\uD83E\uDDE9 ذخیره شد در گرامر", "\uD83E\uDDE9 Saved to grammar")
                : msg("\uD83E\uDDE9 افزودن به یادگیری گرامر", "\uD83E\uDDE9 Add to grammar learning"));
        cardBtnLeitner.setText(cardLeitnerDone
                ? msg("به جعبه‌ی لایتنر اضافه شد", "Added to Leitner box")
                : msg("افزودن به جعبه‌ی لایتنر", "Add to Leitner box"));
        styleCardAction(cardBtnStory, cardStoryDone);
        styleCardAction(cardBtnGrammar, cardGrammarDone);
        styleCardAction(cardBtnLeitner, cardLeitnerDone);
    }

    /** ردیف‌های ترجمه: [کدِ زبان، متن]؛ هر ردیف 🔊ِ همان زبان دارد. */
    private void fillRows(LinearLayout box, List<String[]> rows) {
        if (box == null) return;
        box.removeAllViews();
        for (String[] r : rows) {
            if (!r[0].isEmpty() && r[0].equalsIgnoreCase(selSrc)) continue;   // مبدأ = مقصد: ترجمه‌ی هم‌زبان نشان داده نمی‌شود
            LinearLayout row = new LinearLayout(this);
            row.setOrientation(LinearLayout.HORIZONTAL);
            row.setGravity(Gravity.CENTER_VERTICAL);
            final String lg = r[0], tx = r[1];
            if (!lg.isEmpty()) {
                TextView lab = txt(lg.toUpperCase(Locale.ROOT), COLOR_GOLD, 11);
                lab.setTypeface(lab.getTypeface(), android.graphics.Typeface.BOLD);
                lab.setMinWidth(dp(28));
                row.addView(lab);
            }
            TextView t = txt(tx, Color.parseColor("#E8EAF2"), 15);
            fonts().style(t, 15, false);
            row.addView(t, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
            if (!lg.isEmpty()) {
                final TextView sp = speakBtn();
                sp.setOnClickListener(v -> toggleSpeak(sp, tx, lg));
                row.addView(sp);
            }
            box.addView(row, matchWrap(4));
        }
    }

    // 🔊 خوانش با همان سیستمِ خوانشِ اپ (Piper اگر بسته‌ی زبان دانلود شده، وگرنه TTS گوشی) — برای هر زبانی؛ با تکرارِ 🔁
    private void stopSpeech() {
        speakTok++;
        if (speakingBtn != null) { speakingBtn.setText("\uD83D\uDD0A"); speakingBtn.setTextColor(Color.WHITE); speakingBtn = null; }
        try { PanelTts.stop(this); } catch (Throwable ignored) {}
        if (popup != null && popupBar != null) armPopupTimer();      // خوانش تمام/قطع شد → نوارِ طلاییِ بسته‌شدنِ خودکار ظاهر شود
        if (wordCard != null && wordCard.getVisibility() == View.VISIBLE && cardBar != null) armCardTimer();
    }

    private void toggleSpeak(final TextView b, String text, String lang) {
        if (text == null || text.trim().isEmpty() || "…".equals(text) || "—".equals(text)) return;
        if (speakingBtn == b) { stopSpeech(); return; }
        stopSpeech();
        speakingBtn = b;
        b.setText("\u23F9");
        b.setTextColor(COLOR_GOLD);
        speakLoop(b, text, lang, ++speakTok, 0);
    }

    private void speakLoop(final TextView b, final String text, final String lang, final int token, final int done) {
        PanelTts.speak(this, text, lang, 1.0f, ok -> main.post(() -> {
            if (token != speakTok) return;
            int rep = repeatSetting();
            int cap = rep == 0 ? 1 : rep == REPEAT_INF ? Integer.MAX_VALUE : rep;
            final int n = done + 1;
            if (ok && n < cap) {
                main.postDelayed(() -> { if (token == speakTok) speakLoop(b, text, lang, token, n); }, 700);
            } else {
                if (speakingBtn != null) { speakingBtn.setText("\uD83D\uDD0A"); speakingBtn.setTextColor(Color.WHITE); speakingBtn = null; }
                // همه‌ی تکرارها تمام شد → نوارِ طلاییِ بسته‌شدنِ خودکار ظاهر می‌شود و شمارش شروع می‌شود
                if (popup != null && popupBar != null) armPopupTimer();
                if (wordCard != null && wordCard.getVisibility() == View.VISIBLE && cardBar != null) armCardTimer();
            }
        }));
    }

    /** لغت/محدوده‌ی انتخاب‌شده (یا کلِ متن با 📄) ← کادرِ لغت باز می‌شود. */
    private void onRangePicked(int i, int j, ArrayList<ElemInfo> el) {
        if (popup == null || wordCard == null || el == null || el.isEmpty()) return;
        final boolean whole = (i == 0 && j == el.size() - 1);
        String word;
        if (whole) {
            word = selOrig;
        } else {
            StringBuilder sb = new StringBuilder();
            for (int k = i; k <= j && k < el.size(); k++) {
                if (sb.length() > 0) sb.append(' ');
                sb.append(el.get(k).t);
            }
            word = sb.toString().trim().replaceAll("^[\\p{Punct}\\u2018\\u2019\\u201C\\u201D]+|[\\p{Punct}\\u2018\\u2019\\u201C\\u201D]+$", "");
        }
        if (word.isEmpty()) return;
        armPopupTimer();
        stopSpeech();
        final int my = ++cardSeq;
        cardWord = word;
        cardMeaning = "";
        cardMeaningLang = "fa";
        cardStoryDone = cardGrammarDone = cardLeitnerDone = false;
        wordTerm.setText(word);
        fonts().apply(wordTerm);
        wordCard.setVisibility(View.VISIBLE);
        applyScrollMax();
        cardActed = false;
        armCardTimer();                        // ⏳ ۶ ثانیه تا بسته‌شدنِ خودکار (نوارِ طلایی)
        refreshCardButtons();

        if (whole && !wholeResults.isEmpty()) {           // ترجمه‌ی کلِ متن را از قبل داریم
            fillRows(wordRows, wholeResults);
            adoptMeaning(wholeResults);
            placePopup();
            return;
        }
        ArrayList<String[]> wait = new ArrayList<>();
        wait.add(new String[]{"", "…"});
        fillRows(wordRows, wait);
        placePopup();

        requestWordMeanings(my, word);
    }

    /** ترجمه‌ی لغت/محدوده به همه‌ی زبان‌های انتخابی (پس‌زمینه) ← ردیف‌های کادرِ لغت. */
    private void requestWordMeanings(final int my, final String w2) {
        final String from = selSrc;
        final List<String> tg = targets(from);
        runSafe(() -> {
            final ArrayList<String[]> out = new ArrayList<>();
            for (String t : tg) {
                String r;
                try { r = translateOne(w2, from, t); }
                catch (Exception ex) { r = ""; }
                out.add(new String[]{t, (r == null || r.trim().isEmpty()) ? "—" : r.trim()});
            }
            main.post(() -> onWordMeanings(my, out));
        });
    }

    private void adoptMeaning(List<String[]> rows) {
        for (String[] r : rows) {
            if (!"—".equals(r[1]) && !r[1].isEmpty()) { cardMeaningLang = r[0]; cardMeaning = r[1]; return; }
        }
    }

    private void onWordMeanings(int token, List<String[]> rows) {
        if (token != cardSeq || wordRows == null) return;
        fillRows(wordRows, rows);
        adoptMeaning(rows);
        if (cardStoryDone) queueWord("story");
        if (cardLeitnerDone) queueWord("leitner");
        placePopup();
        startWordReview(token, cardWord, new ArrayList<>(rows));
    }

    private void queueWord(String action) {
        if (cardWord == null || cardWord.isEmpty()) return;
        try {
            JSONObject o = new JSONObject()
                    .put("key", action + "|" + selSrc + "|" + cardWord.toLowerCase(Locale.ROOT))
                    .put("action", action)
                    .put("word", cardWord)
                    .put("lang", selSrc)
                    .put("meaning", cardMeaning == null ? "" : cardMeaning)
                    .put("meaningLang", cardMeaningLang == null ? "fa" : cardMeaningLang)
                    .put("sentence", selOrig == null || selOrig.isEmpty() ? cardWord : selOrig)
                    .put("rev", System.currentTimeMillis());
            WordQueue.add(this, o);
            BubblePlugin.notifyWordQueued();
        } catch (Throwable t) {
            toast(msg("ذخیره نشد", "Save failed"));
        }
    }

    private void onCardStory()   { markCardActed(); if (cardStoryDone) return;   cardStoryDone = true;   queueWord("story");   refreshCardButtons(); }
    private void onCardGrammar() { markCardActed(); if (cardGrammarDone) return; cardGrammarDone = true; queueWord("grammar"); refreshCardButtons(); }
    private void onCardLeitner() { markCardActed(); if (cardLeitnerDone) return; cardLeitnerDone = true; queueWord("leitner"); refreshCardButtons(); }

    private void toast(String s) { Toast.makeText(getApplicationContext(), s, Toast.LENGTH_SHORT).show(); }

    private int dp(float v) { return Math.round(v * getResources().getDisplayMetrics().density); }

    // ═══════════════════════════════════════════════════════════════════════
    //  🔎 اندازه، جابه‌جایی، فونت و زبانِ کادرِ ترجمه (مثلِ کادرِ ترجمه‌ی زنده)
    // ═══════════════════════════════════════════════════════════════════════

    private OverlayFonts fonts() {
        if (fonts == null) fonts = new OverlayFonts(this, PREFS);
        return fonts;
    }

    /** ScrollView با سقفِ ارتفاع (برای دستگیره‌ی تغییرِ اندازه). */
    private static final class MaxHScroll extends ScrollView {
        int maxH = Integer.MAX_VALUE;

        MaxHScroll(Context c) { super(c); }

        @Override protected void onMeasure(int wSpec, int hSpec) {
            int mode = MeasureSpec.getMode(hSpec), size = MeasureSpec.getSize(hSpec);
            int lim = mode == MeasureSpec.UNSPECIFIED ? maxH : Math.min(maxH, size);
            super.onMeasure(wSpec, MeasureSpec.makeMeasureSpec(lim, MeasureSpec.AT_MOST));
        }
    }

    private void applyScrollMax() {
        if (bodyScroll == null) return;
        boolean compact = wordCard != null && wordCard.getVisibility() == View.VISIBLE;
        int base = Math.max(dp(60), (int) (capH * popupHFrac));
        bodyScroll.maxH = compact ? Math.max(dp(90), (int) (base * 0.55f)) : base;
        bodyScroll.requestLayout();
    }

    /** ردیفِ زبان / فونت / شفافیت: هر کدام که باز شد بقیه بسته می‌شوند. */
    private void toggleRow(View row) {
        if (row == null) return;
        boolean show = row.getVisibility() != View.VISIBLE;
        if (show) {
            View[] all = {opacityRow, langRow, fontRow};
            for (View r : all) if (r != null && r != row) r.setVisibility(View.GONE);
        }
        row.setVisibility(show ? View.VISIBLE : View.GONE);
        refreshLangPill();
        paintFontButton();
        placePopup();
    }

    // ───────── 🌐 انتخابِ زبانِ ترجمه از داخلِ خودِ کادر ─────────
    private static final String[] PICK_LANGS = {"en", "es", "de", "fr", "fa", "it", "ar", "tr", "ru", "hi", "zh", "ja", "ko"};
    private static final String[] PICK_LANGS_FA = {"انگلیسی", "اسپانیایی", "آلمانی", "فرانسوی", "فارسی", "ایتالیایی", "عربی", "ترکی", "روسی", "هندی", "چینی", "ژاپنی", "کره‌ای"};
    private static final String[] PICK_LANGS_EN = {"English", "Spanish", "German", "French", "Persian", "Italian", "Arabic", "Turkish", "Russian", "Hindi", "Chinese", "Japanese", "Korean"};

    private View buildLangRow() {
        langRow = new LinearLayout(this);
        langRow.setOrientation(LinearLayout.VERTICAL);
        langRow.setLayoutDirection(View.LAYOUT_DIRECTION_LTR);
        langRow.setVisibility(View.GONE);
        langRow.setPadding(0, dp(4), 0, dp(6));
        langChips.clear();

        HorizontalScrollView hs = new HorizontalScrollView(this);
        hs.setHorizontalScrollBarEnabled(false);
        hs.setOverScrollMode(View.OVER_SCROLL_NEVER);
        LinearLayout chips = new LinearLayout(this);
        chips.setOrientation(LinearLayout.HORIZONTAL);
        chips.setLayoutDirection(View.LAYOUT_DIRECTION_LTR);
        final boolean fa = uiFa();
        for (int i = 0; i < PICK_LANGS.length; i++) {
            final String code = PICK_LANGS[i];
            TextView c = new TextView(this);
            c.setTag(code);
            c.setText(code.toUpperCase(Locale.ROOT));
            c.setContentDescription(fa ? PICK_LANGS_FA[i] : PICK_LANGS_EN[i]);
            c.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
            c.setTypeface(Typeface.DEFAULT_BOLD);
            c.setGravity(Gravity.CENTER);
            c.setSingleLine(true);
            c.setMinWidth(dp(46));
            c.setPadding(dp(12), dp(6), dp(12), dp(6));
            c.setOnClickListener(v -> onPickLang(code));
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            lp.setMarginEnd(dp(6));
            chips.addView(c, lp);
            langChips.add(c);
        }
        hs.addView(chips, new ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        langRow.addView(hs, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        paintLangChips();
        return langRow;
    }

    /** همه‌ی زبان‌های انتخابی (بدونِ حذفِ زبانِ متن) به همان ترتیبِ انتخاب. */
    private ArrayList<String> pickedTargets() {
        ArrayList<String> out = new ArrayList<>();
        String csv = prefs().getString("targets", "");
        if (csv != null) {
            for (String t : csv.split(",")) {
                t = t.trim().toLowerCase(Locale.ROOT);
                if (!t.isEmpty() && !out.contains(t)) out.add(t);
            }
        }
        if (out.isEmpty()) out.add(prefs().getString("target", "fa"));
        return out;
    }

    /** روشن = طلایی؛ خاموش = شیشه‌ای؛ زبانِ خودِ متن کم‌رنگ (ترجمه‌ی هم‌زبان بی‌معنی است). */
    private void paintLangChips() {
        if (langChips.isEmpty()) return;
        final List<String> picked = pickedTargets();
        for (TextView c : langChips) {
            final String code = (String) c.getTag();
            final boolean on = picked.contains(code);
            GradientDrawable g = new GradientDrawable();
            g.setCornerRadius(dp(14));
            g.setColor(on ? COLOR_GOLD : Color.parseColor("#26FFFFFF"));
            c.setBackground(g);
            c.setTextColor(on ? COLOR_INK : Color.WHITE);
            c.setAlpha(1f);
        }
    }

    private void refreshLangPill() {
        if (tvLangPill == null) return;
        final boolean open = langRow != null && langRow.getVisibility() == View.VISIBLE;
        StringBuilder sb = new StringBuilder(open ? "\u25B4 " : "\u25BE ");
        List<String> ts = targets(selSrc);
        for (int i = 0; i < ts.size(); i++) sb.append(i == 0 ? "" : " / ").append(ts.get(i).toUpperCase(Locale.ROOT));
        tvLangPill.setText(sb.toString());
        tvLangPill.setAlpha(open ? 1f : 0.85f);
        paintLangChips();
    }

    private void onPickLang(String code) {
        final ArrayList<String> list = pickedTargets();
        if (list.contains(code)) {
            list.remove(code);
            if (list.isEmpty()) {
                toast(msg("حداقل یک زبان باید روشن بماند", "Keep at least one language on"));
                return;
            }
        } else {
            list.add(code);
        }
        StringBuilder csv = new StringBuilder();
        for (String t : list) { if (csv.length() > 0) csv.append(','); csv.append(t); }
        // پرچمِ dirty: اپ (حتی اگر الان بسته باشد) دفعه‌ی بعد این انتخاب را برمی‌دارد
        prefs().edit()
                .putString("targets", csv.toString())
                .putBoolean("targetsDirty", true)
                .putLong("targetsDirtyAt", System.currentTimeMillis())
                .apply();
        try { BubblePlugin.notifyTargetsChanged(); } catch (Throwable ignored) {}
        refreshLangPill();
        retranslateAll();
    }

    /** بعد از تغییرِ زبان‌ها: ترجمه‌ی کلِ متن (و لغتِ بازِ کادر) دوباره برای زبان‌های تازه ساخته می‌شود. */
    private void retranslateAll() {
        if (popup == null || rowsBox == null || selOrig == null || selOrig.isEmpty()) return;
        final int my = ++langSeq;
        final String from = selSrc, orig = selOrig;
        final List<String> tg = targets(from);
        ArrayList<String[]> wait = new ArrayList<>();
        for (String t : tg) wait.add(new String[]{t, "…"});
        wholeResults.clear();
        wholeResults.addAll(wait);
        fillRows(rowsBox, wholeResults);
        boolean cardOpen = wordCard != null && wordCard.getVisibility() == View.VISIBLE && wordRows != null;
        if (cardOpen) {
            if (cardWord.equals(selOrig)) {
                fillRows(wordRows, wholeResults);
            } else {
                ArrayList<String[]> w2 = new ArrayList<>();
                w2.add(new String[]{"", "…"});
                fillRows(wordRows, w2);
                requestWordMeanings(cardSeq, cardWord);
            }
            armCardTimer();
        }
        placePopup();
        bg(() -> {
            final ArrayList<String[]> out = new ArrayList<>();
            for (String t : tg) {
                String r;
                try { r = translateOne(orig, from, t); }
                catch (Exception ex) { r = null; }
                out.add(new String[]{t, (r == null || r.trim().isEmpty()) ? "—" : r.trim()});
            }
            main.post(() -> {
                if (my != langSeq || popup == null || rowsBox == null) return;
                wholeResults.clear();
                wholeResults.addAll(out);
                fillRows(rowsBox, wholeResults);
                if (wordCard != null && wordCard.getVisibility() == View.VISIBLE && wordRows != null
                        && cardWord.equals(selOrig)) {
                    fillRows(wordRows, wholeResults);
                    adoptMeaning(wholeResults);
                }
                placePopup();
                startWholeReview(out);
            });
        });
    }

    /** کارِ پس‌زمینه‌ی بی‌صدا (خطا فقط لاگ می‌شود؛ ذره‌بین و حالتِ «busy» دست نمی‌خورد). */
    private void bg(final Runnable r) {
        try {
            worker.execute(() -> {
                try { r.run(); } catch (Throwable t) { Log.w(TAG, "background task failed", t); }
            });
        } catch (Exception ignored) { /* سرویس در حال بسته شدن است */ }
    }

    // ───────── Aa فونت + A−/A+ اندازه‌ی متن ─────────

    private TextView buildFontButton() {
        TextView t = new TextView(this);
        SpannableString sp = new SpannableString("Aa");
        sp.setSpan(new android.text.style.RelativeSizeSpan(0.78f), 1, 2, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
        t.setText(sp);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
        t.setTypeface(Typeface.DEFAULT_BOLD);
        t.setGravity(Gravity.CENTER);
        t.setPadding(dp(11), dp(4), dp(11), dp(4));
        t.setContentDescription(msg("تغییرِ فونت", "Change font"));
        t.setOnClickListener(v -> toggleRow(fontRow));
        t.setOnLongClickListener(v -> { resetView(); return true; });
        paintFontButton(t, false);
        return t;
    }

    private void paintFontButton(TextView t, boolean active) {
        GradientDrawable g = new GradientDrawable();
        g.setCornerRadius(dp(14));
        g.setColor(active ? COLOR_GOLD : Color.parseColor("#1AFFFFFF"));
        g.setStroke(dp(1), active ? COLOR_GOLD : Color.parseColor("#40FFFFFF"));
        t.setBackground(g);
        t.setTextColor(active ? COLOR_INK : Color.WHITE);
    }

    private void paintFontButton() {
        if (tvFontBtn == null) return;
        paintFontButton(tvFontBtn, fontRow != null && fontRow.getVisibility() == View.VISIBLE);
    }

    private View buildFontRow() {
        fontRow = new LinearLayout(this);
        fontRow.setOrientation(LinearLayout.VERTICAL);
        fontRow.setLayoutDirection(View.LAYOUT_DIRECTION_LTR);
        fontRow.setVisibility(View.GONE);
        fontRow.setPadding(0, dp(2), 0, dp(6));
        appFontChips.clear();

        HorizontalScrollView hs = new HorizontalScrollView(this);
        hs.setHorizontalScrollBarEnabled(false);
        hs.setOverScrollMode(View.OVER_SCROLL_NEVER);
        LinearLayout chips = new LinearLayout(this);
        chips.setOrientation(LinearLayout.HORIZONTAL);
        chips.setLayoutDirection(View.LAYOUT_DIRECTION_LTR);
        final boolean fa = uiFa();
        for (int i = 0; i < OverlayFonts.APP_FONT_IDS.length; i++) {
            final String id = OverlayFonts.APP_FONT_IDS[i];
            TextView c = new TextView(this);
            c.setTag(id);
            c.setText(fonts().presetChipText(id));
            c.setContentDescription(fa ? OverlayFonts.APP_FONT_FA[i] : OverlayFonts.APP_FONT_EN[i]);
            c.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
            c.setGravity(Gravity.CENTER);
            c.setMaxLines(1);
            c.setMinWidth(dp(48));
            c.setLineSpacing(0f, 1.05f);
            c.setTextDirection(View.TEXT_DIRECTION_LTR);
            c.setPadding(dp(12), dp(6), dp(12), dp(6));
            c.setOnClickListener(v -> pickAppFont(id));
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            lp.setMarginEnd(dp(6));
            chips.addView(c, lp);
            appFontChips.add(c);
        }
        hs.addView(chips, new ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        fontRow.addView(hs, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        refreshFontChips();
        return fontRow;
    }

    private void refreshFontChips() {
        String sel = fonts().currentAppFont();
        for (TextView c : appFontChips) {
            boolean on = sel.equals(c.getTag());
            GradientDrawable g = new GradientDrawable();
            g.setCornerRadius(dp(14));
            g.setColor(on ? COLOR_GOLD : Color.parseColor("#26FFFFFF"));
            c.setBackground(g);
            c.setTextColor(on ? COLOR_INK : Color.WHITE);
        }
    }

    private void pickAppFont(String id) {
        fonts().saveAppFont(id);
        fonts().applyAppFont();
        refreshFontChips();
        relayoutAfterStyle();
    }

    private void relayoutAfterStyle() {
        if (popup == null) return;
        fonts().restyle(popup);
        popup.requestLayout();
        placePopup();
    }

    private void setFontScale(float v) {
        OverlayFonts f = fonts();
        float q = Math.round(Math.max(OverlayFonts.FONT_MIN, Math.min(OverlayFonts.FONT_MAX, v)) * 20f) / 20f;   // قدم‌های ۰٫۰۵
        if (Math.abs(q - f.scale) < 0.001f) return;
        f.scale = q;
        relayoutAfterStyle();
        f.saveScale();
    }

    /** نگه‌داشتنِ دکمه‌ی Aa: اندازه‌ی متن، فونت، ارتفاع و شفافیت به حالتِ اولیه برمی‌گردد. */
    private void resetView() {
        OverlayFonts f = fonts();
        f.scale = 1f;
        f.saveScale();
        f.resetAppFont();
        f.applyAppFont();
        popupHFrac = POPUP_H_DEFAULT;
        panelAlpha = 1f;
        prefs().edit().putFloat("magHFrac", popupHFrac).putFloat("panelAlphaV2", 1f).apply();
        if (opacityBar != null) opacityBar.setProgress(100);
        applyPopupAlpha();
        applyScrollMax();
        refreshFontChips();
        relayoutAfterStyle();
        toast(msg("اندازه، شفافیت و فونت به حالت اولیه برگشت", "Size, opacity and font reset"));
    }

    // ───────── نوارِ دستگیره (پایینِ کادر) ─────────

    private TextView fontStep(String label, int sp, final float delta) {
        TextView t = new TextView(this);
        t.setText(label);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, sp);
        t.setTextColor(Color.parseColor("#B3FFFFFF"));
        t.setGravity(Gravity.CENTER);
        t.setMinWidth(dp(34));
        t.setPadding(dp(4), 0, dp(4), 0);
        t.setOnClickListener(v -> setFontScale(fonts().scale + delta));
        return t;
    }

    /** نوارِ تیره با آیکنِ ↕؛ کشیدنِ عمودی = ارتفاعِ کادر ، کشیدنِ افقی = جابه‌جایی ، سمتِ چپ کپسولِ A− | A+ . */
    private View makeGrip() {
        final HatchBar f = new HatchBar(this);
        f.setContentDescription(msg("بکش: تغییرِ اندازه یا جابه‌جایی", "Drag: resize or move"));

        LinearLayout cap = new LinearLayout(this);
        cap.setOrientation(LinearLayout.HORIZONTAL);
        cap.setLayoutDirection(View.LAYOUT_DIRECTION_LTR);
        cap.setGravity(Gravity.CENTER_VERTICAL);
        GradientDrawable capBg = new GradientDrawable();
        capBg.setColor(Color.parseColor("#59000000"));
        capBg.setCornerRadius(dp(10));
        cap.setBackground(capBg);
        cap.addView(fontStep("A\u2212", 11, -0.1f));
        View div = new View(this);
        div.setBackgroundColor(Color.parseColor("#33FFFFFF"));
        cap.addView(div, new LinearLayout.LayoutParams(dp(1), dp(12)));
        cap.addView(fontStep("A+", 14, +0.1f));
        FrameLayout.LayoutParams clp = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, dp(22), Gravity.START | Gravity.CENTER_VERTICAL);
        clp.setMarginStart(dp(12));
        f.addView(cap, clp);

        // سمتِ راستِ نوارِ پایین: 🔁 تکرار + Aa فونت
        LinearLayout tools = new LinearLayout(this);
        tools.setOrientation(LinearLayout.HORIZONTAL);
        tools.setLayoutDirection(View.LAYOUT_DIRECTION_LTR);
        tools.setGravity(Gravity.CENTER_VERTICAL);
        if (tvRepeat != null) {
            tvRepeat.setMinHeight(dp(26));
            tvRepeat.setMinWidth(dp(36));
            tvRepeat.setTextSize(15);
            tools.addView(tvRepeat, new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        }
        if (tvFontBtn != null) {
            tvFontBtn.setPadding(dp(10), dp(2), dp(10), dp(2));
            LinearLayout.LayoutParams fbLp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT, dp(24));
            fbLp.setMarginStart(dp(4));
            tools.addView(tvFontBtn, fbLp);
        }
        FrameLayout.LayoutParams tlp = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, dp(28), Gravity.END | Gravity.CENTER_VERTICAL);
        tlp.setMarginEnd(dp(22));
        f.addView(tools, tlp);

        final float[] d = new float[6];      // 0 downY, 1 startH(frac), 2 downX, 3 mode(0 نامعلوم/1 اندازه/2 جابه‌جایی), 4 popupX, 5 popupY
        final int slop = ViewConfiguration.get(this).getScaledTouchSlop();
        f.setOnTouchListener((v, ev) -> {
            switch (ev.getActionMasked()) {
                case MotionEvent.ACTION_DOWN:
                    d[0] = ev.getRawY(); d[1] = popupHFrac; d[2] = ev.getRawX(); d[3] = 0;
                    d[4] = popupLp != null ? popupLp.x : 0;
                    d[5] = popupLp != null ? popupLp.y : 0;
                    f.setActive(true);
                    return true;
                case MotionEvent.ACTION_MOVE: {
                    float rdx = ev.getRawX() - d[2], rdy = ev.getRawY() - d[0];
                    if (d[3] == 0 && Math.max(Math.abs(rdx), Math.abs(rdy)) > slop) {
                        d[3] = Math.abs(rdy) >= Math.abs(rdx) ? 1 : 2;
                        popupFree = true;                         // بالای کادر سرِ جایش می‌ماند
                        popupFreeX = (int) d[4]; popupFreeY = (int) d[5];
                        if (d[3] == 2) showPopupCloseTarget();
                    }
                    if (d[3] == 1) {
                        popupHFrac = Math.max(POPUP_H_MIN, Math.min(POPUP_H_MAX, d[1] + rdy / Math.max(1, capH)));
                        applyScrollMax();
                        placePopup();
                    } else if (d[3] == 2) {
                        popupFreeX = Math.round(d[4] + rdx);
                        popupFreeY = Math.round(d[5] + rdy);
                        placePopup();
                        popupHotCheck(ev.getRawX(), ev.getRawY());
                    }
                    return true;
                }
                case MotionEvent.ACTION_UP:
                case MotionEvent.ACTION_CANCEL:
                    f.setActive(false);
                    if (d[3] == 2) popupDragEnd(ev.getActionMasked() == MotionEvent.ACTION_UP);
                    if (d[3] == 1) prefs().edit().putFloat("magHFrac", popupHFrac).apply();
                    return true;
            }
            return true;
        });
        return f;
    }

    /** نوارِ دستگیره با آیکنِ ↕. */
    private final class HatchBar extends FrameLayout {
        private final Paint fill = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint icBg = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint ic = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Path arrows = new Path();
        private boolean active;

        HatchBar(Context c) {
            super(c);
            setWillNotDraw(false);
            ic.setStyle(Paint.Style.STROKE);
            ic.setStrokeWidth(dp(2));
            ic.setStrokeCap(Paint.Cap.ROUND);
            ic.setStrokeJoin(Paint.Join.ROUND);
            icBg.setColor(Color.parseColor("#80000000"));
        }

        void setActive(boolean a) { active = a; invalidate(); }

        @Override protected void dispatchDraw(Canvas cv) {
            final int w = getWidth(), h = getHeight();
            fill.setColor(active ? Color.parseColor("#40F2C14E") : Color.parseColor("#59000000"));
            cv.drawRect(0, 0, w, h, fill);
            final float cx = w / 2f, cy = h / 2f;
            cv.drawRoundRect(cx - dp(18), cy - dp(11), cx + dp(18), cy + dp(11), dp(11), dp(11), icBg);
            ic.setColor(active ? COLOR_GOLD : Color.WHITE);
            final float a = dp(5.5f), c = dp(3.5f);
            arrows.reset();
            arrows.moveTo(cx, cy - a); arrows.lineTo(cx, cy + a);
            arrows.moveTo(cx - c, cy - a + c); arrows.lineTo(cx, cy - a); arrows.lineTo(cx + c, cy - a + c);
            arrows.moveTo(cx - c, cy + a - c); arrows.lineTo(cx, cy + a); arrows.lineTo(cx + c, cy + a - c);
            cv.drawPath(arrows, ic);
            super.dispatchDraw(cv);
        }
    }

    // ───────── جابه‌جایی و بستنِ کادر (✕ی پایینِ صفحه) ─────────

    /** ✕ی بستن را (که قبل از کادر ساخته شده) دوباره می‌سازد تا روی کادر دیده شود. */
    private void showPopupCloseTarget() {
        if (closeView == null || closeLp == null) return;
        try {
            wm.removeViewImmediate(closeView);
            wm.addView(closeView, closeLp);
        } catch (Exception ignored) {}
        closeView.setVisibility(View.VISIBLE);
    }

    private void popupHotCheck(float rx, float ry) {
        boolean h = closeView != null && Math.hypot(rx - capW / 2.0, ry - (capH - dp(120))) < dp(90);
        if (h == popupHot) return;
        popupHot = h;
        if (closeView != null) closeView.setHot(h);
        if (popup != null) {
            if (h) popup.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP);
            popup.animate().scaleX(h ? 0.55f : 1.02f).scaleY(h ? 0.55f : 1.02f).alpha(h ? 0.6f : 1f).setDuration(140).start();
        }
    }

    /** پایانِ کشیدنِ کادر: روی ✕ رها شد → کادر کوچک و بسته می‌شود؛ وگرنه سرِ جای تازه می‌ماند. */
    private void popupDragEnd(boolean dropped) {
        final boolean onX = popupHot;
        popupHot = false;
        hideCloseTarget();
        if (popup == null) return;
        if (dropped && onX) {
            popup.animate().scaleX(0f).scaleY(0f).alpha(0f).setDuration(150)
                    .withEndAction(this::clearSelection).start();
        } else {
            popup.animate().scaleX(1f).scaleY(1f).alpha(1f).setDuration(140).start();
        }
    }

    /** کشیدنِ سربرگ = جابه‌جایی؛ نگه‌داشتن = «برداشتنِ» کادر؛ رها کردن روی ✕ = بستن. */
    private final class PopupMover implements View.OnTouchListener {
        private final int slop = ViewConfiguration.get(MagnifierService.this).getScaledTouchSlop();
        private final long longMs = ViewConfiguration.getLongPressTimeout();
        private float downX, downY;
        private int startX, startY;
        private boolean moved, picked;
        private final Runnable longRun = () -> {
            if (moved || popup == null) return;
            picked = true;
            popup.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS);
            popup.animate().scaleX(1.02f).scaleY(1.02f).setDuration(120).start();
            showPopupCloseTarget();
        };

        @Override public boolean onTouch(View v, MotionEvent e) {
            if (popup == null || popupLp == null) return false;
            switch (e.getActionMasked()) {
                case MotionEvent.ACTION_DOWN:
                    startX = popupLp.x; startY = popupLp.y;
                    downX = e.getRawX(); downY = e.getRawY();
                    moved = false; picked = false;
                    main.removeCallbacks(longRun);
                    main.postDelayed(longRun, longMs);
                    return true;
                case MotionEvent.ACTION_MOVE: {
                    float dx = e.getRawX() - downX, dy = e.getRawY() - downY;
                    if (!moved && (Math.abs(dx) > slop || Math.abs(dy) > slop)) {
                        moved = true;
                        if (!picked) main.removeCallbacks(longRun);
                        showPopupCloseTarget();          // به‌محضِ شروعِ کشیدن، ✕ی پایینِ صفحه ظاهر می‌شود
                    }
                    if (moved) {
                        popupFree = true;
                        popupFreeX = Math.round(startX + dx);
                        popupFreeY = Math.round(startY + dy);
                        placePopup();
                    }
                    if (picked || moved) popupHotCheck(e.getRawX(), e.getRawY());
                    return true;
                }
                case MotionEvent.ACTION_UP:
                case MotionEvent.ACTION_CANCEL: {
                    main.removeCallbacks(longRun);
                    boolean wasActive = picked || moved;
                    picked = false; moved = false;
                    if (wasActive) popupDragEnd(e.getActionMasked() == MotionEvent.ACTION_UP);
                    return true;
                }
            }
            return true;
        }
    }

    // ───────────────────────── نماها ─────────────────────────

    /** پنجره‌ی هایلایت روی متنِ انتخاب‌شده؛ ضربه/کشیدن روی لغت‌ها = انتخابِ لغت یا محدوده. */
    private final class SelView extends View {
        private final ArrayList<ElemInfo> el;
        private final int ox, oy;
        private int a = -1, b = -1;
        private final Paint blockP = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint blockStroke = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint selP = new Paint(Paint.ANTI_ALIAS_FLAG);

        SelView(Context c, ArrayList<ElemInfo> el, int ox, int oy) {
            super(c);
            this.el = el; this.ox = ox; this.oy = oy;
            blockP.setColor(Color.parseColor("#33C9A227"));
            blockStroke.setStyle(Paint.Style.STROKE);
            blockStroke.setStrokeWidth(dp(2));
            blockStroke.setColor(COLOR_GOLD);
            selP.setColor(Color.parseColor("#8CC9A227"));
        }

        @Override protected void onDraw(Canvas cv) {
            RectF all = new RectF(dp(1), dp(1), getWidth() - dp(1), getHeight() - dp(1));
            cv.drawRoundRect(all, dp(8), dp(8), blockP);
            cv.drawRoundRect(all, dp(8), dp(8), blockStroke);
            if (a >= 0 && b >= 0) {
                int lo = Math.min(a, b), hi = Math.max(a, b);
                for (int i = lo; i <= hi && i < el.size(); i++) {
                    Rect r = el.get(i).r;
                    RectF rf = new RectF(r.left - ox - dp(2), r.top - oy - dp(1), r.right - ox + dp(2), r.bottom - oy + dp(1));
                    cv.drawRoundRect(rf, dp(4), dp(4), selP);
                }
            }
        }

        private int nearest(float x, float y) {
            int best = -1; double bd = Double.MAX_VALUE;
            for (int i = 0; i < el.size(); i++) {
                Rect r = el.get(i).r;
                double d = dist(new Rect(r.left - ox, r.top - oy, r.right - ox, r.bottom - oy), x, y);
                if (d < bd) { bd = d; best = i; }
            }
            return best;
        }

        void selectAll() {
            if (el.isEmpty()) return;
            a = 0; b = el.size() - 1;
            invalidate();
            onRangePicked(0, el.size() - 1, el);
        }

        @Override public boolean onTouchEvent(MotionEvent e) {
            switch (e.getActionMasked()) {
                case MotionEvent.ACTION_DOWN:
                    a = b = nearest(e.getX(), e.getY());
                    invalidate();
                    return true;
                case MotionEvent.ACTION_MOVE: {
                    int i = nearest(e.getX(), e.getY());
                    if (i >= 0 && i != b) { b = i; invalidate(); }
                    return true;
                }
                case MotionEvent.ACTION_UP:
                    if (a >= 0 && b >= 0) onRangePicked(Math.min(a, b), Math.max(a, b), el);
                    return true;
                case MotionEvent.ACTION_CANCEL:
                    return true;
            }
            return true;
        }
    }

    /** ذره‌بین: کنارِ صفحه = حبابِ گرد (هم‌سبکِ حبابِ ترجمه‌ی زنده)؛ هنگامِ کشیدن = حلقه‌ی با وسطِ شفاف تا متنِ زیرش خوانده شود. */
    private final class LensView extends View {
        private final Paint fill = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint outline = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint gold = new Paint(Paint.ANTI_ALIAS_FLAG);
        private boolean working;

        LensView(Context c) {
            super(c);
            outline.setStyle(Paint.Style.STROKE);
            outline.setStrokeCap(Paint.Cap.ROUND);
            gold.setStyle(Paint.Style.STROKE);
            gold.setStrokeCap(Paint.Cap.ROUND);
        }

        void setBusy(boolean b) { working = b; invalidate(); }

        @Override protected void onDraw(Canvas cv) {
            if (lensMode) drawRing(cv); else drawDisc(cv);
        }

        private void drawRing(Canvas cv) {
            float cx = dp(LENS_C), cy = dp(LENS_C), r = dp(LENS_R);
            float hx0 = cx + r * 0.72f, hy0 = cy + r * 0.72f, hx1 = hx0 + dp(10), hy1 = hy0 + dp(10);
            outline.setColor(COLOR_INK);
            outline.setStrokeWidth(dp(6));
            cv.drawCircle(cx, cy, r, outline);
            cv.drawLine(hx0, hy0, hx1, hy1, outline);
            gold.setColor(working ? Color.WHITE : COLOR_GOLD);
            gold.setStrokeWidth(dp(3));
            cv.drawCircle(cx, cy, r, gold);
            cv.drawLine(hx0, hy0, hx1, hy1, gold);
        }

        private void drawDisc(Canvas cv) {
            float d = getResources().getDisplayMetrics().density;
            float w = getWidth(), h = getHeight();
            float r = Math.min(w, h) / 2f - 8 * d;
            fill.setColor(COLOR_INK);
            cv.drawCircle(w / 2f, h / 2f, r, fill);
            gold.setColor(COLOR_GOLD);
            gold.setStrokeWidth(2 * d);
            cv.drawCircle(w / 2f, h / 2f, r, gold);
            outline.setColor(Color.WHITE);
            outline.setStrokeWidth(2.4f * d);
            float cx = w / 2f - 2 * d, cy = h / 2f - 2 * d, lr = 6 * d;
            cv.drawCircle(cx, cy, lr, outline);
            float o = lr * 0.72f;
            cv.drawLine(cx + o, cy + o, cx + o + 6 * d, cy + o + 6 * d, outline);
        }
    }

    /** دایره‌ی ✕ی بستن: شیشه‌ای تیره با حلقه‌ی تپنده؛ وقتی حباب/ذره‌بین نزدیک می‌شود بزرگ و قرمز می‌شود. */
    private static final class CloseTargetView extends View {
        private final float d;
        private final Paint glow = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint fill = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint ring = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint pulse = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint cross = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final android.animation.ArgbEvaluator argb = new android.animation.ArgbEvaluator();
        private float hot = 0f, t = 0f;
        private android.animation.ValueAnimator hotAnim, pulseAnim;

        CloseTargetView(Context c) {
            super(c);
            d = c.getResources().getDisplayMetrics().density;
            setLayerType(LAYER_TYPE_SOFTWARE, null);
            ring.setStyle(Paint.Style.STROKE);
            ring.setStrokeWidth(1.4f * d);
            pulse.setStyle(Paint.Style.STROKE);
            pulse.setStrokeWidth(1.6f * d);
            cross.setStyle(Paint.Style.STROKE);
            cross.setStrokeCap(Paint.Cap.ROUND);
            cross.setStrokeWidth(2.5f * d);
            cross.setColor(Color.WHITE);
        }

        void setHot(boolean h) {
            if (hotAnim != null) hotAnim.cancel();
            hotAnim = android.animation.ValueAnimator.ofFloat(hot, h ? 1f : 0f);
            hotAnim.setDuration(150);
            hotAnim.setInterpolator(new android.view.animation.OvershootInterpolator(1.6f));
            hotAnim.addUpdateListener(a -> { hot = Math.max(0f, (Float) a.getAnimatedValue()); invalidate(); });
            hotAnim.start();
        }

        @Override protected void onAttachedToWindow() {
            super.onAttachedToWindow();
            pulseAnim = android.animation.ValueAnimator.ofFloat(0f, 1f);
            pulseAnim.setDuration(1300);
            pulseAnim.setRepeatCount(android.animation.ValueAnimator.INFINITE);
            pulseAnim.addUpdateListener(a -> { t = (Float) a.getAnimatedValue(); invalidate(); });
            if (getVisibility() == VISIBLE) pulseAnim.start();
        }

        @Override protected void onVisibilityChanged(View v, int vis) {
            super.onVisibilityChanged(v, vis);
            if (pulseAnim == null) return;
            if (vis == VISIBLE) { if (!pulseAnim.isStarted()) pulseAnim.start(); }
            else pulseAnim.cancel();
        }

        @Override protected void onDetachedFromWindow() {
            super.onDetachedFromWindow();
            if (hotAnim != null) { hotAnim.cancel(); hotAnim = null; }
            if (pulseAnim != null) { pulseAnim.cancel(); pulseAnim = null; }
        }

        @Override protected void onDraw(Canvas cv) {
            float cx = getWidth() / 2f, cy = getHeight() / 2f;
            float r = 26f * d;

            // حلقه‌ی تپنده‌ی بیرونی (راهنمای «اینجا رها کن»)
            float pr = r + (14f * d) * t;
            pulse.setColor((Integer) argb.evaluate(hot, 0xFFFFFFFF, COLOR_REC));
            pulse.setAlpha((int) (110 * (1f - t)));
            cv.drawCircle(cx, cy, pr, pulse);

            float sc = 1f + 0.22f * hot;
            cv.save();
            cv.scale(sc, sc, cx, cy);

            // هاله‌ی قرمز هنگامِ نزدیک شدن
            if (hot > 0.02f) {
                glow.setColor(COLOR_REC);
                glow.setAlpha((int) (70 * hot));
                cv.drawCircle(cx, cy, r + 6f * d, glow);
            }

            int top = (Integer) argb.evaluate(hot, 0xF0333F6E, 0xFFEF5350);
            int bot = (Integer) argb.evaluate(hot, 0xF0141C38, 0xFFC62828);
            fill.setShader(new android.graphics.LinearGradient(cx, cy - r, cx, cy + r, top, bot,
                    android.graphics.Shader.TileMode.CLAMP));
            fill.setShadowLayer(9f * d, 0f, 3f * d, 0x77000000);
            cv.drawCircle(cx, cy, r, fill);

            ring.setColor((Integer) argb.evaluate(hot, 0x66FFFFFF, 0xEEFFFFFF));
            cv.drawCircle(cx, cy, r - 0.7f * d, ring);

            cv.rotate(90f * hot, cx, cy);                    // ✕ هنگامِ نزدیک شدن نرم می‌چرخد
            float k = 7.2f * d;
            cv.drawLine(cx - k, cy - k, cx + k, cy + k, cross);
            cv.drawLine(cx - k, cy + k, cx + k, cy - k, cross);
            cv.restore();
        }
    }
}
