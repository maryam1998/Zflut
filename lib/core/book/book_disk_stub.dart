// وب: ذخیره‌ی دیسکی نداریم؛ موتور فقط از حافظه (LRU) استفاده می‌کند.
import 'dart:typed_data';

import 'book_disk_api.dart';

class _NoBookDisk implements BookDisk {
  @override
  Future<Uint8List?> readBytes(String doc, String name) async => null;
  @override
  Future<void> writeBytes(String doc, String name, Uint8List data) async {}
  @override
  Future<void> deleteDoc(String doc) async {}
  @override
  Future<void> trim({required int maxBytes, String? keepDoc}) async {}
  @override
  Future<void> cleanTemp() async {}
}

BookDisk createBookDisk() => _NoBookDisk();
