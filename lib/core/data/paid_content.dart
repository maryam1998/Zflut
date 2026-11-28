import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
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

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
  ));
  /// 🎒 بلاب‌های مرحله‌های تحصیلی (Education stage): لغات + تمرین‌ها. کلید = کلیدِ `/api/content/blob`.
  static const List<String> eduBlobKeys = [
    'primary-a1',
    'primary-a2',
    'primary-b1',
    'primary-b2',
    'primary-a1-listening',
    'primary-a1-questions',
    'primary-a1-writing',
    'primary-a2-listening',
    'primary-a2-questions',
    'primary-a2-writing',
    'primary-b1-listening',
    'primary-b1-questions',
    'primary-b1-writing',
  ];

  static final List<String> _keys = [
    'words:daily',
    'words:slang',
    'words:vocab',
    for (final k in eduBlobKeys) 'blob:$k',
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

  /// 💎 یک موضوعِ کاملِ مکالمه (لود تنبل) — null اگر Pro نیستی/در دسترس نیست.
  /// کش: <پوشه‌ی اپ>/paid_content/conv/<id>.json (نسخه داخلِ خودِ فایل است).
  /// اگر کش بود فوراً برمی‌گردد و نسخه در پس‌زمینه چک می‌شود (بازشدنِ بعدی تازه است).
  static Future<Map<String, dynamic>?> conversationTopic(String id) {
    if (!ProStatus.isPro) return Future.value(null);
    // ⏱ سقفِ کلِ باز کردنِ محتوا: ۶ ثانیه (کلید ۴ ثانیه داخلِ همین ۶ ثانیه است)
    return _conversationTopicInner(id).timeout(const Duration(seconds: 6),
        onTimeout: () {
      // 🐢 شبکه‌ی کند: کاربر فعلاً نسخه‌ی داخلِ اپ را می‌بیند، ولی دانلود در پس‌زمینه
      // ادامه دارد؛ هر وقت تمام شد (تا ۲ دقیقه) موضوع خودکار با متنِ کامل تازه می‌شود.
      unawaited(_deliverLate(id));
      return null;
    });
  }

  static final Set<String> _lateWaiting = <String>{};

  static Future<void> _deliverLate(String id) async {
    if (!_lateWaiting.add(id)) return;
    try {
      // کمی صبر تا دانلودِ در جریان ثبت شود
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final inflight = _dlInflight[id];
      if (inflight == null) return;
      final t = await inflight.timeout(const Duration(minutes: 2));
      if (t != null && ProStatus.isPro) {
        onTopicUpdated?.call(id);
        revision.value++; // لیست/موضوعِ باز دوباره بارگذاری شود
      }
    } catch (_) {
    } finally {
      _lateWaiting.remove(id);
    }
  }

  static Future<Map<String, dynamic>?> _conversationTopicInner(
      String id) async {
    try {
      await _ensureCacheMatchesApp();
      final f = await _convFile(id);
      String? have;
      if (await f.exists()) {
        try {
          final m = await compute(_decodeMap, await f.readAsString());
          have = m['version']?.toString();
          final t = m['topic'];
          if (t is Map<String, dynamic>) {
            // بررسیِ نسخه فقط هر ۱۰ دقیقه برای هر موضوع
            final last = _topicChecked[id];
            if (last == null ||
                DateTime.now().difference(last) > const Duration(minutes: 10)) {
              _topicChecked[id] = DateTime.now();
              unawaited(_refreshTopic(id, have));
            }
            return t;
          }
        } catch (e) {
          // 🛟 فایلِ کشِ خراب/ناقص (قطعیِ برق، آپدیتِ اپ…) → پاک و ادامه با نسخه‌ی داخلِ اپ/شبکه
          debugPrint('PaidContent.cache($id) corrupt: $e');
          have = null;
          try {
            await f.delete();
          } catch (_) {}
        }
      }
      // ⚡ کاربر منتظر است: پیش‌دانلودِ پس‌زمینه کنار می‌رود و حداکثر ۶ ثانیه صبر می‌کنیم
      _userWaiting++;
      try {
        return await _downloadTopic(id, have)
            .timeout(const Duration(seconds: 6), onTimeout: () => null);
      } finally {
        _userWaiting--;
      }
    } catch (e) {
      debugPrint('PaidContent.conversationTopic($id): $e');
      return null;
    }
  }

  // ───────────── 🛟 ایمنی در آپدیتِ اپ (مایکت/بازار/پلی‌استور) ─────────────
  // کشِ دانلودی با «اثرانگشتِ محتوای داخلِ APK» برچسب می‌خورد. اگر نسخه‌ی جدیدِ اپ
  // با محتوای عوض‌شده نصب شود، اثرانگشت فرق می‌کند و کشِ قدیمی پاک می‌شود تا
  // محتوای تازه‌ی APK دیده شود (کشِ قدیمی نسخه‌ی جدید را پنهان نکند).
  static const String _fpPref = 'conv_cache_fp_v1';
  static const String _revalPref = 'conv_cache_reval_pending';
  static Future<void>? _fpCheck;

  static Future<void> _ensureCacheMatchesApp() =>
      _fpCheck ??= _doEnsureCacheMatchesApp();

  static Future<void> _doEnsureCacheMatchesApp() async {
    try {
      final raw =
          await rootBundle.loadString('assets/data/conversations_index.json');
      var h = 5381;
      for (final u in raw.codeUnits) {
        h = ((h * 33) ^ u) & 0x7fffffff;
      }
      final fp = '$h:${raw.length}';
      final p = await SharedPreferences.getInstance();
      if (p.getString(_fpPref) != fp) {
        // ⚡ کش پاک نمی‌شود (موضوع‌ها همچنان فوری باز می‌شوند)؛ فقط نسخه‌ی بسته‌ها فراموش
        // می‌شود و در پس‌زمینه با سرور هم‌خوان می‌شود (فایلِ هر موضوع فقط اگر نسخه‌اش عوض
        // شده باشد جایگزین می‌شود). فایلِ خراب هم مثلِ قبل خودکار پاک و دوباره گرفته می‌شود.
        await p.remove(_bundleVerPref);
        await p.remove(_eduBundleVerPref);
        await p.setBool(_revalPref, true);
        await p.setString(_fpPref, fp);
        _topicChecked.clear();
      }
    } catch (e) {
      debugPrint('PaidContent.fp: $e');
      _fpCheck = null; // دفعه‌ی بعد دوباره تلاش شود
    }
  }

  static Future<File> _convFile(String id) async {
    final d = Directory('${(await _dir()).path}/conv');
    if (!await d.exists()) await d.create(recursive: true);
    _convDirPath = d.path;
    return File('${d.path}/$id.json');
  }

  static final Map<String, DateTime> _topicChecked = {};
  static final Map<String, Future<Map<String, dynamic>?>> _dlInflight = {};

  /// دانلودِ هم‌زمانِ یک موضوع یک‌بار انجام می‌شود (پیش‌دانلود و بازکردنِ کاربر یک درخواست را شریک می‌شوند).
  static Future<Map<String, dynamic>?> _downloadTopic(String id, String? have) {
    return _dlInflight[id] ??=
        _downloadTopicRaw(id, have).whenComplete(() => _dlInflight.remove(id));
  }

  static bool _prefetching = false;

  /// تعدادِ موضوع‌هایی که کاربر همین الان منتظرشان است (پیش‌دانلود در این مدت مکث می‌کند)
  static int _userWaiting = 0;

  /// 🚀 همه‌ی موضوع‌ها را با «یک درخواست» می‌گیرد و روی گوشی کش می‌کند (الگوی دولینگو:
  /// درس‌ها از قبل در پس‌زمینه دانلود می‌شوند، لمسِ کاربر فوری باز می‌شود).
  /// اگر سرور هنوز endpoint تازه را ندارد، موضوع‌ها یکی‌یکی (۲ تا هم‌زمان) گرفته می‌شوند.
  static Future<void> prefetchTopics(List<String> ids) async {
    if (_prefetching || !ProStatus.isPro) return;
    _prefetching = true;
    var gotAny = false;
    try {
      await _ensureCacheMatchesApp();
      // 🔄 بعد از آپدیتِ اپ: کش حفظ شده؛ نسخه‌ها در پس‌زمینه با سرور هم‌خوان می‌شوند
      // (اگر شبکه نبود، پرچم می‌ماند و دفعه‌ی بعد دوباره تلاش می‌شود)
      final sp = await SharedPreferences.getInstance();
      if (sp.getBool(_revalPref) == true) {
        final r = await Future.wait([
          _downloadBundle(kind: 'primary'),
          _downloadBundle(),
        ]);
        if (r.every((e) => e)) {
          await sp.remove(_revalPref);
          gotAny = true;
        }
      }
      // 🔁 اگر سرور/شبکه جواب نداد، با فاصله‌های بیشتر دوباره تلاش می‌شود (تا ۶ دور)
      const waits = [0, 20, 60, 120, 300, 600]; // ثانیه
      for (final w in waits) {
        if (!ProStatus.isPro) break;
        if (w > 0) await Future<void>.delayed(Duration(seconds: w));
        final todo = <String>[];
        for (final id in ids) {
          if (id.isEmpty) continue;
          if (!await (await _convFile(id)).exists()) todo.add(id);
        }
        if (todo.isEmpty) break;
        final before = todo.length;
        // 🎒 مکالمه‌های مرحله‌های تحصیلی (p-…) بسته‌ی جدا دارند؛ بقیه مثلِ قبل
        final hasEdu = todo.any((id) => id.startsWith('p-'));
        final hasOther = todo.any((id) => !id.startsWith('p-'));
        // 🎒 مکالمه‌های تحصیلی نسخه‌ی داخلِ اپ ندارند (فقط روی سرورند) پس اولویت با آن‌هاست؛
        // هر دو بسته هم‌زمان گرفته می‌شوند
        final eduF = hasEdu
            ? _downloadBundle(kind: 'primary')
            : Future<bool>.value(false);
        final otherF = hasOther ? _downloadBundle() : Future<bool>.value(false);
        if (await eduF) {
          todo.removeWhere((id) => id.startsWith('p-') && _existsSync(id));
        }
        if (await otherF) {
          todo.removeWhere((id) => !id.startsWith('p-') && _existsSync(id));
        }
        var next = 0;
        Future<void> worker() async {
          while (next < todo.length && ProStatus.isPro) {
            while (_userWaiting > 0) {
              await Future<void>.delayed(const Duration(milliseconds: 400));
            }
            final id = todo[next++];
            try {
              await _downloadTopic(id, null);
            } catch (e) {
              debugPrint('PaidContent.prefetch($id): $e');
            }
          }
        }

        await Future.wait([worker(), worker()]);
        // چیزی دانلود شد؟
        var left = 0;
        for (final id in ids) {
          if (id.isNotEmpty && !await (await _convFile(id)).exists()) left++;
        }
        if (left < before) gotAny = true;
        if (left == 0) break;
      }
    } finally {
      _prefetching = false;
    }
    // موضوعی که کاربر با نسخه‌ی ناقص باز کرده بود با متنِ کامل تازه شود
    if (gotAny && ProStatus.isPro) revision.value++;
  }

  // ───────────── 🚀 پیش‌دانلودِ زودهنگام (همان لحظه‌ای که اپ می‌فهمد کاربر Pro است) ─────────────
  // قبلاً پیش‌دانلود فقط بعد از بارگذاریِ تبِ مکالمه شروع می‌شد. حالا با اولین لحظه‌ای که
  // وضعیتِ Pro معلوم شود (باز شدنِ اپ با Pro ذخیره‌شده، یا Pro شدن/ورود) در پس‌زمینه شروع می‌شود.
  // خودِ دانلودها همان prefetchTopics/prefetchEducation هستند (قفلِ تکراری‌نشدن دارند).
  static bool _earlyHooked = false;

  /// یک‌بار در شروعِ اپ صدا زده شود؛ بعد از آن خودکار به تغییرِ وضعیتِ Pro گوش می‌دهد.
  static void startEarlyPrefetch() {
    if (_earlyHooked) return;
    _earlyHooked = true;
    ProStatus.pro.addListener(() {
      if (ProStatus.isPro) unawaited(_earlyPrefetchNow());
    });
    if (ProStatus.isPro) unawaited(_earlyPrefetchNow());
  }

  static Future<void> _earlyPrefetchNow() async {
    try {
      // چند ثانیه صبر تا بالا آمدنِ اولیه‌ی اپ کند نشود
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!ProStatus.isPro) return;
      final ids = await _allTopicIds();
      await Future.wait([
        if (ids.isNotEmpty) prefetchTopics(ids),
        prefetchEducation(),
      ]);
    } catch (e) {
      debugPrint('PaidContent.earlyPrefetch: $e');
    }
  }

  /// شناسه‌ی همه‌ی موضوع‌های مکالمه (همان فهرستی که ConversationRepository می‌سازد).
  static Future<List<String>> _allTopicIds() async {
    final ids = <String>[];
    for (final f in const [
      'assets/data/conversations_index.json',
      'assets/data/primary_conversations_index.json',
      'assets/data/primary_a2_conversations_index.json',
      'assets/data/primary_b1_conversations_index.json',
      'assets/data/primary_b2_conversations_index.json',
    ]) {
      try {
        final j = jsonDecode(await rootBundle.loadString(f));
        final l = j is Map ? j['list'] : null;
        if (l is! List) continue;
        for (final e in l) {
          if (e is! Map) continue;
          final id = e['id']?.toString() ?? '';
          if (id.isNotEmpty) ids.add(id);
        }
      } catch (e) {
        debugPrint('PaidContent.allTopicIds($f): $e');
      }
    }
    return ids;
  }

  static bool _existsSync(String id) {
    try {
      return File('${_convDirPath ?? ''}/$id.json').existsSync();
    } catch (_) {
      return false;
    }
  }

  static String? _convDirPath;

  /// ⬇️ یک درخواست برای همه‌ی موضوع‌ها: /api/content/conv-bundle → {version, topics:{id:{version,topic}}}
  /// هر موضوع در همان فایلِ قدیمیِ conv/<id>.json (قالبِ {version, topic}) نوشته می‌شود،
  /// پس بقیه‌ی کد بدون تغییر کار می‌کند. نسخه‌ی بسته در SharedPreferences است؛ اگر عوض نشده باشد
  /// سرور فقط {notModified} برمی‌گرداند. اگر endpoint نبود (سرورِ قدیمی) false برمی‌گردد.
  static const String _bundleVerPref = 'paid_v:conv-bundle';
  static const String _eduBundleVerPref = 'paid_v:conv-bundle-primary';

  static Future<bool> _downloadBundle({String? kind}) async {
    try {
      final verPref = kind == 'primary' ? _eduBundleVerPref : _bundleVerPref;
      final p = await SharedPreferences.getInstance();
      final have = p.getString(verPref);
      final r = await _fetch(
          '/api/content/conv-bundle?f=1${kind != null ? '&kind=$kind' : ''}',
          have);
      if (r == null) return false;
      if (r['notModified'] == true) return true;
      final topics = r['topics'];
      if (topics is! Map) return false;
      final dir = Directory('${(await _dir()).path}/conv');
      if (!await dir.exists()) await dir.create(recursive: true);
      _convDirPath = dir.path;
      final changedIds = <String>[];
      for (final e in topics.entries) {
        final id = e.key.toString();
        if (!RegExp(r'^[a-z0-9-]{1,80}$').hasMatch(id)) continue;
        final v = e.value;
        if (v is! Map || v['topic'] is! Map) continue;
        final f = File('${dir.path}/$id.json');
        String? old;
        if (await f.exists()) {
          try {
            old = (jsonDecode(await f.readAsString()) as Map)['version']?.toString();
          } catch (_) {}
        }
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsString(
            jsonEncode({'version': v['version'], 'topic': v['topic']}),
            flush: true);
        await tmp.rename(f.path); // اتمی
        if (old != null && old != v['version']?.toString()) changedIds.add(id);
      }
      await p.setString(verPref, r['version']?.toString() ?? '');
      for (final id in changedIds) {
        onTopicUpdated?.call(id);
      }
      return true;
    } catch (e) {
      debugPrint('PaidContent.bundle: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>?> _downloadTopicRaw(
      String id, String? have) async {
    final r = await _fetch(
        '/api/content/conversation?id=${Uri.encodeQueryComponent(id)}', have);
    if (r == null || r['notModified'] == true) return null;
    final t = r['topic'];
    if (t is! Map<String, dynamic>) return null;
    final f = await _convFile(id);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(r['__raw'] as String, flush: true);
    await tmp.rename(f.path); // اتمی: فایلِ نیمه‌کاره هیچ‌وقت خوانده نمی‌شود
    return t;
  }

  /// نسخه‌ی موضوع را چک می‌کند؛ اگر عوض شده بود کش را به‌روز می‌کند و حافظه را خالی می‌کند.
  static Future<void> _refreshTopic(String id, String? have) async {
    try {
      final t = await _downloadTopic(id, have);
      if (t != null) onTopicUpdated?.call(id);
    } catch (e) {
      debugPrint('PaidContent.refreshTopic($id): $e');
    }
  }

  /// وقتی موضوعی در کش به‌روز شد (ConversationRepository حافظه‌ی همان موضوع را خالی می‌کند).
  static void Function(String id)? onTopicUpdated;

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

  // ─────────── 🎒 مرحله‌های تحصیلی (Education stage): لغات و تمرین‌ها ───────────
  // کلِ فایلِ JSON از `/api/content/blob?key=` می‌آید و روی گوشی کش می‌شود (paid_content/blob_<key>.json).
  // ✅ قواعدِ «هیچ‌وقت گیر نکن»:
  //   ۱) کش اول: اگر یک‌بار دانلود شده باشد، همیشه فوری و آفلاین باز می‌شود؛ نسخه فقط در پس‌زمینه چک می‌شود.
  //   ۲) دانلودِ هم‌زمانِ یک کلید یک‌بار انجام می‌شود (prefetch و بازکردنِ صفحه یک درخواست را شریک می‌شوند).
  //   ۳) فایلِ کشِ خراب پاک می‌شود و دوباره دانلود می‌شود؛ نوشتن اتمی است (tmp → rename).
  //   ۴) پیش‌دانلودِ پس‌زمینه با تلاشِ دوباره (۰/۲۰/۶۰/۱۲۰/۳۰۰/۶۰۰ ثانیه)؛ شکستِ آن هیچ خطایی به کاربر نشان نمی‌دهد.

  static final Map<String, Future<Map<String, dynamic>?>> _blobInflight = {};
  static final Map<String, DateTime> _blobChecked = {};

  /// داده‌ی یک بلاب (همان JSON فایل) یا null اگر Pro نیستی / کش نیست و دانلود نشد.
  static Future<Map<String, dynamic>?> blob(String key) async {
    if (!ProStatus.isPro) return null;
    try {
      final cached = await _readBlobCache(key);
      if (cached != null) {
        final last = _blobChecked[key];
        if (last == null ||
            DateTime.now().difference(last) > const Duration(minutes: 10)) {
          _blobChecked[key] = DateTime.now();
          unawaited(_refreshBlob(key));
        }
        return cached['data'] as Map<String, dynamic>;
      }
      final r = await _downloadBlob(key)
          .timeout(const Duration(seconds: 40), onTimeout: () => null);
      return r;
    } catch (e) {
      debugPrint('PaidContent.blob($key): $e');
      return null;
    }
  }

  static Future<File> _blobFile(String key) async =>
      File('${(await _dir()).path}/${_fileName('blob:$key')}');

  static Future<bool> _blobCached(String key) async {
    try {
      return await (await _blobFile(key)).exists();
    } catch (_) {
      return false;
    }
  }

  /// {version, data} از کش، یا null (نبود/خراب).
  static Future<Map<String, dynamic>?> _readBlobCache(String key) async {
    final f = await _blobFile(key);
    try {
      if (!await f.exists()) return null;
      final m = await compute(_decodeMap, await f.readAsString());
      if (m['data'] is Map<String, dynamic>) return m;
      throw const FormatException('no data');
    } catch (e) {
      debugPrint('PaidContent.blobCache($key) corrupt: $e');
      try {
        await f.delete();
      } catch (_) {}
      return null;
    }
  }

  static Future<Map<String, dynamic>?> _downloadBlob(String key,
      {String? have}) {
    return _blobInflight[key] ??= _downloadBlobRaw(key, have)
        .whenComplete(() => _blobInflight.remove(key));
  }

  static Future<Map<String, dynamic>?> _downloadBlobRaw(
      String key, String? have) async {
    final r = await _fetch(
        '/api/content/blob?key=${Uri.encodeQueryComponent(key)}', have);
    if (r == null || r['notModified'] == true) return null;
    final d = r['data'];
    if (d is! Map<String, dynamic>) return null;
    final f = await _blobFile(key);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(r['__raw'] as String, flush: true);
    await tmp.rename(f.path); // اتمی
    final p = await SharedPreferences.getInstance();
    await p.setString(_verKey('blob:$key'), r['version']?.toString() ?? '');
    return d;
  }

  /// نسخه را چک می‌کند؛ اگر تازه‌تر بود کش را عوض می‌کند و لیست‌ها دوباره بارگذاری می‌شوند.
  static Future<void> _refreshBlob(String key) async {
    try {
      final p = await SharedPreferences.getInstance();
      final have = p.getString(_verKey('blob:$key'));
      final d = await _downloadBlob(key, have: have);
      if (d != null && ProStatus.isPro) revision.value++;
    } catch (e) {
      debugPrint('PaidContent.refreshBlob($key): $e');
    }
  }

  static bool _eduPrefetching = false;

  /// 🚀 لغات/تمرین‌های مرحله‌های تحصیلی را در پس‌زمینه می‌گیرد تا لمسِ کاربر فوری باز شود.
  /// با اینترنتِ ضعیف/خطای سرور بی‌صدا چند بار با فاصله دوباره تلاش می‌کند.
  static Future<void> prefetchEducation() async {
    if (_eduPrefetching || !ProStatus.isPro) return;
    _eduPrefetching = true;
    var gotAny = false;
    try {
      const waits = [0, 20, 60, 120, 300, 600]; // ثانیه
      for (final w in waits) {
        if (!ProStatus.isPro) break;
        if (w > 0) await Future<void>.delayed(Duration(seconds: w));
        var left = 0;
        for (final k in eduBlobKeys) {
          if (!ProStatus.isPro) break;
          if (await _blobCached(k)) continue;
          while (_userWaiting > 0) {
            await Future<void>.delayed(const Duration(milliseconds: 400));
          }
          try {
            final d = await _downloadBlob(k);
            if (d != null) {
              gotAny = true;
            } else {
              left++;
            }
          } catch (e) {
            left++;
            debugPrint('PaidContent.prefetchEducation($k): $e');
          }
        }
        if (left == 0) break;
      }
    } finally {
      _eduPrefetching = false;
    }
    if (gotAny && ProStatus.isPro) revision.value++;
  }

  // ─────────── شبکه ───────────

  /// پاسخِ سرور (به‌همراهِ '__raw' = متنِ خام برای ذخیره در کش) یا null.
  static Future<Map<String, dynamic>?> _fetch(String path, String? have) async {
    Future<Response<String>> once() => _dio.get<String>(
          '${TtsConfig.backendUrl}$path${have != null ? '&v=$have' : ''}',
          options: Options(
            headers: WorkerAuth.headers,
            responseType: ResponseType.plain,
            sendTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 30),
            validateStatus: (_) => true,
          ),
        );
    await WorkerAuth.ensureFresh();
    Response<String> res;
    try {
      res = await once();
    } on DioException {
      // یک بار دوباره (شبکه‌ی ضعیف / بیدار شدنِ سرور)
      res = await once();
    }
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
      unawaited(_dropLegacyConvCache());
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
        // 🎒 بلابِ تحصیلی که هنوز دانلود نشده را اینجا نمی‌گیریم (prefetchEducation/باز کردنِ صفحه می‌گیرد)
        if (key.startsWith('blob:') && have == null) continue;
        final isWords = key.startsWith('words:');
        final name = key.split(':')[1];
        final path = key.startsWith('blob:')
            ? '/api/content/blob?key=$name'
            : isWords
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

  /// کشِ قدیمیِ «کلِ مکالمه‌ها در یک فایل» (قبل از لود تنبل) را پاک می‌کند.
  static Future<void> _dropLegacyConvCache() async {
    try {
      final d = await _dir();
      for (final n in ['conv_daily.json', 'conv_thematic.json']) {
        final f = File('${d.path}/$n');
        if (await f.exists()) await f.delete();
      }
      final p = await SharedPreferences.getInstance();
      await p.remove('paid_v:conv:daily');
      await p.remove('paid_v:conv:thematic');
    } catch (_) {}
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
      await p.remove(_eduBundleVerPref);
      await p.remove(_bundleVerPref); // وگرنه بعد از ورودِ دوباره «notModified» می‌آید ولی فایل‌ها پاک شده‌اند
      _topicChecked.clear();
      _blobChecked.clear();
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
