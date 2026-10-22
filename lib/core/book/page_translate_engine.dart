// 📁 مسیر: lib/core/book/page_translate_engine.dart
//
// موتورِ ترجمه‌ی صفحه‌به‌صفحه‌ی کتاب/PDF (مستقل از ویجت و پلتفرم).
//
// اصول طراحی:
//   ۱. یک صفحه در هر لحظه (OCR سنگین است) — صفِ اولویت‌دار: صفحه‌ی فعلی ← چند صفحه‌ی
//      بعد (lookahead) ← فقط اگر کاربر «کل کتاب» را روشن کرده باشد بقیه‌ی کتاب.
//   ۲. حافظه محدود: فقط چند صفحه‌ی آخر در RAM (LRU با سقفِ بایت)، بقیه روی دیسک.
//   ۳. پیشرفت ماندگار: هر صفحه‌ی تمام‌شده فوراً روی دیسک نوشته می‌شود و فهرستِ
//      صفحه‌های انجام‌شده هم ذخیره می‌شود؛ بعد از کرش/بستنِ برنامه ادامه می‌دهد.
//   ۴. تحملِ خطا: هر صفحه تا ۳ بار با تأخیرِ فزاینده؛ اگر چند صفحه‌ی پشت‌سرهم شکست
//      خورد (اینترنت قطع) خودکار مکث می‌کند به‌جای اینکه کل کتاب را «خراب» کند.
//   ۵. هیچ‌چیز خودبه‌خود کل کتاب را شروع نمی‌کند.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'book_disk.dart';

/// خطای «غیرقابل‌تکرار» (مثلاً زبانِ OCR پشتیبانی نمی‌شود) — موتور متوقف می‌شود.
class PageTranslateFatal implements Exception {
  final String message;
  const PageTranslateFatal(this.message);
  @override
  String toString() => 'PageTranslateFatal: $message';
}

enum PageStatus { pending, working, done, empty, failed }

/// هش پایدار (FNV-1a) — String.hashCode بین اجراها تضمینِ یکسان‌بودن ندارد.
String stableHash(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h.toRadixString(36);
}

class PageTranslateEngine extends ChangeNotifier {
  PageTranslateEngine({
    required this.docKey,
    required this.sig,
    required this.pageCount,
    required this.disk,
    required this.worker,
    this.lookahead = 5,
    this.memoryBudgetBytes = 24 * 1024 * 1024,
    this.maxAttempts = 3,
  }) : _tag = stableHash(sig);

  final String docKey;
  final String sig;
  final int pageCount;
  final BookDisk disk;

  /// ترجمه‌ی کاملِ یک صفحه (رندر ← OCR ← ترجمه ← ساختنِ عکس).
  /// خروجی: بایت‌های PNG؛ null = صفحه متنی ندارد (همان عکسِ اصلی نشان داده شود).
  final Future<Uint8List?> Function(int page) worker;

  final int lookahead;
  final int memoryBudgetBytes;
  final int maxAttempts;
  final String _tag;

  final Map<int, PageStatus> _status = <int, PageStatus>{};
  final Map<int, int> _attempts = <int, int>{};
  final LinkedHashMap<int, Uint8List> _mem = LinkedHashMap<int, Uint8List>();
  int _memBytes = 0;

  int _focus = 0;
  bool _active = false;
  bool _paused = false;
  bool _wholeBook = false;
  bool _disposed = false;
  bool _loopRunning = false;
  int _consecutiveFails = 0;
  int? _working;
  String _note = '';
  Timer? _metaTimer;
  bool _metaDirty = false;

  // ───────────── وضعیت (برای UI) ─────────────
  bool get active => _active;
  bool get paused => _paused;
  bool get wholeBook => _wholeBook;
  bool get running => _active && !_paused;
  int? get workingPage => _working;
  String get note => _note;
  int get focus => _focus;

  int _count(PageStatus s) {
    var n = 0;
    for (final v in _status.values) {
      if (v == s) n++;
    }
    return n;
  }

  int get doneCount => _count(PageStatus.done);
  int get emptyCount => _count(PageStatus.empty);
  int get failedCount => _count(PageStatus.failed);

  /// صفحه‌هایی که تکلیفشان روشن است (ترجمه‌شده یا بدونِ متن)
  int get settledCount => doneCount + emptyCount;

  PageStatus statusOf(int page) => _status[page] ?? PageStatus.pending;

  String get _metaName => 'meta_$_tag.json';
  String _imgName(int page) => 'p${page}_$_tag.png';

  // ───────────── چرخه‌ی عمر ─────────────
  /// پیشرفتِ ذخیره‌شده‌ی قبلی را از دیسک می‌خواند (اگر باشد).
  Future<void> init() async {
    try {
      final raw = await disk.readBytes(docKey, _metaName);
      if (raw == null || _disposed) return;
      final j = jsonDecode(utf8.decode(raw));
      if (j is! Map) return;
      if (j['pages'] != pageCount) return; // فایلِ دیگری با همین کلید
      final done = j['done'];
      final empty = j['empty'];
      if (done is List) {
        for (final e in done) {
          if (e is int && e >= 0 && e < pageCount) _status[e] = PageStatus.done;
        }
      }
      if (empty is List) {
        for (final e in empty) {
          if (e is int && e >= 0 && e < pageCount) {
            _status[e] = PageStatus.empty;
          }
        }
      }
      _notify();
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _active = false;
    _metaTimer?.cancel();
    if (_metaDirty) unawaited(_flushMeta());
    _mem.clear();
    _memBytes = 0;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ───────────── کنترل ─────────────
  /// شروعِ ترجمه‌ی خودکار از صفحه‌ی [page] (صفحه‌ی فعلی + lookahead).
  void activate({int? page}) {
    if (_disposed) return;
    if (page != null) _focus = page.clamp(0, pageCount - 1).toInt();
    _active = true;
    _paused = false;
    _consecutiveFails = 0;
    _note = '';
    _notify();
    _kick();
  }

  /// توقفِ کامل (صفحه‌ای که در حالِ ترجمه است تمام می‌شود و ذخیره می‌شود).
  void deactivate() {
    _active = false;
    _paused = false;
    _note = 'متوقف شد';
    _notify();
  }

  void pause() {
    if (!_active) return;
    _paused = true;
    _notify();
  }

  void resume() {
    if (_disposed) return;
    _active = true;
    _paused = false;
    _consecutiveFails = 0;
    _note = '';
    _notify();
    _kick();
  }

  /// روشن/خاموش‌کردنِ ترجمه‌ی کلِ کتاب در پس‌زمینه.
  void setWholeBook(bool v) {
    _wholeBook = v;
    if (v) {
      _active = true;
      _paused = false;
      _consecutiveFails = 0;
      _note = '';
    }
    _notify();
    if (v) _kick();
  }

  /// کاربر به صفحه‌ی دیگری رفته؛ صف از همان‌جا ادامه پیدا می‌کند.
  void focusOn(int page) {
    final p = page.clamp(0, pageCount - 1).toInt();
    if (p == _focus) return;
    _focus = p;
    if (_active && !_paused) _kick();
  }

  /// صفحه‌های ناموفق دوباره امتحان می‌شوند.
  void retryFailed() {
    for (final e in _status.entries.toList()) {
      if (e.value == PageStatus.failed) {
        _status[e.key] = PageStatus.pending;
        _attempts.remove(e.key);
      }
    }
    _active = true;
    _paused = false;
    _consecutiveFails = 0;
    _note = '';
    _notify();
    _kick();
  }

  // ───────────── خواندنِ عکس ─────────────
  /// عکسِ ترجمه‌شده‌ی یک صفحه (اول RAM، بعد دیسک). اگر نبود null.
  Future<Uint8List?> imageFor(int page) async {
    if (statusOf(page) != PageStatus.done) return null;
    final hit = _mem.remove(page);
    if (hit != null) {
      _mem[page] = hit; // تازه‌ترین
      return hit;
    }
    final bytes = await disk.readBytes(docKey, _imgName(page));
    if (bytes == null || _disposed) {
      // فایل گم شده (مثلاً دیسک پاک شد) → دوباره در صف
      if (!_disposed && statusOf(page) == PageStatus.done) {
        _status[page] = PageStatus.pending;
        _metaDirty = true;
        _scheduleMeta();
        _notify();
        if (_active && !_paused) _kick();
      }
      return null;
    }
    _putMem(page, bytes);
    return bytes;
  }

  void _putMem(int page, Uint8List bytes) {
    final old = _mem.remove(page);
    if (old != null) _memBytes -= old.length;
    _mem[page] = bytes;
    _memBytes += bytes.length;
    while (_memBytes > memoryBudgetBytes && _mem.length > 2) {
      final k = _mem.keys.first;
      if (k == _focus && _mem.length > 1) {
        // صفحه‌ی فعلی را آخرین‌نفر کنیم تا پاک نشود
        final v = _mem.remove(k)!;
        _mem[k] = v;
        continue;
      }
      final v = _mem.remove(k);
      if (v != null) _memBytes -= v.length;
    }
  }

  // ───────────── حلقه‌ی کار ─────────────
  void _kick() {
    if (_disposed || !_active || _paused) return;
    if (_loopRunning) return; // حلقه‌ی فعلی وضعیتِ جدید را خودش می‌بیند
    _loopRunning = true;
    unawaited(_runLoop());
  }

  int? _nextPage() {
    bool want(int i) => (_status[i] ?? PageStatus.pending) == PageStatus.pending;
    for (var k = 0; k <= lookahead; k++) {
      final i = _focus + k;
      if (i < pageCount && want(i)) return i;
    }
    if (!_wholeBook) return null;
    for (var i = _focus + lookahead + 1; i < pageCount; i++) {
      if (want(i)) return i;
    }
    for (var i = 0; i < _focus; i++) {
      if (want(i)) return i;
    }
    return null;
  }

  Future<void> _runLoop() async {
    try {
      while (!_disposed && _active && !_paused) {
        final i = _nextPage();
        if (i == null) {
          _note = _wholeBook && failedCount == 0
              ? 'ترجمه‌ی همه‌ی صفحه‌ها تموم شد ✓'
              : '';
          if (!_wholeBook) {
            // حالتِ lookahead: بیکار می‌مانیم تا کاربر صفحه عوض کند (active می‌ماند)
          }
          break;
        }
        _status[i] = PageStatus.working;
        _working = i;
        _note = 'در حال ترجمه‌ی صفحه‌ی ${i + 1} از $pageCount...';
        _notify();
        try {
          final bytes = await worker(i);
          if (_disposed) return;
          if (bytes == null) {
            _status[i] = PageStatus.empty;
          } else {
            await disk.writeBytes(docKey, _imgName(i), bytes);
            if (_disposed) return;
            _putMem(i, bytes);
            _status[i] = PageStatus.done;
          }
          _attempts.remove(i);
          _consecutiveFails = 0;
          _metaDirty = true;
          _scheduleMeta();
        } on PageTranslateFatal catch (e) {
          if (_disposed) return;
          _status[i] = PageStatus.pending;
          _active = false;
          _note = e.message;
          _working = null;
          _notify();
          return;
        } catch (_) {
          if (_disposed) return;
          final n = (_attempts[i] ?? 0) + 1;
          _attempts[i] = n;
          _status[i] = n >= maxAttempts ? PageStatus.failed : PageStatus.pending;
          _consecutiveFails++;
          if (_consecutiveFails >= 3) {
            _paused = true;
            _note =
                'چند صفحه‌ی پشت‌سرهم ترجمه نشد — اینترنتت رو چک کن و «ادامه» رو بزن';
          } else {
            // تأخیرِ فزاینده: ۲، ۴، ۸ ثانیه
            final sh = _consecutiveFails - 1;
            final shift = sh < 0 ? 0 : (sh > 2 ? 2 : sh);
            await Future<void>.delayed(Duration(seconds: 2 << shift));
          }
        }
        _working = null;
        _notify();
        // به UI و GC فرصت نفس‌کشیدن بده (در حالتِ کل‌کتاب بیشتر)
        await Future<void>.delayed(
            Duration(milliseconds: _wholeBook ? 400 : 80));
      }
    } finally {
      _loopRunning = false;
      _working = null;
      if (!_disposed) {
        if (_metaDirty) unawaited(_flushMeta());
        _notify();
      }
    }
  }

  // ───────────── ذخیره‌ی فهرستِ پیشرفت ─────────────
  void _scheduleMeta() {
    _metaTimer?.cancel();
    _metaTimer = Timer(const Duration(milliseconds: 1500), () {
      unawaited(_flushMeta());
    });
  }

  Future<void> _flushMeta() async {
    _metaDirty = false;
    final done = <int>[];
    final empty = <int>[];
    _status.forEach((k, v) {
      if (v == PageStatus.done) done.add(k);
      if (v == PageStatus.empty) empty.add(k);
    });
    done.sort();
    empty.sort();
    try {
      final data = utf8.encode(jsonEncode(
          {'v': 1, 'pages': pageCount, 'done': done, 'empty': empty}));
      await disk.writeBytes(docKey, _metaName, Uint8List.fromList(data));
    } catch (_) {}
  }
}
