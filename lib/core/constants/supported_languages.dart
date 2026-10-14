import 'package:flutter/material.dart';

/// ۱۳ زبانِ محتوایی که اپ پشتیبانی می‌کند.
/// معادلِ LANGUAGES در languages.js.
@immutable
class SupportedLanguage {
  final String code;
  final String abbr;
  final String faLabel;
  final String enLabel;
  final TextDirection dir;

  const SupportedLanguage({
    required this.code,
    required this.abbr,
    required this.faLabel,
    required this.enLabel,
    required this.dir,
  });
}

const List<SupportedLanguage> kSupportedLanguages = [
  SupportedLanguage(code: 'fa', abbr: 'FA', faLabel: 'فارسی',      enLabel: 'Persian',   dir: TextDirection.rtl),
  SupportedLanguage(code: 'en', abbr: 'EN', faLabel: 'انگلیسی',    enLabel: 'English',   dir: TextDirection.ltr),
  SupportedLanguage(code: 'it', abbr: 'IT', faLabel: 'ایتالیایی',  enLabel: 'Italian',   dir: TextDirection.ltr),
  SupportedLanguage(code: 'hi', abbr: 'HI', faLabel: 'هندی',       enLabel: 'Hindi',     dir: TextDirection.ltr),
  SupportedLanguage(code: 'tr', abbr: 'TR', faLabel: 'ترکی',       enLabel: 'Turkish',   dir: TextDirection.ltr),
  SupportedLanguage(code: 'ar', abbr: 'AR', faLabel: 'عربی',       enLabel: 'Arabic',    dir: TextDirection.rtl),
  SupportedLanguage(code: 'es', abbr: 'ES', faLabel: 'اسپانیایی',  enLabel: 'Spanish',   dir: TextDirection.ltr),
  SupportedLanguage(code: 'de', abbr: 'DE', faLabel: 'آلمانی',     enLabel: 'German',    dir: TextDirection.ltr),
  SupportedLanguage(code: 'fr', abbr: 'FR', faLabel: 'فرانسوی',    enLabel: 'French',    dir: TextDirection.ltr),
  SupportedLanguage(code: 'zh', abbr: 'ZH', faLabel: 'چینی',       enLabel: 'Chinese',   dir: TextDirection.ltr),
  SupportedLanguage(code: 'ko', abbr: 'KO', faLabel: 'کره‌ای',     enLabel: 'Korean',    dir: TextDirection.ltr),
  SupportedLanguage(code: 'ru', abbr: 'RU', faLabel: 'روسی',       enLabel: 'Russian',   dir: TextDirection.ltr),
  SupportedLanguage(code: 'ja', abbr: 'JA', faLabel: 'ژاپنی',      enLabel: 'Japanese',  dir: TextDirection.ltr),
];

const List<String> kRtlLangCodes = ['fa', 'ar'];

TextDirection dirFor(String code) =>
    kRtlLangCodes.contains(code) ? TextDirection.rtl : TextDirection.ltr;
