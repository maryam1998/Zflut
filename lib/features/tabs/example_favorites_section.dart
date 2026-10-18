import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/example_favorites_provider.dart';
import '../../core/providers/speech_provider.dart';
import '../../core/theme/app_theme_colors.dart';

/// مثال‌های ⭐‌دارِ مثال‌ساز (جمله‌ی اصلی یا ترجمه‌هایشان) — بالای لیست علاقه‌مندی‌ها.
class ExampleFavoritesSection extends ConsumerWidget {
  const ExampleFavoritesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favs = ref.watch(exampleFavoritesProvider);
    if (favs.isEmpty) return const SizedBox.shrink();
    final c = context.appColors;
    final fa = Localizations.localeOf(context).languageCode == 'fa';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            fa ? 'مثال‌ها' : 'Examples',
            style: TextStyle(
                color: c.ink, fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          for (final f in favs)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.cardBorder),
              ),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Row(
                  children: [
                    InkResponse(
                      onTap: () => ref
                          .read(exampleFavoritesProvider.notifier)
                          .toggle(f.text, f.lang, f.word),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.star,
                            size: 18, color: Color(0xFFF5C518)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Directionality(
                        textDirection: (f.lang == 'fa' || f.lang == 'ar')
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                        child: Text(f.text,
                            style: TextStyle(
                                color: c.ink,
                                fontSize: 13.5,
                                height: 1.4,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                    InkResponse(
                      onTap: () => ref
                          .read(speechControllerProvider.notifier)
                          .toggle(f.text, f.lang),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.volume_up_outlined,
                            size: 18, color: c.gold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
