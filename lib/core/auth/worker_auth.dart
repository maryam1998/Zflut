import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../tts/tts_config.dart';
import '../data/paid_content.dart';
import '../usage/pro_status.dart';

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
  static const String _kPro = 'worker_pro';
  static const String _kProAt = 'worker_pro_at';
  // 🔒 شناسه‌ی این دستگاه (با پیشوندِ zflut-auth- از همگام‌سازیِ ابری مستثناست)
  static const String _kDeviceId = 'zflut-auth-device-id';
  // وضعیتِ Pro حداکثر هر ۶ ساعت از سرور دوباره پرسیده می‌شود
  static const int _proMaxAgeSec = 6 * 3600;
  // اگر Pro نیستیم (مثلاً مقدارِ کهنه‌ای از بکاپِ گوگل برگشته یا تازه VIP شده‌ایم) زودتر دوباره می‌پرسیم
  static const int _nonProMaxAgeSec = 5 * 60;
  static const int _renewBeforeSec = 7 * 24 * 3600;

  static SharedPreferences? _prefs;
  static String _token = '';
  static int _exp = 0;
  static int _proAt = 0;
  static Future<void>? _inflight;
  static String _deviceId = '';
  static String _deviceType = '';
  static String _deviceModel = '';

  static void init(SharedPreferences prefs) {
    _prefs = prefs;
    _token = prefs.getString(_kToken) ?? '';
    _exp = prefs.getInt(_kExp) ?? 0;
    _proAt = prefs.getInt(_kProAt) ?? 0;
    _deviceId = prefs.getString(_kDeviceId) ?? '';
    if (_deviceId.isEmpty) _newDeviceId();
    ProStatus.pro.value = prefs.getBool(_kPro) ?? false;
  }

  static void _newDeviceId() {
    final r = math.Random.secure();
    _deviceId = List.generate(24, (_) => r.nextInt(16).toRadixString(16)).join();
    unawaited(_prefs?.setString(_kDeviceId, _deviceId));
  }

  /// نوع و مدلِ دستگاه (برای لیستِ «دستگاه‌های متصل»)؛ هر خطایی = خالی.
  static Future<void> _loadDeviceInfo() async {
    if (_deviceType.isNotEmpty) return;
    try {
      if (kIsWeb) {
        _deviceType = 'web';
        _deviceModel = 'Browser';
      } else if (Platform.isAndroid) {
        final i = await DeviceInfoPlugin().androidInfo;
        _deviceType = 'android';
        _deviceModel = '${i.manufacturer} ${i.model}'.trim();
      } else if (Platform.isIOS) {
        final i = await DeviceInfoPlugin().iosInfo;
        _deviceType = 'ios';
        _deviceModel = i.utsname.machine;
      } else {
        _deviceType = Platform.operatingSystem;
      }
    } catch (_) {
      _deviceType = kIsWeb ? 'web' : 'unknown';
    }
  }

  static Map<String, String> get _deviceHeaders => {
        'X-Device-Id': _deviceId,
        if (_deviceType.isNotEmpty) 'X-Device-Type': _deviceType,
        if (_deviceModel.isNotEmpty) 'X-Device-Model': _deviceModel,
      };

  /// 🔒 این دستگاه از حساب خارج شده (دستگاهِ جدید وارد شد / «خروج از همه»):
  /// خروجِ خودکار؛ دفعه‌ی بعد شناسه‌ی تازه ساخته می‌شود.
  static Future<void> _deviceRevoked() async {
    _newDeviceId();
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    await clear();
  }

  /// وضعیتِ اکانت + دستگاه‌های متصل (GET /api/devices) — null = خطا.
  static Future<Map<String, dynamic>?> fetchDevices() async {
    try {
      await ensureFresh();
      final res = await Dio().get<dynamic>(
        '${TtsConfig.backendUrl}/api/devices',
        options: Options(
          headers: headers,
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          validateStatus: (_) => true,
        ),
      );
      final d = res.data;
      if (res.statusCode == 200 && d is Map) return Map<String, dynamic>.from(d);
    } catch (e) {
      debugPrint('WorkerAuth.fetchDevices: $e');
    }
    return null;
  }

  /// «خروج از همه‌ی دستگاه‌ها» — [accessToken] باید تازه با کدِ ایمیل گرفته شده باشد.
  static Future<bool> logoutAllDevices(String accessToken) async {
    try {
      final res = await Dio().post<dynamic>(
        '${TtsConfig.backendUrl}/api/devices/logout-all',
        options: Options(
          headers: {'Authorization': 'Bearer $accessToken'},
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
          validateStatus: (_) => true,
        ),
      );
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('WorkerAuth.logoutAllDevices: $e');
      return false;
    }
  }

  static int get _now => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  /// هدرهای لازم برای درخواست به Worker (خالی اگر هنوز توکن نداریم).
  static Map<String, String> get headers =>
      _token.isEmpty ? const <String, String>{} : {'X-App-Token': _token};

  /// فقط برای آدرسِ Workerِ خودمان هدر اضافه می‌شود (نه سرویس‌های دیگر).
  static bool isWorkerUrl(String url) => url.startsWith(TtsConfig.backendUrl);

  /// اگر توکن نیست یا کم‌اعتبار شده، تازه می‌کند.
  static Future<void> ensureFresh() {
    final maxAge = ProStatus.pro.value ? _proMaxAgeSec : _nonProMaxAgeSec;
    if (_token.isNotEmpty &&
        _exp - _now > _renewBeforeSec &&
        _now - _proAt < maxAge) {
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
      await _loadDeviceInfo();
      final res = await Dio().post<dynamic>(
        '${TtsConfig.backendUrl}/api/session',
        options: Options(
          headers: {
            'Authorization': 'Bearer ${session.accessToken}',
            ..._deviceHeaders,
          },
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
        _proAt = _now;
        final pro = data['pro'] == true;
        final wasPro = ProStatus.pro.value;
        ProStatus.pro.value = pro;
        // Pro تمام شد → محتوای پولیِ کش‌شده از گوشی پاک شود
        if (wasPro && !pro) unawaited(PaidContent.clearCache());
        await _prefs?.setBool(_kPro, pro);
        await _prefs?.setInt(_kProAt, _proAt);
      } else if (res.statusCode == 401 &&
          data is Map &&
          data['code'] == 'device_revoked') {
        await _deviceRevoked();
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
    _proAt = 0;
    ProStatus.pro.value = false;
    unawaited(PaidContent.clearCache());
    await _prefs?.remove(_kToken);
    await _prefs?.remove(_kExp);
    await _prefs?.remove(_kPro);
    await _prefs?.remove(_kProAt);
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
