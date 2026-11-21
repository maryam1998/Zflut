import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../providers/auth_provider.dart';

// 🎨 رنگ‌های برندِ AllLingOne (هماهنگ با لوگو)
// 🎨 سبزِ تیره + زردِ خردلی/طلایی (عنوان، دکمه‌ی ورود، «Create one»)
const Color _kDarkGreen = Color(0xFF0F3D2E);
const Color _kMustard = Color(0xFFD4A017);
const Color _kMustardPressed = Color(0xFFB8860B);

/// صفحه‌ی ورود: گوگل · ایمیل/رمز (ورود و ساخت حساب + فراموشی رمز) · مهمان.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _isSignup = false;
  bool _showPass = false;
  bool _busy = false;
  bool _googleBusy = false;
  String? _errorMsg;
  String? _infoMsg;

  @override
  void initState() {
    super.initState();
    // ⚡ گوگل را از قبل آماده کن تا بعد از لمسِ دکمه تأخیر نداشته باشد
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        try {
          ref.read(authRepositoryProvider).warmUp();
        } catch (_) {}
      }
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  String _mapError(Object e, AppLocalizations L) {
    if (e is AuthException) {
      final msg = e.message.toLowerCase();
      if (msg.contains('already registered') ||
          msg.contains('already been registered')) {
        return L.auth_email_already_registered;
      }
      if (msg.contains('invalid login')) return L.auth_invalid_credentials;
      if (msg.contains('email not confirmed')) return L.auth_email_not_confirmed;
      if (msg.contains('password should be')) return L.auth_password_too_short;
    }
    return L.auth_generic_error;
  }

  Future<void> _submit() async {
    final L = context.l10n;
    final email = _emailCtrl.text.trim();
    if (email.isEmpty ||
        _passCtrl.text.isEmpty ||
        (_isSignup && _nameCtrl.text.trim().isEmpty)) {
      setState(() {
        _errorMsg = L.auth_fill_all_fields;
        _infoMsg = null;
      });
      return;
    }
    if (_isSignup && _passCtrl.text.length < 6) {
      setState(() {
        _errorMsg = L.auth_password_too_short;
        _infoMsg = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _errorMsg = null;
      _infoMsg = null;
    });
    try {
      final repo = ref.read(authRepositoryProvider);
      if (_isSignup) {
        await repo.signUpWithEmail(
          email: email,
          password: _passCtrl.text,
          name: _nameCtrl.text.trim(),
        );
        if (mounted) setState(() => _infoMsg = L.auth_verify_email_sent);
      } else {
        await repo.signInWithEmail(email: email, password: _passCtrl.text);
        // ناوبری خودکار با تغییر authStateProvider.
      }
    } catch (e) {
      if (mounted) setState(() => _errorMsg = _mapError(e, L));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    final L = context.l10n;
    setState(() {
      _busy = true;
      _googleBusy = true;
      _errorMsg = null;
      _infoMsg = null;
    });
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
    } catch (e) {
      if (mounted) {
        final fa = Localizations.localeOf(context).languageCode == 'fa';
        final net = e is PlatformException && e.code == 'network_error';
        setState(() => _errorMsg = net
            ? (fa
                ? 'اینترنت کند یا ناپایدار است؛ چند ثانیه بعد دوباره امتحان کن.'
                : 'Slow or unstable connection. Please try again in a few seconds.')
            : '${L.auth_google_failed}$e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _googleBusy = false;
        });
      }
    }
  }

  Future<void> _forgot() async {
    final L = context.l10n;
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() {
        _errorMsg = L.auth_enter_email_first;
        _infoMsg = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _errorMsg = null;
      _infoMsg = null;
    });
    try {
      await ref.read(authRepositoryProvider).resetPassword(email);
      if (mounted) setState(() => _infoMsg = L.auth_reset_sent);
    } catch (e) {
      if (mounted) setState(() => _errorMsg = _mapError(e, L));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _guest() async {
    // روتر با تغییر guestModeProvider خودش به اپ می‌رود.
    await ref.read(guestModeProvider.notifier).enter();
  }

  InputDecoration _fieldDeco(BuildContext context,
      {required String hint, required IconData icon, Widget? suffix}) {
    final c = context.appColors;
    OutlineInputBorder border(Color color) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: color, width: 1),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: c.inkSoft.withOpacity(0.7), fontSize: 15),
      prefixIcon: Icon(icon, color: c.inkSoft, size: 22),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      enabledBorder: border(Colors.transparent),
      focusedBorder: border(c.gold),
      border: border(Colors.transparent),
    );
  }

  /// «ورود به All Ling One»: جمله‌ی کوچک و ملایم بالا، و نامِ برند به‌صورتِ لوگوتایپ:
  /// All و One سبزِ تیره، Ling داخلِ کپسولِ سبزِ تیره با متنِ طلایی (کنتراستِ بالا).
  Widget _brandTitle(String full, TextStyle? base, bool dark) {
    const brand = 'AllLingOne';
    final i = full.indexOf(brand);
    if (i < 0) {
      return Text(full, style: base, textAlign: TextAlign.center);
    }
    final prefix = full.substring(0, i).trim();
    final suffix = full.substring(i + brand.length).trim();
    final green = dark ? const Color(0xFF6FCF97) : _kDarkGreen;
    final pill = dark ? const Color(0xFF14532D) : _kDarkGreen;
    final gold = dark ? const Color(0xFFE6B422) : const Color(0xFFF2C94C);
    final big = (base ?? const TextStyle()).copyWith(
      fontSize: 30,
      fontWeight: FontWeight.w900,
      height: 1.1,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (prefix.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              prefix,
              textAlign: TextAlign.center,
              style: base?.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: base.color?.withOpacity(0.65),
              ),
            ),
          ),
        // لوگوتایپ همیشه LTR (حتی در فارسی/عربی)
        Directionality(
          textDirection: TextDirection.ltr,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('All', style: big.copyWith(color: green)),
                const SizedBox(width: 8),
                Container(
                  // دمِ حرفِ g پایین می‌زند؛ کمی بالاتر و با فضای بیشتر در پایین تا Ling وسطِ کپسول دیده شود
                  padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
                  decoration: BoxDecoration(
                    color: pill,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text('Ling', style: big.copyWith(color: gold)),
                ),
                const SizedBox(width: 8),
                Text('One', style: big.copyWith(color: green)),
              ],
            ),
          ),
        ),
        if (suffix.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(suffix,
                textAlign: TextAlign.center,
                style: base?.copyWith(fontSize: 15)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final L = context.l10n;
    final c = context.appColors;
    final text = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              // جهتِ کارت از زبانِ خودِ متن‌ها: انگلیسی = چپ‌به‌راست (علامت‌های «?»، جای آیکن و راهنمای فیلدها درست)،
              // فارسی/عربی = راست‌به‌چپ
              child: Directionality(
                textDirection: const ['fa', 'ar', 'he', 'ur']
                        .contains(Localizations.localeOf(context).languageCode)
                    ? TextDirection.rtl
                    : TextDirection.ltr,
                child: Container(
                padding: const EdgeInsets.fromLTRB(22, 30, 22, 22),
                decoration: BoxDecoration(
                  color: c.paperDark,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.10),
                      blurRadius: 28,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // آیکن
                    Center(
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                            // سبزِ تیره + آیکنِ طلایی (هماهنگ با پالتِ برند، نه سرمه‌ای)
                            color: dark
                                ? const Color(0xFF14532D)
                                : _kDarkGreen,
                            shape: BoxShape.circle),
                        child: Icon(
                          _isSignup ? Icons.person_add_alt_1 : Icons.login,
                          color: dark ? const Color(0xFFE6B422) : const Color(0xFFF2C94C),
                          size: 30,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _isSignup
                        ? Text(
                            L.auth_signup_title,
                            style: text.headlineSmall?.copyWith(
                                color: c.ink, fontWeight: FontWeight.w800),
                            textAlign: TextAlign.center,
                          )
                        : _brandTitle(
                            L.auth_login_title,
                            text.headlineSmall?.copyWith(
                                color: c.ink, fontWeight: FontWeight.w800),
                            dark),
                    const SizedBox(height: 8),
                    Text(
                      L.auth_login_subtitle,
                      style: text.bodyMedium?.copyWith(color: c.inkSoft),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),

                    // ═══ Google ═══
                    _GoogleButton(
                      label: L.auth_continue_with_google,
                      onTap: _busy ? null : _google,
                      loading: _googleBusy,
                    ),
                    const SizedBox(height: 18),

                    Row(children: [
                      Expanded(
                          child: Divider(color: c.cardBorder, thickness: 1)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(L.auth_or_with_email,
                            style: TextStyle(color: c.inkSoft, fontSize: 13)),
                      ),
                      Expanded(
                          child: Divider(color: c.cardBorder, thickness: 1)),
                    ]),
                    const SizedBox(height: 18),

                    // ═══ ایمیل / رمز ═══
                    if (_isSignup) ...[
                      TextField(
                        controller: _nameCtrl,
                        enabled: !_busy,
                        decoration: _fieldDeco(context,
                            hint: L.auth_name_placeholder,
                            icon: Icons.person_outline),
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.name],
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: _emailCtrl,
                      enabled: !_busy,
                      decoration: _fieldDeco(context,
                          hint: L.auth_email_placeholder,
                          icon: Icons.mail_outline),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      textDirection: TextDirection.ltr,
                      autofillHints: const [AutofillHints.email],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passCtrl,
                      enabled: !_busy,
                      decoration: _fieldDeco(
                        context,
                        hint: L.auth_password_placeholder,
                        icon: Icons.lock_outline,
                        suffix: IconButton(
                          icon: Icon(
                            _showPass
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: c.inkSoft,
                            size: 20,
                          ),
                          onPressed: () =>
                              setState(() => _showPass = !_showPass),
                        ),
                      ),
                      obscureText: !_showPass,
                      textDirection: TextDirection.ltr,
                      onSubmitted: (_) => _busy ? null : _submit(),
                      autofillHints: [
                        _isSignup
                            ? AutofillHints.newPassword
                            : AutofillHints.password
                      ],
                    ),

                    if (!_isSignup)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton(
                          onPressed: _busy ? null : _forgot,
                          style: TextButton.styleFrom(
                              foregroundColor: c.inkSoft,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4)),
                          child: Text(L.auth_forgot_password,
                              style: const TextStyle(fontSize: 12.5)),
                        ),
                      )
                    else
                      const SizedBox(height: 8),

                    if (_errorMsg != null) ...[
                      const SizedBox(height: 4),
                      Text(_errorMsg!,
                          style: TextStyle(color: c.rose, fontSize: 13),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                    ],
                    if (_infoMsg != null) ...[
                      const SizedBox(height: 4),
                      Text(_infoMsg!,
                          style: TextStyle(color: c.teal, fontSize: 13),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                    ],

                    SizedBox(
                      height: 54,
                      child: FilledButton(
                        onPressed: _busy ? null : _submit,
                        style: FilledButton.styleFrom(
                          foregroundColor: _kDarkGreen,
                          shape: const StadiumBorder(),
                          textStyle: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700),
                        ).copyWith(
                          // زردِ خردلی؛ موقعِ لمس یک پله تیره‌تر
                          backgroundColor:
                              MaterialStateProperty.resolveWith((states) {
                            if (states.contains(MaterialState.disabled)) {
                              return _kMustard.withOpacity(0.5);
                            }
                            if (states.contains(MaterialState.pressed)) {
                              return _kMustardPressed;
                            }
                            return _kMustard;
                          }),
                        ),
                        child: _busy
                            ? SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.4, color: _kDarkGreen))
                            : Text(_isSignup
                                ? L.auth_signup_submit
                                : L.auth_login_submit),
                      ),
                    ),
                    const SizedBox(height: 10),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _isSignup ? L.auth_have_account : L.auth_no_account,
                          style: TextStyle(color: c.inkSoft, fontSize: 14),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                    _isSignup = !_isSignup;
                                    _errorMsg = null;
                                    _infoMsg = null;
                                  }),
                          style: TextButton.styleFrom(
                              foregroundColor:
                                  dark ? const Color(0xFF6FCF97) : _kDarkGreen,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6)),
                          child: Text(
                            _isSignup ? L.auth_go_to_login : L.auth_go_to_signup,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// دکمه‌ی سفیدِ «ادامه با گوگل» با لوگوی چندرنگِ G.
class _GoogleButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  const _GoogleButton(
      {required this.label, required this.onTap, this.loading = false});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Material(
      color: Colors.white,
      shape: const StadiumBorder(),
      elevation: 0,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.6 : 1,
          child: SizedBox(
            height: 56,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                loading
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: c.ink),
                      )
                    : ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (r) => const SweepGradient(
                    center: Alignment(0.0, 0.05),
                    startAngle: -0.8,
                    endAngle: 5.5,
                    colors: [
                      Color(0xFF4285F4),
                      Color(0xFF34A853),
                      Color(0xFFFBBC05),
                      Color(0xFFEA4335),
                      Color(0xFF4285F4),
                    ],
                    stops: [0.0, 0.25, 0.5, 0.75, 1.0],
                  ).createShader(r),
                  child: const Text(
                    'G',
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Roboto',
                      height: 1.0,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(label,
                    style: TextStyle(
                        color: c.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
