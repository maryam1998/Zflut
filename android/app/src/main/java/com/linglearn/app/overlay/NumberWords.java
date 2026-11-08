package com.linglearn.app.overlay;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * تبدیل اعداد به حروف قبل از TTS (انگلیسی و فارسی).
 * Kokoro (انگلیسی) و Piper/espeak (فارسی) اعداد را خودشان درست نمی‌خوانند؛ اینجا قبل از ساخت صدا
 * به کلمه تبدیل می‌شوند. فقط متنِ ورودیِ TTS عوض می‌شود، نه متنِ نمایش‌داده‌شده.
 */
final class NumberWords {
    private NumberWords() {}

    private static final Pattern TIME = Pattern.compile("(?<![\\w:.])(\\d{1,2}):(\\d{2})(?![\\w:])");
    private static final Pattern NUM = Pattern.compile(
            "(?<![\\w.])([$\u20AC\u00A3])?(\\d+)(?:\\.(\\d+))?(?!\\.\\d)(st|nd|rd|th)?(\\s?%)?");
    private static final Pattern FA_PERCENT = Pattern.compile("(\\d)\\s*%");

    /** lang = زبانِ «درخواستیِ» متن (نه زبانِ موتور). زبان‌های دیگر دست‌نخورده برمی‌گردند. */
    static String expand(String lang, String t) {
        if (t == null || t.isEmpty() || lang == null) return t;
        boolean hasDigit = false;
        for (int i = 0; i < t.length(); i++) {
            char c = t.charAt(i);
            if (c >= '0' && c <= '9') { hasDigit = true; break; }
        }
        if (!hasDigit) return t;
        try {
            if ("en".equals(lang)) return expandEn(t);
            if ("fa".equals(lang)) {
                String r = FA_PERCENT.matcher(t).replaceAll("$1 \u062F\u0631\u0635\u062F");
                r = PersianNormalizer.numbersToWords(r);
                return r.replaceAll("\\s+", " ").trim();
            }
        } catch (Throwable ignored) {}
        return t;
    }

    // ---------------- English ----------------
    private static final String[] ONES = {"zero", "one", "two", "three", "four", "five", "six", "seven", "eight",
            "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen",
            "eighteen", "nineteen"};
    private static final String[] TENS = {"", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy",
            "eighty", "ninety"};
    private static final String[] SCALES = {"", "thousand", "million", "billion", "trillion"};

    private static String expandEn(String s) {
        // ساعت: 10:30 → ten thirty
        Matcher tm = TIME.matcher(s);
        StringBuffer tb = new StringBuffer();
        while (tm.find()) {
            int h = Integer.parseInt(tm.group(1)), m = Integer.parseInt(tm.group(2));
            String rep;
            if (h > 24 || m > 59) rep = tm.group();
            else if (m == 0) rep = h == 0 ? "midnight" : (cardinal(h) + " o'clock");
            else if (m < 10) rep = cardinal(h) + " oh " + cardinal(m);
            else rep = cardinal(h) + " " + cardinal(m);
            tm.appendReplacement(tb, Matcher.quoteReplacement(rep));
        }
        tm.appendTail(tb);
        s = tb.toString();

        Matcher m = NUM.matcher(s);
        StringBuffer out = new StringBuffer();
        while (m.find()) {
            String cur = m.group(1), ip = m.group(2), fp = m.group(3), ord = m.group(4), pct = m.group(5);
            String rep;
            if (cur != null) {
                rep = money(cur, ip, fp);
            } else if (ord != null && fp == null) {
                rep = ordinal(ip);
            } else if (fp != null) {
                StringBuilder sb = new StringBuilder(bigOrDigits(ip)).append(" point");
                for (int i = 0; i < fp.length(); i++) sb.append(' ').append(ONES[fp.charAt(i) - '0']);
                rep = sb.toString();
            } else {
                rep = isYear(ip) ? year(Integer.parseInt(ip)) : bigOrDigits(ip);
            }
            if (pct != null) rep += " percent";
            if (m.end() < s.length() && Character.isLetter(s.charAt(m.end()))) rep += " ";   // 5km → five km
            m.appendReplacement(out, Matcher.quoteReplacement(rep));
        }
        m.appendTail(out);
        return out.toString().replaceAll("\\s+", " ").trim();
    }

    private static boolean isYear(String d) {
        if (d.length() != 4 || d.charAt(0) == '0') return false;
        int y = Integer.parseInt(d);
        return y >= 1100 && y <= 2099;
    }

    private static String year(int y) {
        if (y >= 2000 && y <= 2009) return y == 2000 ? "two thousand" : "two thousand " + cardinal(y - 2000);
        int hi = y / 100, lo = y % 100;
        if (lo == 0) return cardinal(hi) + " hundred";
        if (lo < 10) return cardinal(hi) + " oh " + cardinal(lo);
        return cardinal(hi) + " " + cardinal(lo);
    }

    /** صفرِ اول، یا خیلی بلند (شماره تلفن/کد) → رقم‌به‌رقم؛ وگرنه عددِ عادی. */
    private static String bigOrDigits(String d) {
        if (d.length() > 1 && d.charAt(0) == '0' || d.length() > 9) return digits(d);   // کد/شماره تلفن → رقم‌به‌رقم
        return cardinal(Long.parseLong(d));
    }

    private static String digits(String d) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < d.length(); i++) {
            if (i > 0) sb.append(' ');
            sb.append(ONES[d.charAt(i) - '0']);
        }
        return sb.toString();
    }

    private static String money(String cur, String ip, String fp) {
        String one, many, sub1, subN;
        if ("$".equals(cur)) { one = "dollar"; many = "dollars"; sub1 = "cent"; subN = "cents"; }
        else if ("\u20AC".equals(cur)) { one = "euro"; many = "euros"; sub1 = "cent"; subN = "cents"; }
        else { one = "pound"; many = "pounds"; sub1 = "penny"; subN = "pence"; }
        if (ip.length() > 12) return digits(ip);
        long whole = Long.parseLong(ip);
        StringBuilder sb = new StringBuilder(cardinal(whole)).append(' ').append(whole == 1 ? one : many);
        if (fp != null) {
            String f = (fp + "0").substring(0, 2);
            int c = Integer.parseInt(f);
            if (c > 0) sb.append(" and ").append(cardinal(c)).append(' ').append(c == 1 ? sub1 : subN);
        }
        return sb.toString();
    }

    static String cardinal(long n) {
        if (n < 0) return "minus " + cardinal(-n);
        if (n < 20) return ONES[(int) n];
        if (n < 100) return TENS[(int) (n / 10)] + (n % 10 > 0 ? "-" + ONES[(int) (n % 10)] : "");
        if (n < 1000) return ONES[(int) (n / 100)] + " hundred" + (n % 100 > 0 ? " " + cardinal(n % 100) : "");
        StringBuilder sb = new StringBuilder();
        int scale = 0;
        java.util.ArrayList<String> parts = new java.util.ArrayList<>();
        while (n > 0 && scale < SCALES.length) {
            int g = (int) (n % 1000);
            n /= 1000;
            if (g != 0) parts.add(0, cardinal(g) + (SCALES[scale].isEmpty() ? "" : " " + SCALES[scale]));
            scale++;
        }
        for (int i = 0; i < parts.size(); i++) { if (i > 0) sb.append(' '); sb.append(parts.get(i)); }
        return sb.toString();
    }

    private static String ordinal(String ip) {
        if (ip.length() > 12) return digits(ip);
        long n = Long.parseLong(ip);
        String c = cardinal(n);
        int sp = Math.max(c.lastIndexOf(' '), c.lastIndexOf('-'));
        String head = c.substring(0, sp + 1), last = c.substring(sp + 1);
        switch (last) {
            case "one": last = "first"; break;
            case "two": last = "second"; break;
            case "three": last = "third"; break;
            case "five": last = "fifth"; break;
            case "eight": last = "eighth"; break;
            case "nine": last = "ninth"; break;
            case "twelve": last = "twelfth"; break;
            default:
                if (last.endsWith("y")) last = last.substring(0, last.length() - 1) + "ieth";
                else last = last + "th";
        }
        return head + last;
    }
}
