import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ═══════════════════════════════════════════════════════════════════
// 💎 ایندکسِ شمارِ لغات (assets/data/words_index.json)
//
// فایلِ لغاتِ داخلِ اپ فقط ده لغتِ رایگانِ هر دسته را دارد؛ ولی کاربرِ رایگان باید
// ببیند هر دسته «در کل» چند لغت دارد (و چندتایش قفل است). این ایندکس فقط «شمارش» است
// (به‌تفکیکِ سطح) و خودِ لغات در آن نیست. با scripts/build-paid-content.mjs ساخته می‌شود.
// ═══════════════════════════════════════════════════════════════════

const List<String> kIndexLevels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

@immutable
class _Counts {
  /// کلِ لغات به‌تفکیکِ سطح (A1..C2)
  final List<int> t;

  /// لغاتِ رایگان به‌تفکیکِ سطح
  final List<int> f;
  const _Counts(this.t, this.f);

  factory _Counts.fromJson(Object? j) {
    List<int> l(Object? x) => x is List
        ? [for (final e in x) (e as num).toInt()]
        : List<int>.filled(kIndexLevels.length, 0);
    final m = j is Map ? j : const {};
    return _Counts(l(m['t']), l(m['f']));
  }
}

/// وضعیتِ هر سطح (A1..C2) در یک محدوده‌ی لغات (لیست / موضوع / دسته) برای کاربرِ رایگان
@immutable
class LevelAvailability {
  /// سطح‌هایی که لغت دارند ولی هیچ‌کدام رایگان نیست (قفل، ولی قابلِ انتخاب)
  final Set<String> locked;

  /// سطح‌هایی که در این محدوده اصلاً لغتی ندارند (کم‌رنگ و غیرقابلِ انتخاب)
  final Set<String> empty;
  const LevelAvailability(this.locked, this.empty);
}

class WordsIndex {
  final Map<String, Map<String, _Counts>> _groups;
  final Map<String, _Counts> _vocabCats;
  const WordsIndex._(this._groups, this._vocabCats);

  factory WordsIndex.fromJson(Map<String, dynamic> j) {
    Map<String, _Counts> parse(Object? x) {
      if (x is! Map) return const <String, _Counts>{};
      return {for (final e in x.entries) e.key.toString(): _Counts.fromJson(e.value)};
    }

    final groups = <String, Map<String, _Counts>>{};
    for (final list in const ['daily', 'slang', 'vocab']) {
      final l = j[list];
      groups[list] = parse(l is Map ? l['groups'] : null);
    }
    final v = j['vocab'];
    return WordsIndex._(groups, parse(v is Map ? v['cats'] : null));
  }

  Iterable<_Counts> _pick(String list, Set<String> groups, String? category) {
    if (list == 'vocab' && category != null) {
      final c = _vocabCats[category];
      return c == null ? const <_Counts>[] : [c];
    }
    final all = _groups[list] ?? const <String, _Counts>{};
    if (groups.isEmpty) return all.values;
    return [for (final g in groups) if (all[g] != null) all[g]!];
  }

  int _sum(Iterable<_Counts> src, Set<String> levels, {required bool free}) {
    var n = 0;
    for (final c in src) {
      final a = free ? c.f : c.t;
      for (var i = 0; i < kIndexLevels.length && i < a.length; i++) {
        if (levels.isEmpty || levels.contains(kIndexLevels[i])) n += a[i];
      }
    }
    return n;
  }

  /// کلِ لغاتِ یک دسته (یا چند دسته) — [groups] خالی = کلِ لیست
  int total(String list,
          {Set<String> groups = const <String>{},
          String? category,
          Set<String> levels = const <String>{}}) =>
      _sum(_pick(list, groups, category), levels, free: false);

  /// لغاتِ قفل‌شده (کل − رایگان)
  int locked(String list,
      {Set<String> groups = const <String>{},
      String? category,
      Set<String> levels = const <String>{}}) {
    final src = _pick(list, groups, category);
    final n = _sum(src, levels, free: false) - _sum(src, levels, free: true);
    return n < 0 ? 0 : n;
  }

  /// لغاتِ قفل‌شده به‌تفکیکِ سطح (فقط سطح‌هایی که در فیلتر هستند و چیزی قفل دارند)
  Map<String, int> lockedByLevel(String list,
      {Set<String> groups = const <String>{},
      String? category,
      Set<String> levels = const <String>{}}) {
    final out = <String, int>{};
    for (final lv in kIndexLevels) {
      if (levels.isNotEmpty && !levels.contains(lv)) continue;
      final n = locked(list, groups: groups, category: category, levels: {lv});
      if (n > 0) out[lv] = n;
    }
    return out;
  }

  /// وضعیتِ هر سطح در محدوده‌ی [groups]/[category] — برای چیپ‌های سطح:
  /// «قفل» = لغت دارد ولی هیچ‌کدام رایگان نیست · «خالی» = اصلاً لغتی ندارد.
  LevelAvailability availability(String list,
      {Set<String> groups = const <String>{}, String? category}) {
    final src = _pick(list, groups, category).toList();
    final locked = <String>{};
    final empty = <String>{};
    for (var i = 0; i < kIndexLevels.length; i++) {
      var t = 0, f = 0;
      for (final c in src) {
        if (i < c.t.length) t += c.t[i];
        if (i < c.f.length) f += c.f[i];
      }
      if (t == 0) {
        empty.add(kIndexLevels[i]);
      } else if (f == 0) {
        locked.add(kIndexLevels[i]);
      }
    }
    return LevelAvailability(locked, empty);
  }

  /// لغاتِ قفل‌شده به‌تفکیکِ گروه (موضوع/دسته) برای فیلترِ سطحِ فعلی
  Map<String, int> lockedByGroup(String list,
      {Set<String> groups = const <String>{},
      Set<String> levels = const <String>{}}) {
    final all = _groups[list] ?? const <String, _Counts>{};
    final out = <String, int>{};
    for (final e in all.entries) {
      if (groups.isNotEmpty && !groups.contains(e.key)) continue;
      final n = locked(list, groups: {e.key}, levels: levels);
      if (n > 0) out[e.key] = n;
    }
    return out;
  }
}

Future<WordsIndex?> _load() async {
  try {
    final raw = await rootBundle.loadString('assets/data/words_index.json');
    return WordsIndex.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } catch (e) {
    debugPrint('WordsIndex: $e');
    return null;
  }
}

/// فقط یک‌بار خوانده می‌شود (فایلِ کوچکِ داخلِ اپ).
final wordsIndexProvider = FutureProvider<WordsIndex?>((ref) => _load());
