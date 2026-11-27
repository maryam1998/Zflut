#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
🔤 رومی‌سازیِ «محتوای ثابت» (یک‌بار اجرا) — ژاپنی، چینی، کره‌ای، هندی، روسی → حروفِ لاتین

ورودی : assets/data/free_translations.json   (ساختار: {"v":1,"t":{"<english>":{"hi":"…","zh":"…",…}}})
خروجی : assets/data/free_romanization.json   (همان کلیدها: {"v":1,"r":{"<english>":{"hi":"aap kaise hain?",…}}})

کتابخانه‌ها (همه رایگان، آفلاین، بدونِ API):
  zh  → pypinyin  (+ اختیاری jieba برای چسباندنِ هجاها به‌صورتِ «کلمه»)   → پین‌یینِ همراهِ تُن
  ja  → pykakasi                                                          → هپبورن (روماجی)
  ko  → korean-romanizer                                                  → Revised Romanization (با قوانینِ تلفظ)
  hi  → بدونِ کتابخانه (همین فایل): کتابخانه‌های موجود حذفِ «آ»ی پایانی/میانی را انجام نمی‌دهند
        و «नाम» را «naama» می‌نویسند؛ اینجا حذفِ schwa پیاده شده → «naam»
  ru  → بدونِ کتابخانه (جدولِ ساده، مثلِ BGN/PCGN ولی فقط ASCII)

نصب:
  pip install pypinyin pykakasi korean-romanizer jieba

اجرا (از ریشه‌ی پروژه):
  python3 scripts/romanize-static.py              ← همه‌ی زبان‌ها → assets/data/free_romanization.json
  python3 scripts/romanize-static.py --selftest   ← فقط چند جمله‌ی نمونه را چاپ می‌کند تا با چشم چک کنی
  python3 scripts/romanize-static.py --langs=hi,ru
  python3 scripts/romanize-static.py --src=… --out=…

بعد از هر تغییر در free_translations.json دوباره اجرا کن (اجرا سریع و قطعی است).
"""
import argparse
import json
import re
import sys
import unicodedata
from pathlib import Path

DEFAULT_LANGS = ["hi", "zh", "ja", "ko", "ru"]

# ───────────────────────── پس‌پردازشِ مشترک (علامت‌ها، فاصله‌ها، حرفِ بزرگِ اولِ جمله) ─────────────────────────
_PUNCT = {
    "。": ". ", "｡": ". ", "．": ". ", "।": ". ", "॥": ". ",
    "，": ", ", "、": ", ", "､": ", ", "､": ", ",
    "！": "! ", "？": "? ", "：": ": ", "；": "; ",
    "（": " (", "）": ") ", "［": " [", "］": "] ",
    "「": ' "', "」": '" ', "『": ' "', "』": '" ',
    "“": '"', "”": '"', "«": '"', "»": '"', "‘": "'", "’": "'",
    "～": "~", "〜": "~", "・": " ", "　": " ", "—": " - ", "–": "-",
}
_PUNCT_TABLE = {ord(k): v for k, v in _PUNCT.items()}
_DIGITS_HI = {ord(c): str(i) for i, c in enumerate("०१२३४५६७८९")}


def tidy(s: str) -> str:
    s = s.translate(_PUNCT_TABLE).translate(_DIGITS_HI)
    s = re.sub(r"\s+", " ", s)
    s = re.sub(r"\s+([,.!?;:)\]])", r"\1", s)          # فاصله قبل از علامت نباشد
    s = re.sub(r"([(\[])\s+", r"\1", s)                 # فاصله بعد از پرانتزِ باز نباشد
    s = re.sub(r'"\s+(?=[,.!?;:])', '"', s)
    s = s.strip()
    # حرفِ بزرگِ اولِ جمله (اولِ متن، بعد از . ! ? … و بعد از گیومه/پرانتز بازِ اولِ جمله)
    s = re.sub(
        r'(^|[.!?…]\s+)(["(\[]?)([^\W\d_])',
        lambda m: m.group(1) + m.group(2) + m.group(3).upper(),
        s,
    )
    return s


# ───────────────────────── هندی (دوناگری → لاتین، با حذفِ schwa) ─────────────────────────
_HI_VOWELS = {  # حروفِ صدادارِ مستقل
    "अ": "a", "आ": "aa", "इ": "i", "ई": "ee", "उ": "u", "ऊ": "oo", "ऋ": "ri",
    "ए": "e", "ऐ": "ai", "ओ": "o", "औ": "au", "ऑ": "o", "ऍ": "e",
}
_HI_MATRAS = {
    "ा": "aa", "ि": "i", "ी": "ee", "ु": "u", "ू": "oo", "ृ": "ri",
    "े": "e", "ै": "ai", "ो": "o", "ौ": "au", "ॉ": "o", "ॅ": "e",
}
_HI_CONS = {
    "क": "k", "ख": "kh", "ग": "g", "घ": "gh", "ङ": "ng",
    "च": "ch", "छ": "chh", "ज": "j", "झ": "jh", "ञ": "ny",
    "ट": "t", "ठ": "th", "ड": "d", "ढ": "dh", "ण": "n",
    "त": "t", "थ": "th", "द": "d", "ध": "dh", "न": "n",
    "प": "p", "फ": "ph", "ब": "b", "भ": "bh", "म": "m",
    "य": "y", "र": "r", "ल": "l", "व": "v", "श": "sh", "ष": "sh", "स": "s", "ह": "h",
    "ळ": "l",
}
_HI_NUKTA = {  # base + ़
    "क": "q", "ख": "kh", "ग": "g", "ज": "z", "ड": "r", "ढ": "rh", "फ": "f", "य": "y",
}
_VIRAMA, _NUKTA = "्", "़"
_NASALS = {"ं": "n", "ँ": "n", "ः": "h"}
_LABIALS = set("पफबभम")
_DEVA = re.compile(r"[\u0900-\u097F]+")


def _hi_word(word: str) -> str:
    """یک «کلمه»ی دوناگری (بدونِ فاصله) → لاتین. هر هجا = dict(on, cl, v, nasal)."""
    word = unicodedata.normalize("NFC", word)
    units = []          # هجاها
    cur = None          # هجای در حالِ ساخت: {"cons": [...]}
    i, n = 0, len(word)

    def flush(vowel):   # vowel: None = schwa
        nonlocal cur
        if cur is not None:
            units.append({"on": "".join(cur["cons"]), "cl": len(cur["cons"]) > 1,
                          "v": vowel, "nasal": ""})
            cur = None

    while i < n:
        ch = word[i]
        if ch in _HI_CONS:
            rom = _HI_CONS[ch]
            if i + 1 < n and word[i + 1] == _NUKTA:
                rom = _HI_NUKTA.get(ch, rom)
                i += 1
            if cur is not None and cur.get("open"):          # بعد از virama → ادامه‌ی خوشه
                cur["cons"].append(rom)
                cur["open"] = False
            else:
                flush(None)                                    # هجای قبلی schwa داشت
                cur = {"cons": [rom], "open": False}
        elif ch == _VIRAMA:
            if cur is not None:
                cur["open"] = True
        elif ch in _HI_MATRAS:
            flush(_HI_MATRAS[ch])
        elif ch in _HI_VOWELS:
            flush(None)
            units.append({"on": "", "cl": False, "v": _HI_VOWELS[ch], "nasal": ""})
        elif ch in _NASALS:
            flush(None)
            if units:
                nxt = word[i + 1] if i + 1 < n else ""
                units[-1]["nasal"] = "m" if (ch == "ं" and nxt in _LABIALS) else _NASALS[ch]
        elif ch == _NUKTA:
            pass
        else:
            flush(None)
            units.append({"on": unicodedata.normalize("NFKD", ch), "cl": False, "v": "", "nasal": ""})
        i += 1
    # خوشه‌ی بازِ پایانِ کلمه (مثلاً «…्») بدونِ schwa بسته می‌شود
    if cur is not None:
        if cur.get("open"):
            units.append({"on": "".join(cur["cons"]), "cl": len(cur["cons"]) > 1, "v": "", "nasal": ""})
            cur = None
        else:
            flush(None)

    # ── حذفِ schwa ──
    # ۱) schwaی پایانِ کلمه (به‌جز کلمه‌ی تک‌هجایی و هجای نون‌دار)
    # ۲) schwaی میانی: از راست به چپ؛ حذف فقط اگر هجای قبلی صدا دارد، هجای بعدی صدایش حفظ می‌شود
    #    و هجای بعدی با خوشه (مثلِ «ste» در «नमस्ते») شروع نمی‌شود.
    is_schwa = lambda u: u["v"] is None and u["on"] != ""
    if len(units) > 1 and is_schwa(units[-1]) and not units[-1]["nasal"]:
        units[-1]["v"] = ""
    for k in range(len(units) - 2, 0, -1):
        u, prev, nxt = units[k], units[k - 1], units[k + 1]
        if not is_schwa(u) or u["nasal"] or u["cl"]:   # هجای نون‌دار/خوشه‌ای (मन्य…) schwa را نگه می‌دارد
            continue
        if prev["v"] == "":                  # هجای قبلی صدایش حذف شده → حذفِ پشتِ‌هم ممنوع
            continue
        if nxt["v"] == "" or nxt["cl"]:      # هجای بعدی صدا ندارد یا با خوشه شروع می‌شود
            continue
        u["v"] = ""
    out = []
    last = len(units) - 1
    for idx, u in enumerate(units):
        v = "a" if u["v"] is None and u["on"] else (u["v"] or "")
        # املای رایجِ «هینگلیش»: kya / mera / bhi / khushi / hui / mein
        if v == "aa" and idx == last and u["on"] and not u["nasal"]:
            v = "a"                                   # کا → ka (نه kaa)
        elif v == "ee" and (idx == last or (u["on"] == "" and idx > 0)):
            v = "i"                                   # भी → bhi ، हुई → hui
        elif v == "e" and u["nasal"] == "n":
            v = "ei"                                  # में → mein
        out.append(u["on"] + v + u["nasal"])
    return "".join(out)


def romanize_hi(text: str) -> str:
    text = unicodedata.normalize("NFC", text)
    return tidy(_DEVA.sub(lambda m: _hi_word(m.group(0)), text))


# ───────────────────────── روسی ─────────────────────────
_RU = {
    "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "ё": "yo", "ж": "zh", "з": "z", "и": "i",
    "й": "y", "к": "k", "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r", "с": "s",
    "т": "t", "у": "u", "ф": "f", "х": "kh", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "shch",
    "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya",
}
_RU_VOWELS_SIGNS = set("аеёиоуэюяъь")  # «ы» عمداً نیست: впервые → vpervye (نه vpervyye)


def romanize_ru(text: str) -> str:
    text = unicodedata.normalize("NFC", text)
    out = []
    n = len(text)
    for i, ch in enumerate(text):
        low = ch.lower()
        if low == "е":  # «е» = ye در ابتدای کلمه و بعد از مصوت/ъ/ь، وگرنه e
            prev = text[i - 1].lower() if i > 0 else ""
            rep = "ye" if (not prev.isalpha() or prev in _RU_VOWELS_SIGNS) else "e"
        elif low in _RU:
            rep = _RU[low]
        else:
            out.append(ch)
            continue
        if ch != low and rep:  # حرفِ بزرگ
            nxt = text[i + 1] if i + 1 < n else ""
            prv = text[i - 1] if i > 0 else ""
            allcaps = (nxt.isalpha() and nxt.isupper()) or (prv.isalpha() and prv.isupper())
            rep = rep.upper() if (allcaps and len(rep) > 1) else rep.capitalize()
        out.append(rep)
    return tidy("".join(out))


# ───────────────────────── چینی (pypinyin [+ jieba]) ─────────────────────────
_HAN = re.compile(r"[\u3400-\u9FFF]")


def make_zh():
    from pypinyin import lazy_pinyin, Style
    try:
        import jieba  # اختیاری: هجاها را در سطحِ کلمه بچسباند («gāoxìng» به‌جای «gāo xìng»)
        jieba.setLogLevel(60)
    except Exception:
        jieba = None

    def conv(text: str) -> str:
        text = unicodedata.normalize("NFC", text)
        parts = []
        tokens = jieba.cut(text) if jieba else [text]
        for tok in tokens:
            if not _HAN.search(tok):
                parts.append(tok)
                continue
            syl = lazy_pinyin(tok, style=Style.TONE)
            # بدونِ jieba: هر هجا جدا؛ با jieba: هجاهای یک کلمه به‌هم چسبیده، کلمه‌ها با فاصله
            parts.append((" " if not jieba else "").join(syl))
            parts.append(" ")
        return tidy("".join(parts))

    return conv


# ───────────────────────── ژاپنی (pykakasi) ─────────────────────────
_JA_FIX = {  # قطعه‌هایی که pykakasi به‌صورتِ املا می‌نویسد (ha / he / wo) ولی تلفظ فرق دارد
    "は": "wa", "へ": "e", "を": "o",
    "こんにちは": "konnichiwa", "こんばんは": "konbanwa",
}


def make_ja():
    import pykakasi
    kks = pykakasi.kakasi()

    def conv(text: str) -> str:
        text = unicodedata.normalize("NFKC", text)
        parts = []
        for seg in kks.convert(text):
            orig = seg.get("orig", "")
            parts.append(_JA_FIX.get(orig, seg.get("hepburn", orig)))
        return tidy(" ".join(parts))

    return conv


# ───────────────────────── کره‌ای (korean-romanizer) ─────────────────────────
def make_ko():
    from korean_romanizer.romanizer import Romanizer

    def conv(text: str) -> str:
        text = unicodedata.normalize("NFC", text)
        return tidy(Romanizer(text).romanize())

    return conv


CONVERTERS = {
    "hi": lambda: romanize_hi,
    "ru": lambda: romanize_ru,
    "zh": make_zh,
    "ja": make_ja,
    "ko": make_ko,
}
INSTALL_HINT = {
    "zh": "pip install pypinyin jieba",
    "ja": "pip install pykakasi",
    "ko": "pip install korean-romanizer",
}

SELFTEST = {
    "hi": ["नमस्ते, आप कैसे हैं?", "मैं शिकागो से हूँ।", "आपसे मिलकर मुझे भी खुशी हुई।", "क्या आप यहाँ नए हैं?"],
    "zh": ["我也很高兴认识你。你是新来的吗？", "欢迎！你是哪里人？"],
    "ja": ["こんにちは！", "初対面（カジュアル）", "ようこそ！どこの出身？", "私は学生です。"],
    "ko": ["나도 만나서 반가워. 여기 새로 왔어?", "환영해! 어디에서 왔어?"],
    "ru": ["Мне тоже приятно. Ты здесь новенький?", "Добро пожаловать! Ты откуда?", "Я из Чикаго."],
}


def load_converters(langs):
    conv = {}
    for lang in langs:
        if lang not in CONVERTERS:
            sys.exit(f"زبانِ پشتیبانی‌نشده: {lang} (مجاز: {', '.join(CONVERTERS)})")
        try:
            conv[lang] = CONVERTERS[lang]()
        except ImportError as e:
            sys.exit(f"کتابخانه‌ی «{lang}» نصب نیست ({e}).\n   نصب: {INSTALL_HINT.get(lang, '?')}")
    return conv


def main():
    ap = argparse.ArgumentParser(description="رومی‌سازیِ ترجمه‌های ثابتِ اپ")
    ap.add_argument("--src", default="assets/data/free_translations.json")
    ap.add_argument("--out", default="assets/data/free_romanization.json")
    ap.add_argument("--langs", default=",".join(DEFAULT_LANGS))
    ap.add_argument("--selftest", action="store_true", help="فقط نمونه‌ها را چاپ کن")
    args = ap.parse_args()

    langs = [l.strip() for l in args.langs.split(",") if l.strip()]
    conv = load_converters(langs)

    if args.selftest:
        for lang in langs:
            print(f"── {lang}")
            for s in SELFTEST.get(lang, []):
                print(f"   {s}\n   → {conv[lang](s)}")
        return

    src = Path(args.src)
    if not src.exists():
        sys.exit(f"فایل پیدا نشد: {src} (از ریشه‌ی پروژه اجرا کن)")
    data = json.loads(src.read_text(encoding="utf-8"))
    table = data.get("t", {})

    result, count, empty = {}, 0, []
    for en, per in table.items():
        row = {}
        for lang in langs:
            txt = (per or {}).get(lang)
            if not txt:
                continue
            try:
                rom = conv[lang](txt)
            except Exception as e:  # یک جمله‌ی خراب نباید کلِ کار را بخواباند
                print(f"  ✗ [{lang}] {txt!r}: {e}", file=sys.stderr)
                continue
            if not rom or re.search(r"[\u0900-\u097F\u3040-\u30FF\u3400-\u9FFF\uAC00-\uD7AF\u0400-\u04FF]", rom):
                empty.append((lang, txt, rom))  # هنوز حرفِ غیرلاتین مانده = رومی‌سازیِ ناقص
                continue
            row[lang] = rom
            count += 1
        if row:
            result[en] = row

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({"v": 1, "r": result}, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"✓ {count} رومی‌سازی ({len(result)} متن × {len(langs)} زبان) → {out}")
    for lang, txt, rom in empty[:20]:
        print(f"  ⚠️ ناقص [{lang}] {txt!r} → {rom!r}", file=sys.stderr)
    if empty:
        print(f"  ⚠️ {len(empty)} مورد ناقص ردّ شد.", file=sys.stderr)


if __name__ == "__main__":
    main()
