package com.linglearn.app.overlay;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.widget.Toast;

import org.json.JSONArray;
import org.json.JSONObject;

import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
import java.util.Locale;
import java.util.TimeZone;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * 📤 «Share → Hope»: کاربر در اینستاگرام/تیک‌تاک/تلگرام/… دکمه‌ی اشتراک‌گذاری را می‌زند و Hope را انتخاب می‌کند.
 * لینکِ دقیقِ همان ویدیو/ریل به «داستان‌های ذخیره‌شده» اضافه می‌شود. هیچ مجوزِ ویژه‌ای لازم نیست و
 * هیچ‌چیز از برنامه‌های دیگر خوانده نمی‌شود؛ فقط متنی که خودِ کاربر می‌فرستد.
 */
public class ShareReceiverActivity extends Activity {

    private static final Pattern URL = Pattern.compile("(?i)\\b(https?://[^\\s\"'<>]+)");

    /** از 💾 حباب: به‌جای متنِ Share، لینکِ کپی‌شده‌ی کلیپ‌بورد خوانده می‌شود. */
    static final String EXTRA_FROM_CLIP = "com.linglearn.app.FROM_CLIP";
    static final String EXTRA_REPLACE_KEY = "com.linglearn.app.REPLACE_KEY";   // ردیفِ بدونِ لینکِ قبلی که باید با لینک کامل شود
    static final String EXTRA_TITLE = "com.linglearn.app.TITLE";
    private boolean fromClip = false, clipDone = false;

    /** از ▶ حباب (وقتی «دسترسی به اعلان‌ها» نیست): توضیحِ شفاف + انتخابِ «همگام با پخش» یا «فقط متنِ کامل». */
    static final String EXTRA_YT_CHOOSE = "com.linglearn.app.YT_CHOOSE";
    /** از ▶ حباب (بدونِ دسترسیِ اعلان): بدونِ پرسش، لینکِ یوتیوبِ کلیپ‌بورد خوانده و کلِ زیرنویس یک‌جا آورده می‌شود. */
    static final String EXTRA_YT_FULL_CLIP = "com.linglearn.app.YT_FULL_CLIP";
    static final String EXTRA_FA = "com.linglearn.app.FA";
    /** زبانِ رابطِ اپ: fa / en / es / de / fr / ar (جایگزینِ EXTRA_FAِ دوحالته). */
    static final String EXTRA_LANG = "com.linglearn.app.LANG";
    private String uiLang = "en";
    private String L(String fa, String en) { return NativeI18n.tr(uiLang, fa, en); }
    private String intentLang(Intent in) {
        String l = in.getStringExtra(EXTRA_LANG);
        return l != null ? NativeI18n.normalize(l) : (in.getBooleanExtra(EXTRA_FA, true) ? "fa" : "en");
    }
    private boolean ytFullClip = false;

    /** از 🎙 حباب، وقتی بسته‌ی تشخیص گفتارِ آفلاین روی گوشی نیست: پیامِ تأییدِ دانلود. */
    static final String EXTRA_ASR_PACK = "com.linglearn.app.ASR_PACK";
    static final String EXTRA_PACK_KIND = "com.linglearn.app.PACK_KIND";
    static final String EXTRA_PACK_ID = "com.linglearn.app.PACK_ID";
    static final String EXTRA_PACK_NAME = "com.linglearn.app.PACK_NAME";
    static final String EXTRA_PACK_MB = "com.linglearn.app.PACK_MB";

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        fromClip = getIntent() != null && getIntent().getBooleanExtra(EXTRA_FROM_CLIP, false);
        if (getIntent() != null && getIntent().getBooleanExtra(EXTRA_ASR_PACK, false)) {
            Intent in = getIntent();
            showAsrPackDialog(intentLang(in), in.getStringExtra(EXTRA_PACK_KIND),
                    in.getStringExtra(EXTRA_PACK_ID), in.getStringExtra(EXTRA_PACK_NAME), in.getIntExtra(EXTRA_PACK_MB, 0));
            return;
        }
        if (getIntent() != null && getIntent().getBooleanExtra(EXTRA_YT_FULL_CLIP, false)) {
            uiLang = intentLang(getIntent());
            ytFullClip = true; fromClip = true; clipDone = false;
            // کلیپ‌بورد فقط وقتی خوانده می‌شود که پنجره فوکوس داشته باشد
            new Handler(Looper.getMainLooper()).postDelayed(this::finishFromClip, 900);
            return;
        }
        if (getIntent() != null && getIntent().getBooleanExtra(EXTRA_YT_CHOOSE, false)) {
            showYtChoice(intentLang(getIntent()));
            return;
        }
        if (fromClip) {
            // کلیپ‌بورد فقط وقتی خوانده می‌شود که پنجره فوکوس داشته باشد؛ اگر فوکوس دیر آمد، بعد از ۱.۲ ثانیه هم امتحان می‌کنیم
            new Handler(Looper.getMainLooper()).postDelayed(this::finishFromClip, 1200);
            return;
        }
        boolean ok = false;
        try {
            ok = handle(getIntent());
        } catch (Throwable ignored) {}
        Toast.makeText(this, ok ? "ذخیره شد ✓ — Saved to Hope" : "لینکی پیدا نشد — No link found",
                Toast.LENGTH_SHORT).show();
        finish();
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus && fromClip) finishFromClip();
    }

    private void showAsrPackDialog(final String ui, final String kind, final String id, String name, int mb) {
        uiLang = ui;
        final boolean whisper = "whisper".equals(kind);
        String size = mb > 0 ? L("حدود " + mb + " مگابایت", "about " + mb + " MB")
                : L("چند ده تا چند صد مگابایت", "tens to a few hundred MB");
        String msg = L("ترجمه‌ی زنده با تشخیص گفتارِ آفلاین انجام می‌شود: پردازش کاملاً روی گوشی شماست، صدا به هیچ سروری ارسال نمی‌شود و صفحه روان می‌ماند.",
                "Live translation uses offline speech recognition: processing happens entirely on your phone, no audio is sent to any server, and the screen stays smooth.")
                + "\n\n"
                + (whisper
                    ? L("برای این زبان (یا حالت «خودکار») بسته‌ی چندزبانه‌ی Whisper لازم است. این بسته از بسته‌های اختصاصیِ هر زبان کندتر است و ترجمه ممکن است با چند ثانیه تأخیر نمایش داده شود.",
                        "This language (or “Auto”) needs the multilingual Whisper pack. It is slower than the per-language packs, so translations may appear a few seconds late.")
                    : L("برای زبان «" + name + "» لازم است بسته‌ی آفلاین یک‌بار دانلود شود.",
                        "A one-time offline pack is required for “" + name + "”."))
                + "\n\n"
                + L("حجم بسته: " + size + " — پیشنهاد می‌شود با Wi‑Fi وصل باشید. دانلود در صورت قطع شدن از همان‌جا ادامه پیدا می‌کند.",
                    "Pack size: " + size + ". We recommend Wi‑Fi. An interrupted download resumes where it stopped.")
                + "\n\n"
                + L("بدون این بسته، ترجمه‌ی زنده کار نمی‌کند. دانلود شود؟",
                    "Without this pack, live translation will not work. Download it now?");
        AlertDialog d = new AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
                .setTitle(L("دانلود بسته‌ی تشخیص گفتار آفلاین", "Download offline speech pack"))
                .setMessage(msg)
                .setPositiveButton(L("دانلود", "Download"), (dlg, w) -> {
                    BubbleService.startAsrPackDownload(getApplicationContext(), kind, id);
                    finish();
                })
                .setNegativeButton(L("فعلاً نه", "Not now"), (dlg, w) -> finish())
                .create();
        d.setOnCancelListener(x -> finish());
        d.show();
    }

    private void showYtChoice(final String ui) {
        uiLang = ui;
        String msg = L("۱) همگام با پخش: جمله‌ی در حال پخش پررنگ می‌شود و دکمه‌های ⏮ و ↺ کار می‌کنند. این روش «دسترسی به اعلان‌ها» می‌خواهد. "
                + "فقط اعلانِ خودِ یوتیوب برای تشخیصِ ویدیو و زمانِ پخش بررسی می‌شود؛ اعلان‌های برنامه‌های دیگر خوانده یا ذخیره نمی‌شوند، "
                + "و هر وقت خواستی از تنظیماتِ اندروید خاموشش کن.",
                "1) Synced: highlights the sentence being played; ⏮ and ↺ work. Needs “Notification access”. "
                + "Only YouTube's own notification is checked (to detect the video and its play time); other apps' notifications are not read or stored. "
                + "You can turn it off anytime in Android settings.")
                + "\n\n"
                + L("۲) فقط متنِ کامل: بدونِ هیچ دسترسی. لینکِ ویدیو را در یوتیوب کپی کن (Share ← Copy link)، بعد «فقط متنِ کامل» را بزن؛ "
                + "کلِ زیرنویس یک‌جا می‌آید، بدونِ پررنگ‌شدن، با دکمه‌ی تکرارِ کلِ متن.",
                "2) Full text only: no permission. Copy the video link in YouTube (Share → Copy link), then tap “Full text only”; "
                + "all subtitles load at once, with no highlighting, plus a repeat-all-text button.");
        AlertDialog d = new AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
                .setTitle(L("زیرنویس یوتیوب", "YouTube subtitles"))
                .setMessage(msg)
                .setPositiveButton(L("فقط متنِ کامل", "Full text only"), (dlg, w) -> {
                    ytFullClip = true; fromClip = true; clipDone = false;
                    // کلیپ‌بورد فقط وقتی خوانده می‌شود که پنجره فوکوس داشته باشد
                    new Handler(Looper.getMainLooper()).postDelayed(this::finishFromClip, 900);
                })
                .setNeutralButton(L("همگام‌سازی", "Synced"), (dlg, w) -> {
                    YtMedia.openAccessSettings(this);
                    finish();
                })
                .setNegativeButton(L("بستن", "Close"), (dlg, w) -> finish())
                .create();
        d.setOnCancelListener(x -> finish());
        d.show();
    }

    private void finishFromClip() {
        if (clipDone) return;
        clipDone = true;
        boolean ok = false;
        if (ytFullClip) {
            try {
                ClipboardManager cm = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
                ClipData cd = cm == null ? null : cm.getPrimaryClip();
                CharSequence t = cd != null && cd.getItemCount() > 0 ? cd.getItemAt(0).coerceToText(this) : null;
                String id = t == null ? null : YtMedia.idFromText(t.toString());
                if (id == null && t != null && YtMedia.isValidYouTubeVideoId(t.toString().trim())) id = t.toString().trim();
                if (id != null) { BubbleService.startYoutubeFull(getApplicationContext(), id); ok = true; }
            } catch (Throwable ignored) {}
            if (!ok) Toast.makeText(this, "لینکِ یوتیوب در کلیپ‌بورد نیست — در یوتیوب Share ← Copy link را بزن و دوباره ▶",
                    Toast.LENGTH_LONG).show();
            finish();
            return;
        }
        try {
            ClipboardManager cm = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
            ClipData cd = cm == null ? null : cm.getPrimaryClip();
            if (cd != null && cd.getItemCount() > 0) {
                CharSequence t = cd.getItemAt(0).coerceToText(this);
                if (t != null) ok = handleText(t.toString(), null,
                        getIntent().getStringExtra(EXTRA_REPLACE_KEY), getIntent().getStringExtra(EXTRA_TITLE));
            }
        } catch (Throwable ignored) {}
        Toast.makeText(this, ok ? "لینکِ کپی‌شده ذخیره شد ✓ — Saved to Hope"
                : "لینکی در کلیپ‌بورد نیست — اول در همان برنامه Share ← Copy link را بزن",
                Toast.LENGTH_LONG).show();
        finish();
    }

    @Override
    protected void onNewIntent(Intent i) {
        super.onNewIntent(i);
        setIntent(i);
    }

    private boolean handle(Intent in) throws Exception {
        if (in == null || !Intent.ACTION_SEND.equals(in.getAction())) return false;
        return handleText(in.getStringExtra(Intent.EXTRA_TEXT), in.getStringExtra(Intent.EXTRA_SUBJECT), null, null);
    }

    private boolean handleText(String text, String subject, String replaceKey, String titleOverride) throws Exception {
        if (text == null || text.trim().isEmpty()) return false;
        Matcher m = URL.matcher(text);
        if (!m.find()) return false;
        String url = m.group(1).replaceAll("[)\\].,;!?]+$", "");

        String host = "";
        try { host = new java.net.URI(url).getHost(); } catch (Throwable ignored) {}
        host = host == null ? "" : host.toLowerCase(Locale.ROOT).replaceFirst("^(www|m|vm|vt|mobile)\\.", "");
        String app = appName(host);

        // عنوان: متنِ همراهِ لینک (مثلاً کپشنِ تیک‌تاک)، وگرنه نامِ برنامه
        String title = text.replace(m.group(1), "").replaceAll("\\s+", " ").trim();
        if (title.length() > 120) title = title.substring(0, 120).trim() + "…";
        if (title.isEmpty() && subject != null && !subject.trim().isEmpty()) title = subject.trim();
        if (title.isEmpty()) title = app;
        if (titleOverride != null && !titleOverride.trim().isEmpty()) title = titleOverride.trim();

        // 📺 لینکِ ویدیوی یوتیوب: لینک بلافاصله ذخیره می‌شود، بعد عنوان + زیرنویسِ کامل در پس‌زمینه گرفته می‌شود
        //    (بدونِ نیاز به حبابِ روشن، دسترسیِ اعلان یا کلیپ‌بورد).
        String ytId = (host.endsWith("youtube.com") || host.equals("youtu.be") || host.endsWith("youtube-nocookie.com"))
                ? YtMedia.idFromText(url) : null;
        if (ytId != null && (replaceKey == null || replaceKey.isEmpty())) {
            String shared = (titleOverride != null && !titleOverride.trim().isEmpty()) ? titleOverride.trim()
                    : (title.equals(app) ? "" : title);
            boolean saved = YtSaved.add(this, buildYtItem(ytId, shared, "YouTube", "en", null));
            if (saved) startYoutubeFetch(ytId, shared);
            return saved;
        }

        long now = System.currentTimeMillis();
        SimpleDateFormat fmt = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US);
        fmt.setTimeZone(TimeZone.getTimeZone("UTC"));

        JSONObject src = new JSONObject()
                .put("app", app)
                .put("pkg", "")
                .put("title", title)
                .put("artist", "")
                .put("url", url)
                .put("inApp", false)
                .put("timed", false);
        JSONObject item = new JSONObject()
                .put("key", (replaceKey != null && !replaceKey.isEmpty()) ? replaceKey : "share-" + Integer.toHexString(url.hashCode()))
                .put("live", false)
                .put("title", title)
                .put("channel", app)
                .put("url", url)
                .put("lang", "en")
                .put("targets", new JSONArray())
                .put("rev", now)
                .put("savedAt", fmt.format(new Date(now)))
                .put("lines", new JSONArray())
                .put("source", src);
        return YtSaved.add(this, item);
    }

    // ───────────────────────── 📺 یوتیوب: عنوان + زیرنویس در پس‌زمینه ─────────────────────────

    private static final String WORKER_BASE = "https://phrasebook-api.maryam-s-sharifiyan.workers.dev";
    private static final OkHttpClient HTTP = new OkHttpClient.Builder()
            .connectTimeout(8, TimeUnit.SECONDS)
            .readTimeout(15, TimeUnit.SECONDS)
            .writeTimeout(10, TimeUnit.SECONDS)
            .callTimeout(20, TimeUnit.SECONDS)
            .retryOnConnectionFailure(true)
            .build();
    private static final ExecutorService YT_EX = Executors.newSingleThreadExecutor();

    private static JSONObject buildYtItem(String id, String title, String channel, String lang, JSONArray lines) throws Exception {
        long now = System.currentTimeMillis();
        SimpleDateFormat fmt = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US);
        fmt.setTimeZone(TimeZone.getTimeZone("UTC"));
        String url = "https://youtu.be/" + id;
        String t = (title == null || title.trim().isEmpty()) ? "YouTube" : title.trim();
        JSONObject src = new JSONObject()
                .put("app", "YouTube").put("pkg", "").put("title", t).put("artist", channel == null ? "" : channel)
                .put("url", url).put("inApp", false).put("timed", false);
        return new JSONObject()
                .put("key", id)
                .put("videoId", id)
                .put("live", false)
                .put("title", t)
                .put("channel", channel == null ? "" : channel)
                .put("url", url)
                .put("lang", lang == null || lang.isEmpty() ? "en" : lang)
                .put("targets", new JSONArray())
                .put("rev", now)
                .put("savedAt", fmt.format(new Date(now)))
                .put("lines", lines == null ? new JSONArray() : lines)
                .put("source", src);
    }

    private void startYoutubeFetch(final String id, final String sharedTitle) {
        final Context app = getApplicationContext();
        final Handler ui = new Handler(Looper.getMainLooper());
        YT_EX.execute(new Runnable() {
            @Override public void run() {
                String title = sharedTitle == null ? "" : sharedTitle;
                String channel = "YouTube";
                // عنوان و کانال از oEmbed (بدونِ کلید)
                try {
                    Request rq = new Request.Builder()
                            .url("https://www.youtube.com/oembed?format=json&url=" + java.net.URLEncoder.encode("https://youtu.be/" + id, "UTF-8"))
                            .build();
                    try (Response r = HTTP.newCall(rq).execute()) {
                        if (r.isSuccessful() && r.body() != null) {
                            JSONObject o = new JSONObject(r.body().string());
                            String t = o.optString("title", "").trim();
                            if (!t.isEmpty()) title = t;
                            String a = o.optString("author_name", "").trim();
                            if (!a.isEmpty()) channel = a;
                        }
                    }
                } catch (Throwable ignored) {}

                YtCaptionFetcher.Out out = null;
                String err = null;
                try {
                    out = YtDiskCache.loadCaps(app, id, "auto");
                    if (out == null) {
                        out = YtCaptionFetcher.fetch(HTTP, WORKER_BASE, id, "auto");
                        YtDiskCache.saveCaps(app, id, "auto", out);
                    }
                } catch (YtCaptionFetcher.Fail f) {
                    err = f.noCaptions ? "این ویدیو زیرنویس ندارد" : f.getMessage();
                } catch (Throwable t) {
                    err = t.getMessage() == null ? "error" : t.getMessage();
                }

                JSONArray lines = new JSONArray();
                String lang = "en";
                if (out != null && out.cues != null) {
                    for (String ln : toSentences(out.cues)) lines.put(ln);
                    if (out.lang != null && !out.lang.isEmpty()) lang = out.lang.split("[-_]")[0].toLowerCase(Locale.ROOT);
                }
                final boolean ok = lines.length() > 0;
                final int n = lines.length();
                final String ferr = err;
                try {
                    YtSaved.add(app, buildYtItem(id, title, channel, lang, lines));
                } catch (Throwable ignored) {}
                ui.post(new Runnable() {
                    @Override public void run() {
                        Toast.makeText(app, ok ? "زیرنویس ذخیره شد ✓ (" + n + " جمله) — در «داستان‌های ذخیره‌شده»"
                                : "لینک ذخیره شد، ولی زیرنویس نیامد" + (ferr == null ? "" : ": " + ferr),
                                Toast.LENGTH_LONG).show();
                    }
                });
            }
        });
    }

    /** تکه‌های زیرنویس ← جمله‌های کامل (برای زیرنویسِ خودکار که نقطه ندارد، هر ~۲۲ کلمه یک جمله). */
    private static List<String> toSentences(List<YtSubtitles.Cue> cues) {
        StringBuilder sb = new StringBuilder();
        for (YtSubtitles.Cue c : cues) {
            if (c == null || c.text == null) continue;
            String t = c.text.replace('\n', ' ').replaceAll("\\s+", " ").trim();
            if (t.isEmpty() || t.matches("^\\[[^\\]]*\\]$")) continue;     // [Music] و مشابه
            if (sb.length() > 0) sb.append(' ');
            sb.append(t);
        }
        List<String> out = new ArrayList<>();
        for (String part : sb.toString().split("(?<=[.!?…؟。¿])\\s+")) {
            String p = part.trim();
            if (p.isEmpty()) continue;
            String[] w = p.split("\\s+");
            if (w.length <= 32) { out.add(p); continue; }
            StringBuilder cur = new StringBuilder();
            int cnt = 0;
            for (String x : w) {
                if (cur.length() > 0) cur.append(' ');
                cur.append(x);
                if (++cnt >= 22) { out.add(cur.toString()); cur.setLength(0); cnt = 0; }
            }
            if (cur.length() > 0) out.add(cur.toString());
        }
        return out;
    }

    private static String appName(String h) {
        if (h.endsWith("instagram.com")) return "Instagram";
        if (h.endsWith("tiktok.com")) return "TikTok";
        if (h.endsWith("youtube.com") || h.equals("youtu.be")) return "YouTube";
        if (h.equals("t.me") || h.endsWith("telegram.me") || h.endsWith("telegram.org")) return "Telegram";
        if (h.endsWith("facebook.com") || h.equals("fb.watch") || h.equals("fb.me")) return "Facebook";
        if (h.equals("x.com") || h.endsWith("twitter.com")) return "X";
        if (h.endsWith("snapchat.com")) return "Snapchat";
        if (h.endsWith("reddit.com") || h.equals("redd.it")) return "Reddit";
        if (h.endsWith("vimeo.com")) return "Vimeo";
        if (h.endsWith("twitch.tv")) return "Twitch";
        if (h.endsWith("linkedin.com")) return "LinkedIn";
        if (h.endsWith("pinterest.com") || h.equals("pin.it")) return "Pinterest";
        if (h.endsWith("spotify.com")) return "Spotify";
        return h.isEmpty() ? "Link" : h;
    }
}
