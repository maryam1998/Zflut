import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/big_story_store.dart';
import '../storage/local_storage.dart';
import '../storage/story_page_store.dart';

const String _kStoriesKey = 'zflut-saved-stories-v1';

/// نسخه‌ی پشتیبانِ سبک (هم در دستگاه و هم در حساب ابری می‌ماند) و فهرست شناسه‌ی
/// داستان‌هایی که کاربر عمداً حذف کرده — تا داستانی بی‌صدا گم نشود.
const String _kStoriesBackupKey = 'zflut-saved-stories-bak-v1';
const String _kStoriesDeletedKey = 'zflut-saved-stories-del-v1';
const int _kBackupFullLimit = 20000;

List<String> _strList(dynamic v) =>
    v is List ? [for (final w in v) w.toString()] : <String>[];

/// داستان‌های بلندتر از این (حرف) بدنه‌شان در BigStoryStore نگه‌داری می‌شود، نه در prefs.
const int _kBigTextChars = 120000;
const int _kPreviewChars = 3000;

/// داستانِ ذخیره‌شده در «کتابخانه‌ی من».
@immutable
class SavedStory {
  final String id;
  final String title;
  final String text;
  final String langCode;
  final String level;
  final String contentType;
  final List<String> words;
  final DateTime createdAt;

  /// ترجمه‌ی هر پاراگراف به زبان‌های انتخابی: کد زبان → لیست ترجمه‌ی پاراگراف‌ها
  final Map<String, List<String>> translations;

  /// یادداشت‌های کاربر درباره‌ی این داستان
  final String notes;

  /// علاقه‌مندی (ستاره)
  final bool favorite;

  /// بدنه (متن + ترجمه‌ها) در BigStoryStore است و در prefs فقط پیش‌نمایش مانده.
  final bool big;

  /// عکسِ صفحه‌های PDF این داستان: نام‌هایی مثل «o3» (اصلیِ صفحه‌ی ۴) و «t3» (ترجمه‌شده‌ی آن).
  /// خودِ عکس‌ها روی دیسک‌اند (StoryPageStore)، نه در prefs.
  final List<String> images;

  const SavedStory({
    required this.id,
    required this.title,
    required this.text,
    required this.langCode,
    required this.level,
    required this.contentType,
    required this.words,
    required this.createdAt,
    this.translations = const {},
    this.notes = '',
    this.favorite = false,
    this.big = false,
    this.images = const [],
  });

  SavedStory copyWith({
    Map<String, List<String>>? translations,
    String? title,
    String? text,
    String? langCode,
    String? notes,
    bool? favorite,
    bool? big,
    List<String>? images,
  }) =>
      SavedStory(
        id: id,
        title: title ?? this.title,
        text: text ?? this.text,
        langCode: langCode ?? this.langCode,
        level: level,
        contentType: contentType,
        words: words,
        createdAt: createdAt,
        translations: translations ?? this.translations,
        notes: notes ?? this.notes,
        favorite: favorite ?? this.favorite,
        big: big ?? this.big,
        images: images ?? this.images,
      );

  /// نسخه‌ی سبک برای prefs: بدونِ متنِ کامل و ترجمه‌ها (آن‌ها در BigStoryStore‌اند).
  Map<String, dynamic> toLeanJson() => {
        'id': id,
        'title': title,
        'text': text.length > _kPreviewChars
            ? text.substring(0, _kPreviewChars)
            : text,
        'langCode': langCode,
        'level': level,
        'contentType': contentType,
        'words': words,
        'createdAt': createdAt.toIso8601String(),
        'translations': const <String, dynamic>{},
        'notes': notes,
        'favorite': favorite,
        'big': true,
        if (images.isNotEmpty) 'images': images,
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'text': text,
        'langCode': langCode,
        'level': level,
        'contentType': contentType,
        'words': words,
        'createdAt': createdAt.toIso8601String(),
        'translations': translations,
        'notes': notes,
        'favorite': favorite,
        if (images.isNotEmpty) 'images': images,
      };

  factory SavedStory.fromJson(Map<String, dynamic> j) => SavedStory(
        id: (j['id'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        text: (j['text'] ?? '').toString(),
        langCode: (j['langCode'] ?? 'en').toString(),
        level: (j['level'] ?? 'B1').toString(),
        contentType: (j['contentType'] ?? 'general').toString(),
        words: _strList(j['words']),
        createdAt:
            DateTime.tryParse((j['createdAt'] ?? '').toString()) ?? DateTime.now(),
        notes: (j['notes'] ?? '').toString(),
        favorite: j['favorite'] == true,
        big: j['big'] == true,
        images: _strList(j['images']),
        translations: {
          if (j['translations'] is Map)
            for (final e in (j['translations'] as Map).entries)
              e.key.toString(): _strList(e.value),
        },
      );
}

class StoryLibraryNotifier extends StateNotifier<List<SavedStory>> {
  final LocalStorage _storage;

  /// شناسه‌ی داستان‌های بلندی که هنوز بدنه‌شان از دیتابیس نیامده (فعلاً فقط پیش‌نمایش دارند).
  /// تا آن موقع بدنه‌ی آن‌ها هرگز بازنویسی نمی‌شود.
  final Set<String> _pending = <String>{};

  /// امضای آخرین بدنه‌ی نوشته‌شده برای هر داستان (برای ننوشتنِ دوباره‌ی بی‌تغییرها).
  final Map<String, int> _bodySig = <String, int>{};

  /// شناسه‌ی داستان‌هایی که کاربر خودش حذف کرده (برای بازیابیِ نسخه‌ی پشتیبان).
  final Set<String> _deleted = <String>{};

  Future<void> _chain = Future<void>.value();

  StoryLibraryNotifier(this._storage) : super(_read(_storage)) {
    for (final s in state) {
      if (s.big) _pending.add(s.id);
    }
    _deleted.addAll(_readDeleted(_storage));
    if (_pending.isNotEmpty) unawaited(_hydrate());
    // داستانی از نسخه‌ی پشتیبان برگشته که در فهرست اصلی نبود → دوباره در اصلی نوشته شود
    final mainIds = _rawItems(_storage, _kStoriesKey)
        .map((e) => (e['id'] ?? '').toString())
        .toSet();
    if (state.any((e) => !mainIds.contains(e.id))) _set(state);
  }

  static List<Map<String, dynamic>> _rawItems(LocalStorage s, String key) {
    final raw = s.readJson(key)['items'];
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if (e is Map) Map<String, dynamic>.from(e),
    ];
  }

  static Set<String> _readDeleted(LocalStorage s) {
    final raw = s.readJson(_kStoriesDeletedKey)['ids'];
    return raw is List ? {for (final e in raw) e.toString()} : <String>{};
  }

  static List<SavedStory> _read(LocalStorage s) {
    final out = <SavedStory>[];
    final seen = <String>{};
    final deleted = _readDeleted(s);
    void take(List<Map<String, dynamic>> raws, {required bool fromBackup}) {
      for (final e in raws) {
        try {
          final st = SavedStory.fromJson(e);
          if (st.id.isNotEmpty && seen.contains(st.id)) continue;
          if (fromBackup && deleted.contains(st.id)) continue;
          seen.add(st.id);
          out.add(st);
        } catch (_) {}
      }
    }

    take(_rawItems(s, _kStoriesKey), fromBackup: false);
    take(_rawItems(s, _kStoriesBackupKey), fromBackup: true);
    return out;
  }

  static int _sigOf(SavedStory s) {
    var n = 0;
    for (final l in s.translations.values) {
      for (final t in l) {
        n += t.length + 1;
      }
    }
    return Object.hash(s.text.length, s.text.hashCode, n, s.translations.length);
  }

  /// بدنه‌ی داستان‌های بلند را بعد از باز شدنِ برنامه (بدونِ مسدودکردنِ شروع) برمی‌گرداند.
  Future<void> _hydrate() async {
    for (final id in _pending.toList()) {
      if (!mounted) return;
      final body = await BigStoryStore.instance.get(id);
      if (!mounted) return;
      if (body == null) continue; // بدنه نیست → پیش‌نمایش می‌ماند و بازنویسی نمی‌شود
      final text = (body['text'] ?? '').toString();
      final tr = body['translations'];
      final translations =
          tr is Map<String, List<String>> ? tr : const <String, List<String>>{};
      state = [
        for (final e in state)
          e.id == id ? e.copyWith(text: text, translations: translations) : e,
      ];
      final cur = state.where((e) => e.id == id);
      if (cur.isNotEmpty) _bodySig[id] = _sigOf(cur.first);
      _pending.remove(id);
    }
  }

  void _set(List<SavedStory> next) {
    _deleted.removeAll(next.map((e) => e.id)); // دوباره ذخیره شد → دیگر «حذف‌شده» نیست
    state = next;
    final snapshot = next;
    _chain = _chain.then((_) => _persist(snapshot)).catchError((_) {});
  }

  /// ذخیره‌ی پیاپی و به‌ترتیب. داستانِ بلند اول در BigStoryStore نوشته می‌شود و
  /// فقط اگر نوشتن موفق بود نسخه‌ی سبک در prefs می‌ماند؛ وگرنه همان روشِ قدیمی (امن).
  Future<void> _persist(List<SavedStory> list) async {
    final items = <Map<String, dynamic>>[];
    for (final s in list) {
      final offload = s.big || s.text.length > _kBigTextChars;
      if (!offload) {
        items.add(s.toJson());
        continue;
      }
      if (_pending.contains(s.id)) {
        items.add(s.toLeanJson()); // بدنه دست‌نخورده می‌ماند
        continue;
      }
      final sig = _sigOf(s);
      var ok = _bodySig[s.id] == sig;
      if (!ok) {
        ok = await BigStoryStore.instance.put(s.id, s.text, s.translations);
        if (ok) _bodySig[s.id] = sig;
      }
      items.add(ok ? s.toLeanJson() : s.toJson());
    }
    await _storage.writeJson(_kStoriesKey, {'items': items});
    // نسخه‌ی پشتیبانِ سبک
    final bak = <Map<String, dynamic>>[
      for (final s in list)
        (s.text.length <= _kBackupFullLimit && !_pending.contains(s.id))
            ? s.toJson()
            : s.toLeanJson(),
    ];
    await _storage.writeJson(_kStoriesBackupKey, {'items': bak});
    await _storage.writeJson(
        _kStoriesDeletedKey, {'ids': _deleted.toList()});
  }

  /// جدیدترین اول.
  void add(SavedStory s) => _set([s, ...state]);

  void update(SavedStory s) =>
      _set([for (final e in state) e.id == s.id ? s : e]);

  void toggleFavorite(String id) => _set([
        for (final e in state)
          e.id == id ? e.copyWith(favorite: !e.favorite) : e,
      ]);

  void remove(String id) {
    _deleted.add(id);
    _pending.remove(id);
    _bodySig.remove(id);
    unawaited(BigStoryStore.instance.delete(id));
    unawaited(StoryPageStore.deleteStory(id));
    _set(state.where((s) => s.id != id).toList());
  }
}

final storyLibraryProvider =
    StateNotifierProvider<StoryLibraryNotifier, List<SavedStory>>(
  (ref) => StoryLibraryNotifier(ref.read(localStorageProvider)),
);

/// لغاتی که از «لغات ذخیره‌شده» با دکمه‌ی «افزودن به داستان‌ساز» فرستاده شده‌اند.
/// داستان‌ساز آن‌ها را برمی‌دارد و provider را دوباره null می‌کند.
@immutable
class StoryDraft {
  final String langCode;
  final List<String> words;
  const StoryDraft(this.langCode, this.words);
}

final storyDraftProvider = StateProvider<StoryDraft?>((ref) => null);
