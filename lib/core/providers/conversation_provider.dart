import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/conversation_repository.dart';
import '../models/conversation.dart';

final conversationRepoProvider = Provider<ConversationRepository>((ref) {
  return ConversationRepository.instance;
});

final conversationLoaderProvider = FutureProvider<void>((ref) async {
  await ref.watch(conversationRepoProvider).load();
});

final allTopicsProvider = Provider<List<ConversationTopic>>((ref) {
  final repo = ref.watch(conversationRepoProvider);
  ref.watch(conversationLoaderProvider); // re-run on load
  return repo.all;
});
