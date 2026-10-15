import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// پل به TTS نیتیو اندروید (Piper/Sherpa) از طریق MethodChannel.
/// روی وب این کانال کار نمی‌کنه — همیشه false برمی‌گردونه.
///
/// مثل نسخه‌ی Hope (nativeTtsFast.js)، هر خوانش یک `id` یکتا داره تا
/// رویداد «تمام شد»ِ یک خوانشِ قدیمی (مثلاً بعد از stop/pause) به‌اشتباه
/// خوانشِ جدید رو تمام‌شده حساب نکنه.
class NativeTtsBridge {
  static const _channel = MethodChannel('lingolearn/tts');

  static bool get isAvailable {
    if (kIsWeb) return false;
    return true;
  }

  /// چک کن بسته‌ی این زبان نصب شده یا نه
  static Future<bool> isModelReady(String lang) async {
    if (!isAvailable) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('checkModel', {'lang': lang});
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// TTS نیتیو (Piper)
  static Future<bool> speak(
    String text,
    String lang,
    double rate, {
    String? id,
  }) async {
    if (!isAvailable) return false;
    try {
      await _channel.invokeMethod('speak', {
        'text': text,
        'lang': lang,
        'speed': rate,
        if (id != null) 'id': id,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// TTS خود گوشی (Android System TTS)
  static Future<bool> speakSystem(
    String text,
    String lang,
    double rate, {
    String? id,
  }) async {
    if (!isAvailable) return false;
    try {
      await _channel.invokeMethod('speakSystem', {
        'text': text,
        'lang': lang,
        'speed': rate,
        if (id != null) 'id': id,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// توقف
  static Future<void> stop() async {
    if (!isAvailable) return;
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
  }

  /// منتظر پایان صحبت. handler پارامترهای (id, ok) می‌گیره؛
  /// اگر سمت نیتیو id نفرسته، id == null و ok == true میاد.
  static void onDone(void Function(String? id, bool ok) handler) {
    if (!isAvailable) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'ttsDone') {
        String? id;
        var ok = true;
        final args = call.arguments;
        if (args is Map) {
          id = args['id']?.toString();
          ok = args['ok'] != false;
        }
        handler(id, ok);
      }
      return null;
    });
  }
}
