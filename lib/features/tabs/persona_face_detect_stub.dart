import 'dart:typed_data';

/// وب: تشخیصِ لب پشتیبانی نمی‌شود → null (همان آواتارِ ساده می‌ماند).
Future<({String file, Map<String, double> face})?> detectPersonaFace(
        Uint8List original) async =>
    null;

Future<Uint8List?> loadPersonaPhotoBytes(String file) async => null;

Future<void> deletePersonaPhoto(String file) async {}
