import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../tts/tts_config.dart';

/// 🔐 توکنِ نشست برای Worker.
///
/// بعد از لاگین، توکنِ Supabase یک‌بار به `/api/session` داده می‌شود و Worker یک توکنِ
/// امضاشده (۱۴ روزه) برمی‌گرداند. همه‌ی درخواست‌ها به Worker آن را در هدر `X-App-Token`
/// می‌فرستند. توکن در SharedPreferences ذخیره می‌شود؛ بخشِ بومیِ اندروید (حبابِ ترجمه‌ی زنده)
/// هم همان را از فایلِ FlutterSharedPreferences (کلیدِ flutter.worker_token) می‌خواند.
class WorkerAuth {
  WorkerAuth._();

  static const String _kToken = 'worker_token';
  static const String _kExp = 'worker_token_exp';
  static const int _renewBeforeSec = 7 * 24 * 3600;

  static SharedPreferences? _prefs;
  static String _token = '';
  static int _exp = 0;
  static Future<void>? _inflight;

  static void init(SharedPreferences prefs) {
    _prefs = prefs;
    _token = prefs.getString(_kToken) ?? '';
    _exp = prefs.getInt(_kExp) ?? 0;
  }

  static int get _now => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  /// هدرهای لازم برای درخواست به Worker (خالی اگر هنوز توکن نداریم).
  static Map<String, String> get headers =>
      _token.isEmpty ? const <String, String>{} : {'X-App-Token': _token};

  /// فقط برای آدرسِ Workerِ خودمان هدر اضافه می‌شود (نه سرویس‌های دیگر).
  static bool isWorkerUrl(String url) => url.startsWith(TtsConfig.backendUrl);

  /// اگر توکن نیست یا کم‌اعتبار شده، تازه می‌کند.
  static Future<void> ensureFresh() {
    if (_token.isNotEmpty && _exp - _now > _renewBeforeSec) {
      return Future.value();
    }
    return refresh();
  }

  static Future<void> refresh() {
    return _inflight ??= _doRefresh().whenComplete(() => _inflight = null);
  }

  static Future<void> _doRefresh() async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) return;
      final res = await Dio().post<dynamic>(
        '${TtsConfig.backendUrl}/api/session',
        options: Options(
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          validateStatus: (_) => true,
        ),
      );
      final data = res.data;
      if (res.statusCode == 200 && data is Map && data['token'] is String) {
        _token = data['token'] as String;
        _exp = (data['exp'] as num?)?.toInt() ?? (_now + 3600);
        await _prefs?.setString(_kToken, _token);
        await _prefs?.setInt(_kExp, _exp);
      } else {
        debugPrint('WorkerAuth: HTTP ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('WorkerAuth refresh failed: $e');
    }
  }

  /// خروج از حساب
  static Future<void> clear() async {
    _token = '';
    _exp = 0;
    await _prefs?.remove(_kToken);
    await _prefs?.remove(_kExp);
  }

  /// به تغییرِ وضعیتِ ورود گوش می‌دهد (لاگین → گرفتنِ توکن، خروج → پاک کردن).
  static void listen() {
    try {
      Supabase.instance.client.auth.onAuthStateChange.listen((s) {
        if (s.event == AuthChangeEvent.signedOut) {
          unawaited(clear());
        } else if (s.session != null) {
          unawaited(ensureFresh());
        }
      });
    } catch (e) {
      debugPrint('WorkerAuth.listen: $e');
    }
  }
}

/// به هر درخواستِ Dio که به Workerِ خودمان می‌رود هدر اضافه می‌کند؛ با 401 یک‌بار توکن را
/// تازه کرده و همان درخواست را دوباره می‌فرستد.
class WorkerAuthInterceptor extends Interceptor {
  WorkerAuthInterceptor(this._dio);
  final Dio _dio;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (WorkerAuth.isWorkerUrl(options.uri.toString())) {
      await WorkerAuth.ensureFresh();
      options.headers.addAll(WorkerAuth.headers);
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    final o = response.requestOptions;
    if (response.statusCode == 401 &&
        WorkerAuth.isWorkerUrl(o.uri.toString()) &&
        o.extra['wa_retry'] != true) {
      await WorkerAuth.refresh();
      o.extra['wa_retry'] = true;
      o.headers.addAll(WorkerAuth.headers);
      try {
        return handler.resolve(await _dio.fetch<dynamic>(o));
      } catch (_) {/* پایین: همان پاسخِ 401 */}
    }
    handler.next(response);
  }
}
