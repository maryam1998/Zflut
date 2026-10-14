import 'package:supabase_flutter/supabase_flutter.dart';

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

  Future<void> signOut() => _client.auth.signOut();

  /// ورود گوگل — در وب از OAuth redirect؛ در اندروید از deep-link
  /// com.linglearn.app://login-callback (پیاده‌سازی نیتیو در فاز ۶).
  Future<bool> signInWithGoogle() async {
    return _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'com.linglearn.app://login-callback',
    );
  }
}
