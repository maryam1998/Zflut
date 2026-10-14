import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/ui/login_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/tabs/conversations_tab.dart';
import '../../features/tabs/favorites_tab.dart';
import '../../features/tabs/grammar_tab.dart';
import '../../features/tabs/review_tab.dart';
import '../../features/tabs/saved_tab.dart';
import '../../features/tabs/slang_tab.dart';
import '../../features/tabs/speaking_tab.dart';
import '../../features/tabs/story_tab.dart';
import '../../features/tabs/vocab_in_use_tab.dart';
import '../../features/tabs/words_tab.dart';

/// روتر — معادلِ تصمیم App.jsx بین LoginScreen و PhrasebookMain.
/// redirect بر اساس سشن Supabase.
final appRouterProvider = Provider<GoRouter>((ref) {
  // GoRouter فقط یک‌بار ساخته می‌شود؛ تغییر سشن از طریق refreshListenable
  // redirect را دوباره اجرا می‌کند (قبلاً با هر تغییر، روتر از نو ساخته می‌شد).
  final refresh = ValueNotifier<int>(0);
  ref.listen(authStateProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/story',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = ref.read(authRepositoryProvider).currentSession != null;
      final goingToLogin = state.matchedLocation == '/login';
      if (!loggedIn) return goingToLogin ? null : '/login';
      if (goingToLogin) return '/story';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/conversations', builder: (_, __) => const ConversationsTab()),
          GoRoute(path: '/story',         builder: (_, __) => const StoryTab()),
          GoRoute(path: '/saved',         builder: (_, __) => const SavedTab()),
          GoRoute(path: '/grammar',       builder: (_, __) => const GrammarTab()),
          GoRoute(path: '/speaking',      builder: (_, __) => const SpeakingTab()),
          GoRoute(path: '/words',         builder: (_, __) => const WordsTab()),
          GoRoute(path: '/vocab-in-use',  builder: (_, __) => const VocabInUseTab()),
          GoRoute(path: '/slang',         builder: (_, __) => const SlangTab()),
          GoRoute(path: '/favorites',     builder: (_, __) => const FavoritesTab()),
          GoRoute(path: '/review',        builder: (_, __) => const ReviewTab()),
        ],
      ),
    ],
    errorBuilder: (_, state) => Scaffold(
      body: Center(child: Text('Route not found: ${state.uri}')),
    ),
  );
});
