import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_prefs_provider.dart';
import '../../../core/theme/app_theme_colors.dart';

/// دکمه‌ی «منابع و مجوزها» (پایین‌ترین بخشِ تنظیمات، زیرِ راهنما)
class CreditsButton extends ConsumerWidget {
  const CreditsButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final fa = ref.watch(appPrefsProvider).uiLang == 'fa';
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.ink,
        side: BorderSide(color: c.cardBorder),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: Icon(Icons.favorite_border_rounded, color: c.gold),
      label: Text(fa ? 'منابع و مجوزها (Credits)' : 'Credits & licenses'),
      onPressed: () => Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
            fullscreenDialog: true, builder: (_) => const CreditsPage()),
      ),
    );
  }
}

class _Credit {
  final String name;
  final Map<String, String> role;
  final String license;
  final String url;
  final String? asset; // متنِ کاملِ مجوز (assets/licenses/…)
  const _Credit(this.name, this.role, this.license, this.url, {this.asset});
}

const List<_Credit> _credits = [
  _Credit(
    'Supertonic 3 — Supertone Inc.',
    {
      'fa': 'صدای آفلاین برای آلمانی، فرانسوی، اسپانیایی، ایتالیایی، روسی، ترکی، عربی، هندی، کره‌ای و ژاپنی',
      'en': 'Offline voice for German, French, Spanish, Italian, Russian, Turkish, Arabic, Hindi, Korean and Japanese',
    },
    'OpenRAIL-M',
    'https://github.com/supertone-inc/supertonic',
    asset: 'assets/licenses/supertonic-openrail-m.txt',
  ),
  _Credit(
    'Kokoro-82M (multi-lang v1.0) — hexgrad',
    {
      'fa': 'صدای آفلاین برای انگلیسی و چینی (بسته‌ی sherpa-onnx)',
      'en': 'Offline voice for English and Chinese (sherpa-onnx package)',
    },
    'Apache License 2.0',
    'https://huggingface.co/hexgrad/Kokoro-82M',
    asset: 'assets/licenses/kokoro-apache-2.0.txt',
  ),
  _Credit(
    'sherpa-onnx — k2-fsa (Next-gen Kaldi)',
    {
      'fa': 'موتورِ اجرای مدل‌های گفتار (TTS و تشخیص گفتار)',
      'en': 'Runtime for the speech models (TTS and speech recognition)',
    },
    'Apache License 2.0',
    'https://github.com/k2-fsa/sherpa-onnx',
    asset: 'assets/licenses/kokoro-apache-2.0.txt',
  ),
  _Credit(
    'Mana-TTS — Mahta Fetrat',
    {
      'fa': 'صدای فارسی (مدل Mana برای Piper و دیتاستِ Mana-TTS)',
      'en': 'Persian voice (Mana model for Piper and the Mana-TTS dataset)',
    },
    'MIT',
    'https://huggingface.co/MahtaFetrat/Mana-Persian-Piper',
  ),
  _Credit(
    'Piper — Rhasspy / OHF-Voice',
    {
      'fa': 'قالبِ مدل‌های VITS که صدای فارسی با آن اجرا می‌شود؛ صداهای فارسیِ اضافه هم از بسته‌های Piper هستند و مجوزِ هرکدام در کارتِ مدلِ خودش آمده است',
      'en': 'VITS model format used by the Persian voices; the extra Persian voices are Piper packages whose licenses are listed on their own model cards',
    },
    'MIT',
    'https://github.com/rhasspy/piper',
  ),
  _Credit(
    'espeak-ng',
    {
      'fa': 'تبدیل متن به واج برای صدای فارسی (و کلماتِ خارج از لغت‌نامه در Kokoro)',
      'en': 'Text-to-phoneme conversion for the Persian voice (and out-of-dictionary words in Kokoro)',
    },
    'GPL-3.0',
    'https://github.com/espeak-ng/espeak-ng',
  ),
];

class CreditsPage extends ConsumerWidget {
  const CreditsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final lang = ref.watch(appPrefsProvider).uiLang;
    final fa = lang == 'fa';
    final rtl = lang == 'fa' || lang == 'ar';
    return Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: c.paper,
        appBar: AppBar(
          backgroundColor: c.headerFrom,
          foregroundColor: c.headerText,
          title: Text(fa ? 'منابع و مجوزها' : 'Credits & licenses'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Text(
              fa
                  ? 'صداهای آفلاینِ این برنامه با کمکِ پروژه‌ها و دیتاست‌های متن‌باز ساخته شده‌اند. از سازندگانشان سپاسگزاریم.'
                  : 'The offline voices in this app are built on open-source projects and datasets. Thank you to their authors.',
              style: TextStyle(color: c.inkSoft, fontSize: 13, height: 1.8),
            ),
            const SizedBox(height: 12),
            for (final cr in _credits) _CreditCard(credit: cr, lang: lang),
          ],
        ),
      ),
    );
  }
}

class _CreditCard extends StatelessWidget {
  final _Credit credit;
  final String lang;
  const _CreditCard({required this.credit, required this.lang});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final fa = lang == 'fa';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.paperDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(credit.name,
              textDirection: TextDirection.ltr,
              style: TextStyle(
                  color: c.ink, fontWeight: FontWeight.w800, fontSize: 14)),
          const SizedBox(height: 4),
          Text(credit.role[fa ? 'fa' : 'en'] ?? credit.role['en']!,
              style: TextStyle(color: c.inkSoft, fontSize: 12.5, height: 1.7)),
          const SizedBox(height: 6),
          Text('${fa ? 'مجوز' : 'License'}: ${credit.license}',
              style: TextStyle(
                  color: c.ink, fontSize: 12.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          SelectableText(credit.url,
              textDirection: TextDirection.ltr,
              style: TextStyle(color: c.teal, fontSize: 12)),
          if (credit.asset != null)
            _LicenseText(asset: credit.asset!, fa: fa),
        ],
      ),
    );
  }
}

/// متنِ کاملِ مجوز از assets/licenses/… (در صورتِ نبودنِ فایل، فقط لینکِ بالا نمایش داده می‌شود)
class _LicenseText extends StatelessWidget {
  final String asset;
  final bool fa;
  const _LicenseText({required this.asset, required this.fa});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return FutureBuilder<String>(
      future: rootBundle.loadString(asset),
      builder: (ctx, snap) {
        final txt = snap.data;
        if (txt == null || txt.trim().isEmpty) return const SizedBox.shrink();
        return Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: Text(fa ? 'متنِ مجوز' : 'License text',
                style: TextStyle(
                    color: c.ink, fontSize: 12.5, fontWeight: FontWeight.w700)),
            children: [
              SelectableText(txt,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(color: c.inkSoft, fontSize: 11, height: 1.5)),
            ],
          ),
        );
      },
    );
  }
}
