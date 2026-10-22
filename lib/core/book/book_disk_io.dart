// اندروید / iOS / دسکتاپ: هر سند یک پوشه زیرِ <appSupport>/book_cache/
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'book_disk_api.dart';

class _IoBookDisk implements BookDisk {
  Directory? _root;

  Future<Directory> _rootDir() async {
    final r = _root;
    if (r != null) return r;
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}/book_cache');
    if (!await d.exists()) await d.create(recursive: true);
    _root = d;
    return d;
  }

  String _safe(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');

  Future<Directory> _docDir(String doc, {bool create = false}) async {
    final root = await _rootDir();
    final d = Directory('${root.path}/${_safe(doc)}');
    if (create && !await d.exists()) await d.create(recursive: true);
    return d;
  }

  @override
  Future<Uint8List?> readBytes(String doc, String name) async {
    try {
      final d = await _docDir(doc);
      final f = File('${d.path}/${_safe(name)}');
      if (!await f.exists()) return null;
      return await f.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeBytes(String doc, String name, Uint8List data) async {
    try {
      final d = await _docDir(doc, create: true);
      final path = '${d.path}/${_safe(name)}';
      final tmp = File('$path.part');
      await tmp.writeAsBytes(data, flush: true);
      await tmp.rename(path);
    } catch (_) {
      // دیسک پر/خطا: فقط حافظه کار می‌کند؛ برنامه نباید بیفتد
    }
  }

  @override
  Future<void> deleteDoc(String doc) async {
    try {
      final d = await _docDir(doc);
      if (await d.exists()) await d.delete(recursive: true);
    } catch (_) {}
  }

  @override
  Future<void> trim({required int maxBytes, String? keepDoc}) async {
    try {
      final root = await _rootDir();
      final items = <_DocInfo>[];
      var total = 0;
      await for (final e in root.list(followLinks: false)) {
        if (e is! Directory) continue;
        var size = 0;
        var newest = DateTime.fromMillisecondsSinceEpoch(0);
        await for (final f in e.list(recursive: true, followLinks: false)) {
          if (f is! File) continue;
          try {
            final st = await f.stat();
            size += st.size;
            if (st.modified.isAfter(newest)) newest = st.modified;
          } catch (_) {}
        }
        total += size;
        items.add(_DocInfo(e, size, newest));
      }
      if (total <= maxBytes) return;
      items.sort((a, b) => a.newest.compareTo(b.newest));
      final keep = keepDoc == null ? null : _safe(keepDoc);
      for (final it in items) {
        if (total <= maxBytes) break;
        final name = it.dir.path.split(Platform.pathSeparator).last;
        if (keep != null && name == keep) continue;
        try {
          await it.dir.delete(recursive: true);
          total -= it.size;
        } catch (_) {}
      }
    } catch (_) {}
  }

  @override
  Future<void> cleanTemp() async {
    try {
      final tmp = await getTemporaryDirectory();
      final cutoff = DateTime.now().subtract(const Duration(minutes: 30));
      await for (final e in tmp.list(followLinks: false)) {
        if (e is! File) continue;
        final n = e.path.split(Platform.pathSeparator).last;
        if (!(n.startsWith('ocr_') || n.startsWith('ocrb_'))) continue;
        try {
          final st = await e.stat();
          if (st.modified.isBefore(cutoff)) await e.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }
}

class _DocInfo {
  final Directory dir;
  final int size;
  final DateTime newest;
  _DocInfo(this.dir, this.size, this.newest);
}

BookDisk createBookDisk() => _IoBookDisk();
