// 📁 مسیر: lib/core/storage/big_story_store.dart
//
// ذخیره‌ی بدنه‌ی داستان‌های خیلی بلند (متن + ترجمه‌ها) در دیتابیسِ جدا (sembast).
// SharedPreferences همه‌چیز را در حافظه نگه می‌دارد و هر تغییر کلِ JSON را دوباره
// می‌نویسد؛ برای کتابِ چندصد صفحه‌ای این یعنی کندیِ شروعِ برنامه و قفل‌شدنِ UI.
// در prefs فقط «سرنخِ سبک» (عنوان، سطح، یادداشت، پیش‌نمایش) می‌ماند.

import 'dart:async';

import 'package:sembast/sembast.dart';

import 'db_factory.dart';

class BigStoryStore {
  BigStoryStore._();
  static final BigStoryStore instance = BigStoryStore._();

  static const String _dbName = 'zflut-big-stories.db';
  final StoreRef<String, Map<String, Object?>> _store =
      StoreRef<String, Map<String, Object?>>('big_stories');

  Database? _db;
  Future<Database?>? _opening;

  Future<Database?> _open() => _opening ??= () async {
        try {
          return await openCacheDatabase(_dbName);
        } catch (_) {
          return null;
        }
      }();

  /// true = دیتابیس باز شد و می‌شود به آن اعتماد کرد.
  Future<bool> ensureOpen() async {
    _db ??= await _open();
    return _db != null;
  }

  /// ذخیره؛ true فقط وقتی واقعاً نوشته شد.
  Future<bool> put(
      String id, String text, Map<String, List<String>> translations) async {
    try {
      if (!await ensureOpen()) return false;
      await _store.record(id).put(_db!, <String, Object?>{
        'text': text,
        'translations': <String, Object?>{
          for (final e in translations.entries) e.key: List<String>.from(e.value),
        },
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// {'text': String, 'translations': Map<String, List<String>>} یا null
  Future<Map<String, Object?>?> get(String id) async {
    try {
      if (!await ensureOpen()) return null;
      final v = await _store.record(id).get(_db!);
      if (v == null) return null;
      final tr = <String, List<String>>{};
      final raw = v['translations'];
      if (raw is Map) {
        raw.forEach((k, val) {
          if (val is List) {
            tr[k.toString()] = [for (final x in val) x.toString()];
          }
        });
      }
      return <String, Object?>{
        'text': (v['text'] ?? '').toString(),
        'translations': tr,
      };
    } catch (_) {
      return null;
    }
  }

  Future<void> delete(String id) async {
    try {
      if (!await ensureOpen()) return;
      await _store.record(id).delete(_db!);
    } catch (_) {}
  }
}
