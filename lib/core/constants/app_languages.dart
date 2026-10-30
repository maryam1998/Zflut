import 'package:flutter/material.dart';

/// زبان‌های رابط (software UI language).
/// معادلِ APP_LANGUAGES در theme.js.
@immutable
class AppLanguage {
  final String code;      // 'fa', 'en', ...
  final String label;     // نام بومیِ زبان، همیشه به خودش
  final TextDirection dir;

  const AppLanguage({
    required this.code,
    required this.label,
    required this.dir,
  });
}

const Map<String, AppLanguage> kAppLanguages = {
  'en': AppLanguage(code: 'en', label: 'English', dir: TextDirection.ltr),
  'es': AppLanguage(code: 'es', label: 'Español', dir: TextDirection.ltr),
  'de': AppLanguage(code: 'de', label: 'Deutsch', dir: TextDirection.ltr),
  'fa': AppLanguage(code: 'fa', label: 'فارسی', dir: TextDirection.rtl),
  'fr': AppLanguage(code: 'fr', label: 'Français', dir: TextDirection.ltr),
  'ar': AppLanguage(code: 'ar', label: 'Arabic', dir: TextDirection.rtl),
};

/// تاریخ‌های قابل‌انتخاب در تنظیمات.
enum CalendarSystem { jalali, gregorian, both }

const List<CalendarSystem> kCalendarSystems = CalendarSystem.values;
