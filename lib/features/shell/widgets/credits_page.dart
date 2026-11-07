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

/// درباره‌ی برنامه ← فناوری‌های اپ
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
              dense: true,
              leading: Icon(Icons.memory_rounded,
                  color: c.inkSoft, size: 20),
              title: Text(fa ? 'فناوری‌های اپ' : 'App Technologies',
                  style: TextStyle(
                      color: c.inkSoft,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500)),
              trailing: Icon(Icons.chevron_right_rounded,
                  color: c.inkSoft, size: 20),
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
  final String author;
  final String license;
  final String? asset; // متنِ کاملِ مجوز (assets/licenses/…)
  const _Credit(this.name, this.license, {this.author = '', this.asset});
}

const List<_Credit> _credits = [
  _Credit(
    'Supertonic 3',
    'OpenRAIL-M',
    author: 'Supertone Inc.',
    asset: 'assets/licenses/supertonic-openrail-m.txt',
  ),
  _Credit(
    'Kokoro-82M',
    'Apache 2.0',
    author: 'hexgrad',
    asset: 'assets/licenses/kokoro-apache-2.0.txt',
  ),
  _Credit(
    'sherpa-onnx',
    'Apache 2.0',
    author: 'k2-fsa (Next-gen Kaldi)',
    asset: 'assets/licenses/kokoro-apache-2.0.txt',
  ),
  // ── تشخیص گفتار (STT) ──
  _Credit(
    'Whisper',
    'MIT',
    author: 'OpenAI',
    asset: 'assets/licenses/whisper-mit.txt',
  ),
  _Credit(
    'Vosk',
    'Apache 2.0',
    author: 'Alpha Cephei Inc.',
    asset: 'assets/licenses/vosk-apache-2.0.txt',
  ),
  _Credit(
    'Streaming Zipformer (EN)',
    'Apache 2.0',
    author: 'Zengwei Yao, k2-fsa (icefall)',
  ),
  _Credit(
    'Streaming Zipformer (ZH–EN)',
    'Apache 2.0',
    author: 'pfluo, k2-fsa (icefall)',
  ),
  _Credit(
    'Streaming Zipformer (RU)',
    'Apache 2.0',
    author: 'Alpha Cephei Inc. (Vosk)',
  ),
  _Credit(
    'Homo-GE2PE',
    'MIT',
    author: 'Mahta Fetrat',
  ),
  _Credit(
    'Mana-TTS',
    'MIT',
    author: 'Mahta Fetrat',
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
        ),
        body: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Text(
              fa
                  ? 'این برنامه از موتورهای پیشرفته‌ی پردازش زبان و صدا برای ارائه‌ی بهترین کیفیت استفاده می‌کند. اطلاعات و مجوزهای این فناوری‌ها در ادامه آمده است.'
                  : 'This app uses advanced language and speech processing engines to deliver the best quality. Details and licenses of these technologies are listed below.',
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
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: c.paperDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(credit.name,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                        color: c.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ),
              const SizedBox(width: 8),
              Text(credit.license,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(color: c.inkSoft, fontSize: 11.5)),
            ],
          ),
          if (credit.author.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(credit.author,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(color: c.inkSoft, fontSize: 11)),
            ),
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
            childrenPadding: const EdgeInsets.only(bottom: 8),
            title: Text(fa ? 'جزئیات مجوز' : 'License details',
                style: TextStyle(
                    color: c.inkSoft, fontSize: 11.5, fontWeight: FontWeight.w600)),
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
