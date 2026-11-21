import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/worker_auth.dart';
import '../../../core/theme/app_theme_colors.dart';

// ═══════════════════════════════════════════════════════════════════
// 🔒 وضعیتِ اکانت + دستگاه‌های متصل + «خروج از همه‌ی دستگاه‌ها» (با کدِ ایمیل)
// فقط وقتی کاربر واردِ حساب شده در تنظیمات نمایش داده می‌شود.
// ═══════════════════════════════════════════════════════════════════
class DevicesSection extends StatefulWidget {
  const DevicesSection({super.key});

  @override
  State<DevicesSection> createState() => _DevicesSectionState();
}

class _DevicesSectionState extends State<DevicesSection> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _busy = false;

  bool get _fa => Localizations.localeOf(context).languageCode == 'fa';
  String _t(String fa, String en) => _fa ? fa : en;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final d = await WorkerAuth.fetchDevices();
    if (!mounted) return;
    setState(() {
      _data = d;
      _loading = false;
    });
  }

  String _ago(num ms) {
    final diff = DateTime.now().millisecondsSinceEpoch - ms.toInt();
    final m = diff ~/ 60000;
    if (m < 2) return _t('همین الان', 'just now');
    if (m < 60) return _t('$m دقیقه پیش', '$m min ago');
    final h = m ~/ 60;
    if (h < 24) return _t('$h ساعت پیش', '${h}h ago');
    final d = h ~/ 24;
    return _t('$d روز پیش', '${d}d ago');
  }

  IconData _icon(String type) {
    switch (type) {
      case 'ios':
        return Icons.phone_iphone_rounded;
      case 'web':
        return Icons.language_rounded;
      default:
        return Icons.smartphone_rounded;
    }
  }

  String _name(Map d) {
    final model = '${d['model'] ?? ''}'.trim();
    if (model.isNotEmpty) return model;
    switch ('${d['type'] ?? ''}') {
      case 'android':
        return 'Android';
      case 'ios':
        return 'iPhone / iPad';
      case 'web':
        return 'Web';
    }
    return _t('دستگاه', 'Device');
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(m)));
  }

  Future<String?> _askCode(String email) {
    final ctl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: _fa ? TextDirection.rtl : TextDirection.ltr,
        child: AlertDialog(
          title: Text(_t('کدِ ایمیل', 'Email code')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_t('کدی که به $email فرستادیم را وارد کن.',
                  'Enter the code we sent to $email.')),
              const SizedBox(height: 10),
              TextField(
                controller: ctl,
                autofocus: true,
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
                maxLength: 8,
                decoration: const InputDecoration(counterText: ''),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(_t('انصراف', 'Cancel'))),
            TextButton(
                onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
                child: Text(_t('تأیید', 'Confirm'))),
          ],
        ),
      ),
    );
  }

  Future<void> _logoutAll() async {
    final auth = Supabase.instance.client.auth;
    final email = auth.currentUser?.email ?? '';
    if (email.isEmpty || _busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: _fa ? TextDirection.rtl : TextDirection.ltr,
        child: AlertDialog(
          title: Text(_t('خروج از همه‌ی دستگاه‌ها', 'Log out of all devices')),
          content: Text(_t(
              'یک کد به $email فرستاده می‌شود. بعد از تأیید، همه‌ی دستگاه‌ها (از جمله همین دستگاه) از حساب خارج می‌شوند.',
              'We will email a code to $email. After you confirm, every device (including this one) is signed out.')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(_t('انصراف', 'Cancel'))),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(_t('ارسال کد', 'Send code'))),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await auth.signInWithOtp(email: email, shouldCreateUser: false);
      if (!mounted) return;
      final code = await _askCode(email);
      if (code == null || code.isEmpty || !mounted) return;
      final res = await auth.verifyOTP(
          email: email, token: code, type: OtpType.email);
      final token = res.session?.accessToken;
      if (token == null) throw 'no session';
      final done = await WorkerAuth.logoutAllDevices(token);
      if (!done) {
        _snack(_t('انجام نشد؛ دوباره امتحان کن.', 'Failed — please try again.'));
        return;
      }
      // خروج از همه‌ی نشست‌های Supabase هم (این دستگاه هم خارج می‌شود)
      try {
        await auth.signOut(scope: SignOutScope.global);
      } catch (_) {}
      await WorkerAuth.clear();
    } catch (_) {
      _snack(_t('کد نادرست است یا ارسال نشد.', 'Wrong code or it could not be sent.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final d = _data;
    final pro = d?['pro'] == true;
    final devices = (d?['devices'] is List) ? (d!['devices'] as List) : const [];
    final modeOn = d?['mode'] == 'on';

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user_outlined, size: 15, color: c.gold),
              const SizedBox(width: 6),
              Text(_t('وضعیت اکانت', 'Account status'),
                  style: TextStyle(
                      color: c.ink, fontSize: 12.5, fontWeight: FontWeight.w800)),
              const Spacer(),
              if (d != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: pro ? c.gold.withOpacity(0.2) : c.goldSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(pro ? 'Pro' : _t('رایگان', 'Free'),
                      style: TextStyle(
                          color: pro ? c.gold : c.inkSoft,
                          fontSize: 11,
                          fontWeight: FontWeight.w800)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(_t('دستگاه‌های متصل', 'Connected devices'),
              style: TextStyle(color: c.inkSoft, fontSize: 11.5)),
          const SizedBox(height: 4),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(
                  child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else if (d == null)
            Text(_t('در حال حاضر در دسترس نیست.', 'Not available right now.'),
                style: TextStyle(color: c.inkSoft, fontSize: 11.5))
          else if (devices.isEmpty)
            Text(_t('—', '—'), style: TextStyle(color: c.inkSoft, fontSize: 11.5))
          else
            for (final x in devices)
              if (x is Map)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Icon(_icon('${x['type'] ?? ''}'), size: 18, color: c.teal),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _name(x) +
                                  (x['current'] == true
                                      ? ' · ${_t('این دستگاه', 'this device')}'
                                      : ''),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: c.ink,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700),
                            ),
                            Text(
                              '${_t('آخرین بازدید', 'Last seen')}: ${x['last_seen'] is num ? _ago(x['last_seen'] as num) : '—'}',
                              style: TextStyle(color: c.inkSoft, fontSize: 10.5),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
          if (modeOn) ...[
            const SizedBox(height: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _busy ? null : _logoutAll,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.devices_other_rounded, size: 14, color: c.rose),
                  const SizedBox(width: 8),
                  Text(_t('خروج از همه‌ی دستگاه‌ها', 'Log out of all devices'),
                      style: TextStyle(color: c.rose, fontSize: 12)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
