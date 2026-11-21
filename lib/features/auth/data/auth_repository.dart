import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Web Client ID گوگل (همان که در Supabase → Google گذاشته‌ای) — از --dart-define می‌آید.
const String _googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

/// لایه‌ی نازک روی Supabase Auth — معادلِ LoginScreen + supabaseClient.
class AuthRepository {
  final SupabaseClient _client;
  AuthRepository(this._client);

  Session? get currentSession => _client.auth.currentSession;

  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    String? name,
  }) {
    return _client.auth.signUp(
      email: email,
      password: password,
      data: {if (name != null) 'name': name},
    );
  }

  GoogleSignIn? _gsi;

  GoogleSignIn get _google => _gsi ??= GoogleSignIn(
        serverClientId: _googleWebClientId,
        scopes: const ['email', 'profile'],
      );

  Future<void> signOut() async {
    if (!kIsWeb && _googleWebClientId.isNotEmpty) {
      try {
        await _google.signOut();      // دفعه‌ی بعد دوباره انتخابِ حساب نشان داده شود
      } catch (_) {}
    }
    await _client.auth.signOut();
  }

  /// ارسال لینک بازیابی رمز عبور به ایمیل.
  Future<void> resetPassword(String email) =>
      _client.auth.resetPasswordForEmail(email);

  bool _cleared = false; // قبلاً signOut شده → قبل از هر ورود دوباره لازم نیست

  /// ⚡ پیش‌گرمایش: ساختنِ GoogleSignIn و پاک‌کردنِ حسابِ قبلی همان موقعِ باز شدنِ صفحه‌ی ورود،
  /// تا لمسِ دکمه‌ی گوگل منتظرِ این کارها نماند.
  Future<void> warmUp() async {
    if (kIsWeb || _googleWebClientId.isEmpty || _cleared) return;
    try {
      await _google.signOut();
      _cleared = true;
    } catch (_) {}
  }

  /// خطای گذرای شبکه (اینترنت کند/قطع) که ارزشِ یک بار تلاشِ دوباره را دارد.
  static bool _transient(Object e) {
    if (e is PlatformException) return e.code == 'network_error';
    if (e is TimeoutException) return true;
    final t = e.runtimeType.toString();
    if (t.contains('Retryable')) return true;
    final m = '$e';
    return m.contains('SocketException') || m.contains('ClientException');
  }

  static Future<T> _retry<T>(Future<T> Function() run) async {
    try {
      return await run();
    } catch (e) {
      if (!_transient(e)) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 700));
      return await run();
    }
  }

  /// ورود گوگل.
  /// • اندروید (وقتی GOOGLE_WEB_CLIENT_ID هست): ورودِ بومی با google_sign_in و تحویلِ idToken به Supabase؛
  ///   صفحه‌ی انتخابِ حسابِ گوگل اسمِ LingoLearn را نشان می‌دهد، نه آدرسِ supabase.co.
  /// • وب (یا اگر Client ID تنظیم نشده): مثلِ قبل با OAuth و redirect.
  /// برمی‌گرداند false اگر کاربر انصراف داد.
  Future<bool> signInWithGoogle() async {
    if (!kIsWeb && _googleWebClientId.isNotEmpty) {
      if (!_cleared) {
        await _google.signOut().catchError((_) => null);  // انتخابِ حساب نشان داده شود
        _cleared = true;
      }
      final account = await _retry(() => _google.signIn());
      if (account == null) return false;                  // انصراف
      final auth = await _retry(() => account.authentication);
      final idToken = auth.idToken;
      if (idToken == null) throw 'Google did not return an ID token';
      await _retry(() => _client.auth
          .signInWithIdToken(
            provider: OAuthProvider.google,
            idToken: idToken,
            accessToken: auth.accessToken,
          )
          .timeout(const Duration(seconds: 25)));
      _cleared = false; // بعد از ورود، signOutِ برنامه دوباره حساب را پاک می‌کند
      return true;
    }
    return _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? _webRedirectUrl() : 'com.linglearn.app://login-callback',
    );
  }

  static String _webRedirectUrl() {
    final b = Uri.base;
    final path = b.path.endsWith('/') ? b.path : '${b.path}/';
    return Uri(
      scheme: b.scheme,
      host: b.host,
      port: b.hasPort ? b.port : null,
      path: path,
    ).toString();
  }
}
