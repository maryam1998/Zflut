import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// پل به TTS نیتیو اندروید (Piper/Sherpa) از طریق MethodChannel.
/// روی وب این کانال کار نمی‌کنه — همیشه false برمی‌گردونه.
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
  static Future<bool> speak(String text, String lang, double rate) async {
    if (!isAvailable) return false;
    try {
      await _channel.invokeMethod('speak', {
        'text': text,
        'lang': lang,
        'speed': rate,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// TTS خود گوشی (Android System TTS)
  static Future<bool> speakSystem(String text, String lang, double rate) async {
    if (!isAvailable) return false;
    try {
      await _channel.invokeMethod('speakSystem', {
        'text': text,
        'lang': lang,
        'speed': rate,
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

  /// منتظر پایان صحبت (به رویداد می‌گوشه)
  static void onDone(VoidCallback handler) {
    if (!isAvailable) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'ttsDone') handler();
      return null;
    });
  }
}
