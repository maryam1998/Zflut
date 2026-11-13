import '../usage/free_limit.dart';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/worker_auth.dart';
import '../constants/supported_languages.dart';
import '../storage/durable_store.dart';
import '../storage/local_storage.dart';
import '../translate/translation_service.dart';
import '../tts/tts_config.dart';
import 'ai_gateway.dart';

// پورتِ app/words/wordExamples.js — همان کلیدِ وب، پس ساختار یکی است.
const String kWordExamplesKey = 'phrasebook-word-examples-v1';

class WordExample {
  final String id;
  final String text;
  final Map<String, String> translations;

  const WordExample({
    required this.id,
    required this.text,
    this.translations = const {},
  });

  WordExample copyWith({String? text, Map<String, String>? translations}) =>
      WordExample(
        id: id,
        text: text ?? this.text,
        translations: translations ?? this.translations,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'translations': translations,
        'createdAt': DateTime.now().toIso8601String(),
      };

  factory WordExample.fromJson(Map<String, dynamic> j) => WordExample(
        id: (j['id'] ?? '').toString(),
        text: (j['text'] ?? '').toString(),
        translations: {
          for (final e in ((j['translations'] as Map?) ?? const {}).entries)
            e.key.toString(): e.value.toString(),
        },
      );
}

class WordExamplesStore {
  final SharedPreferences _sp;
  WordExamplesStore(this._sp);

  static String _key(String word, String lang) =>
      '$lang::${word.trim().toLowerCase()}';

  Map<String, dynamic> _all() {
    final raw = _sp.getString(kWordExamplesKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final d = jsonDecode(raw);
      return d is Map<String, dynamic> ? d : {};
    } catch (_) {
      return {};
    }
  }

  /// مثال‌ها هم در prefs و هم بلافاصله در نسخه‌ی دائمیِ دستگاه (DurableStore) ذخیره می‌شوند
  /// تا با بستنِ اپ، خروج از حساب یا خالی‌شدنِ prefs از بین نروند.
  Future<void> _write(Map<String, dynamic> all) async {
    await _sp.setString(kWordExamplesKey, jsonEncode(all));
    DurableStore.instance.schedule(_sp);
    await DurableStore.instance.flush();
  }

  List<WordExample> load(String word, String lang) {
    final list = _all()[_key(word, lang)];
    if (list is! List) return [];
    return [
      for (final e in list)
        if (e is Map) WordExample.fromJson(Map<String, dynamic>.from(e)),
    ];
  }

  Future<List<WordExample>> add(String word, String lang, String text) async {
    final all = _all();
    final k = _key(word, lang);
    final cur = load(word, lang);
    final ex = WordExample(
      id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      text: text,
    );
    cur.insert(0, ex);
    all[k] = cur.map((e) => e.toJson()).toList();
    await _write(all);
    return cur;
  }

  Future<List<WordExample>> replace(
      String word, String lang, String id, String text) async {
    final all = _all();
    final k = _key(word, lang);
    final cur = load(word, lang);
    final i = cur.indexWhere((e) => e.id == id);
    if (i == -1) return cur;
    // ترجمه‌های قبلی مالِ متنِ قدیمی بودند
    cur[i] = cur[i].copyWith(text: text, translations: const {});
    all[k] = cur.map((e) => e.toJson()).toList();
    await _write(all);
    return cur;
  }

  Future<void> setTranslation(
      String word, String lang, String id, String target, String text) async {
    if (text.trim().isEmpty) return;
    final all = _all();
    final k = _key(word, lang);
    final cur = load(word, lang);
    final i = cur.indexWhere((e) => e.id == id);
    if (i == -1) return;
    cur[i] = cur[i].copyWith(
        translations: {...cur[i].translations, target: text.trim()});
    all[k] = cur.map((e) => e.toJson()).toList();
    await _write(all);
  }
}

final wordExamplesStoreProvider = Provider<WordExamplesStore>(
    (ref) => WordExamplesStore(ref.watch(sharedPrefsProvider)));

String _langLabel(String code) {
  for (final l in kSupportedLanguages) {
    if (l.code == code) return l.enLabel;
  }
  return englishLangName(code);
}

/// یک جمله‌ی مثالِ واقعی و امروزی — و صریحاً می‌گوییم کدام مثال‌ها قبلاً
/// ساخته شده‌اند تا تکراری نسازد (همان پرامپتِ وب).
Future<String> generateWordExample({
  required TranslationService svc,
  required AiSettings settings,
  required String word,
  required String langCode,
  String meaningNative = '',
  String nativeLabel = '',
  List<String> existing = const [],
  bool reportLimit = true,
}) async {
  final langLabel = _langLabel(langCode);
  final avoid = existing.isEmpty
      ? ''
      : 'Do NOT reuse or closely paraphrase any of these already-used examples for this same word:\n'
          '${[for (var i = 0; i < existing.length; i++) '${i + 1}. ${existing[i]}'].join('\n')}\n\n';
  final meaning = meaningNative.isEmpty
      ? ''
      : ' (its ${nativeLabel.isEmpty ? 'native-language' : nativeLabel} meaning is: "$meaningNative")';
  final prompt =
      'Write exactly ONE natural example sentence in $langLabel that uses the word/expression "$word"$meaning '
      'in a way that reflects REAL, current, everyday usage — the kind of sentence a native speaker might actually say or write today. '
      'Avoid textbook-sounding, generic sentences. '
      'Keep it natural length (roughly 8-20 words), grammatically correct, and appropriate for a language learner to study.\n\n'
      '${avoid}Respond with ONLY the example sentence itself in $langLabel — no quotes, no translation, no numbering, no explanation, nothing else.';

  final out = await aiGenerate(
    svc: svc,
    settings: settings,
    prompt: prompt,
    maxTokens: 200,
    retries: 1,
    timeoutMs: 12000,
    // بیشتر از یک خط یا خیلی بلند = جمله‌ی مثال نیست
    extraCheck: (t) => !t.trim().contains('\n') && t.length <= 300,
    feature: Feature.example, // 💎 سقفِ «کل عمر» نسخه‌ی رایگان
    reportLimit: reportLimit,
  );
  final s = out
      .replaceAll(RegExp(r'''^["'«»“”\s]+|["'«»“”.\s]+$'''), '')
      .trim();
  if (s.isEmpty) throw const AiOutputException('empty');
  return s;
}


// ═══════════════════════════════════════════════════════════════════
// 🧩 مثال‌سازِ مشترک (Pro) + مثال‌های آماده (رایگان)
// ═══════════════════════════════════════════════════════════════════

/// Worker گفت این بخش مخصوص Pro است (کد 403 pro_required).
class ProRequiredException implements Exception {
  const ProRequiredException();
  @override
  String toString() => 'ProRequiredException';
}

class SharedExampleResult {
  /// مثالِ تازه برای این کاربر؛ null یعنی exhausted
  final String? text;

  /// true = همه‌ی مثال‌های ذخیره‌شده‌ی این لغت را دیده و سقفِ ذخیره هم پر است
  final bool exhausted;
  const SharedExampleResult({this.text, this.exhausted = false});
}

final Dio _exDio = Dio();

/// از Worker یک مثالِ «دیده‌نشده» برای این لغت می‌گیرد: اول از کشِ سراسریِ مثال‌های بقیه‌ی کاربران؛
/// فقط اگر کم بود، Worker با AI یکی می‌سازد و برای بقیه هم ذخیره می‌کند. فقط Pro.
Future<SharedExampleResult> fetchSharedWordExample({
  required String word,
  required String langCode,
  required List<String> have,
  String meaningNative = '',
  String nativeLabel = '',
}) async {
  Future<Response<dynamic>> once() => _exDio.post<dynamic>(
        '${TtsConfig.backendUrl}/api/word-example',
        data: {
          'word': word,
          'lang': langCode,
          'have': have,
          if (meaningNative.isNotEmpty) 'meaning': meaningNative,
          if (nativeLabel.isNotEmpty) 'nativeLabel': nativeLabel,
        },
        options: Options(
          headers: WorkerAuth.headers,
          contentType: 'application/json',
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          validateStatus: (_) => true,
        ),
      );
  await WorkerAuth.ensureFresh();
  var res = await once();
  if (res.statusCode == 401) {
    await WorkerAuth.refresh();
    res = await once();
  }
  if (res.statusCode == 403) throw const ProRequiredException();
  final data = res.data;
  if (res.statusCode != 200 || data is! Map) {
    throw Exception('word-example HTTP ${res.statusCode}');
  }
  if (data['exhausted'] == true) return const SharedExampleResult(exhausted: true);
  final t = (data['text'] ?? '').toString().trim();
  if (t.isEmpty) throw const AiOutputException('empty');
  return SharedExampleResult(text: t);
}

Map<String, List<String>>? _seedExamples;

/// مثال‌های آمادهِ لغات رایگان (assets/data/seed_examples.json) — بدونِ اینترنت و بدونِ AI.
/// فقط انگلیسی (لغاتِ اپ انگلیسی‌اند).
Future<List<String>> seedExamplesFor(String word, String langCode) async {
  if (langCode.split('-').first != 'en') return const [];
  if (_seedExamples == null) {
    try {
      final raw = await rootBundle.loadString('assets/data/seed_examples.json');
      final m = jsonDecode(raw) as Map<String, dynamic>;
      _seedExamples = {
        for (final e in m.entries)
          e.key: [for (final x in (e.value as List)) x.toString()],
      };
    } catch (e) {
      debugPrint('seedExamples load failed: $e');
      _seedExamples = {};
    }
  }
  return _seedExamples![word.trim().toLowerCase()] ?? const [];
}
