import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ⚠️ مسیرها را با ساختار پروژه خودتان چک کنید
import '../../../core/models/saved_word.dart';
import '../../../core/models/grammar_note.dart';
import '../../../core/providers/reader_providers.dart';
import '../../../core/providers/translation_provider.dart';
import '../../../core/providers/ai_settings_provider.dart';
import '../../../core/theme/app_theme_colors.dart';

class SelectionPopup extends ConsumerStatefulWidget {
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
  ConsumerState<SelectionPopup> createState() => _SelectionPopupState();
}

class _SelectionPopupState extends ConsumerState<SelectionPopup> {
  String? _meaning;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _loadMeaning();
  }

  Future<void> _loadMeaning() async {
    try {
      final service = ref.read(translationServiceProvider);

      // ۱) اول از کش بخوان
      final cached = service.peekCached(
        widget.word,
        widget.langCode,
        widget.nativeLang,
      );
      if (cached != null && cached.trim().isNotEmpty) {
        if (mounted) {
          setState(() {
            _meaning = cached;
            _loading = false;
          });
        }
        return;
      }

      // ۲) از سرویس ترجمه بگیر
      final ai = ref.read(aiSettingsProvider);
      final result = await service.translate(
        text: widget.word,
        targetLang: widget.nativeLang,
        sourceLang: widget.langCode,
        aiSettings: ai,
      );

      if (mounted) {
        setState(() {
          _meaning = (result == null || result.trim().isEmpty)
              ? 'معنی پیدا نشد'
              : result.trim();
          _loading = false;
          _failed = (result == null || result.trim().isEmpty);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _meaning = 'خطا در دریافت معنی';
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final savedWords = ref.watch(savedWordsProvider);
    final isSaved = savedWords.any(
      (w) => w.word == widget.word && w.langCode == widget.langCode,
    );

    // محاسبه‌ی ابعاد صفحه برای جلوگیری از بیرون‌زدگی کادر
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    const popupWidth = 260.0;
    const popupHeight = 220.0;

    double left = widget.position.dx - popupWidth / 2;
    if (left < 8) left = 8;
    if (left + popupWidth > screenWidth - 8) {
      left = screenWidth - popupWidth - 8;
    }

    double top = widget.position.dy - popupHeight - 12;
    if (top < 8) top = widget.position.dy + 24;
    if (top + popupHeight > screenHeight - 8) {
      top = screenHeight - popupHeight - 8;
    }

    return Positioned(
      left: left,
      top: top,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: popupWidth,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.ink,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ردیف اول: کلمه + آیکون پخش صدا
              Row(
                children: [
                  Icon(Icons.volume_up, color: c.gold, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.word,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // ترجمه
              if (_loading)
                Row(
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.6,
                        color: c.gold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'در حال یافتن معنی...',
                      style: TextStyle(
                        color: c.paper.withOpacity(0.85),
                        fontSize: 12,
                      ),
                    ),
                  ],
                )
              else
                Text(
                  _meaning ?? '...',
                  style: TextStyle(
                    color: _failed
                        ? const Color(0xFFEF9A9A)
                        : c.paper.withOpacity(0.92),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),

              const SizedBox(height: 12),
              const Divider(color: Colors.white24, height: 1),
              const SizedBox(height: 8),

              // دکمه ۱: ذخیره برای داستان بعدی
              _PopupButton(
                icon: isSaved ? Icons.bookmark : Icons.bookmark_border,
                label: isSaved
                    ? 'ذخیره شد برای داستان بعدی'
                    : 'ذخیره برای داستان بعدی',
                isActive: isSaved,
                onTap: () {
                  ref.read(savedWordsProvider.notifier).toggleSave(
                        SavedWord(
                          word: widget.word,
                          langCode: widget.langCode,
                          meaning: _meaning ?? '',
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
                          word: widget.word,
                          sentence: widget.sentence,
                          markdown:
                              '## ${widget.word}\n\n**معنی:** ${_meaning ?? ''}\n\n**جمله:** ${widget.sentence}',
                          langCode: widget.langCode,
                          savedAt: DateTime.now(),
                        ),
                      );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('به گرامر اضافه شد'),
                      duration: Duration(seconds: 1),
                    ),
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
                          word: widget.word,
                          langCode: widget.langCode,
                          meaning: _meaning ?? '',
                          savedAt: DateTime.now(),
                        ),
                      );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('به لایتنر اضافه شد'),
                      duration: Duration(seconds: 1),
                    ),
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
