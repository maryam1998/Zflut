// 📁 مسیر: lib/core/constants/app_appearance.dart

import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════
// تم‌ها (۱۳ تم از Hope)
// ═══════════════════════════════════════════════════════════════
class AppThemeDef {
  final String key;
  final String labelFa;
  final String labelEn;
  final Color swatch;
  final Color paper;
  final Color paperDark;
  final Color ink;
  final Color inkSoft;
  final Color gold;
  final Color goldSoft;
  final Color teal;
  final Color rose;
  final Color cardBorder;
  final Color headerFrom;
  final Color headerTo;
  final Color headerText;

  const AppThemeDef({
    required this.key,
    required this.labelFa,
    required this.labelEn,
    required this.swatch,
    required this.paper,
    required this.paperDark,
    required this.ink,
    required this.inkSoft,
    required this.gold,
    required this.goldSoft,
    required this.teal,
    required this.rose,
    required this.cardBorder,
    required this.headerFrom,
    required this.headerTo,
    required this.headerText,
  });
}

const kAppThemes = <String, AppThemeDef>{
  'vintage': AppThemeDef(
    key: 'vintage',
    labelFa: 'کلاسیک (پیش‌فرض)',
    labelEn: 'Classic (default)',
    swatch: Color(0xFFC99A2E),
    paper: Color(0xFFEFE6C9), paperDark: Color(0xFFE6DAB2),
    ink: Color(0xFF1E2A26), inkSoft: Color(0xFF4B5551),
    gold: Color(0xFFC99A2E), goldSoft: Color(0xFFE3C77E),
    teal: Color(0xFF1B4640), rose: Color(0xFF9E3B3B),
    cardBorder: Color(0xFFE7DEC1),
    headerFrom: Color(0xFF1B4640), headerTo: Color(0xFF1E2A26),
    headerText: Color(0xFFEFE6C9),
  ),
  'ocean': AppThemeDef(
    key: 'ocean', labelFa: 'اقیانوسی', labelEn: 'Ocean',
    swatch: Color(0xFF2E86DE),
    paper: Color(0xFFEAF4F4), paperDark: Color(0xFFD7E9EA),
    ink: Color(0xFF0F2A38), inkSoft: Color(0xFF2A4E5C),
    gold: Color(0xFF1C7C93), goldSoft: Color(0xFF8FCBD8),
    teal: Color(0xFF1C7C93), rose: Color(0xFFB4533F),
    cardBorder: Color(0xFFBBD6D8),
    headerFrom: Color(0xFF3AA0F2), headerTo: Color(0xFF1C7C93),
    headerText: Color(0xFFF4FBFD),
  ),
  'forest': AppThemeDef(
    key: 'forest', labelFa: 'جنگلی', labelEn: 'Forest',
    swatch: Color(0xFF2FA84F),
    paper: Color(0xFFF1F0E4), paperDark: Color(0xFFE2E0CC),
    ink: Color(0xFF26321D), inkSoft: Color(0xFF41522C),
    gold: Color(0xFF8A6D2F), goldSoft: Color(0xFFC9B77E),
    teal: Color(0xFF5C7A3A), rose: Color(0xFF9C4A3A),
    cardBorder: Color(0xFFCBCBA8),
    headerFrom: Color(0xFF3FAE5C), headerTo: Color(0xFF2C6B3D),
    headerText: Color(0xFFF5F8EC),
  ),
  'rosewine': AppThemeDef(
    key: 'rosewine', labelFa: 'گلبهی', labelEn: 'Rosewine',
    swatch: Color(0xFFC2185B),
    paper: Color(0xFFF7EAEA), paperDark: Color(0xFFEBD6D8),
    ink: Color(0xFF3A1F26), inkSoft: Color(0xFF5C3540),
    gold: Color(0xFFA34960), goldSoft: Color(0xFFE3AFBC),
    teal: Color(0xFF6E5A78), rose: Color(0xFFA34960),
    cardBorder: Color(0xFFDDBFC4),
    headerFrom: Color(0xFFD45079), headerTo: Color(0xFF9C2E56),
    headerText: Color(0xFFFDF1F2),
  ),
  'midnight': AppThemeDef(
    key: 'midnight', labelFa: 'تیره (شب)', labelEn: 'Midnight',
    swatch: Color(0xFF3F51B5),
    paper: Color(0xFF1B1F2A), paperDark: Color(0xFF262C3B),
    ink: Color(0xFFF1E8D6), inkSoft: Color(0xFFC9C2AE),
    gold: Color(0xFFD9A441), goldSoft: Color(0xFF8A6A2C),
    teal: Color(0xFF5FA997), rose: Color(0xFFD9776A),
    cardBorder: Color(0xFF3A4258),
    headerFrom: Color(0xFF4A5AC4), headerTo: Color(0xFF232A3D),
    headerText: Color(0xFFF1E8D6),
  ),
  'sunset': AppThemeDef(
    key: 'sunset', labelFa: 'غروب', labelEn: 'Sunset',
    swatch: Color(0xFFE8622C),
    paper: Color(0xFFFCEFE2), paperDark: Color(0xFFF5DFC6),
    ink: Color(0xFF3A2313), inkSoft: Color(0xFF6B4A2C),
    gold: Color(0xFFD9752E), goldSoft: Color(0xFFF0B784),
    teal: Color(0xFF4E7A6E), rose: Color(0xFFB23A3A),
    cardBorder: Color(0xFFE6C79E),
    headerFrom: Color(0xFFF0793D), headerTo: Color(0xFFC24A34),
    headerText: Color(0xFFFDF3E7),
  ),
  'lavender': AppThemeDef(
    key: 'lavender', labelFa: 'بنفش (اسطوخودوس)', labelEn: 'Lavender',
    swatch: Color(0xFF8E44AD),
    paper: Color(0xFFF1EEF8), paperDark: Color(0xFFE1DAF0),
    ink: Color(0xFF2C2140), inkSoft: Color(0xFF4C3E68),
    gold: Color(0xFF7A5FA8), goldSoft: Color(0xFFC5B3E3),
    teal: Color(0xFF4C7A8A), rose: Color(0xFFA8517F),
    cardBorder: Color(0xFFD2C5EA),
    headerFrom: Color(0xFF9C5FC4), headerTo: Color(0xFF6A3F92),
    headerText: Color(0xFFF8F3FC),
  ),
  'mint': AppThemeDef(
    key: 'mint', labelFa: 'نعنایی', labelEn: 'Mint',
    swatch: Color(0xFF1AAE8C),
    paper: Color(0xFFEAF7F1), paperDark: Color(0xFFD6EEE2),
    ink: Color(0xFF12332A), inkSoft: Color(0xFF2E5548),
    gold: Color(0xFF2E9E7B), goldSoft: Color(0xFF9BDCC3),
    teal: Color(0xFF2E9E7B), rose: Color(0xFFB25353),
    cardBorder: Color(0xFFBEE0D0),
    headerFrom: Color(0xFF2BC49E), headerTo: Color(0xFF1B8F71),
    headerText: Color(0xFFF2FBF7),
  ),
  'amber': AppThemeDef(
    key: 'amber', labelFa: 'کهربایی', labelEn: 'Amber',
    swatch: Color(0xFFF0A202),
    paper: Color(0xFFFDF4E3), paperDark: Color(0xFFF7E7C4),
    ink: Color(0xFF3D2B0E), inkSoft: Color(0xFF6B4F22),
    gold: Color(0xFFD98E04), goldSoft: Color(0xFFF3C567),
    teal: Color(0xFF4E7A3A), rose: Color(0xFFB23A3A),
    cardBorder: Color(0xFFEEDBA6),
    headerFrom: Color(0xFFF5A623), headerTo: Color(0xFFC77800),
    headerText: Color(0xFFFFF8EC),
  ),
  'coral': AppThemeDef(
    key: 'coral', labelFa: 'مرجانی', labelEn: 'Coral',
    swatch: Color(0xFFFF6F61),
    paper: Color(0xFFFDECE9), paperDark: Color(0xFFF8D7D0),
    ink: Color(0xFF3A1B15), inkSoft: Color(0xFF6B3A2E),
    gold: Color(0xFFE0644F), goldSoft: Color(0xFFF5AFA0),
    teal: Color(0xFF3F8E85), rose: Color(0xFFE0644F),
    cardBorder: Color(0xFFF0C4B8),
    headerFrom: Color(0xFFFF7A62), headerTo: Color(0xFFD9432E),
    headerText: Color(0xFFFFF3EF),
  ),
  'sky': AppThemeDef(
    key: 'sky', labelFa: 'آسمانی', labelEn: 'Sky',
    swatch: Color(0xFF4FC3F7),
    paper: Color(0xFFEAF7FD), paperDark: Color(0xFFD5EEFA),
    ink: Color(0xFF123244), inkSoft: Color(0xFF2E5568),
    gold: Color(0xFF2B93C4), goldSoft: Color(0xFF9BD8EF),
    teal: Color(0xFF2B93C4), rose: Color(0xFFC0504F),
    cardBorder: Color(0xFFBFE3F3),
    headerFrom: Color(0xFF63C8F5), headerTo: Color(0xFF1E86B8),
    headerText: Color(0xFFF2FBFE),
  ),
  'berry': AppThemeDef(
    key: 'berry', labelFa: 'توتی', labelEn: 'Berry',
    swatch: Color(0xFF9C1F5C),
    paper: Color(0xFFF8ECF1), paperDark: Color(0xFFEED8E2),
    ink: Color(0xFF350F22), inkSoft: Color(0xFF5E2C42),
    gold: Color(0xFFA8356E), goldSoft: Color(0xFFDE9AB9),
    teal: Color(0xFF6C3B57), rose: Color(0xFFA8356E),
    cardBorder: Color(0xFFE0C0D0),
    headerFrom: Color(0xFFB93A79), headerTo: Color(0xFF7A1E4C),
    headerText: Color(0xFFFCF0F5),
  ),
  'olive': AppThemeDef(
    key: 'olive', labelFa: 'زیتونی', labelEn: 'Olive',
    swatch: Color(0xFF6B8E23),
    paper: Color(0xFFF3F2E6), paperDark: Color(0xFFE6E4CC),
    ink: Color(0xFF2B2E17), inkSoft: Color(0xFF4C512C),
    gold: Color(0xFF8A7A2F), goldSoft: Color(0xFFC9BE7E),
    teal: Color(0xFF6B8E23), rose: Color(0xFFA15A3A),
    cardBorder: Color(0xFFD8D6B0),
    headerFrom: Color(0xFF7FA02E), headerTo: Color(0xFF556B1B),
    headerText: Color(0xFFF6F8EA),
  ),
  'slate': AppThemeDef(
    key: 'slate', labelFa: 'دودی', labelEn: 'Slate',
    swatch: Color(0xFF5B7C99),
    paper: Color(0xFFEEF2F5), paperDark: Color(0xFFDFE6EB),
    ink: Color(0xFF1D2C38), inkSoft: Color(0xFF3D5566),
    gold: Color(0xFF4E7B99), goldSoft: Color(0xFFA9C6D6),
    teal: Color(0xFF4E7B99), rose: Color(0xFFB0524A),
    cardBorder: Color(0xFFCBD8E0),
    headerFrom: Color(0xFF6E93B0), headerTo: Color(0xFF3E5F78),
    headerText: Color(0xFFF3F7FA),
  ),
};

// ═══════════════════════════════════════════════════════════════
// فونت‌ها (۶ فونت)
// در Flutter از پکیج google_fonts استفاده می‌کنیم
// ═══════════════════════════════════════════════════════════════
class AppFontDef {
  final String key;
  final String labelFa;
  final String labelEn;
  final String faFontName;    // Google Font name for Persian
  final String latinFontName; // Google Font name for Latin
  const AppFontDef({
    required this.key,
    required this.labelFa,
    required this.labelEn,
    required this.faFontName,
    required this.latinFontName,
  });
}

const kAppFonts = <String, AppFontDef>{
  'default': AppFontDef(
    key: 'default', labelFa: 'پیش‌فرض', labelEn: 'Default',
    faFontName: 'Vazirmatn', latinFontName: 'Lora',
  ),
  'modern': AppFontDef(
    key: 'modern', labelFa: 'مدرن', labelEn: 'Modern',
    faFontName: 'Vazirmatn', latinFontName: 'Inter',
  ),
  'classic': AppFontDef(
    key: 'classic', labelFa: 'کلاسیک', labelEn: 'Classic',
    faFontName: 'NotoNaskhArabic', latinFontName: 'Merriweather',
  ),
  'elegant': AppFontDef(
    key: 'elegant', labelFa: 'شیک', labelEn: 'Elegant',
    faFontName: 'ArefRuqaa', latinFontName: 'PlayfairDisplay',
  ),
  'rounded': AppFontDef(
    key: 'rounded', labelFa: 'گرد', labelEn: 'Rounded',
    faFontName: 'NotoKufiArabic', latinFontName: 'Poppins',
  ),
  'warm': AppFontDef(
    key: 'warm', labelFa: 'گرم', labelEn: 'Warm',
    faFontName: 'NotoSansArabic', latinFontName: 'Nunito',
  ),
};

// ═══════════════════════════════════════════════════════════════
// اندازه‌های فونت (۴ اندازه)
// ═══════════════════════════════════════════════════════════════
class AppFontSizeDef {
  final String key;
  final String labelFa;
  final String labelEn;
  final double scale;
  const AppFontSizeDef({
    required this.key,
    required this.labelFa,
    required this.labelEn,
    required this.scale,
  });
}

const kAppFontSizes = <String, AppFontSizeDef>{
  'small': AppFontSizeDef(
    key: 'small', labelFa: 'کوچک', labelEn: 'Small', scale: 0.9,
  ),
  'medium': AppFontSizeDef(
    key: 'medium', labelFa: 'متوسط (پیش‌فرض)', labelEn: 'Medium (default)', scale: 1.0,
  ),
  'large': AppFontSizeDef(
    key: 'large', labelFa: 'بزرگ', labelEn: 'Large', scale: 1.15,
  ),
  'xlarge': AppFontSizeDef(
    key: 'xlarge', labelFa: 'خیلی بزرگ', labelEn: 'Extra large', scale: 1.3,
  ),
};

// ═══════════════════════════════════════════════════════════════
// زبان‌های رابط کاربری (۶ زبان)
// ═══════════════════════════════════════════════════════════════
class AppLanguageDef {
  final String code;
  final String label;
  final TextDirection dir;
  const AppLanguageDef({
    required this.code,
    required this.label,
    required this.dir,
  });
}

const kAppLanguages = <String, AppLanguageDef>{
  'fa': AppLanguageDef(code: 'fa', label: 'فارسی', dir: TextDirection.rtl),
  'en': AppLanguageDef(code: 'en', label: 'English', dir: TextDirection.ltr),
  'de': AppLanguageDef(code: 'de', label: 'Deutsch', dir: TextDirection.ltr),
  'es': AppLanguageDef(code: 'es', label: 'Español', dir: TextDirection.ltr),
  'fr': AppLanguageDef(code: 'fr', label: 'Français', dir: TextDirection.ltr),
  'ar': AppLanguageDef(code: 'ar', label: 'العربية', dir: TextDirection.rtl),
};

// ═══════════════════════════════════════════════════════════════
// پالت رنگ هایلایت (۱۲ رنگ pastel از Hope)
// ═══════════════════════════════════════════════════════════════
const kHighlightColorPalette = <String>[
  '#F7E98E', // زرد کم‌رنگ
  '#FBD9AE', // هلویی
  '#F7C48C', // نارنجیِ ملایم
  '#F1968E', // صورتی‌مرجانی
  '#DCE07E', // زیتونی روشن
  '#9AD98A', // سبز کم‌رنگ
  '#8DE0BE', // فیروزه‌ای
  '#A6DEE9', // آبیِ خیلی روشن
  '#A9C7F0', // آبی کم‌رنگ
  '#C7B6EC', // بنفشِ کم‌رنگ
  '#F0AEEC', // بنفشیِ صورتی
  '#F4AAC0', // صورتی
];
