import 'package:flutter/foundation.dart' show kIsWeb;
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

  /// ورود گوگل.
  /// • اندروید (وقتی GOOGLE_WEB_CLIENT_ID هست): ورودِ بومی با google_sign_in و تحویلِ idToken به Supabase؛
  ///   صفحه‌ی انتخابِ حسابِ گوگل اسمِ LingoLearn را نشان می‌دهد، نه آدرسِ supabase.co.
  /// • وب (یا اگر Client ID تنظیم نشده): مثلِ قبل با OAuth و redirect.
  /// برمی‌گرداند false اگر کاربر انصراف داد.
  Future<bool> signInWithGoogle() async {
    if (!kIsWeb && _googleWebClientId.isNotEmpty) {
      await _google.signOut().catchError((_) => null);   // همیشه انتخابِ حساب نشان بده
      final account = await _google.signIn();
      if (account == null) return false;                  // انصراف
      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) throw 'Google did not return an ID token';
      await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: auth.accessToken,
      );
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
