// 📁 مسیر: lib/core/storage/story_page_store.dart
//
// عکسِ صفحه‌های PDF (اصلی + ترجمه‌شده) برای داستان‌های ذخیره‌شده در «کتابخانه‌ی داستان‌ساز».
// هر داستان یک پوشه زیرِ <appSupport>/story_pages/<storyId>/ دارد (o3.png = اصلیِ صفحه‌ی ۴، t3.png = ترجمه‌اش).
// وب: ذخیره‌ی دیسکی نیست؛ همه‌ی متدها بی‌صدا false/null برمی‌گردانند.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

class StoryPageStore {
  StoryPageStore._();

  static Directory? _root;

  static String _safe(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');

  static Future<Directory?> _rootDir() async {
    if (kIsWeb) return null;
    final r = _root;
    if (r != null) return r;
    try {
      final base = await getApplicationSupportDirectory();
      final d = Directory('${base.path}/story_pages');
      if (!await d.exists()) await d.create(recursive: true);
      return _root = d;
    } catch (_) {
      return null;
    }
  }

  static String origName(int page) => 'o$page';
  static String transName(int page) => 't$page';

  /// ذخیره‌ی یک عکس (name مثل «o3» یا «t3»). true فقط وقتی واقعاً نوشته شد.
  static Future<bool> put(String storyId, String name, Uint8List bytes) async {
    try {
      final root = await _rootDir();
      if (root == null) return false;
      final d = Directory('${root.path}/${_safe(storyId)}');
      if (!await d.exists()) await d.create(recursive: true);
      final path = '${d.path}/${_safe(name)}.png';
      final tmp = File('$path.part');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(path);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<Uint8List?> get(String storyId, String name) async {
    try {
      final root = await _rootDir();
      if (root == null) return null;
      final f = File('${root.path}/${_safe(storyId)}/${_safe(name)}.png');
      if (!await f.exists()) return null;
      return await f.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  static Future<void> deleteStory(String storyId) async {
    try {
      final root = await _rootDir();
      if (root == null) return;
      final d = Directory('${root.path}/${_safe(storyId)}');
      if (await d.exists()) await d.delete(recursive: true);
    } catch (_) {}
  }
}
