import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/saved_word.dart';
import '../../../core/models/grammar_note.dart';
import '../../../core/providers/reader_providers.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/translate/translation_service.dart';

class SelectionPopup extends ConsumerWidget {
  final String word;
  final String sentence;
  final String langCode;
  final String nativeLang;
  final Offset position;
  final VoidCallback onDismiss;

  const SelectionPopup({
    super.key,
    required this.word,
    required this.sentence,
    required this.langCode,
    required this.nativeLang,
    required this.position,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final savedWords = ref.watch(savedWordsProvider);
    final isSaved = savedWords.any((w) => w.word == word && w.langCode == langCode);

    // در اینجا می‌توانید از یک Provider برای ترجمه استفاده کنید
    // فعلاً به صورت موقت معنی را از سرویس ترجمه می‌گیریم
    final meaning = ref.watch(translationServiceProvider).peekCached(word, langCode, nativeLang) ?? '...';

    return Positioned(
      left: position.dx,
      top: position.dy - 180, // فاصله از کلمه
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 250,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.ink, // رنگ تیره مشابه عکس
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ردیف اول: کلمه و آیکون پخش صدا
              Row(
                children: [
                  Icon(Icons.volume_up, color: c.gold, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    word,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // ترجمه
              Text(
                meaning,
                style: TextStyle(color: c.paper.withOpacity(0.9), fontSize: 14),
              ),
              const SizedBox(height: 12),
              const Divider(color: Colors.white24, height: 1),
              const SizedBox(height: 8),

              // دکمه ۱: ذخیره برای داستان بعدی
              _PopupButton(
                icon: isSaved ? Icons.bookmark : Icons.bookmark_border,
                label: isSaved ? 'ذخیره شد برای داستان بعدی' : 'ذخیره برای داستان بعدی',
                isActive: isSaved,
                onTap: () {
                  ref.read(savedWordsProvider.notifier).toggleSave(
                    SavedWord(
                      word: word,
                      langCode: langCode,
                      meaning: meaning,
                      savedAt: DateTime.now(),
                    ),
                  );
                },
              ),

              // دکمه ۲: افزودن به گرامر
              _PopupButton(
                icon: Icons.text_fields,
                label: 'افزودن به یادگیری گرامر',
                isActive: false,
                onTap: () {
                  ref.read(grammarNotesProvider.notifier).addNote(
                    GrammarNote(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      word: word,
                      sentence: sentence,
                      markdown: '## $word\n\n**معنی:** $meaning\n\n**جمله:** $sentence',
                      langCode: langCode,
                      savedAt: DateTime.now(),
                    ),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('به گرامر اضافه شد'), duration: Duration(seconds: 1)),
                  );
                },
              ),

              // دکمه ۳: افزودن به لایتنر
              _PopupButton(
                icon: Icons.rotate_left,
                label: 'افزودن به جعبه لایتنر',
                isActive: false,
                onTap: () {
                  ref.read(leitnerProvider.notifier).addToLeitner(
                    SavedWord(
                      word: word,
                      langCode: langCode,
                      meaning: meaning,
                      savedAt: DateTime.now(),
                    ),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('به لایتنر اضافه شد'), duration: Duration(seconds: 1)),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PopupButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _PopupButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isActive ? c.gold : Colors.white70),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isActive ? c.gold : Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
