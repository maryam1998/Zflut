package com.linglearn.app.overlay;

import java.util.HashMap;
import java.util.HashSet;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

/**
 * تشخیصِ زبانِ گفتار از روی «متنِ تشخیص‌داده‌شده» — کاملاً آفلاین و بدونِ وابستگی.
 *
 * زبان‌هایی که در تنظیماتِ اپ هستند: en de fr es it pt nl tr (لاتین) + fa ar ur (عربی‌خط)
 * + ru ja ko zh hi.
 *  - رسم‌الخطِ غیرلاتین (سیریلیک، هانگول، کانا، هان، دیواناگری) تقریباً قطعی است.
 *  - فارسی / عربی / اردو با حرف‌های اختصاصیِ هر کدام جدا می‌شوند (پ چ ژ گ ← فارسی، ة ي ك ← عربی، ٹ ڈ ے ← اردو).
 *  - زبان‌های لاتین با شمارشِ «کلمه‌های پرتکرار» + حرف‌های اختصاصی (ñ ß ç ğ ş ı …) امتیاز می‌گیرند.
 * جوابِ null یعنی «مطمئن نیستم» (متنِ خیلی کوتاه یا امتیازِ نزدیک).
 */
final class LangDetect {

    private LangDetect() {}

    private static final Map<String, Set<String>> STOP = new HashMap<>();

    private static void add(String lang, String csv) {
        Set<String> s = new HashSet<>();
        for (String w : csv.split(",")) { w = w.trim(); if (!w.isEmpty()) s.add(w); }
        STOP.put(lang, s);
    }

    static {
        add("en", "the,and,is,are,was,were,you,your,that,this,with,for,have,has,not,but,what,they,will,would,can,could,it's,i'm,don't,of,to,in,on,at,we,he,she,my,me,do,just,so,be,been,there,about,from,like,going,know,think,because");
        add("de", "der,die,das,und,ist,nicht,ich,du,sie,er,wir,ihr,ein,eine,einen,mit,für,auf,den,dem,des,zu,von,war,es,auch,aber,wie,was,wenn,dass,noch,nur,schon,mal,bin,habe,hat,sind,sich,doch,oder,wird");
        add("fr", "le,la,les,un,une,des,et,est,que,qui,pas,pour,dans,avec,sur,ce,cette,je,tu,il,elle,nous,vous,ils,ne,de,du,au,aux,en,mais,ou,où,plus,être,avoir,suis,sont,c'est,j'ai,n'est,très,fait,comme,tout");
        add("es", "el,la,los,las,un,una,y,es,que,no,por,para,con,en,de,del,se,lo,le,me,te,mi,tu,su,pero,como,más,muy,está,estoy,son,fue,hay,qué,cómo,yo,usted,esto,eso,ya,si,sí,también,porque,cuando");
        add("it", "il,lo,la,gli,le,un,una,e,è,che,non,per,con,di,da,in,su,mi,ti,si,ci,ma,come,più,molto,sono,siamo,questo,quello,anche,perché,cosa,io,tu,lui,lei,noi,voi,loro,ho,hai,ha,ha,del,della,nel,nella");
        add("pt", "o,a,os,as,um,uma,e,é,que,não,por,para,com,em,de,do,da,dos,das,no,na,se,me,te,eu,você,ele,ela,nós,eles,mas,como,mais,muito,está,estou,são,foi,tem,tenho,também,porque,quando,isso,isto,ao");
        add("nl", "de,het,een,en,is,niet,dat,die,ik,je,jij,hij,zij,wij,we,jullie,ze,van,voor,met,op,aan,in,te,maar,ook,als,dan,nog,wel,heb,hebben,ben,bent,zijn,was,wordt,naar,er,om,dit,deze,wat,hoe");
        add("tr", "bir,bu,ve,için,ile,de,da,ne,ben,sen,biz,siz,o,var,yok,çok,daha,gibi,ama,ki,mi,mı,mu,mü,değil,evet,hayır,şey,şu,ben,bunu,onu,olarak,kadar,sonra,her,en,ya,veya,çünkü,nasıl,neden");
    }

    private static final String[] LATIN = {"en", "de", "fr", "es", "it", "pt", "nl", "tr"};

    /** null = نامطمئن. */
    static String detect(String text) {
        if (text == null) return null;
        final String t = text.trim();
        if (t.length() < 3) return null;

        int fa = 0, ar = 0, ur = 0, arabicLetters = 0;
        int cyr = 0, hangul = 0, kana = 0, han = 0, deva = 0, latin = 0;
        for (int i = 0; i < t.length(); ) {
            int cp = t.codePointAt(i);
            i += Character.charCount(cp);
            if (!Character.isLetter(cp)) continue;
            if (cp >= 0x0600 && cp <= 0x06FF || cp >= 0x0750 && cp <= 0x077F) {
                arabicLetters++;
                switch (cp) {
                    case 0x067E: case 0x0686: case 0x0698: case 0x06AF: case 0x06A9: case 0x06CC:   // پ چ ژ گ ک ی
                        fa++; break;
                    case 0x0629: case 0x064A: case 0x0643: case 0x0649:                              // ة ي ك ى
                        ar++; break;
                    case 0x0679: case 0x0688: case 0x0691: case 0x06BA: case 0x06D2: case 0x06C1: case 0x06BE: // ٹ ڈ ڑ ں ے ہ ھ
                        ur++; break;
                    default: break;
                }
            } else if (cp >= 0x0400 && cp <= 0x04FF) cyr++;
            else if (cp >= 0xAC00 && cp <= 0xD7AF || cp >= 0x1100 && cp <= 0x11FF) hangul++;
            else if (cp >= 0x3040 && cp <= 0x30FF) kana++;
            else if (cp >= 0x4E00 && cp <= 0x9FFF) han++;
            else if (cp >= 0x0900 && cp <= 0x097F) deva++;
            else if (cp < 0x0250) latin++;
        }

        int total = arabicLetters + cyr + hangul + kana + han + deva + latin;
        if (total == 0) return null;

        // ── رسم‌الخطِ غیرلاتین (اگر غالب بود) ──
        if (kana > 0 && (kana + han) * 2 >= total) return "ja";
        if (hangul * 2 >= total) return "ko";
        if (han * 2 >= total) return "zh";
        if (deva * 2 >= total) return "hi";
        if (cyr * 2 >= total) return "ru";
        if (arabicLetters * 2 >= total) {
            if (ur > 0 && ur >= fa && ur >= ar) return "ur";
            if (fa > 0 && fa >= ar) return "fa";
            if (ar > 0) return "ar";
            // حرف‌های اختصاصی ندارد → با کلمه‌های پرتکرار حدس بزن
            return arabicByWords(t);
        }
        if (latin * 2 < total) return null;

        return latinLang(t);
    }

    private static String arabicByWords(String t) {
        int fa = 0, ar = 0, ur = 0;
        for (String w : t.split("[\\s\\p{Punct}\\u060C\\u061F]+")) {
            switch (w) {
                case "است": case "که": case "را": case "با": case "این": case "آن": case "من": case "تو": case "ما":
                case "برای": case "یک": case "هم": case "نه": case "بود": case "می": case "شد": case "هست": case "خیلی":
                    fa++; break;
                case "في": case "على": case "إلى": case "هذا": case "هذه": case "ذلك": case "أن": case "لا":
                case "هو": case "هي": case "كان": case "عن": case "مع":
                    ar++; break;
                case "ہے": case "ہیں": case "کا": case "کی": case "کے": case "اور": case "میں": case "نہیں": case "یہ":
                case "وہ": case "سے": case "کو": case "بھی": case "تھا": case "ہو":
                    ur++; break;
                default: break;
            }
        }
        if (fa == 0 && ar == 0 && ur == 0) return null;
        if (ur > fa && ur > ar) return "ur";
        if (ar > fa) return "ar";
        return "fa";
    }

    private static String latinLang(String t) {
        final String low = t.toLowerCase(Locale.ROOT).replace('\u2019', '\'');
        final String[] words = low.split("[^\\p{L}']+");
        int n = 0;
        for (String w : words) if (!w.isEmpty()) n++;
        if (n == 0) return null;

        final Map<String, Double> score = new HashMap<>();
        for (String l : LATIN) score.put(l, 0.0);

        for (String w : words) {
            if (w.isEmpty()) continue;
            for (String l : LATIN) {
                if (STOP.get(l).contains(w)) score.put(l, score.get(l) + 1.0);
            }
        }
        // حرف‌های اختصاصی
        bump(score, low, "ß", "de", 2.0);
        bump(score, low, "ä", "de", 1.0); bump(score, low, "ö", "de", 1.0); bump(score, low, "ü", "de", 1.0);
        bump(score, low, "ñ", "es", 2.0); bump(score, low, "¿", "es", 2.0); bump(score, low, "¡", "es", 2.0);
        bump(score, low, "ç", "fr", 0.7); bump(score, low, "è", "fr", 1.0); bump(score, low, "ê", "fr", 1.0);
        bump(score, low, "ù", "fr", 1.0); bump(score, low, "â", "fr", 0.7); bump(score, low, "œ", "fr", 1.5);
        bump(score, low, "ã", "pt", 2.0); bump(score, low, "õ", "pt", 2.0); bump(score, low, "ç", "pt", 0.7);
        bump(score, low, "ğ", "tr", 2.5); bump(score, low, "ş", "tr", 2.5); bump(score, low, "ı", "tr", 2.5);
        bump(score, low, "ö", "tr", 0.5); bump(score, low, "ü", "tr", 0.5);
        bump(score, low, "ì", "it", 1.0); bump(score, low, "ò", "it", 1.0);
        bump(score, low, "ij", "nl", 0.5);

        String best = null; double bs = 0, second = 0;
        for (String l : LATIN) {
            double s = score.get(l);
            if (s > bs) { second = bs; bs = s; best = l; }
            else if (s > second) second = s;
        }
        if (best == null) return n >= 4 ? "en" : null;         // هیچ نشانه‌ای نیست؛ لاتینِ ساده → انگلیسی (پیش‌فرضِ معقول)

        // حداقل شواهد: متنِ کوتاه باید حداقل یک نشانه و برتریِ واضح داشته باشد
        double margin = bs - second;
        if (n <= 3) return (bs >= 2 && margin >= 1) ? best : null;
        if (bs < 2 && margin < 1) return null;
        return margin >= 1 || bs >= 2.5 * Math.max(1, second) ? best : null;
    }

    private static void bump(Map<String, Double> score, String low, String ch, String lang, double w) {
        int idx = 0, c = 0;
        while ((idx = low.indexOf(ch, idx)) >= 0) { c++; idx += ch.length(); if (c >= 3) break; }
        if (c > 0) score.put(lang, score.get(lang) + w * c);
    }
}
