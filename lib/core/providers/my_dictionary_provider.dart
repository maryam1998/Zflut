import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/dictionary_topics.dart';
import '../constants/vocab_topics.dart';
import '../models/daily_word.dart';
import '../models/filter_state.dart';
import '../storage/local_storage.dart';
import '../translate/translation_service.dart' show textMatchesScript;
import 'conversation_provider.dart';
import 'language_selection_provider.dart';
import 'reader_providers.dart';
import 'word_sources_provider.dart';
import 'words_filter_provider.dart';

// ═══════════════════════════════════════════════════════════════════
// «دیکشنری من» (تبِ لغات) — مثل Hope:
//   • هر لغت/عبارتِ انگلیسی که کاربر با «ذخیره برای داستان بعدی» نشان
//     می‌کند، هم در «لغات ذخیره‌شده» می‌ماند و هم این‌جا (تبِ دیکشنری من)
//     با برچسب «شخصی» دیده می‌شود.
//   • ✕ روی کارتِ شخصی فقط از همین تب پنهانش می‌کند؛ از «لغات ذخیره‌شده»
//     پاک نمی‌شود. اگر کاربر دوباره همان لغت را ذخیره کند، خودکار برمی‌گردد.
// ═══════════════════════════════════════════════════════════════════

const String _kHiddenKey = 'zflut-words-tab-hidden-v1';

/// کلیدِ نرمال‌شده ← لحظه‌ی پنهان‌کردن.
/// (لغتِ ذخیره‌شده فقط وقتی پنهان است که savedAt اش قدیمی‌تر از لحظه‌ی
/// پنهان‌کردن باشد؛ ذخیره‌ی دوباره = savedAt تازه ⇒ خودکار از پنهان درمی‌آید.)
class WordsTabHiddenNotifier extends StateNotifier<Map<String, DateTime>> {
  final LocalStorage _storage;

  WordsTabHiddenNotifier(this._storage) : super(_read(_storage));

  static Map<String, DateTime> _read(LocalStorage s) {
    final raw = s.readJson(_kHiddenKey)['items'];
    final out = <String, DateTime>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        final t = DateTime.tryParse(v.toString());
        if (t != null) out[k.toString()] = t;
      });
    }
    return out;
  }

  void hide(String word) {
    final k = normWord(word);
    if (k.isEmpty) return;
    final next = {...state, k: DateTime.now()};
    state = next;
    unawaited(_storage.writeJson(_kHiddenKey, {
      'items': next.map((key, v) => MapEntry(key, v.toIso8601String())),
    }));
  }
}

final wordsTabHiddenProvider =
    StateNotifierProvider<WordsTabHiddenNotifier, Map<String, DateTime>>(
  (ref) => WordsTabHiddenNotifier(ref.read(localStorageProvider)),
);

const List<String> _levels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

String _cleanToken(String s) => s
    .toLowerCase()
    .replaceAll(_edgePunct, '')
    .trim();

final RegExp _edgePunct = RegExp(
    r'''^[«»"'.,!?;:()\u060C\u061B\u061F]+|[«»"'.,!?;:()\u060C\u061B\u061F]+$''');

/// ایندکسِ سطحِ لغاتِ شناخته‌شده (لغات روزمره + اسلنگ + Vocabulary in Use).
final _levelIndexProvider = Provider<Map<String, String>>((ref) {
  final lists = <List<DailyWord>>[
    ref.watch(allDailyWordsProvider),
    ref.watch(slangWordsProvider).valueOrNull ?? const <DailyWord>[],
    ref.watch(vocabInUseWordsProvider).valueOrNull ?? const <DailyWord>[],
  ];
  final idx = <String, String>{};
  for (final l in lists) {
    for (final w in l) {
      final k = _cleanToken(w.en);
      if (k.isNotEmpty) idx.putIfAbsent(k, () => w.level);
    }
  }
  return idx;
});

/// کلیدِ لغاتِ روزمره (برای این‌که لغتِ تکراری دوباره اضافه نشود).
final _dailyKeysProvider = Provider<Set<String>>((ref) {
  return ref
      .watch(allDailyWordsProvider)
      .map((w) => normWord(w.en))
      .toSet();
});

String _estimateLevel(String text, Map<String, String> idx) {
  final k = _cleanToken(text);
  final direct = idx[k];
  if (direct != null) return direct;
  final toks =
      k.split(RegExp(r'\s+')).map(_cleanToken).where((t) => t.isNotEmpty);
  var best = -1;
  for (final t in toks) {
    final lv = idx[t];
    if (lv == null) continue;
    final r = _levels.indexOf(lv);
    if (r > best) best = r;
  }
  return best >= 0 ? _levels[best] : '';
}

/// لغات/عبارات شخصیِ دیکشنری من (جدیدترین اول)، بدون موارد پنهان‌شده.
final myDictionaryWordsProvider = Provider<List<DailyWord>>((ref) {
  final saved = ref.watch(savedWordsProvider);
  if (saved.isEmpty) return const <DailyWord>[];
  final hidden = ref.watch(wordsTabHiddenProvider);
  final existing = ref.watch(_dailyKeysProvider);
  final idx = ref.watch(_levelIndexProvider);
  final native = ref.watch(languageSelectionProvider.select((s) => s.native));

  final sorted = [...saved]..sort((a, b) => b.savedAt.compareTo(a.savedAt));
  final seen = <String>{};
  final out = <DailyWord>[];
  for (final e in sorted) {
    final k = normWord(e.word);
    if (k.isEmpty) continue;
    final isEn = e.langCode == 'en';
    // لغاتِ روزمره‌ی انگلیسی دوباره اضافه نمی‌شوند؛ زبان‌های دیگر محدودیتی ندارند.
    if ((isEn && existing.contains(k)) || !seen.add('${e.langCode}::$k')) {
      continue;
    }
    final hiddenAt = hidden[k];
    if (hiddenAt != null && !e.savedAt.isAfter(hiddenAt)) continue;
    final meaning = e.meaning.trim();
    out.add(DailyWord(
      id: -1,
      key: isEn ? 'saved:$k' : 'saved:${e.langCode}:$k',
      lang: e.langCode,
      isPersonal: true,
      level: isEn ? _estimateLevel(e.word, idx) : '',
      pos: '',
      en: e.word,
      fa: '',
      translations: () {
        // 🌐 ترجمه‌ی همه‌ی زبان‌های انتخاب‌شده (نه فقط اولی)
        final tr = <String, String>{};
        e.translations.forEach((k, v) {
          final t = v.trim();
          if (k != e.langCode && t.isNotEmpty && textMatchesScript(t, k)) {
            tr[k] = t;
          }
        });
        if (meaning.isNotEmpty &&
            native != e.langCode &&
            !tr.containsKey(native) &&
            textMatchesScript(meaning, native)) {
          tr[native] = meaning;
        }
        return tr;
      }(),
    ));
  }
  return out;
});

bool _matches(DailyWord w, WordsFilterState f) {
  // لغتِ شخصیِ بی‌سطح با فیلترِ سطح پنهان نشود (تا بلافاصله بعد از ذخیره دیده شود)
  if (!(w.isPersonal && w.level.isEmpty) && !f.matchesLevel(w.level)) {
    return false;
  }
  final q = f.query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return w.en.toLowerCase().contains(q) ||
      w.fa.contains(q) ||
      w.translations.values.any((t) => t.toLowerCase().contains(q));
}

// ═══════════════════════════════════════════════════════════════════
// دسته‌بندیِ موضوعیِ تبِ «دیکشنری من» (غذا، سفر، سلامت، ...) — خودکار برای همه‌ی
// موارد، حتی لغات/عبارت‌هایی که خودِ کاربر اضافه می‌کند. لغت، عبارت، اصطلاح و
// اسلنگ همه داخلِ همان موضوعِ مربوط به خودشان قرار می‌گیرند.
// ═══════════════════════════════════════════════════════════════════

/// موضوع‌های انتخاب‌شده — خالی = همه؛ وگرنه هر ترکیبی از موضوع‌ها
final wordsTopicProvider = StateProvider<Set<String>>((ref) => const <String>{});

// ───────────── موضوع‌یابی ─────────────

/// ایندکسِ «لغت ← موضوع» از روی Vocabulary in Use و Slang
/// (دسته‌ی هر لغت در فایل‌های داده).
final _topicIndexProvider = Provider<Map<String, String>>((ref) {
  final idx = <String, String>{};
  final vocab =
      ref.watch(vocabInUseWordsProvider).valueOrNull ?? const <DailyWord>[];
  for (final w in vocab) {
    final vt = vocabTopicOfCategory(w.category);
    final t = vt == null ? null : kVocabToDictTopic[vt.key];
    if (t == null) continue;
    final k = _cleanToken(w.en);
    if (k.isNotEmpty) idx.putIfAbsent(k, () => t);
  }
  final slang =
      ref.watch(slangWordsProvider).valueOrNull ?? const <DailyWord>[];
  for (final w in slang) {
    final t = kSlangToDictTopic[w.category];
    if (t == null) continue;
    final k = _cleanToken(w.en);
    if (k.isNotEmpty) idx.putIfAbsent(k, () => t);
  }
  return idx;
});

String? _keywordTopic(String token) {
  final direct = kDictKeywordTopic[token];
  if (direct != null) return direct;
  // ریشه‌یابیِ ساده: s / es / ies / ed / d / ing / ly
  final cands = <String>[];
  if (token.endsWith('ies') && token.length > 4) {
    cands.add('${token.substring(0, token.length - 3)}y');
  }
  if (token.endsWith('es') && token.length > 3) {
    cands.add(token.substring(0, token.length - 2));
  }
  if (token.endsWith('s') && token.length > 3) {
    cands.add(token.substring(0, token.length - 1));
  }
  if (token.endsWith('ed') && token.length > 4) {
    cands.add(token.substring(0, token.length - 2));
    cands.add(token.substring(0, token.length - 1));
  }
  if (token.endsWith('ing') && token.length > 5) {
    final b = token.substring(0, token.length - 3);
    cands.add(b);
    cands.add('${b}e');
  }
  if (token.endsWith('ly') && token.length > 4) {
    cands.add(token.substring(0, token.length - 2));
  }
  for (final c in cands) {
    final t = kDictKeywordTopic[c];
    if (t != null) return t;
  }
  return null;
}

/// موضوعِ یک مورد (کلیدِ kDictTopics).
String dictTopicOf(DailyWord w, Map<String, String> idx) {
  // 💎 لغاتِ روزمره موضوعشان از قبل (هنگامِ ساختِ داده) حساب شده؛ این‌طوری شمارِ هر موضوع
  // برای کاربرِ رایگان و Pro یکی است (کاربرِ رایگان فقط بخشی از لغات را دارد).
  if (!w.isPersonal && w.category.isNotEmpty) return w.category;
  final k = _cleanToken(w.en);
  final isExpr = w.pos == 'idiom' || w.pos == 'slang';
  // ۱) واژه‌نامه‌ی دستی: عبارت‌ها/اصطلاح‌ها بر اساسِ کاربردشان، لغت‌ها بر
  //    اساسِ معنی
  final manual = kDictPhraseTopic[k] ?? (isExpr ? null : kDictKeywordTopic[k]);
  if (manual != null) return manual;
  // ۲) دسته‌ی همان لغت/عبارت در Vocabulary in Use / Slang
  final fromIdx = idx[k];
  if (fromIdx != null) return fromIdx;
  if (isExpr) return 'talk';
  // ۳) تطبیقِ کلمه‌به‌کلمه
  final toks = k
      .split(RegExp(r'\s+'))
      .map(_cleanToken)
      .where((t) => t.length > 2)
      .toList();
  final votes = <String, int>{};
  for (final t in toks) {
    final tp = _keywordTopic(t) ?? idx[t];
    if (tp != null) votes[tp] = (votes[tp] ?? 0) + 1;
  }
  if (votes.isNotEmpty) {
    String best = votes.keys.first;
    for (final e in votes.entries) {
      if (e.value > votes[best]!) best = e.key;
    }
    return best;
  }
  return kTopicOther;
}

/// لیستِ تبِ «دیکشنری من» (قبل از فیلترِ موضوع): اول لغاتِ شخصی، بعد روزمره.
final wordsTabBaseItemsProvider = Provider<List<DailyWord>>((ref) {
  final daily = ref.watch(filteredDailyWordsProvider);
  final personal = ref.watch(myDictionaryWordsProvider);
  if (personal.isEmpty) return daily;
  final f = ref.watch(wordsFilterProvider);
  final mine = personal.where((w) => _matches(w, f)).toList(growable: false);
  if (mine.isEmpty) return daily;
  return [...mine, ...daily];
});

/// موضوعِ هر مورد (sid ← کلیدِ موضوع) برای لیستِ پایه
final wordsTabTopicsProvider = Provider<Map<String, String>>((ref) {
  final base = ref.watch(wordsTabBaseItemsProvider);
  final idx = ref.watch(_topicIndexProvider);
  return {for (final w in base) w.sid: dictTopicOf(w, idx)};
});

/// لیستِ نهایی تبِ «دیکشنری من» بعد از فیلترِ موضوع.
final wordsTabItemsProvider = Provider<List<DailyWord>>((ref) {
  final base = ref.watch(wordsTabBaseItemsProvider);
  final topic = ref.watch(wordsTopicProvider);
  if (topic.isEmpty) return base;
  final topics = ref.watch(wordsTabTopicsProvider);
  return base
      .where((w) => topic.contains(topics[w.sid] ?? kTopicOther))
      .toList(growable: false);
});
