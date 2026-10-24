package com.linglearn.app.overlay;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.graphics.drawable.Icon;
import android.media.MediaMetadata;
import android.media.session.MediaSession;
import android.media.session.PlaybackState;
import android.os.Build;
import android.os.IBinder;

/**
 * 🎧 کنترلِ پلیرِ اپ از بیرونِ برنامه (نوتیفیکیشنِ مدیا، مثل پلیرِ یوتیوب/موسیقی):
 * قبلی ⏮ · پخش/توقف ⏯ · بعدی ⏭ — روی نوتیفیکیشن، صفحه‌ی قفل و دکمه‌های هدست.
 * خودِ خوانش در Dart انجام می‌شود؛ این سرویس فقط وضعیت را نشان می‌دهد و فرمان‌ها را
 * با رویدادِ «mediaCmd» ({cmd: toggle|prev|next|stop}) به Dart برمی‌گرداند.
 */
public class MediaNotifService extends Service {

    private static final String CH = "zflut_player_media";
    private static final int NID = 7421;

    private static final String ACT_UPDATE = "com.linglearn.app.MEDIA_UPDATE";
    private static final String ACT_PREV = "com.linglearn.app.MEDIA_PREV";
    private static final String ACT_TOGGLE = "com.linglearn.app.MEDIA_TOGGLE";
    private static final String ACT_NEXT = "com.linglearn.app.MEDIA_NEXT";
    private static final String ACT_STOP = "com.linglearn.app.MEDIA_STOP";

    private static volatile MediaNotifService inst;
    private static volatile boolean curPlaying = false;

    private MediaSession session;

    // ───────────── API از BubblePlugin ─────────────
    static void show(Context ctx, String title, String sub, boolean playing, boolean prev, boolean next) {
        curPlaying = playing;
        Intent i = new Intent(ctx, MediaNotifService.class).setAction(ACT_UPDATE)
                .putExtra("title", title).putExtra("sub", sub)
                .putExtra("playing", playing).putExtra("prev", prev).putExtra("next", next);
        MediaNotifService s = inst;
        if (s != null) { s.apply(title, sub, playing, prev, next); return; }
        try { ctx.startForegroundService(i); } catch (Throwable ignored) {}
    }

    static void hide(Context ctx) {
        MediaNotifService s = inst;
        if (s == null) return;
        try { s.stopForeground(true); } catch (Throwable ignored) {}
        s.stopSelf();
    }

    // ───────────── Service ─────────────
    @Override public IBinder onBind(Intent intent) { return null; }

    @Override
    public void onCreate() {
        super.onCreate();
        inst = this;
        try {
            session = new MediaSession(this, "zflut-player");
            session.setCallback(new MediaSession.Callback() {
                @Override public void onPlay() { if (!curPlaying) BubblePlugin.notifyMediaCmd("toggle"); }
                @Override public void onPause() { if (curPlaying) BubblePlugin.notifyMediaCmd("toggle"); }
                @Override public void onSkipToNext() { BubblePlugin.notifyMediaCmd("next"); }
                @Override public void onSkipToPrevious() { BubblePlugin.notifyMediaCmd("prev"); }
                @Override public void onStop() { BubblePlugin.notifyMediaCmd("stop"); }
            });
            session.setActive(true);
        } catch (Throwable ignored) {}
    }

    @Override
    public int onStartCommand(Intent in, int flags, int startId) {
        String a = in == null ? null : in.getAction();
        if (ACT_UPDATE.equals(a)) {
            apply(in.getStringExtra("title"), in.getStringExtra("sub"),
                    in.getBooleanExtra("playing", false), in.getBooleanExtra("prev", false),
                    in.getBooleanExtra("next", false));
        } else if (ACT_PREV.equals(a)) {
            BubblePlugin.notifyMediaCmd("prev");
        } else if (ACT_NEXT.equals(a)) {
            BubblePlugin.notifyMediaCmd("next");
        } else if (ACT_TOGGLE.equals(a)) {
            BubblePlugin.notifyMediaCmd("toggle");
        } else if (ACT_STOP.equals(a)) {
            BubblePlugin.notifyMediaCmd("stop");
        }
        return START_NOT_STICKY;
    }

    @Override
    public void onDestroy() {
        inst = null;
        try { if (session != null) { session.setActive(false); session.release(); } } catch (Throwable ignored) {}
        session = null;
        super.onDestroy();
    }

    // ───────────── ساختِ نوتیفیکیشن ─────────────
    private PendingIntent act(String action, int code) {
        Intent i = new Intent(this, MediaNotifService.class).setAction(action);
        return PendingIntent.getService(this, code, i,
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
    }

    private Notification.Action action(int iconRes, String title, PendingIntent pi) {
        return new Notification.Action.Builder(Icon.createWithResource(this, iconRes), title, pi).build();
    }

    void apply(String title, String sub, boolean playing, boolean hasPrev, boolean hasNext) {
        try {
            NotificationManager nm = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
            if (nm.getNotificationChannel(CH) == null) {
                NotificationChannel ch = new NotificationChannel(CH, "Player", NotificationManager.IMPORTANCE_LOW);
                ch.setShowBadge(false);
                ch.setSound(null, null);
                nm.createNotificationChannel(ch);
            }
            if (title == null || title.isEmpty()) title = "…";
            if (sub == null) sub = "";

            if (session != null) {
                session.setMetadata(new MediaMetadata.Builder()
                        .putString(MediaMetadata.METADATA_KEY_TITLE, title)
                        .putString(MediaMetadata.METADATA_KEY_ARTIST, sub)
                        .build());
                long acts = PlaybackState.ACTION_PLAY | PlaybackState.ACTION_PAUSE
                        | PlaybackState.ACTION_PLAY_PAUSE | PlaybackState.ACTION_STOP
                        | PlaybackState.ACTION_SKIP_TO_NEXT | PlaybackState.ACTION_SKIP_TO_PREVIOUS;
                session.setPlaybackState(new PlaybackState.Builder()
                        .setActions(acts)
                        .setState(playing ? PlaybackState.STATE_PLAYING : PlaybackState.STATE_PAUSED,
                                PlaybackState.PLAYBACK_POSITION_UNKNOWN, 1f)
                        .build());
            }

            Intent open = getPackageManager().getLaunchIntentForPackage(getPackageName());
            PendingIntent content = open == null ? null : PendingIntent.getActivity(this, 0, open,
                    PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);

            Notification.Builder b = new Notification.Builder(this, CH)
                    .setSmallIcon(android.R.drawable.ic_media_play)
                    .setContentTitle(title)
                    .setContentText(sub)
                    .setContentIntent(content)
                    .setOnlyAlertOnce(true)
                    .setShowWhen(false)
                    .setOngoing(playing)
                    .setVisibility(Notification.VISIBILITY_PUBLIC)
                    .setDeleteIntent(act(ACT_STOP, 4));
            b.addAction(action(android.R.drawable.ic_media_previous, "Previous", act(ACT_PREV, 1)));
            b.addAction(action(playing ? android.R.drawable.ic_media_pause : android.R.drawable.ic_media_play,
                    playing ? "Pause" : "Play", act(ACT_TOGGLE, 2)));
            b.addAction(action(android.R.drawable.ic_media_next, "Next", act(ACT_NEXT, 3)));
            Notification.MediaStyle st = new Notification.MediaStyle().setShowActionsInCompactView(0, 1, 2);
            if (session != null) st.setMediaSession(session.getSessionToken());
            b.setStyle(st);

            Notification n = b.build();
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(NID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK);
            } else {
                startForeground(NID, n);
            }
        } catch (Throwable ignored) {}
    }
}
