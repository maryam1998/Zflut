package com.linglearn.app.overlay;

import org.json.JSONArray;
import org.json.JSONObject;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
import okhttp3.ResponseBody;

/**
 * 🎵 ترانه‌ی زنده‌ی آهنگ از LRCLIB (https://lrclib.net).
 *
 * فقط «نامِ آهنگ + خواننده + مدت» (از MediaSession/نوتیفیکیشنِ پلیر) به LRCLIB فرستاده می‌شود و ترانه‌ی
 * زمان‌دار به‌صورتِ زنده فقط در حافظه (RAM) نگه داشته و نشان داده می‌شود؛ هیچ‌جا روی دیسک ذخیره نمی‌شود
 * (نه کش، نه تاریخچه، نه «داستان‌های ذخیره‌شده») و با تغییرِ آهنگ یا بستنِ کادر دور ریخته می‌شود.
 */
final class SongLyrics {

    private SongLyrics() {}

    private static final String API = "https://lrclib.net/api";
    private static final String UA = "LingoLearn/1.0 (https://github.com/maryam1998/Hope)";

    /** ترانه‌ی زمان‌دار پیدا نشد. */
    static final class NotFound extends Exception {
        NotFound() { super("no synced lyrics"); }
    }

    private static final Pattern TS = Pattern.compile("\\[(\\d{1,3}):(\\d{1,2})(?:[.:](\\d{1,3}))?\\]");
    // «(feat. X)»، «[Official Video]»، «- Remastered 2011»، «- Topic» و …
    private static final Pattern NOISE = Pattern.compile(
            "(?i)\\s*[\\(\\[][^\\)\\]]*(official|video|audio|lyric|lyrics|visuali[sz]er|remaster|live|feat\\.?|ft\\.?|hd|4k|mv)[^\\)\\]]*[\\)\\]]"
                    + "|\\s+-\\s+(remaster(ed)?( \\d{4})?|\\d{4} remaster(ed)?|single version|radio edit|topic)\\s*$");

    static String cleanTitle(String t) {
        if (t == null) return "";
        String x = t;
        String y;
        do { y = x; x = NOISE.matcher(x).replaceAll(""); } while (!x.equals(y));
        return x.replaceAll("\\s+", " ").trim();
    }

    static String cleanArtist(String a) {
        if (a == null) return "";
        String x = a.replaceAll("(?i)\\s*-\\s*topic\\s*$", "").trim();
        int c = x.indexOf(',');            // «A, B» → فقط خوانده‌ی اول
        if (c > 0) x = x.substring(0, c).trim();
        return x;
    }

    /** ترانه‌ی همگام را می‌گیرد؛ Cue ها فقط در حافظه‌اند. NotFound = نبود. */
    static List<YtSubtitles.Cue> fetch(OkHttpClient http, String title, String artist, long durSec) throws Exception {
        final String t = cleanTitle(title), a = cleanArtist(artist);
        if (t.isEmpty()) throw new NotFound();

        // ۱) دقیق (با مدت)
        if (!a.isEmpty() && durSec > 0) {
            String u = API + "/get?track_name=" + enc(t) + "&artist_name=" + enc(a) + "&duration=" + durSec;
            String body = getOrNull(http, u);
            List<YtSubtitles.Cue> c = body == null ? null : parseObj(new JSONObject(body));
            if (c != null) return c;
        }
        // ۲) جستجو (نزدیک‌ترین مدت، فقط نتیجه‌ی دارای ترانه‌ی همگام)
        String[] queries = new String[]{
                API + "/search?track_name=" + enc(t) + (a.isEmpty() ? "" : "&artist_name=" + enc(a)),
                API + "/search?q=" + enc((a + " " + t).trim())
        };
        for (String u : queries) {
            String body = getOrNull(http, u);
            if (body == null) continue;
            JSONArray arr = new JSONArray(body);
            JSONObject best = null;
            long bestDiff = Long.MAX_VALUE;
            for (int i = 0; i < arr.length(); i++) {
                JSONObject o = arr.optJSONObject(i);
                if (o == null) continue;
                String lrc = o.optString("syncedLyrics", "");
                if (lrc.isEmpty() || "null".equals(lrc) || o.optBoolean("instrumental", false)) continue;
                long diff = durSec > 0 ? Math.abs(Math.round(o.optDouble("duration", durSec)) - durSec) : 0;
                if (durSec > 0 && diff > 6) continue;           // آهنگِ دیگری با همین نام
                if (diff < bestDiff) { bestDiff = diff; best = o; }
            }
            if (best != null) {
                List<YtSubtitles.Cue> c = parseObj(best);
                if (c != null) return c;
            }
        }
        throw new NotFound();
    }

    private static List<YtSubtitles.Cue> parseObj(JSONObject o) {
        String lrc = o.optString("syncedLyrics", "");
        if (lrc.isEmpty() || "null".equals(lrc)) return null;
        List<YtSubtitles.Cue> c = parseLrc(lrc);
        return c.size() >= 3 ? c : null;
    }

    /** LRC → Cue ها (هر خط یک Cue؛ خط‌های خالی/ساز فقط پایانِ خطِ قبل را تعیین می‌کنند). */
    static List<YtSubtitles.Cue> parseLrc(String lrc) {
        final ArrayList<long[]> starts = new ArrayList<>();
        final ArrayList<String> texts = new ArrayList<>();
        for (String raw : lrc.split("\\r?\\n")) {
            Matcher m = TS.matcher(raw);
            ArrayList<Long> times = new ArrayList<>();
            int end = 0;
            while (m.find() && m.start() == end) {
                long min = Long.parseLong(m.group(1));
                long sec = Long.parseLong(m.group(2));
                String f = m.group(3);
                long ms = 0;
                if (f != null) {
                    ms = Long.parseLong(f);
                    if (f.length() == 1) ms *= 100; else if (f.length() == 2) ms *= 10;
                }
                times.add(min * 60_000L + sec * 1000L + ms);
                end = m.end();
            }
            if (times.isEmpty()) continue;
            String text = raw.substring(end).replaceAll("<\\d+:\\d+(?:[.:]\\d+)?>", "").replaceAll("\\s+", " ").trim();
            for (long tms : times) { starts.add(new long[]{tms, starts.size()}); texts.add(text); }
        }
        // بر اساس زمان مرتب (خط‌های چندزمانه)
        Integer[] order = new Integer[starts.size()];
        for (int i = 0; i < order.length; i++) order[i] = i;
        java.util.Arrays.sort(order, (x, y) -> Long.compare(starts.get(x)[0], starts.get(y)[0]));
        ArrayList<YtSubtitles.Cue> out = new ArrayList<>();
        for (int k = 0; k < order.length; k++) {
            int i = order[k];
            String text = texts.get(i);
            if (text.isEmpty()) continue;
            long st = starts.get(i)[0];
            long en = (k + 1 < order.length) ? starts.get(order[k + 1])[0] : st + 5000;
            if (en <= st) en = st + 2500;
            out.add(new YtSubtitles.Cue(st, en, text));
        }
        return out;
    }

    private static String enc(String s) {
        try { return URLEncoder.encode(s, StandardCharsets.UTF_8.name()); } catch (Exception e) { return ""; }
    }

    /** 404 = null (پیدا نشد)؛ خطای شبکه/سرور = Exception. */
    private static String getOrNull(OkHttpClient http, String url) throws Exception {
        Request req = new Request.Builder().url(url).header("User-Agent", UA).get().build();
        try (Response r = http.newCall(req).execute()) {
            if (r.code() == 404) return null;
            ResponseBody b = r.body();
            String s = b == null ? "" : b.string();
            if (!r.isSuccessful()) throw new Exception("HTTP " + r.code());
            return s;
        }
    }
}
