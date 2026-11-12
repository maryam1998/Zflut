package com.linglearn.app.overlay;

import android.content.Context;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * 🔊 چیپ‌های «زبان‌های خوانش» برای حباب و ذره‌بین (پس‌زمینه) — همان ظاهرِ چیپ‌های انتخابِ زبانِ ترجمه‌ی زنده.
 * هر چیپ = یک زبانِ ترجمه که بعد از متن خوانده می‌شود (طلایی = می‌خواند، شیشه‌ای = نمی‌خواند).
 * 🔊 اولِ ردیف = کلیدِ اصلیِ «خواندن ترجمه‌ها در پس‌زمینه».
 * انتخاب‌ها در همان کلیدهای تنظیماتِ اپ ذخیره می‌شود (zflut-read-trans-bg / -off) پس با تنظیمات یکی است.
 */
final class ReadLangChips {

    interface Langs { List<String> get(); }

    private final Context ctx;
    private final Langs langs;
    private final Runnable onChange;
    private final float density;
    private final int gold, ink;
    private final LinearLayout root;
    private final LinearLayout chips;
    private final TextView master;

    ReadLangChips(Context ctx, Langs langs, int gold, int ink, Runnable onChange) {
        this.ctx = ctx;
        this.langs = langs;
        this.gold = gold;
        this.ink = ink;
        this.onChange = onChange;
        this.density = ctx.getResources().getDisplayMetrics().density;

        root = new LinearLayout(ctx);
        root.setOrientation(LinearLayout.HORIZONTAL);
        root.setGravity(Gravity.CENTER_VERTICAL);
        root.setLayoutDirection(View.LAYOUT_DIRECTION_LTR);
        root.setPadding(0, dp(6), 0, 0);

        master = new TextView(ctx);
        master.setText("🔊");
        master.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        master.setGravity(Gravity.CENTER);
        master.setSingleLine(true);
        master.setMinWidth(dp(46));
        master.setPadding(dp(12), dp(6), dp(12), dp(6));
        master.setOnClickListener(v -> {
            final boolean nowOn = !PanelTts.readTransBg(this.ctx);
            PanelTts.setReadTransBg(this.ctx, nowOn);
            if (nowOn) {
                // اگر همه‌ی چیپ‌ها خاموش بودند، روشن‌کردنِ کلید یعنی «همه را بخوان»
                boolean any = false;
                for (String c : currentCodes()) if (PanelTts.readLangOn(this.ctx, c)) { any = true; break; }
                if (!any) for (String c : currentCodes()) PanelTts.setReadLang(this.ctx, c, true);
            }
            refresh();
            fire();
        });
        LinearLayout.LayoutParams mlp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        mlp.setMarginEnd(dp(6));
        root.addView(master, mlp);

        HorizontalScrollView hs = new HorizontalScrollView(ctx);
        hs.setHorizontalScrollBarEnabled(false);
        hs.setOverScrollMode(View.OVER_SCROLL_NEVER);
        chips = new LinearLayout(ctx);
        chips.setOrientation(LinearLayout.HORIZONTAL);
        chips.setLayoutDirection(View.LAYOUT_DIRECTION_LTR);
        hs.addView(chips, new ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        root.addView(hs, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        refresh();
    }

    View view() { return root; }

    private int dp(float v) { return Math.round(v * density); }

    private void fire() { try { if (onChange != null) onChange.run(); } catch (Throwable ignored) {} }

    private static GradientDrawable pill(boolean on, int gold, int r) {
        GradientDrawable g = new GradientDrawable();
        g.setCornerRadius(r);
        g.setColor(on ? gold : Color.parseColor("#26FFFFFF"));
        return g;
    }

    private List<String> currentCodes() {
        final List<String> codes = new ArrayList<>();
        try {
            List<String> l = langs.get();
            if (l != null) for (String c : l) {
                if (c == null) continue;
                String t = c.trim().toLowerCase(Locale.ROOT);
                if (!t.isEmpty() && !codes.contains(t)) codes.add(t);
            }
        } catch (Throwable ignored) {}
        return codes;
    }

    /** چیپ‌ها را از روی زبان‌های انتخابیِ فعلی و وضعیتِ ذخیره‌شده دوباره می‌چیند. */
    void refresh() {
        final boolean allOn = PanelTts.readTransBg(ctx);
        master.setBackground(pill(allOn, gold, dp(14)));
        master.setTextColor(allOn ? ink : Color.WHITE);

        final List<String> codes = currentCodes();

        chips.removeAllViews();
        for (final String code : codes) {
            final boolean on = allOn && PanelTts.readLangOn(ctx, code);
            TextView c = new TextView(ctx);
            c.setText(code.toUpperCase(Locale.ROOT));
            c.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
            c.setTypeface(Typeface.DEFAULT_BOLD);
            c.setGravity(Gravity.CENTER);
            c.setSingleLine(true);
            c.setMinWidth(dp(46));
            c.setPadding(dp(12), dp(6), dp(12), dp(6));
            c.setBackground(pill(on, gold, dp(14)));
            c.setTextColor(on ? ink : Color.WHITE);
            c.setOnClickListener(v -> {
                final boolean wasMaster = PanelTts.readTransBg(ctx);
                boolean nowOn = !(wasMaster && PanelTts.readLangOn(ctx, code));
                if (nowOn && !wasMaster) {
                    // کلیدِ اصلی خاموش بود: فقط همین زبان بخوانده شود (بقیه خاموش بمانند)
                    PanelTts.setReadTransBg(ctx, true);
                    for (String o : currentCodes()) PanelTts.setReadLang(ctx, o, false);
                }
                PanelTts.setReadLang(ctx, code, nowOn);
                if (!nowOn) {                                   // آخرین چیپ هم خاموش شد → کلیدِ اصلی خاموش
                    boolean any = false;
                    for (String o : currentCodes()) if (PanelTts.readLangOn(ctx, o)) { any = true; break; }
                    if (!any) PanelTts.setReadTransBg(ctx, false);
                }
                refresh();
                fire();
            });
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            lp.setMarginEnd(dp(6));
            chips.addView(c, lp);
        }
    }
}
