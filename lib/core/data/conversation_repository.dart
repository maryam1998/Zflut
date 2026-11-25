import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/conversation.dart';
import '../usage/pro_status.dart';
import 'paid_content.dart';

/// 📚 مکالمه‌ها با «لود تنبل»:
///   • موقعِ شروعِ اپ فقط فهرستِ موضوع‌ها (assets/data/conversations_index.json، ~۱۰KB) خوانده می‌شود؛
///   • متنِ هر موضوع فقط وقتی کاربر آن را باز می‌کند لود می‌شود ([loadTopic]):
///       رایگان → assets/data/conversations/<id>.json (فقط موضوع‌های رایگان، جمله‌های A1)
///       Pro    → Worker `/api/content/conversation?id=` + کشِ گوشی (هر موضوع یک فایل)
class ConversationRepository {
  ConversationRepository._() {
    PaidContent.onTopicUpdated = (id) => _cache.remove(id);
  }
  static final ConversationRepository instance = ConversationRepository._();

  List<ConversationTopic> _all = const [];
  bool _loaded = false;
  String? _error;

  /// موضوع‌های بارگذاری‌شده (id → موضوعِ کامل)
  final Map<String, ConversationTopic> _cache = {};
  final Map<String, Future<ConversationTopic?>> _pending = {};

  /// فهرستِ موضوع‌ها (فقط نام/شناسه؛ scenarios خالی است)
  List<ConversationTopic> get all => _all;
  List<ConversationTopic> get daily =>
      [for (final t in _all) if (t.kind == 'daily') t];
  List<ConversationTopic> get thematic =>
      [for (final t in _all) if (t.kind == 'thematic') t];
  bool get isLoaded => _loaded;
  String? get error => _error;
  int get totalTopics => _all.length;

  Future<void>? _inflight;

  /// ⚡ فقط حافظه‌ی موضوع‌ها را خالی می‌کند (فهرستِ موضوع‌ها دوباره خوانده نمی‌شود).
  /// وقتی Pro شد/محتوای پولی عوض شد صدا زده می‌شود؛ بسیار سریع است و باعث
  /// «چرخیدنِ طولانیِ» تبِ Talk نمی‌شود.
  void resetTopics() {
    _cache.clear();
    _pending.clear();
    if (_loaded && ProStatus.isPro) {
      final ids = [for (final t in _all) if (t.kind != 'primary') t.id];
      Future.delayed(const Duration(seconds: 1),
          () => unawaited(PaidContent.prefetchTopics(ids)));
    }
  }

  /// فقط یک‌بار اجرا می‌شود؛ فراخوانی‌های هم‌زمان همان Future را می‌گیرند.
  /// [force] = دوباره (وقتی Pro شد/محتوای پولی به‌روز شد): حافظه‌ی موضوع‌ها خالی می‌شود.
  Future<void> load({bool force = false}) {
    if (force) {
      _loaded = false;
      _inflight = null;
      _cache.clear();
      _pending.clear();
    }
    return _inflight ??= _doLoad();
  }

  Future<void> _doLoad() async {
    if (_loaded) return;
    try {
      final raw =
          await rootBundle.loadString('assets/data/conversations_index.json');
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final list = j['list'];
      if (list is! List) throw StateError('conversations_index: no list');
      _all = [
        for (final e in list)
          ConversationTopic(
            id: (e as Map)['id']?.toString() ?? '',
            kind: e['kind']?.toString() ?? '',
            topic: e['topic']?.toString() ?? '',
            scenarios: const [],
          ),
      ];
      // 🎒 مکالمه‌های Primary School ▸ A1 و A2 (فایل‌های جدا؛ برای همه باز)
      for (final pf in const [
        'assets/data/primary_conversations_index.json',
        'assets/data/primary_a2_conversations_index.json',
      ]) {
        try {
          final pr = await rootBundle.loadString(pf);
          final pj = jsonDecode(pr) as Map<String, dynamic>;
          final pl = pj['list'];
          if (pl is List) {
            final extra = <ConversationTopic>[];
            for (final e in pl) {
              final m = e as Map;
              final name = m['topic']?.toString() ?? '';
              if (name.isEmpty) continue;
              ProStatus.freeExtraTopics.add(name);
              extra.add(ConversationTopic(
                id: m['id']?.toString() ?? '',
                kind: 'primary',
                topic: name,
                scenarios: const [],
              ));
            }
            _all = [..._all, ...extra];
          }
        } catch (e) {
          debugPrint('ConversationRepository primary ($pf): $e');
        }
      }
      _loaded = true;
      _error = null;
      // 🚀 Pro: متنِ موضوع‌ها را در پس‌زمینه پیش‌دانلود کن تا با لمس فوری باز شوند
      if (ProStatus.isPro) {
        final ids = [for (final t in _all) if (t.kind != 'primary') t.id];
        Future.delayed(const Duration(seconds: 1),
            () => unawaited(PaidContent.prefetchTopics(ids)));
      }
    } catch (e) {
      _error = e.toString();
      _loaded = false;
      _inflight = null; // بار بعد دوباره تلاش شود
    }
  }

  /// متنِ کاملِ یک موضوع (با لود تنبل). null = قفل است/در دسترس نیست.
  Future<ConversationTopic?> loadTopic(ConversationTopic stub) {
    if (stub.id.isEmpty) return Future.value(stub);
    final hit = _cache[stub.id];
    if (hit != null) return Future.value(hit);
    return _pending[stub.id] ??= _loadTopic(stub).whenComplete(() {
      _pending.remove(stub.id);
    });
  }

  /// ⚡ نمایشِ تدریجی: اول نسخه‌ی داخلِ اپ (فوری)، بعد نسخه‌ی کاملِ Pro (کش/شبکه) جایگزین می‌شود.
  /// کاربر هیچ‌وقت اسپینرِ طولانی نمی‌بیند مگر موضوعی که نسخه‌ی داخلِ اپ ندارد.
  Stream<ConversationTopic?> watchTopic(ConversationTopic stub) async* {
    if (stub.id.isEmpty) {
      yield stub;
      return;
    }
    final hit = _cache[stub.id];
    if (hit != null) {
      yield hit;
      return;
    }
    ConversationTopic? preview;
    // 💎 Pro: متنِ کاملِ داخلِ اپ (آفلاین، فوری) — اگر نبود نسخه‌ی رایگان
    final a = (ProStatus.isPro ? await _readProBundle(stub.id) : null) ??
        await _readAsset(stub.id);
    if (a != null) {
      preview = ConversationTopic.fromJson(a, id: stub.id, kind: stub.kind);
      yield preview; // ← فوری
    }
    if (!ProStatus.isPro) {
      if (preview != null) _cache[stub.id] = preview;
      if (preview == null) yield null;
      return;
    }
    final full = await PaidContent.conversationTopic(stub.id);
    if (full != null) {
      try {
        final t =
            ConversationTopic.fromJson(full, id: stub.id, kind: stub.kind);
        _cache[stub.id] = t;
        yield t; // ← نسخه‌ی کامل جایگزین می‌شود
      } catch (e) {
        // 🛟 ساختارِ ناسازگار (مثلاً محتوای سرور جدیدتر از اپ): نسخه‌ی پیش‌نمایش بماند
        debugPrint('ConversationRepository parse ${stub.id}: $e');
        if (preview == null) yield null;
      }
    } else if (preview == null) {
      yield null; // نه داخل اپ هست نه شبکه → «تلاش دوباره»
    }
  }

  Future<ConversationTopic?> _loadTopic(ConversationTopic stub) async {
    Map<String, dynamic>? j;
    var fromPaid = false;
    if (ProStatus.isPro) {
      j = await PaidContent.conversationTopic(stub.id);
      fromPaid = j != null;
    }
    // 💎 Pro بدونِ اینترنت/کش: متنِ کاملِ داخلِ اپ (کش نمی‌شود تا نسخه‌ی تازه‌ی سرور جایش بیاید)
    if (ProStatus.isPro) j ??= await _readProBundle(stub.id);
    // رایگان: نسخه‌ی داخلِ اپ — فقط موضوع‌های رایگان آن را دارند
    j ??= await _readAsset(stub.id);
    if (j == null) return null;
    try {
      final t = ConversationTopic.fromJson(j, id: stub.id, kind: stub.kind);
      // 🛟 Pro که دانلود نشد: نسخه‌ی ناقصِ داخلِ اپ (فقط ۴ سناریوی اول) کش نشود
      if (!ProStatus.isPro || fromPaid) _cache[stub.id] = t;
      return t;
    } catch (e) {
      debugPrint('ConversationRepository parse ${stub.id}: $e');
      return null;
    }
  }

  // ───────────── 💎 بسته‌ی آفلاینِ Pro ─────────────
  // assets/data/pro_conv_bundle.bin (ساخته‌شده با scripts/build-pro-bundle.mjs).
  // فقط برای کاربرِ Pro و فقط وقتی سرور/کش جواب ندهد خوانده می‌شود.
  static const String _bundleKey = 'lingova-pro-conv-v1';
  Map<String, dynamic>? _proBundle;
  Future<Map<String, dynamic>?>? _proBundleLoad;

  Future<Map<String, dynamic>?> _readProBundle(String id) async {
    if (!ProStatus.isPro) return null;
    try {
      _proBundleLoad ??= _loadProBundle();
      final all = await _proBundleLoad;
      final t = all?[id];
      return t is Map<String, dynamic> ? t : null;
    } catch (e) {
      debugPrint('ConversationRepository bundle $id: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _loadProBundle() async {
    try {
      final data = await rootBundle.load('assets/data/pro_conv_bundle.bin');
      final b = Uint8List.fromList(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      final k = utf8.encode(_bundleKey);
      for (var i = 0; i < b.length; i++) {
        b[i] ^= k[i % k.length];
      }
      final m = jsonDecode(utf8.decode(b));
      return m is Map<String, dynamic> ? m : null;
    } catch (e) {
      debugPrint('ConversationRepository bundle load: $e');
      _proBundleLoad = null; // دفعه‌ی بعد دوباره تلاش شود
      return null;
    }
  }

  Future<Map<String, dynamic>?> _readAsset(String id) async {
    try {
      final raw = await rootBundle.loadString('assets/data/conversations/$id.json');
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('ConversationRepository asset $id: $e');
      return null;
    }
  }
}
