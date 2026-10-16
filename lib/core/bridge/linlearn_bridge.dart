// 📁 مسیر: lib/core/bridge/linlearn_bridge.dart

import 'package:flutter/services.dart';

/// پل ارتباطی بین Flutter و کدهای Android Native (LinLearn)
/// این کلاس به MainActivity.kt در سمت اندروید وصل می‌شود.
class LinLearnBridge {
  static const _channel = MethodChannel('com.lingolearn.zflut/native');

  // ═══════════════════════════════════════════════════════════
  // Overlay Permission (اجازه‌ی نمایش حباب شناور)
  // ═══════════════════════════════════════════════════════════
  static Future<bool> canDrawOverlays() async =>
      await _channel.invokeMethod<bool>('canDrawOverlays') ?? false;

  static Future<void> requestOverlayPermission() async =>
      _channel.invokeMethod('requestOverlayPermission');

  // ═══════════════════════════════════════════════════════════
  // Bubble (حباب شناور)
  // ═══════════════════════════════════════════════════════════
  /// mode: 'both' | 'magnifier' | 'translator'
  static Future<void> startBubble({String mode = 'both'}) async =>
      _channel.invokeMethod('startBubble', {'mode': mode});

  static Future<void> stopBubble() async =>
      _channel.invokeMethod('stopBubble');

  /// رنگ کادر حباب (#RRGGBB) و حالت نمایش ('both' | 'translation' | 'original').
  /// اگر سمت نیتیو هنوز این متد را پیاده نکرده باشد، بی‌صدا نادیده گرفته می‌شود.
  static Future<void> setBubbleOptions({
    String? panelColor,
    String? displayMode,
  }) async {
    try {
      await _channel.invokeMethod('setBubbleOptions', {
        if (panelColor != null) 'panelColor': panelColor,
        if (displayMode != null) 'displayMode': displayMode,
      });
    } on MissingPluginException {
      // نیتیو هنوز پیاده نشده
    } on PlatformException {
      // نادیده
    }
  }

  // ═══════════════════════════════════════════════════════════
  // Live Translator (ترجمه‌ی زنده‌ی صدا)
  // ═══════════════════════════════════════════════════════════
  static Future<void> startLiveTranslator({
    required String sourceLang,
    required String targetLang,
  }) async =>
      _channel.invokeMethod('startLiveTranslator', {
        'sourceLang': sourceLang,
        'targetLang': targetLang,
      });

  static Future<void> stopLiveTranslator() async =>
      _channel.invokeMethod('stopLiveTranslator');

  // ═══════════════════════════════════════════════════════════
  // Translation (ترجمه‌ی متن)
  // ═══════════════════════════════════════════════════════════
  static Future<String?> translateText({
    required String text,
    required String sourceLang,
    required String targetLang,
  }) async =>
      await _channel.invokeMethod<String>('translateText', {
        'text': text,
        'sourceLang': sourceLang,
        'targetLang': targetLang,
      });

  // ═══════════════════════════════════════════════════════════
  // TTS (خواندن با صدای نیتیو)
  // ═══════════════════════════════════════════════════════════
  static Future<void> speak({
    required String text,
    required String lang,
  }) async =>
      _channel.invokeMethod('speak', {'text': text, 'lang': lang});

  static Future<void> stopSpeaking() async =>
      _channel.invokeMethod('stopSpeaking');

  // ═══════════════════════════════════════════════════════════
  // YouTube (زیرنویس)
  // ═══════════════════════════════════════════════════════════
  static Future<List<Map<String, dynamic>>?> fetchYtCaptions(
      String url) async {
    final raw = await _channel
        .invokeMethod<List<dynamic>>('fetchYtCaptions', {'url': url});
    return raw?.cast<Map<String, dynamic>>();
  }
}
