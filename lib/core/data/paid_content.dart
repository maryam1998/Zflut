import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/worker_auth.dart';
import '../tts/tts_config.dart';
import '../usage/pro_status.dart';

Map<String, dynamic> _decodeMap(String raw) =>
    jsonDecode(raw) as Map<String, dynamic>;

/// 💎 محتوای پولی (لغاتِ بعد از ۳۰ام + مکالمه‌های کامل) — فقط برای Pro.
///
/// از Worker گرفته می‌شود (`/api/content/*`) و در گوشی کش می‌شود:
///   • فایل: <پوشه‌ی اپ>/paid_content/<کلید>.json (همان پاسخِ سرور)
///   • نسخه: SharedPreferences  (paid_v:<کلید>)
/// کش فوراً خوانده می‌شود؛ تغییرِ نسخه در پس‌زمینه با manifest چک و به‌روز می‌شود
/// (بعد از به‌روزشدن [revision] زیاد می‌شود تا لیست‌ها دوباره بارگذاری شوند).
class PaidContent {
  PaidContent._();

  /// با هر به‌روزرسانی/پاک‌شدنِ کش زیاد می‌شود (providerها به آن گوش می‌دهند).
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static final Dio _dio = Dio();
  static const List<String> _keys = [
    'words:daily',
    'words:slang',
    'words:vocab',
    'conv:daily',
    'conv:thematic',
  ];

  static String _fileName(String key) => '${key.replaceAll(':', '_')}.json';
  static String _verKey(String key) => 'paid_v:$key';

  static Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}/paid_content');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  // ─────────── خواندن ───────────

  /// لغاتِ پولیِ یک لیست ('daily' | 'slang' | 'vocab') — null اگر Pro نیستی/در دسترس نیست.
  static Future<List<dynamic>?> words(String list) =>
      _get('words:$list', '/api/content/words?list=$list', 'words');

  /// موضوع‌های کاملِ مکالمه ('daily' | 'thematic') — null اگر Pro نیستی/در دسترس نیست.
  static Future<List<dynamic>?> conversations(String kind) => _get(
      'conv:$kind', '/api/content/conversations?kind=$kind', 'topics');

  static Future<List<dynamic>?> _get(
      String key, String path, String field) async {
    if (!ProStatus.isPro) return null;
    try {
      final cached = await _readCache(key, field);
      if (cached != null) {
        unawaited(sync()); // در پس‌زمینه نسخه‌ها را چک کن
        return cached;
      }
      final r = await _fetch(path, null);
      if (r == null || r['notModified'] == true) return null;
      final raw = r['__raw'] as String;
      await _writeCache(key, r['version']?.toString() ?? '', raw);
      final list = r[field];
      return list is List ? list : null;
    } catch (e) {
      debugPrint('PaidContent.get($key): $e');
      return null;
    }
  }

  static Future<List<dynamic>?> _readCache(String key, String field) async {
    try {
      final f = File('${(await _dir()).path}/${_fileName(key)}');
      if (!await f.exists()) return null;
      final m = await compute(_decodeMap, await f.readAsString());
      final l = m[field];
      return l is List ? l : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeCache(String key, String version, String raw) async {
    final f = File('${(await _dir()).path}/${_fileName(key)}');
    await f.writeAsString(raw, flush: true);
    final p = await SharedPreferences.getInstance();
    await p.setString(_verKey(key), version);
  }

  // ─────────── شبکه ───────────

  /// پاسخِ سرور (به‌همراهِ '__raw' = متنِ خام برای ذخیره در کش) یا null.
  static Future<Map<String, dynamic>?> _fetch(String path, String? have) async {
    Future<Response<String>> once() => _dio.get<String>(
          '${TtsConfig.backendUrl}$path${have != null ? '&v=$have' : ''}',
          options: Options(
            headers: WorkerAuth.headers,
            responseType: ResponseType.plain,
            sendTimeout: const Duration(seconds: 20),
            receiveTimeout: const Duration(seconds: 60),
            validateStatus: (_) => true,
          ),
        );
    await WorkerAuth.ensureFresh();
    var res = await once();
    if (res.statusCode == 401) {
      await WorkerAuth.refresh();
      res = await once();
    }
    if (res.statusCode == 403) {
      // سرور می‌گوید Pro نیستی → وضعیتِ Pro را از سرور تازه کن
      await WorkerAuth.refresh();
      return null;
    }
    if (res.statusCode != 200 || res.data == null) return null;
    final m = await compute(_decodeMap, res.data!);
    m['__raw'] = res.data!;
    return m;
  }

  static bool _syncing = false;
  static DateTime? _lastSync;

  /// manifest را می‌گیرد و فقط مجموعه‌هایی که نسخه‌شان عوض شده دوباره دانلود می‌شوند.
  static Future<void> sync({bool force = false}) async {
    if (_syncing || !ProStatus.isPro) return;
    if (!force &&
        _lastSync != null &&
        DateTime.now().difference(_lastSync!) < const Duration(minutes: 30)) {
      return;
    }
    _syncing = true;
    var changed = false;
    try {
      final man = await _fetch('/api/content/manifest', null);
      final items = man?['items'];
      if (items is! Map) return;
      _lastSync = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      for (final key in _keys) {
        final remote = items[key];
        if (remote is! Map) continue;
        final rv = remote['version']?.toString() ?? '';
        final have = prefs.getString(_verKey(key));
        if (have == rv) continue;
        final isWords = key.startsWith('words:');
        final name = key.split(':')[1];
        final path = isWords
            ? '/api/content/words?list=$name'
            : '/api/content/conversations?kind=$name';
        final r = await _fetch(path, have);
        if (r == null || r['notModified'] == true) continue;
        await _writeCache(key, r['version']?.toString() ?? rv, r['__raw'] as String);
        changed = true;
      }
    } catch (e) {
      debugPrint('PaidContent.sync: $e');
    } finally {
      _syncing = false;
    }
    if (changed) revision.value++;
  }

  /// خروج از حساب / پایانِ Pro: محتوای پولی از گوشی پاک می‌شود.
  static Future<void> clearCache() async {
    try {
      final d = await _dir();
      if (await d.exists()) await d.delete(recursive: true);
      final p = await SharedPreferences.getInstance();
      for (final k in _keys) {
        await p.remove(_verKey(k));
      }
    } catch (e) {
      debugPrint('PaidContent.clearCache: $e');
    }
    _lastSync = null;
    revision.value++;
  }
}

/// برای providerها: با هر به‌روزرسانیِ محتوای پولی دوباره بارگذاری می‌شوند.
final paidRevisionProvider = Provider<int>((ref) {
  void l() => ref.invalidateSelf();
  PaidContent.revision.addListener(l);
  ref.onDispose(() => PaidContent.revision.removeListener(l));
  return PaidContent.revision.value;
});
