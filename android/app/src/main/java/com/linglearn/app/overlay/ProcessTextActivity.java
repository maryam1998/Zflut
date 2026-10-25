package com.linglearn.app.overlay;

import android.app.Activity;
import android.app.Dialog;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.view.WindowManager;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

import okhttp3.OkHttpClient;

/**
 * ✂️ «ترجمه با Hope» در منوی انتخابِ متنِ اندروید (ACTION_PROCESS_TEXT).
 * کاربر در هر برنامه‌ای متن را انتخاب می‌کند ← «ترجمه با Hope». هیچ مجوزِ ویژه‌ای (دسترسی‌پذیری، ضبط صفحه،
 * نمایش روی برنامه‌ها) لازم نیست؛ فقط همان متنی که کاربر خودش انتخاب کرده به اینجا می‌رسد.
 * فارسی/عربی هم کار می‌کند چون متن مستقیم از خودِ برنامه می‌آید، نه از روی عکسِ صفحه.
 */
public class ProcessTextActivity extends Activity {

    private static final int INK = Color.parseColor("#1C2541");
    private static final int GOLD = Color.parseColor("#C9A227");
    private static final int MAX_CHARS = 1500;

    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService pool = Executors.newSingleThreadExecutor();
    private final OkHttpClient http = new OkHttpClient.Builder()
            .connectTimeout(8, TimeUnit.SECONDS)
            .readTimeout(12, TimeUnit.SECONDS)
            .build();

    private String ui = "en";
    private String text = "", src = "en";
    private String firstTr = "", firstTrLang = "fa";
    private boolean storyDone, grammarDone, leitnerDone;
    private TextView btnStory, btnGrammar, btnLeitner;
    private Dialog dialog;

    private String L(String fa, String en) { return NativeI18n.tr(ui, fa, en); }

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        ui = NativeI18n.lang(this);
        CharSequence cs = getIntent() == null ? null
                : getIntent().getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT);
        String t = cs == null ? "" : cs.toString().replaceAll("\\s+", " ").trim();
        if (t.isEmpty()) { finish(); return; }
        if (t.length() > MAX_CHARS) t = t.substring(0, MAX_CHARS);
        text = t;

        SharedPreferences sp = getSharedPreferences(NativeI18n.PREFS, MODE_PRIVATE);
        String saved = sp.getString("source", "en");
        if (saved == null || saved.isEmpty() || "auto".equals(saved)) saved = "en";
        src = detectSource(text, saved);
        final List<String> targets = targets(sp, src);
        buildDialog(targets);
        translateAll(targets);
    }

    private static String detectSource(String t, String saved) {
        try {
            String ar = MagnifierService.arabicScriptLang(t, saved);   // فارسی/عربی/اردو (حتی وقتی با لاتین قاطی است)
            if (ar != null) return ar;
            String d = LangDetect.detect(t);
            if (d != null) return d;
        } catch (Throwable ignored) { }
        return saved;
    }

    private List<String> targets(SharedPreferences sp, String from) {
        ArrayList<String> out = new ArrayList<>();
        String csv = sp.getString("targets", "");
        if (csv != null) {
            for (String x : csv.split(",")) {
                x = x.trim().toLowerCase(Locale.ROOT);
                if (!x.isEmpty() && !x.equals(from) && !out.contains(x)) out.add(x);
            }
        }
        if (out.isEmpty()) {
            String x = sp.getString("target", "fa");
            if (x != null && !x.isEmpty() && !x.equals(from)) out.add(x);
        }
        if (out.isEmpty()) out.add("en".equals(from) ? "fa" : "en");
        return out;
    }

    private int dp(float v) { return Math.round(v * getResources().getDisplayMetrics().density); }

    private TextView tv(String s, int color, float sp, boolean bold) {
        TextView t = new TextView(this);
        t.setText(s);
        t.setTextColor(color);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, sp);
        if (bold) t.setTypeface(t.getTypeface(), android.graphics.Typeface.BOLD);
        t.setTextIsSelectable(true);
        t.setTextDirection(View.TEXT_DIRECTION_FIRST_STRONG);
        return t;
    }

    private TextView button(String label, View.OnClickListener l) {
        TextView t = new TextView(this);
        t.setText(label);
        t.setTextColor(Color.WHITE);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        t.setGravity(Gravity.CENTER);
        t.setPadding(dp(10), dp(9), dp(10), dp(9));
        GradientDrawable g = new GradientDrawable();
        g.setCornerRadius(dp(10));
        g.setColor(Color.parseColor("#1AFFFFFF"));
        g.setStroke(dp(1), GOLD);
        t.setBackground(g);
        t.setOnClickListener(l);
        return t;
    }

    private final ArrayList<TextView> rowViews = new ArrayList<>();

    private void buildDialog(List<String> targets) {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(16), dp(14), dp(16), dp(14));
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(INK);
        bg.setCornerRadius(dp(16));
        bg.setStroke(dp(1), GOLD);
        root.setBackground(bg);

        // نوارِ بالا: نامِ زبانِ مبدأ + ✕
        LinearLayout head = new LinearLayout(this);
        head.setOrientation(LinearLayout.HORIZONTAL);
        head.setGravity(Gravity.CENTER_VERTICAL);
        TextView pill = tv(src.toUpperCase(Locale.ROOT), GOLD, 11, true);
        pill.setTextIsSelectable(false);
        head.addView(pill, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        TextView x = tv("✕", Color.WHITE, 16, false);
        x.setTextIsSelectable(false);
        x.setPadding(dp(10), dp(4), dp(4), dp(4));
        x.setOnClickListener(v -> dialog.dismiss());
        head.addView(x);
        root.addView(head);

        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.addView(tv(text, Color.WHITE, 17, true));
        for (String tg : targets) {
            TextView lab = tv(tg.toUpperCase(Locale.ROOT), GOLD, 11, true);
            lab.setTextIsSelectable(false);
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            lp.topMargin = dp(12);
            body.addView(lab, lp);
            TextView row = tv("…", Color.parseColor("#E8ECF8"), 16, false);
            row.setTag(tg);
            rowViews.add(row);
            body.addView(row);
        }
        ScrollView sv = new ScrollView(this);
        sv.addView(body);
        LinearLayout.LayoutParams slp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        slp.topMargin = dp(6);
        root.addView(sv, slp);

        // ذخیره‌ها
        btnStory = button("", v -> { if (!storyDone) { storyDone = true; queueWord("story"); refreshButtons(); } });
        btnGrammar = button("", v -> { if (!grammarDone) { grammarDone = true; queueWord("grammar"); refreshButtons(); } });
        btnLeitner = button("", v -> { if (!leitnerDone) { leitnerDone = true; queueWord("leitner"); refreshButtons(); } });
        for (TextView bt : new TextView[]{btnStory, btnGrammar, btnLeitner}) {
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            lp.topMargin = dp(8);
            root.addView(bt, lp);
        }
        refreshButtons();
        TextView copy = button("📋 " + L("کپیِ ترجمه", "Copy translation"), v -> copyTranslation());
        LinearLayout.LayoutParams clp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        clp.topMargin = dp(8);
        root.addView(copy, clp);

        dialog = new Dialog(this);
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
        dialog.setContentView(root);
        dialog.setOnDismissListener(d -> finish());
        dialog.setCanceledOnTouchOutside(true);
        Window w = dialog.getWindow();
        if (w != null) {
            w.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
            int width = Math.min(getResources().getDisplayMetrics().widthPixels - dp(24), dp(560));
            w.setLayout(width, WindowManager.LayoutParams.WRAP_CONTENT);
            w.setGravity(Gravity.CENTER);
        }
        dialog.show();
    }

    private void refreshButtons() {
        btnStory.setText(storyDone
                ? L("🔖 ذخیره شد برای داستان بعدی", "🔖 Saved for next story")
                : L("🔖 ذخیره برای داستان بعدی", "🔖 Save for next story"));
        btnGrammar.setText(grammarDone
                ? L("🧩 ذخیره شد در گرامر", "🧩 Saved to grammar")
                : L("🧩 افزودن به یادگیری گرامر", "🧩 Add to grammar learning"));
        btnLeitner.setText(leitnerDone
                ? L("به جعبه‌ی لایتنر اضافه شد", "Added to Leitner box")
                : L("افزودن به جعبه‌ی لایتنر", "Add to Leitner box"));
        btnStory.setAlpha(storyDone ? 0.6f : 1f);
        btnGrammar.setAlpha(grammarDone ? 0.6f : 1f);
        btnLeitner.setAlpha(leitnerDone ? 0.6f : 1f);
    }

    private void translateAll(final List<String> targets) {
        final String from = src, t = text;
        try {
            pool.execute(() -> {
                for (final String tg : targets) {
                    String r;
                    try {
                        try { r = FreeTranslator.translate(http, t, from, tg); }
                        catch (Exception first) { r = FreeTranslator.translate(http, t, from, tg); }
                    } catch (Exception e) { r = ""; }
                    final String res = r == null ? "" : r.trim();
                    main.post(() -> {
                        for (TextView row : rowViews) {
                            if (tg.equals(row.getTag())) row.setText(res.isEmpty() ? "—" : res);
                        }
                        if (firstTr.isEmpty() && !res.isEmpty()) { firstTr = res; firstTrLang = tg; }
                    });
                }
            });
        } catch (Exception ignored) { }
    }

    private void copyTranslation() {
        if (firstTr.isEmpty()) return;
        try {
            ClipboardManager cm = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
            if (cm != null) cm.setPrimaryClip(ClipData.newPlainText("translation", firstTr));
            Toast.makeText(this, L("کپی شد", "Copied"), Toast.LENGTH_SHORT).show();
        } catch (Throwable ignored) { }
    }

    private void queueWord(String action) {
        try {
            JSONObject o = new JSONObject()
                    .put("key", action + "|" + src + "|" + text.toLowerCase(Locale.ROOT))
                    .put("action", action)
                    .put("word", text)
                    .put("lang", src)
                    .put("meaning", firstTr)
                    .put("meaningLang", firstTrLang)
                    .put("sentence", text)
                    .put("rev", System.currentTimeMillis());
            WordQueue.add(this, o);
            BubblePlugin.notifyWordQueued();
        } catch (Throwable t) {
            Toast.makeText(this, L("ذخیره نشد", "Save failed"), Toast.LENGTH_SHORT).show();
        }
    }

    @Override
    protected void onDestroy() {
        pool.shutdownNow();
        try { if (dialog != null && dialog.isShowing()) dialog.dismiss(); } catch (Throwable ignored) { }
        super.onDestroy();
    }
}
