import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_prefs_provider.dart';
import '../../../core/theme/app_theme_colors.dart';

/// دکمه‌ی کم‌رنگِ «درباره‌ی برنامه» (پایین‌ترین بخشِ تنظیمات)
class AboutButton extends ConsumerWidget {
  const AboutButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final fa = ref.watch(appPrefsProvider).uiLang == 'fa';
    return TextButton.icon(
      style: TextButton.styleFrom(foregroundColor: c.inkSoft),
      icon: const Icon(Icons.info_outline_rounded, size: 18),
      label: Text(fa ? 'درباره برنامه' : 'About',
          style: const TextStyle(fontSize: 12.5)),
      onPressed: () => Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
            fullscreenDialog: true, builder: (_) => const AboutPage()),
      ),
    );
  }
}

/// درباره‌ی برنامه ← مجوزهای متن‌باز
class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

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
          title: Text(fa ? 'درباره برنامه' : 'About'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              leading: Icon(Icons.description_outlined, color: c.gold),
              title: Text(fa ? 'مجوزهای متن‌باز' : 'Open Source Licenses',
                  style: TextStyle(color: c.ink, fontWeight: FontWeight.w700)),
              trailing: Icon(Icons.chevron_right_rounded, color: c.inkSoft),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const CreditsPage()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Credit {
  final String name;
  final String license;
  final String? asset; // متنِ کاملِ مجوز (assets/licenses/…)
  const _Credit(this.name, this.license, {this.asset});
}

const List<_Credit> _credits = [
  _Credit(
    'Supertonic 3 — Supertone Inc.',
    'OpenRAIL-M',
    asset: 'assets/licenses/supertonic-openrail-m.txt',
  ),
  _Credit(
    'Kokoro-82M (multi-lang v1.0) — hexgrad',
    'Apache License 2.0',
    asset: 'assets/licenses/kokoro-apache-2.0.txt',
  ),
  _Credit(
    'sherpa-onnx — k2-fsa (Next-gen Kaldi)',
    'Apache License 2.0',
    asset: 'assets/licenses/kokoro-apache-2.0.txt',
  ),
  // ── تشخیص گفتار (STT) ──
  _Credit(
    'Whisper — OpenAI',
    'MIT',
    asset: 'assets/licenses/whisper-mit.txt',
  ),
  _Credit(
    'Vosk — Alpha Cephei Inc.',
    'Apache License 2.0',
    asset: 'assets/licenses/vosk-apache-2.0.txt',
  ),
  _Credit(
    'Streaming Zipformer (English) — Zengwei Yao, k2-fsa (icefall)',
    'Apache License 2.0',
  ),
  _Credit(
    'Streaming Zipformer (Chinese–English) — pfluo, k2-fsa (icefall)',
    'Apache License 2.0',
  ),
  _Credit(
    'Streaming Zipformer (Korean) — johnBamma, k2-fsa (icefall)',
    'Not specified by the author',
  ),
  _Credit(
    'Streaming Zipformer (Russian) — Alpha Cephei Inc. (Vosk)',
    'Apache License 2.0',
  ),
  _Credit(
    'Mana-TTS — Mahta Fetrat',
    'MIT',
  ),
  _Credit(
    'Piper — Rhasspy / OHF-Voice',
    'MIT',
  ),
  _Credit(
    'espeak-ng',
    'GPL-3.0',
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
          title: Text(fa ? 'مجوزهای متن‌باز' : 'Open Source Licenses'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Text(
              fa
                  ? 'اطلاعیه‌های حقوقی و مجوزهای شخص ثالث'
                  : 'Legal Notices and Third-Party Licenses',
              style: TextStyle(
                  color: c.ink, fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              fa
                  ? 'این برنامه از اجزای متن‌باز زیر استفاده می‌کند.'
                  : 'This app uses the open-source components listed below.',
              style: TextStyle(color: c.inkSoft, fontSize: 12.5, height: 1.7),
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
          Text('${fa ? 'مجوز' : 'License'}: ${credit.license}',
              style: TextStyle(
                  color: c.ink, fontSize: 12.5, fontWeight: FontWeight.w700)),
          if (credit.asset != null)
            _LicenseText(asset: credit.asset!, fa: fa),
        ],
      ),
    );
  }
}

/// متنِ کاملِ مجوز از assets/licenses/… (در صورتِ نبودنِ فایل، چیزی نمایش داده نمی‌شود)
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
