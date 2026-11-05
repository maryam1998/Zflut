/// نسخه‌ی سبکِ Parsivar (Normalizer) برای متن فارسی — بدون وابستگی.
/// معادلِ PersianNormalizer.java در اندروید:
/// ی/ک عربی → فارسی، حذف تطویل و اعراب و کاراکترهای کنترلی، نیم‌فاصله‌ی «می‌/ها/تر/ترین»،
/// اصلاح علائم نگارشی و تبدیل اعداد به حروف.
class PersianNormalizer {
  PersianNormalizer._();

  static const String zwnj = '\u200C';

  static final RegExp _thousands = RegExp(r'(?<=\d),(?=\d{3}(?!\d))');
  static final RegExp _number = RegExp(r'\d+(?:\.\d+)?');
  static final RegExp _miPrefix =
      RegExp('(?<![\u0621-\u06CC])(ن?می) (?=[\u0621-\u06CC])');
  static final RegExp _haSuffix = RegExp(
      ' (ها|های|هایی|هایم|هایت|هایش|هامان|هاتان|هاشان)(?![\u0621-\u06CC])');
  static final RegExp _tarSuffix =
      RegExp(' (تر|ترین|تری)(?![\u0621-\u06CC])');
  static final RegExp _spaceBeforePunct = RegExp(r'\s+([,.;:!?])');
  static final RegExp _multiSpace = RegExp(r'[ \t]+');

  static String normalize(String? input) {
    if (input == null || input.isEmpty) return '';
    final sb = StringBuffer();
    for (final c in input.runes) {
      switch (c) {
        case 0x064A: // ي
        case 0x0649: // ى
        case 0x06CC: // ی
          sb.write('\u06CC');
          break;
        case 0x0643: // ك
          sb.write('\u06A9');
          break;
        case 0x0629: // ة
          sb.write('\u0647');
          break;
        case 0x06C0: // ۀ
          sb.write('\u0647$zwnj\u06CC');
          break;
        case 0x0640: // تطویل
          break;
        case 0x060C:
        case 0x066C:
          sb.write(',');
          break;
        case 0x061B:
          sb.write(';');
          break;
        case 0x061F:
          sb.write('?');
          break;
        case 0x066B:
        case 0x2026:
          sb.write('.');
          break;
        case 0x201C:
        case 0x201D:
        case 0x00AB:
        case 0x00BB:
        case 0x22:
          sb.write(' ');
          break;
        case 0x2018:
        case 0x2019:
        case 0x27:
          break;
        case 0x0D:
        case 0x0A:
        case 0x09:
          sb.write(' ');
          break;
        case 0x200D:
        case 0x200E:
        case 0x200F:
        case 0xFEFF:
        case 0x202A:
        case 0x202B:
        case 0x202C:
        case 0x202D:
        case 0x202E:
        case 0x2066:
        case 0x2067:
        case 0x2068:
        case 0x2069:
          break;
        default:
          if (c >= 0x06F0 && c <= 0x06F9) {
            sb.writeCharCode(0x30 + (c - 0x06F0));
          } else if (c >= 0x0660 && c <= 0x0669) {
            sb.writeCharCode(0x30 + (c - 0x0660));
          } else if ((c >= 0x064B && c <= 0x065F) || c == 0x0670) {
            // اعراب
          } else if (c < 32) {
            sb.write(' ');
          } else {
            sb.writeCharCode(c);
          }
      }
    }
    var r = sb.toString();
    r = r.replaceAll(_thousands, '');
    r = numbersToWords(r);
    r = r.replaceAllMapped(_miPrefix, (m) => '${m[1]}$zwnj');
    r = r.replaceAllMapped(_haSuffix, (m) => '$zwnj${m[1]}');
    r = r.replaceAllMapped(_tarSuffix, (m) => '$zwnj${m[1]}');
    r = r.replaceAll(_multiSpace, ' ');
    r = r.replaceAllMapped(_spaceBeforePunct, (m) => m[1]!);
    return r.trim();
  }

  // ---------------- اعداد → حروف ----------------
  static const _ones = [
    'صفر', 'یک', 'دو', 'سه', 'چهار', 'پنج', 'شش', 'هفت', 'هشت', 'نه', 'ده',
    'یازده', 'دوازده', 'سیزده', 'چهارده', 'پانزده', 'شانزده', 'هفده', 'هجده',
    'نوزده'
  ];
  static const _tens = [
    '', '', 'بیست', 'سی', 'چهل', 'پنجاه', 'شصت', 'هفتاد', 'هشتاد', 'نود'
  ];
  static const _hundreds = [
    '', 'صد', 'دویست', 'سیصد', 'چهارصد', 'پانصد', 'ششصد', 'هفتصد', 'هشتصد',
    'نهصد'
  ];
  static const _scales = ['', 'هزار', 'میلیون', 'میلیارد', 'تریلیون'];

  static String numbersToWords(String s) {
    return s.replaceAllMapped(_number, (m) {
      final num = m[0]!;
      final dot = num.indexOf('.');
      String rep;
      if (dot < 0) {
        rep = intToWords(num);
      } else {
        final frac = num.substring(dot + 1);
        final fw = StringBuffer();
        var z = 0;
        while (z < frac.length && frac[z] == '0') {
          fw.write('صفر ');
          z++;
        }
        if (z < frac.length) fw.write(intToWords(frac.substring(z)));
        rep = '${intToWords(num.substring(0, dot))} ممیز ${fw.toString().trim()}';
      }
      return ' $rep ';
    });
  }

  static String intToWords(String digits) {
    final d = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (d.length > 15) {
      return d.split('').map((ch) => _ones[int.parse(ch)]).join(' ');
    }
    var n = int.parse(d);
    if (n == 0) return _ones[0];
    final parts = <String>[];
    var scale = 0;
    while (n > 0) {
      final g = n % 1000;
      n ~/= 1000;
      if (g != 0) {
        final w = (g == 1 && scale == 1) ? '' : _group(g);
        parts.insert(0, ('${w.isEmpty ? '' : '$w '}${_scales[scale]}').trim());
      }
      scale++;
    }
    return parts.join(' و ');
  }

  static String _group(int g) {
    final p = <String>[];
    final h = g ~/ 100;
    final r = g % 100;
    if (h > 0) p.add(_hundreds[h]);
    if (r > 0) {
      if (r < 20) {
        p.add(_ones[r]);
      } else {
        p.add(_tens[r ~/ 10]);
        if (r % 10 > 0) p.add(_ones[r % 10]);
      }
    }
    return p.join(' و ');
  }
}
