// 📁 مسیر: lib/core/book/book_disk_api.dart
//
// رابطِ ذخیره‌سازیِ دائمیِ «صفحه‌های ترجمه‌شده‌ی کتاب» روی دیسک.
// پیاده‌سازیِ موبایل: book_disk_io.dart — وب: book_disk_stub.dart (بدونِ ذخیره).
import 'dart:typed_data';

abstract class BookDisk {
  /// خواندنِ یک فایل از پوشه‌ی سند؛ اگر نبود null.
  Future<Uint8List?> readBytes(String doc, String name);

  /// نوشتنِ اتمی (اول فایلِ موقت، بعد rename) — اگر وسط کار برنامه کشته شد، فایلِ نیمه‌کاره نمی‌ماند.
  Future<void> writeBytes(String doc, String name, Uint8List data);

  /// حذفِ همه‌ی فایل‌های یک سند.
  Future<void> deleteDoc(String doc);

  /// سقفِ حجمِ کل: قدیمی‌ترین سندها پاک می‌شوند تا زیرِ [maxBytes] برسد
  /// (سندِ [keepDoc] هیچ‌وقت پاک نمی‌شود).
  Future<void> trim({required int maxBytes, String? keepDoc});

  /// پاک‌کردنِ فایل‌های موقتِ OCR که از اجراهای قبلی (مثلاً بعد از ANR/کرش) مانده‌اند.
  Future<void> cleanTemp();
}
