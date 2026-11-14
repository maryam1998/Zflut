import 'dart:async';
import 'dart:convert';

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
      unawaited(PaidContent.prewarmKey());
      final ids = [for (final t in _all) t.id];
      Future.delayed(const Duration(seconds: 6),
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
      _loaded = true;
      _error = null;
      // 🚀 Pro: متنِ موضوع‌ها را در پس‌زمینه پیش‌دانلود کن تا با لمس فوری باز شوند
      if (ProStatus.isPro) {
        unawaited(PaidContent.prewarmKey()); // 🔑 کلیدِ کوچک: همین الان، تا لمسِ اول فوری باشد
        final ids = [for (final t in _all) t.id];
        Future.delayed(const Duration(seconds: 6),
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
    final a = await _readAsset(stub.id);
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
    if (ProStatus.isPro) {
      j = await PaidContent.conversationTopic(stub.id);
    }
    // رایگان (یا Pro بدونِ اینترنت/کش): نسخه‌ی داخلِ اپ — فقط موضوع‌های رایگان آن را دارند
    j ??= await _readAsset(stub.id);
    if (j == null) return null;
    try {
      final t = ConversationTopic.fromJson(j, id: stub.id, kind: stub.kind);
      _cache[stub.id] = t;
      return t;
    } catch (e) {
      debugPrint('ConversationRepository parse ${stub.id}: $e');
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
