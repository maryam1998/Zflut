// 📁 مسیر: lib/core/providers/native_sync_provider.dart
//
// هماهنگ‌سازی اپ با بخش اندروید (معادل کدی که در Hope داخل PhrasebookMain.jsx و
// savedStoryHandlers.js بود):
//  • صفِ لغت‌هایی که از پنل شناور ذخیره شده‌اند ← «ذخیره برای داستان» / «گرامر» / «لایتنر»
//  • زیرنویس‌های ذخیره‌شده‌ی یوتیوب ← کتابخانه‌ی داستان‌ها
//  • وضعیت واقعی حباب بعد از برگشت به اپ
//  • فرستادن زبان‌ها به حباب
// روی وب/iOS هیچ کاری نمی‌کند.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/linlearn_bridge.dart';
import '../models/grammar_note.dart';
import '../models/saved_word.dart';
import '../native/native_bridge.dart';
import 'app_prefs_provider.dart';
import 'language_selection_provider.dart';
import 'linlearn_provider.dart';
import 'reader_providers.dart';
import 'story_library_provider.dart';

class NativeSync with WidgetsBindingObserver {
  final Ref _ref;
  StreamSubscription<Map<String, dynamic>>? _sub;
  bool _busy = false;

  NativeSync(this._ref) {
    if (!NativeBridge.instance.isSupported) return;
    WidgetsBinding.instance.addObserver(this);
    _sub = NativeBridge.instance
        .on('wordQueued')
        .listen((_) => importAll(), onError: (Object _) {});
    // بعد از اولین فریم (تا پروایدرها آماده باشند)
    Future<void>.delayed(const Duration(milliseconds: 600), importAll);
  }

  void dispose() {
    _sub?.cancel();
    if (NativeBridge.instance.isSupported) {
      WidgetsBinding.instance.removeObserver(this);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) importAll();
  }

  Future<void> importAll() async {
    if (_busy) return;
    _busy = true;
    try {
      _pushLangs();
      await _ref.read(bubbleProvider.notifier).syncFromNative();
      await _importWordQueue();
      await _importYtSaved();
    } catch (_) {
      // یک خطا نباید اپ را متوقف کند
    } finally {
      _busy = false;
    }
  }

  void _pushLangs() {
    final prefs = _ref.read(appPrefsProvider);
    final sel = _ref.read(languageSelectionProvider);
    LinLearnBridge.configure(
      uiLang: prefs.uiLang,
      sourceLang: sel.primaryTarget,
      targetLangs: <String>[sel.native],
    );
    NativeBridge.instance.setUiLang(lang: prefs.uiLang).catchError(
        (Object _) => <String, dynamic>{});
  }

  // ───────────── صفِ لغت‌های حباب ─────────────
  Future<void> _importWordQueue() async {
    final res = await NativeBridge.instance.wordQueueList();
    final raw = res['items'];
    if (raw is! List || raw.isEmpty) return;

    final saved = _ref.read(savedWordsProvider.notifier);
    final grammar = _ref.read(grammarNotesProvider.notifier);
    final leitner = _ref.read(leitnerProvider.notifier);
    final acked = <Map<String, dynamic>>[];

    for (final e in raw) {
      if (e is! Map) continue;
      final it = Map<String, dynamic>.from(e);
      acked.add(<String, dynamic>{'key': it['key'], 'rev': it['rev'] ?? 0});

      final word = (it['word'] ?? '').toString().trim();
      if (word.isEmpty) continue;
      final lang = (it['lang'] ?? 'en').toString();
      final meaning = (it['meaning'] ?? '').toString().trim();
      var sentence = (it['sentence'] ?? '').toString().trim();
      if (sentence.isEmpty) sentence = word;
      final now = DateTime.now();

      try {
        switch ((it['action'] ?? '').toString()) {
          case 'story':
            if (!saved.isSaved(word, lang)) {
              saved.toggleSave(SavedWord(
                word: word,
                langCode: lang,
                meaning: meaning,
                savedAt: now,
              ));
            }
            break;
          case 'grammar':
            final md = '## 🧩 $word\n\n'
                '${meaning.isEmpty ? '' : '**🔹 معنی:** $meaning\n\n'}'
                '**جمله:** $sentence';
            grammar.addNote(GrammarNote(
              id: now.microsecondsSinceEpoch.toString(),
              word: word,
              sentence: sentence,
              markdown: md,
              langCode: lang,
              savedAt: now,
            ));
            break;
          case 'leitner':
            leitner.addToLeitner(SavedWord(
              word: word,
              langCode: lang,
              meaning: meaning,
              savedAt: now,
            ));
            break;
        }
      } catch (_) {
        // یک ردیفِ خراب نباید بقیه را متوقف کند
      }
    }

    if (acked.isNotEmpty) {
      try {
        await NativeBridge.instance.wordQueueAck(items: acked);
      } catch (_) {}
    }
  }

  // ───────────── زیرنویس‌های ذخیره‌شده‌ی یوتیوب ─────────────
  Future<void> _importYtSaved() async {
    final res = await NativeBridge.instance.ytSavedList();
    final raw = res['items'];
    if (raw is! List || raw.isEmpty) return;

    final lib = _ref.read(storyLibraryProvider.notifier);
    final acked = <Map<String, dynamic>>[];

    for (final e in raw) {
      if (e is! Map) continue;
      final it = Map<String, dynamic>.from(e);
      final key = (it['key'] ?? '').toString();
      if (key.isEmpty) continue;
      acked.add(<String, dynamic>{'key': key, 'rev': it['rev'] ?? 0});

      final id = 'yt:$key';
      final exists = _ref.read(storyLibraryProvider).any((s) => s.id == id);
      if (exists) continue;

      final live = it['live'] == true;
      final url = (it['url'] ?? '').toString();
      final channel = (it['channel'] ?? '').toString();
      final source = (it['source'] ?? '').toString();
      var title = (it['title'] ?? '').toString().trim();
      if (title.isEmpty) title = live ? 'ترجمه‌ی زنده' : (url.isEmpty ? 'یوتیوب' : url);

      lib.add(SavedStory(
        id: id,
        title: title,
        text: <String>[url, channel, source].where((s) => s.isNotEmpty).join('\n'),
        langCode: (it['lang'] ?? 'en').toString(),
        level: 'B1',
        contentType: 'youtube',
        words: const <String>[],
        createdAt: DateTime.tryParse((it['savedAt'] ?? '').toString()) ??
            DateTime.now(),
      ));
    }

    if (acked.isNotEmpty) {
      try {
        await NativeBridge.instance.ytSavedAck(items: acked);
      } catch (_) {}
    }
  }
}

final nativeSyncProvider = Provider<NativeSync>((ref) {
  final s = NativeSync(ref);
  ref.onDispose(s.dispose);
  return s;
});
