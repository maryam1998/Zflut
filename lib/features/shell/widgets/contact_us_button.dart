// 📁 مسیر: lib/features/shell/widgets/contact_us_button.dart
//
// «ارتباط با ما» در تنظیمات: با لمس، جیمیل (یا برنامه‌ی ایمیلِ گوشی) با آدرسِ
// پشتیبانی باز می‌شود. اگر برنامه‌ی ایمیلی نبود (یا روی وب)، آدرس کپی می‌شود.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/native/native_bridge.dart';
import '../../../core/providers/app_prefs_provider.dart';
import '../../../core/theme/app_theme_colors.dart';

const String kSupportEmail = 'Lingolearn.support@gmail.com';

const Map<String, String> _label = {
  'fa': 'ارتباط با ما',
  'en': 'Contact us',
  'es': 'Contáctanos',
  'de': 'Kontakt',
  'fr': 'Nous contacter',
  'ar': 'اتصل بنا',
};

const Map<String, String> _copied = {
  'fa': 'برنامه‌ی ایمیل پیدا نشد؛ آدرس کپی شد',
  'en': 'No email app found — address copied',
  'es': 'No hay app de correo: dirección copiada',
  'de': 'Keine E-Mail-App – Adresse kopiert',
  'fr': 'Aucune app e-mail : adresse copiée',
  'ar': 'لا يوجد تطبيق بريد — تم نسخ العنوان',
};

class ContactUsButton extends ConsumerWidget {
  const ContactUsButton({super.key});

  Future<void> _open(BuildContext context, String lang) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    var ok = false;
    if (NativeBridge.instance.isSupported) {
      try {
        await NativeBridge.instance.openExternal(
            url: 'mailto:$kSupportEmail?subject=Lingolearn%20Support');
        ok = true;
      } catch (_) {}
    }
    if (ok) return;
    await Clipboard.setData(const ClipboardData(text: kSupportEmail));
    messenger?.showSnackBar(
      SnackBar(content: Text('${_copied[lang] ?? _copied['en']!}\n$kSupportEmail')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final ui = ref.watch(appPrefsProvider).uiLang;
    final lang = _label.containsKey(ui) ? ui : 'en';
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.ink,
        side: BorderSide(color: c.cardBorder),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: Icon(Icons.mail_outline_rounded, color: c.gold),
      label: Text(_label[lang]!),
      onPressed: () => _open(context, lang),
    );
  }
}
