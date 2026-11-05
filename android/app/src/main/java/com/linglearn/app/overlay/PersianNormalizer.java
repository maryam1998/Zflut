package com.linglearn.app.overlay;

import java.text.Normalizer;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * نسخه‌ی سبکِ Parsivar (Normalizer) برای متن فارسی — بدون هیچ وابستگی.
 * کارها: ی/ک عربی → فارسی، حذف تطویل و اعراب و کاراکترهای کنترلی، نیم‌فاصله‌ی «می‌/ها/تر/ترین»،
 * اصلاح علائم نگارشی و تبدیل اعداد به حروف (چون دیگر espeak-ng عددخوانی نمی‌کند).
 * خروجی همچنان نیم‌فاصله (U+200C) دارد؛ مصرف‌کننده خودش تصمیم می‌گیرد.
 */
final class PersianNormalizer {
    private PersianNormalizer() {}

    static final char ZWNJ = '\u200C';

    private static final Pattern THOUSANDS = Pattern.compile("(?<=\\d),(?=\\d{3}(?!\\d))");
    private static final Pattern NUMBER = Pattern.compile("\\d+(?:\\.\\d+)?");
    private static final Pattern MI_PREFIX = Pattern.compile("(?<![\\u0621-\\u06CC])(ن?می) (?=[\\u0621-\\u06CC])");
    private static final Pattern HA_SUFFIX = Pattern.compile(
            " (ها|های|هایی|هایم|هایت|هایش|هامان|هاتان|هاشان)(?![\\u0621-\\u06CC])");
    private static final Pattern TAR_SUFFIX = Pattern.compile(" (تر|ترین|تری)(?![\\u0621-\\u06CC])");
    private static final Pattern SPACE_BEFORE_PUNCT = Pattern.compile("\\s+([,.;:!?])");
    private static final Pattern MULTI_SPACE = Pattern.compile("[ \\t]+");

    static String normalize(String in) {
        if (in == null || in.isEmpty()) return "";
        String t;
        try { t = Normalizer.normalize(in, Normalizer.Form.NFKC); } catch (Throwable e) { t = in; }
        StringBuilder sb = new StringBuilder(t.length());
        for (int i = 0; i < t.length(); i++) {
            char c = t.charAt(i);
            switch (c) {
                case '\u064A': case '\u0649': case '\u06CC': sb.append('\u06CC'); break;   // ي ى ی → ی
                case '\u0643': sb.append('\u06A9'); break;                               // ك → ک
                case '\u0629': sb.append('\u0647'); break;                               // ة → ه
                case '\u06C0': sb.append('\u0647').append(ZWNJ).append('\u06CC'); break; // ۀ → ه‌ی
                case '\u0640': break;                                                    // تطویل
                case '\u060C': sb.append(','); break;
                case '\u061B': sb.append(';'); break;
                case '\u061F': sb.append('?'); break;
                case '\u066B': sb.append('.'); break;
                case '\u066C': sb.append(','); break;
                case '\u2026': sb.append('.'); break;
                case '\u201C': case '\u201D': case '\u00AB': case '\u00BB': case '"': sb.append(' '); break;
                case '\u2018': case '\u2019': case '\'': break;
                case '\r': case '\n': case '\t': sb.append(' '); break;
                case '\u200D': case '\u200E': case '\u200F': case '\uFEFF':
                case '\u202A': case '\u202B': case '\u202C': case '\u202D': case '\u202E':
                case '\u2066': case '\u2067': case '\u2068': case '\u2069':
                    break;
                default:
                    if (c >= '\u06F0' && c <= '\u06F9') sb.append((char) ('0' + (c - '\u06F0')));
                    else if (c >= '\u0660' && c <= '\u0669') sb.append((char) ('0' + (c - '\u0660')));
                    else if ((c >= '\u064B' && c <= '\u065F') || c == '\u0670') { /* اعراب */ }
                    else if (c < 32) sb.append(' ');
                    else sb.append(c);
            }
        }
        String r = sb.toString();
        r = THOUSANDS.matcher(r).replaceAll("");
        r = numbersToWords(r);
        r = MI_PREFIX.matcher(r).replaceAll("$1" + ZWNJ);
        r = HA_SUFFIX.matcher(r).replaceAll(ZWNJ + "$1");
        r = TAR_SUFFIX.matcher(r).replaceAll(ZWNJ + "$1");
        r = MULTI_SPACE.matcher(r).replaceAll(" ");
        r = SPACE_BEFORE_PUNCT.matcher(r).replaceAll("$1");
        return r.trim();
    }

    // ---------------- اعداد → حروف ----------------
    private static final String[] ONES = {"صفر", "یک", "دو", "سه", "چهار", "پنج", "شش", "هفت", "هشت", "نه",
            "ده", "یازده", "دوازده", "سیزده", "چهارده", "پانزده", "شانزده", "هفده", "هجده", "نوزده"};
    private static final String[] TENS = {"", "", "بیست", "سی", "چهل", "پنجاه", "شصت", "هفتاد", "هشتاد", "نود"};
    private static final String[] HUNDREDS = {"", "صد", "دویست", "سیصد", "چهارصد", "پانصد", "ششصد", "هفتصد", "هشتصد", "نهصد"};
    private static final String[] SCALES = {"", "هزار", "میلیون", "میلیارد", "تریلیون"};

    static String numbersToWords(String s) {
        Matcher m = NUMBER.matcher(s);
        StringBuffer out = new StringBuffer();
        while (m.find()) {
            String num = m.group();
            String rep;
            int dot = num.indexOf('.');
            if (dot < 0) {
                rep = intToWords(num);
            } else {
                String frac = num.substring(dot + 1);
                StringBuilder fw = new StringBuilder();
                int z = 0;
                while (z < frac.length() && frac.charAt(z) == '0') { fw.append("صفر "); z++; }
                if (z < frac.length()) fw.append(intToWords(frac.substring(z)));
                rep = intToWords(num.substring(0, dot)) + " ممیز " + fw.toString().trim();
            }
            m.appendReplacement(out, Matcher.quoteReplacement(" " + rep + " "));
        }
        m.appendTail(out);
        return out.toString();
    }

    static String intToWords(String digits) {
        String d = digits.replaceFirst("^0+(?=\\d)", "");
        if (d.length() > 15) {                       // خیلی بلند: رقم‌به‌رقم
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < d.length(); i++) { if (i > 0) sb.append(' '); sb.append(ONES[d.charAt(i) - '0']); }
            return sb.toString();
        }
        long n = Long.parseLong(d);
        if (n == 0) return ONES[0];
        java.util.ArrayList<String> parts = new java.util.ArrayList<>();
        int scale = 0;
        while (n > 0) {
            int g = (int) (n % 1000);
            n /= 1000;
            if (g != 0) {
                String w = (g == 1 && scale == 1) ? "" : groupToWords(g);
                String p = (w.isEmpty() ? "" : w + " ") + SCALES[scale];
                parts.add(0, p.trim());
            }
            scale++;
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < parts.size(); i++) { if (i > 0) sb.append(" و "); sb.append(parts.get(i)); }
        return sb.toString();
    }

    private static String groupToWords(int g) {
        java.util.ArrayList<String> p = new java.util.ArrayList<>();
        int h = g / 100, r = g % 100;
        if (h > 0) p.add(HUNDREDS[h]);
        if (r > 0) {
            if (r < 20) p.add(ONES[r]);
            else {
                p.add(TENS[r / 10]);
                if (r % 10 > 0) p.add(ONES[r % 10]);
            }
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < p.size(); i++) { if (i > 0) sb.append(" و "); sb.append(p.get(i)); }
        return sb.toString();
    }
}
