import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/conversation.dart';
import 'words_index.dart' show kIndexLevels;

// ═══════════════════════════════════════════════════════════════════
// 💎 ایندکسِ شمارشِ مکالمه‌ها (assets/data/conversations_index.json)
//
// نسخه‌ی رایگانِ اپ برای موضوع‌های پولی فقط «نام» دارد (سناریوها خالی‌اند)؛ پس
// بدونِ این ایندکس، با انتخابِ یک سطح (B1, B2, …) همه‌ی آن موضوع‌ها از لیست
// حذف می‌شدند و کاربر «Nothing found» می‌دید.
// این فایل فقط «عدد» است (جمله‌های هر موضوع به‌تفکیکِ سطح) و خودِ جمله‌ها در آن
// نیست. با scripts/build-paid-content.mjs --assets ساخته می‌شود.
// ═══════════════════════════════════════════════════════════════════

@immutable
class ConvCounts {
  /// تعدادِ سناریوهای موضوع
  final int scenarios;

  /// کلِ جمله‌ها به‌تفکیکِ سطح (A1..C2)
  final List<int> t;

  /// جمله‌های رایگان به‌تفکیکِ سطح
  final List<int> f;
  const ConvCounts(this.scenarios, this.t, this.f);

  factory ConvCounts.fromJson(Object? j) {
    List<int> l(Object? x) => x is List
        ? [for (final e in x) (e as num).toInt()]
        : List<int>.filled(kIndexLevels.length, 0);
    final m = j is Map ? j : const {};
    final s = m['s'];
    return ConvCounts(s is num ? s.toInt() : 0, l(m['t']), l(m['f']));
  }

  static int _sum(List<int> a, Set<String> lv) {
    var n = 0;
    for (var i = 0; i < kIndexLevels.length && i < a.length; i++) {
      if (lv.isEmpty || lv.contains(kIndexLevels[i])) n += a[i];
    }
    return n;
  }

  /// کلِ جمله‌ها — [lv] خالی = همه‌ی سطح‌ها
  int total([Set<String> lv = const <String>{}]) => _sum(t, lv);

  /// جمله‌های رایگان
  int free([Set<String> lv = const <String>{}]) => _sum(f, lv);

  /// جمله‌های قفل‌شده (کل − رایگان)
  int locked([Set<String> lv = const <String>{}]) {
    final n = total(lv) - free(lv);
    return n < 0 ? 0 : n;
  }

  /// جمله‌های قفل‌شده‌ی یک سطح
  int lockedAt(String level) => locked(<String>{level});

  /// سطح‌هایی که این موضوع جمله دارد (به ترتیبِ A1..C2)
  List<String> get levels => [
        for (var i = 0; i < kIndexLevels.length && i < t.length; i++)
          if (t[i] > 0) kIndexLevels[i]
      ];
}

/// خلاصه‌ی قفل‌ها برای بنرِ بالای لیستِ موضوع‌ها
@immutable
class ConvLockSummary {
  /// موضوع‌هایی که کارتشان (با فیلترِ فعلی) قفل است
  final int lockedTopics;

  /// کلِ جمله‌های محدوده‌ی فعلی
  final int total;

  /// جمله‌های قفل‌شده
  final int locked;

  /// جمله‌های قفل‌شده به‌تفکیکِ سطح
  final Map<String, int> byLevel;

  const ConvLockSummary({
    required this.lockedTopics,
    required this.total,
    required this.locked,
    required this.byLevel,
  });

  int get free => total - locked;
}

class ConversationsIndex {
  final Map<String, ConvCounts> _topics;
  const ConversationsIndex._(this._topics);

  factory ConversationsIndex.fromJson(Map<String, dynamic> j) {
    final t = j['topics'];
    final out = <String, ConvCounts>{};
    if (t is Map) {
      for (final e in t.entries) {
        out[e.key.toString()] = ConvCounts.fromJson(e.value);
      }
    }
    return ConversationsIndex._(out);
  }

  ConvCounts? of(String topic) => _topics[topic];

  /// خلاصه‌ی قفل‌ها برای فهرستی از موضوع‌ها (مثلاً محدوده‌ی انتخاب‌شده)
  ConvLockSummary summary(
    Iterable<String> topics,
    Set<String> lv, {
    required bool Function(String topic) isLocked,
  }) {
    var total = 0, locked = 0, lockedTopics = 0;
    final byLevel = <String, int>{};
    for (final name in topics) {
      final e = _topics[name];
      if (e == null) continue;
      total += e.total(lv);
      locked += e.locked(lv);
      if (isLocked(name)) lockedTopics++;
      for (final level in kIndexLevels) {
        if (lv.isNotEmpty && !lv.contains(level)) continue;
        final n = e.lockedAt(level);
        if (n > 0) byLevel[level] = (byLevel[level] ?? 0) + n;
      }
    }
    return ConvLockSummary(
      lockedTopics: lockedTopics,
      total: total,
      locked: locked,
      byLevel: byLevel,
    );
  }
}

/// سطح‌هایی که یک موضوعِ «کامل» (نسخه‌ی Pro) جمله دارد.
List<String> conversationLevels(ConversationTopic t) {
  final seen = <String>{};
  for (final s in t.scenarios) {
    for (final l in s.speakerA) {
      seen.add(l.level);
    }
    for (final l in s.speakerB) {
      seen.add(l.level);
    }
  }
  return [for (final lv in kIndexLevels) if (seen.contains(lv)) lv];
}

Future<ConversationsIndex?> _load() async {
  try {
    final raw =
        await rootBundle.loadString('assets/data/conversations_index.json');
    return ConversationsIndex.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } catch (e) {
    debugPrint('ConversationsIndex: $e');
    return null;
  }
}

/// فقط یک‌بار خوانده می‌شود (فایلِ کوچکِ داخلِ اپ).
final conversationsIndexProvider =
    FutureProvider<ConversationsIndex?>((ref) => _load());
