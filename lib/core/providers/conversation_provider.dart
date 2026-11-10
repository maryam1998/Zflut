import '../data/paid_content.dart';
import '../usage/pro_status.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/conversation_repository.dart';
import '../data/daily_words_repository.dart';
import '../models/conversation.dart';
import '../models/daily_word.dart';

// ═══════════════════════════════════════════════════════════════════
// Conversation
// ═══════════════════════════════════════════════════════════════════
final conversationRepoProvider = Provider<ConversationRepository>((ref) {
  return ConversationRepository.instance;
});

final conversationLoaderProvider = FutureProvider<void>((ref) async {
  // 💎 با Pro شدن / به‌روزشدنِ محتوای پولی دوباره بارگذاری می‌شود
  ref.watch(isProProvider);
  ref.watch(paidRevisionProvider);
  await ref.watch(conversationRepoProvider).load(force: true);
});

final allTopicsProvider = Provider<List<ConversationTopic>>((ref) {
  ref.watch(conversationLoaderProvider);
  return ref.watch(conversationRepoProvider).all;
});

/// 📚 متنِ کاملِ یک موضوع (لود تنبل) — با نامِ موضوع کلید می‌خورد.
/// با Pro شدن/به‌روزشدنِ محتوا دوباره ساخته می‌شود.
final conversationTopicProvider =
    FutureProvider.family<ConversationTopic?, String>((ref, name) async {
  ref.watch(isProProvider);
  ref.watch(paidRevisionProvider);
  await ref.watch(conversationLoaderProvider.future);
  final repo = ref.watch(conversationRepoProvider);
  final stub = repo.all.where((t) => t.topic == name).firstOrNull;
  if (stub == null) return null;
  return repo.loadTopic(stub);
});

// ═══════════════════════════════════════════════════════════════════
// Daily Words
// ═══════════════════════════════════════════════════════════════════
final dailyWordsRepoProvider = Provider<DailyWordsRepository>((ref) {
  return DailyWordsRepository.instance;
});

final dailyWordsLoaderProvider = FutureProvider<void>((ref) async {
  ref.watch(isProProvider);
  ref.watch(paidRevisionProvider);
  await ref.watch(dailyWordsRepoProvider).load(force: true);
});

final allDailyWordsProvider = Provider<List<DailyWord>>((ref) {
  ref.watch(dailyWordsLoaderProvider);
  return ref.watch(dailyWordsRepoProvider).words;
});
