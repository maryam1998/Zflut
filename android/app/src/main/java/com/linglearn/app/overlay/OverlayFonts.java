package com.linglearn.app.overlay;

import android.content.Context;
import android.content.SharedPreferences;
import android.graphics.Typeface;
import android.text.SpannableStringBuilder;
import android.text.Spanned;
import android.util.Log;
import android.util.TypedValue;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;

import java.io.File;
import java.io.IOException;
import java.util.Arrays;
import java.util.Locale;

/**
 * فونت و اندازه‌ی متنِ کادرهای شناور (ذره‌بین).
 * همان منطقِ کادرِ ترجمه‌ی زنده‌ی BubbleService: «نوع فونت» (default/modern/classic/elegant/rounded/warm)
 * و «اندازه‌ی متن» (fontScale) از همان SharedPreferences خوانده و ذخیره می‌شود؛ پس انتخابِ کاربر
 * در ذره‌بین و ترجمه‌ی زنده یکی است.
 */
final class OverlayFonts {
    private static final String TAG = "OverlayFonts";

    static final float FONT_MIN = 0.7f, FONT_MAX = 2.4f;
    static final String[] APP_FONT_IDS = {"default", "modern", "classic", "elegant", "rounded", "warm"};
    static final String[] APP_FONT_FA = {"پیش‌فرض", "مدرن", "کلاسیک", "شیک", "گرد", "گرم"};
    static final String[] APP_FONT_EN = {"Default", "Modern", "Classic", "Elegant", "Rounded", "Warm"};

    /** یک گزینه‌ی فونت. keys == null → فونتِ سیستم؛ وگرنه فایل از assets/fonts با کلیدواژه‌ی نام پیدا می‌شود. */
    private static final class FontOpt {
        final String id, sys;
        final String[] keys;
        final boolean noBold, tall, optional;
        final float sizeMul;
        boolean resolved;
        Typeface reg, bold;
        String[] sysKeys;

        FontOpt sys(String... k) { this.sysKeys = k; return this; }

        FontOpt(String id, String sys, String[] keys, boolean noBold, boolean tall, float sizeMul, boolean optional) {
            this.id = id; this.sys = sys; this.keys = keys;
            this.noBold = noBold; this.tall = tall; this.sizeMul = sizeMul; this.optional = optional;
        }
    }

    private static final FontOpt[] FA_FONTS = {
            new FontOpt("fa_default", null, null, false, false, 1f, false),
            new FontOpt("fa_bzar", null, new String[]{"bzar"}, false, false, 1.08f, false),
            new FontOpt("fa_bnazanin", null, new String[]{"bnazanin", "nazanin"}, false, false, 1.12f, false),
            new FontOpt("fa_btitr", null, new String[]{"btitr", "titr"}, true, false, 1f, false),
            new FontOpt("fa_nastaliq", null, new String[]{"nastaliq", "nastaleeq"}, true, true, 1.1f, false),
            new FontOpt("fa_vazir", null, new String[]{"vazir"}, false, false, 1f, true),
            new FontOpt("fa_serif", "serif", null, false, false, 1f, false),
            new FontOpt("fa_medium", "sans-serif-medium", null, false, false, 1f, false),
            new FontOpt("fa_sysnaskh", null, new String[]{"notonaskh"}, false, false, 1.05f, false).sys("notonaskharabic", "droidnaskh", "naskh"),
            new FontOpt("fa_syssans", null, null, false, false, 1f, false).sys("notosansarabic", "droidsansarabic", "sansarabic"),
            new FontOpt("fa_aref", null, new String[]{"aref"}, true, true, 1.1f, true),
            new FontOpt("fa_syskufi", null, null, false, false, 1f, false).sys("kufi"),
            new FontOpt("fa_sysnastaliq", null, null, true, true, 1.1f, false).sys("nastaliq", "nastaleeq"),
    };

    private static final FontOpt[] EN_FONTS = {
            new FontOpt("en_default", null, null, false, false, 1f, false),
            new FontOpt("en_medium", "sans-serif-medium", null, false, false, 1f, false),
            new FontOpt("en_light", "sans-serif-light", null, false, false, 1f, false),
            new FontOpt("en_serif", "serif", null, false, false, 1f, false),
            new FontOpt("en_cond", "sans-serif-condensed", null, false, false, 1f, false),
            new FontOpt("en_mono", "monospace", null, false, false, 1f, false),
            new FontOpt("en_inter", null, new String[]{"inter"}, false, false, 1f, true),
            new FontOpt("en_lora", null, new String[]{"lora"}, false, false, 1f, true),
            new FontOpt("en_cursive", "cursive", null, false, false, 1.1f, false),
            new FontOpt("en_casual", "casual", null, false, false, 1f, false),
            new FontOpt("en_vazir", null, new String[]{"vazir"}, false, false, 1f, true),
            new FontOpt("en_caladea", null, new String[]{"caladea"}, false, false, 1.04f, true),
            new FontOpt("en_aref", null, new String[]{"aref"}, true, true, 1.05f, true),
            new FontOpt("en_carlito", null, new String[]{"carlito"}, false, false, 1.06f, true),
            new FontOpt("en_dvcond", null, new String[]{"dejavusanscondensed"}, false, false, 0.98f, true),
    };

    private static final String[] SYS_FONT_DIRS = {"/system/fonts", "/system/product/fonts", "/product/fonts", "/system_ext/fonts", "/vendor/fonts"};

    private final Context ctx;
    private final SharedPreferences sp;
    private String fontFaId = "fa_default";
    private String fontEnId = "en_default";
    private String[] fontAssets;
    float scale = 1f;

    OverlayFonts(Context ctx, String prefsName) {
        this.ctx = ctx;
        this.sp = ctx.getSharedPreferences(prefsName, Context.MODE_PRIVATE);
    }

    /** اندازه و نوعِ فونت را از تنظیمات می‌خواند. */
    void load() {
        scale = Math.max(FONT_MIN, Math.min(FONT_MAX, sp.getFloat("fontScale", 1f)));
        applyAppFont();
    }

    void saveScale() { sp.edit().putFloat("fontScale", scale).apply(); }

    String currentAppFont() { return sp.getString("appFont", "default"); }

    void saveAppFont(String id) {
        if (id == null) return;
        String f = id.trim().toLowerCase(Locale.ROOT);
        if (!f.matches("default|modern|classic|elegant|rounded|warm")) return;
        sp.edit().putString("appFont", f).apply();
    }

    /** برگشت به فونتی که از تنظیماتِ اپ آمده. */
    void resetAppFont() {
        sp.edit().putString("appFont", sp.getString("appFontLast", "default")).apply();
    }

    void applyAppFont() {
        String[] m = mapAppFont(currentAppFont());
        fontFaId = m[0];
        fontEnId = m[1];
    }

    /** «نوع فونت» → نزدیک‌ترین فونتِ قابل‌استفاده (فارسی، لاتین). */
    private String[] mapAppFont(String id) {
        switch (id == null ? "default" : id) {
            case "modern":  return new String[]{pickFa("fa_vazir", "fa_syssans", "fa_default"), pickEn("en_vazir", "en_light")};
            case "classic": return new String[]{pickFa("fa_sysnaskh", "fa_serif"), pickEn("en_caladea", "en_serif")};
            case "elegant": return new String[]{pickFa("fa_aref", "fa_sysnastaliq", "fa_sysnaskh", "fa_serif"), pickEn("en_aref", "en_cursive")};
            case "rounded": return new String[]{pickFa("fa_syskufi", "fa_medium"), pickEn("en_carlito", "en_casual")};
            case "warm":    return new String[]{pickFa("fa_vazir", "fa_sysnaskh", "fa_default"), pickEn("en_dvcond", "en_cond")};
            default:        return new String[]{pickFa("fa_vazir", "fa_default"), pickEn("en_lora", "en_default")};
        }
    }

    private String pickEn(String... ids) {
        for (String i : ids) if (fontAvailable(fontById(EN_FONTS, i))) return i;
        return ids[ids.length - 1];
    }

    private String pickFa(String... ids) {
        for (String i : ids) if (fontAvailable(fontById(FA_FONTS, i))) return i;
        return ids[ids.length - 1];
    }

    private static FontOpt fontById(FontOpt[] arr, String id) {
        for (FontOpt o : arr) if (o.id.equals(id)) return o;
        return arr[0];
    }

    // ───────── پیدا کردنِ فایلِ فونت ─────────

    private String[] fontAssetList() {
        if (fontAssets == null) {
            try { fontAssets = ctx.getAssets().list("fonts"); } catch (IOException ex) { fontAssets = null; }
            if (fontAssets == null) fontAssets = new String[0];
        }
        return fontAssets;
    }

    private static String normName(String s) {
        return s.toLowerCase(Locale.ROOT).replaceAll("\\.(ttf|otf)$", "").replaceAll("[^a-z0-9]", "");
    }

    private static boolean isBoldName(String n) { return n.endsWith("bd") || n.contains("bold"); }

    private void resolveSystemFont(FontOpt o) {
        File reg = null, bold = null, regUi = null, boldUi = null;
        for (String d : SYS_FONT_DIRS) {
            File[] fs = new File(d).listFiles();
            if (fs == null) continue;
            Arrays.sort(fs);
            for (File f : fs) {
                String lf = f.getName().toLowerCase(Locale.ROOT);
                if (!lf.endsWith(".ttf") && !lf.endsWith(".otf")) continue;
                String n = normName(f.getName());
                boolean hit = false;
                for (String k : o.sysKeys) if (n.contains(k)) { hit = true; break; }
                if (!hit) continue;
                if (n.contains("italic") || n.contains("light") || n.contains("thin") || n.contains("black")
                        || n.contains("medium") || n.contains("semi") || n.contains("extra")) continue;
                boolean ui = n.contains("ui");
                if (isBoldName(n)) { if (!ui) { if (bold == null) bold = f; } else if (boldUi == null) boldUi = f; }
                else if (ui) { if (regUi == null) regUi = f; }
                else if (reg == null) reg = f;
            }
        }
        if (reg == null) reg = regUi;
        if (bold == null) bold = boldUi;
        if (reg == null) reg = bold;
        if (reg == null) { Log.w(TAG, "no system font for " + o.id); return; }
        try {
            o.reg = Typeface.createFromFile(reg);
            o.bold = bold != null && !bold.equals(reg) ? Typeface.createFromFile(bold)
                    : (o.noBold ? o.reg : Typeface.create(o.reg, Typeface.BOLD));
        } catch (Throwable t) {
            Log.w(TAG, "system font load failed: " + reg, t);
            o.reg = null; o.bold = null;
        }
    }

    private void resolveFont(FontOpt o) {
        if (o.resolved) return;
        o.resolved = true;
        if (o.keys == null && o.sysKeys == null) return;
        String regFile = null, boldFile = null;
        if (o.keys != null) for (String f : fontAssetList()) {
            String lf = f.toLowerCase(Locale.ROOT);
            if (!lf.endsWith(".ttf") && !lf.endsWith(".otf")) continue;
            String n = normName(f);
            boolean hit = false;
            for (String k : o.keys) if (n.contains(k)) { hit = true; break; }
            if (!hit) continue;
            if (isBoldName(n)) { if (boldFile == null) boldFile = f; }
            else if (regFile == null) regFile = f;
        }
        if (regFile == null) regFile = boldFile;
        if (regFile == null) {
            if (o.sysKeys != null) resolveSystemFont(o);
            return;
        }
        try {
            o.reg = Typeface.createFromAsset(ctx.getAssets(), "fonts/" + regFile);
            if (boldFile != null && !boldFile.equals(regFile)) o.bold = Typeface.createFromAsset(ctx.getAssets(), "fonts/" + boldFile);
            else o.bold = o.noBold ? o.reg : Typeface.create(o.reg, Typeface.BOLD);
        } catch (Throwable t) {
            Log.w(TAG, "font load failed: " + regFile, t);
            o.reg = null; o.bold = null;
        }
    }

    private boolean fontAvailable(FontOpt o) {
        if (o.keys == null && o.sysKeys == null) return true;
        resolveFont(o);
        return o.reg != null;
    }

    private Typeface typefaceOf(FontOpt o, boolean bold) {
        if (o.keys != null || o.sysKeys != null) {
            resolveFont(o);
            if (o.reg != null) return bold && o.bold != null ? o.bold : o.reg;
        }
        return Typeface.create(o.sys, bold ? Typeface.BOLD : Typeface.NORMAL);
    }

    static boolean hasArabicScript(CharSequence s) {
        if (s == null) return false;
        for (int i = 0, n = s.length(); i < n; i++) {
            char c = s.charAt(i);
            if ((c >= 0x0600 && c <= 0x06FF) || (c >= 0x0750 && c <= 0x077F)
                    || (c >= 0xFB50 && c <= 0xFDFF) || (c >= 0xFE70 && c <= 0xFEFF)) return true;
        }
        return false;
    }

    // ───────── اعمال روی TextView ─────────

    /** اندازه و فونتِ «متنِ محتوا» (جمله، ترجمه، لغت) را ثبت و اعمال می‌کند؛ نوعِ فونت از خودِ حروف تشخیص داده می‌شود. */
    void style(TextView t, float baseSp, boolean bold) {
        t.setTag(new float[]{baseSp, bold ? 1f : 0f});
        apply(t);
    }

    void apply(TextView t) {
        Object tag = t.getTag();
        if (!(tag instanceof float[])) return;
        float[] st = (float[]) tag;
        boolean bold = st[1] > 0;
        FontOpt o = hasArabicScript(t.getText()) ? fontById(FA_FONTS, fontFaId) : fontById(EN_FONTS, fontEnId);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, st[0] * scale * o.sizeMul);
        t.setTypeface(typefaceOf(o, bold && !o.noBold));
        t.setLineSpacing(0f, o.tall ? 1.3f : 1f);          // نستعلیق بلند است؛ بدونِ این بالا/پایینِ حروف بریده می‌شود
    }

    void restyle(View v) {
        if (v instanceof TextView) apply((TextView) v);
        if (v instanceof ViewGroup) {
            ViewGroup g = (ViewGroup) v;
            for (int i = 0; i < g.getChildCount(); i++) restyle(g.getChildAt(i));
        }
    }

    // ───────── پیش‌نمایشِ کلیدهای فونت ─────────

    private static final class FontSpan extends android.text.style.MetricAffectingSpan {
        private final Typeface tf;
        FontSpan(Typeface t) { tf = t; }
        @Override public void updateDrawState(android.text.TextPaint p) { p.setTypeface(tf); }
        @Override public void updateMeasureState(android.text.TextPaint p) { p.setTypeface(tf); }
    }

    /** متنِ کلیدِ فونت: «Aa» با خودِ همان فونت. */
    CharSequence presetChipText(String id) {
        String[] m = mapAppFont(id);
        FontOpt eo = fontById(EN_FONTS, m[1]);
        SpannableStringBuilder sb = new SpannableStringBuilder("Aa");
        sb.setSpan(new FontSpan(typefaceOf(eo, false)), 0, sb.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
        sb.setSpan(new android.text.style.RelativeSizeSpan(1.15f * eo.sizeMul), 0, sb.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
        return sb;
    }
}
