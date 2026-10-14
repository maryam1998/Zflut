import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  final _nameCtrl  = TextEditingController();
  bool _isSignup = false;
  bool _busy = false;
  String? _errorMsg;

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
      if (msg.contains('already registered')) return L.auth_email_already_registered;
      if (msg.contains('invalid login')) return L.auth_invalid_credentials;
      if (msg.contains('email not confirmed')) return L.auth_email_not_confirmed;
    }
    return L.auth_generic_error;
  }

  Future<void> _submit() async {
    final L = context.l10n;
    if (_emailCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty ||
        (_isSignup && _nameCtrl.text.trim().isEmpty)) {
      setState(() => _errorMsg = L.auth_fill_all_fields);
      return;
    }
    setState(() { _busy = true; _errorMsg = null; });
    try {
      final repo = ref.read(authRepositoryProvider);
      if (_isSignup) {
        await repo.signUpWithEmail(
          email: _emailCtrl.text.trim(),
          password: _passCtrl.text,
          name: _nameCtrl.text.trim(),
        );
        if (mounted) {
          setState(() => _errorMsg = L.auth_verify_email_sent);
        }
      } else {
        await repo.signInWithEmail(
          email: _emailCtrl.text.trim(),
          password: _passCtrl.text,
        );
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
    setState(() { _busy = true; _errorMsg = null; });
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
    } catch (e) {
      if (mounted) setState(() => _errorMsg = '${L.auth_google_failed}$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final L = context.l10n;
    final c = context.appColors;

    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _isSignup ? L.auth_signup_title : L.auth_login_title,
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    L.auth_login_subtitle,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: c.inkSoft),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  // Google
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _google,
                    icon: const Icon(Icons.login),
                    label: Text(L.auth_continue_with_google),
                  ),
                  const SizedBox(height: 16),

                  Row(children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(L.auth_or_with_email,
                          style: TextStyle(color: c.inkSoft, fontSize: 12)),
                    ),
                    const Expanded(child: Divider()),
                  ]),
                  const SizedBox(height: 16),

                  if (_isSignup) ...[
                    TextField(
                      controller: _nameCtrl,
                      decoration: InputDecoration(labelText: L.auth_name_placeholder),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _emailCtrl,
                    decoration: InputDecoration(labelText: L.auth_email_placeholder),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passCtrl,
                    decoration: InputDecoration(labelText: L.auth_password_placeholder),
                    obscureText: true,
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 20),

                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_isSignup ? L.auth_signup_submit : L.auth_login_submit),
                  ),
                  const SizedBox(height: 12),

                  if (_errorMsg != null)
                    Text(_errorMsg!,
                        style: TextStyle(color: c.rose, fontSize: 13),
                        textAlign: TextAlign.center),

                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _busy ? null : () =>
                        setState(() { _isSignup = !_isSignup; _errorMsg = null; }),
                    child: Text(_isSignup
                        ? '${L.auth_have_account} ${L.auth_go_to_login}'
                        : '${L.auth_no_account} ${L.auth_go_to_signup}'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
