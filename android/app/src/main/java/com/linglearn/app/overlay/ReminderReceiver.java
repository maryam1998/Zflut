package com.linglearn.app.overlay;

import android.app.AlarmManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;

import java.util.Calendar;

/**
 * 🔔 یادآورِ روزانه برای مرورِ لغات: هر روز سرِ ساعتِ انتخابی یک نوتیفیکیشن می‌آید.
 * با AlarmManager (بدونِ مجوزِ ویژه) زمان‌بندی می‌شود و بعد از ریستارتِ گوشی دوباره برپا می‌شود.
 */
public class ReminderReceiver extends BroadcastReceiver {

    static final String PREFS = "zflut_reminder";
    private static final String ACT_FIRE = "com.linglearn.app.REMINDER_FIRE";
    private static final String CH = "zflut_reminder";
    private static final int NID = 7430;

    /** از BubblePlugin: ذخیره‌ی تنظیمات و (دوباره) زمان‌بندی. */
    static void configure(Context ctx, boolean enabled, int hour, int minute, String title, String body) {
        SharedPreferences sp = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        sp.edit().putBoolean("on", enabled).putInt("h", hour).putInt("m", minute)
                .putString("title", title).putString("body", body).apply();
        if (enabled) schedule(ctx); else cancel(ctx);
    }

    private static PendingIntent pi(Context ctx) {
        Intent i = new Intent(ctx, ReminderReceiver.class).setAction(ACT_FIRE);
        return PendingIntent.getBroadcast(ctx, 7430, i, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
    }

    static void cancel(Context ctx) {
        try {
            AlarmManager am = (AlarmManager) ctx.getSystemService(Context.ALARM_SERVICE);
            am.cancel(pi(ctx));
        } catch (Throwable ignored) {}
    }

    static void schedule(Context ctx) {
        try {
            SharedPreferences sp = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
            if (!sp.getBoolean("on", false)) return;
            Calendar c = Calendar.getInstance();
            c.set(Calendar.HOUR_OF_DAY, sp.getInt("h", 20));
            c.set(Calendar.MINUTE, sp.getInt("m", 0));
            c.set(Calendar.SECOND, 0);
            c.set(Calendar.MILLISECOND, 0);
            if (c.getTimeInMillis() <= System.currentTimeMillis() + 5000) c.add(Calendar.DAY_OF_YEAR, 1);
            AlarmManager am = (AlarmManager) ctx.getSystemService(Context.ALARM_SERVICE);
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, c.getTimeInMillis(), pi(ctx));
        } catch (Throwable ignored) {}
    }

    @Override
    public void onReceive(Context ctx, Intent in) {
        String a = in == null ? null : in.getAction();
        if (Intent.ACTION_BOOT_COMPLETED.equals(a) || Intent.ACTION_MY_PACKAGE_REPLACED.equals(a)) {
            schedule(ctx);
            return;
        }
        if (!ACT_FIRE.equals(a)) return;
        SharedPreferences sp = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        if (!sp.getBoolean("on", false)) return;
        try {
            NotificationManager nm = (NotificationManager) ctx.getSystemService(Context.NOTIFICATION_SERVICE);
            if (nm.getNotificationChannel(CH) == null) {
                nm.createNotificationChannel(new NotificationChannel(CH, "Reminder", NotificationManager.IMPORTANCE_DEFAULT));
            }
            Intent open = ctx.getPackageManager().getLaunchIntentForPackage(ctx.getPackageName());
            PendingIntent content = open == null ? null : PendingIntent.getActivity(ctx, 0, open,
                    PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
            Notification n = new Notification.Builder(ctx, CH)
                    .setSmallIcon(android.R.drawable.ic_popup_reminder)
                    .setContentTitle(sp.getString("title", ""))
                    .setContentText(sp.getString("body", ""))
                    .setStyle(new Notification.BigTextStyle().bigText(sp.getString("body", "")))
                    .setContentIntent(content)
                    .setAutoCancel(true)
                    .build();
            nm.notify(NID, n);
        } catch (Throwable ignored) {}
        schedule(ctx); // فردا
    }
}
