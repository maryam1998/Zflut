import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/favorites_provider.dart';
import '../words/widgets/word_list_view.dart';

/// تبِ علاقه‌مندی‌ها — مثل Hope: فقط چیزهایی که کاربر با ⭐ علامت زده
/// (نه لیستِ تبِ لغات). لغاتِ هر سه تب (لغات / اسلنگ / Vocabulary in Use)
/// اینجا زیرِ عنوانِ «لغات» جمع می‌شوند.
class FavoritesTab extends ConsumerWidget {
  const FavoritesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favIds = ref.watch(wordFavoritesProvider);
    final words = ref.watch(favoritedWordsProvider);

    return WordListView(
      words: words,
      // اگر چیزی علاقه‌مند نشده، پیامِ Hope را نشان بده (نه «داده‌ای بارگذاری نشد»)
      hasAnyData: true,
      heading: 'لغات',
      emptyMessage: favIds.isEmpty
          ? 'هنوز چیزی به علاقه‌مندی‌ها اضافه نکردی. روی ⭐ کنار هر عبارت یا لغت بزن.'
          : 'چیزی پیدا نشد',
    );
  }
}
