import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/saved_word.dart';
import '../../../core/models/grammar_note.dart';
import '../../../core/providers/reader_providers.dart';
import '../../../core/providers/translation_provider.dart';
import '../../../core/providers/ai_settings_provider.dart';
import '../../../core/theme/app_theme_colors.dart';
import 'neural_path_dialog.dart'; // فایل دایالوگ سیستم عصبی

class SelectionPopup extends ConsumerStatefulWidget {
  final String word;
  final String sentence;
  final String sourceLang;
  final String nativeLang;
  final List<String> targetLangs;
  final Offset position;
  final VoidCallback onDismiss;

  const SelectionPopup({
    super.key,
    required this.word,
    required this.sentence,
    required this.sourceLang,
    required this.nativeLang,
    required this.targetLangs,
    required this.position,
    required this.onDismiss,
  });

  @override
  ConsumerState<SelectionPopup> createState() => _SelectionPopupState();
}

class _SelectionPopupState extends ConsumerState<SelectionPopup> {
  final Map<String, String> _translations = {};
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _loadMeanings();
  }

  Future<void> _loadMeanings() async {
    try {
      final service = ref.read(translationServiceProvider);
      final ai = ref.read(aiSettingsProvider);

      // زبان‌هایی که باید ترجمه شوند: زبان مادری + زبان‌های مقصد
      final allLangs = {widget.nativeLang, ...widget.targetLangs};

      for (final lang in allLangs) {
        // ۱) اول از کش بخوان
        final cached = service.peekCached(widget.word, widget.sourceLang, lang);
        if (cached != null && cached.trim().isNotEmpty) {
          _translations[lang] = cached;
          continue;
        }

        // ۲) از سرویس ترجمه بگیر
        try {
          final result = await service.translate(
            text: widget.word,
            targetLang: lang,
            sourceLang: widget.sourceLang,
            aiSettings: ai,
          );
          if (result != null && result.trim().isNotEmpty) {
            _translations[lang] = result.trim();
          }
        } catch (_) {
          // اگر خطا داد، رد شو
        }
      }

      if (mounted) {
        setState(() {
          _loading = false;
          _failed = _translations.isEmpty;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
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
      (w) => w.word == widget.word && w.langCode == widget.sourceLang,
    );

    // محاسبه‌ی موقعیت کادر
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    const popupWidth = 280.0;
    
    // تخمین ارتفاع بر اساس تعداد زبان‌ها
    double popupHeight = 200.0 + (_translations.length * 40.0);

    double left = widget.position.dx - popupWidth / 2;
    if (left < 8) left = 8;
    if (left + popupWidth > screenWidth - 8) left = screenWidth - popupWidth - 8;

    double top = widget.position.dy - popupHeight - 12;
    if (top < 8) top = widget.position.dy + 24;
    if (top + popupHeight > screenHeight - 8) top = screenHeight - popupHeight - 8;

    return Positioned(
      left: left,
      top: top,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: popupWidth,
          decoration: BoxDecoration(
            color: c.paper, // ✅ رنگ کرم/بژ حرفه‌ای
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.cardBorder, width: 1),
            boxShadow: [
              BoxShadow(
                color: c.ink.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // هدر: کلمه و آیکون پخش
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.cardBorder)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.volume_up, color: c.gold, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.word,
                        style: TextStyle(
                          color: c.ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, size: 18, color: c.inkSoft),
                      onPressed: widget.onDismiss,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),

              // ترجمه‌ها
              Padding(
                padding: const EdgeInsets.all(16),
                child: _loading
                    ? Row(
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: c.gold,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'در حال یافتن معنی...',
                            style: TextStyle(color: c.inkSoft, fontSize: 13),
                          ),
                        ],
                      )
                    : _failed
                        ? Text(
                            'معنی پیدا نشد.',
                            style: TextStyle(color: c.rose, fontSize: 13),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: _translations.entries.map((e) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: c.paperDark,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: c.cardBorder),
                                      ),
                                      child: Text(
                                        e.key.toUpperCase(),
                                        style: TextStyle(
                                          color: c.gold,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        e.value,
                                        style: TextStyle(
                                          color: c.ink,
                                          fontSize: 14,
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
              ),

              // دکمه‌ها
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: c.cardBorder)),
                ),
                child: Column(
                  children: [
                    _PopupButton(
                      icon: isSaved ? Icons.bookmark : Icons.bookmark_border,
                      label: isSaved ? 'ذخیره شد برای داستان بعدی' : 'ذخیره برای داستان بعدی',
                      isActive: isSaved,
                      c: c,
                      onTap: () {
                        ref.read(savedWordsProvider.notifier).toggleSave(
                              SavedWord(
                                word: widget.word,
                                langCode: widget.sourceLang,
                                meaning: _translations[widget.nativeLang] ?? '',
                                savedAt: DateTime.now(),
                              ),
                            );
                      },
                    ),
                    _PopupButton(
                      icon: Icons.text_fields,
                      label: 'افزودن به یادگیری گرامر',
                      isActive: false,
                      c: c,
                      onTap: () {
                        ref.read(grammarNotesProvider.notifier).addNote(
                              GrammarNote(
                                id: DateTime.now().millisecondsSinceEpoch.toString(),
                                word: widget.word,
                                sentence: widget.sentence,
                                markdown:
                                    '## ${widget.word}\n\n**معنی:** ${_translations[widget.nativeLang] ?? ''}\n\n**جمله:** ${widget.sentence}',
                                langCode: widget.sourceLang,
                                savedAt: DateTime.now(),
                              ),
                            );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('به گرامر اضافه شد'), duration: Duration(seconds: 1)),
                        );
                      },
                    ),
                    _PopupButton(
                      icon: Icons.rotate_left,
                      label: 'افزودن به جعبه لایتنر',
                      isActive: false,
                      c: c,
                      onTap: () {
                        ref.read(leitnerProvider.notifier).addToLeitner(
                              SavedWord(
                                word: widget.word,
                                langCode: widget.sourceLang,
                                meaning: _translations[widget.nativeLang] ?? '',
                                savedAt: DateTime.now(),
                              ),
                            );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('به لایتنر اضافه شد'), duration: Duration(seconds: 1)),
                        );
                      },
                    ),
                    // ✅ دکمه سیستم عصبی
                    _PopupButton(
                      icon: Icons.hub_outlined,
                      label: 'سیستم عصبی این لغت',
                      isActive: false,
                      c: c,
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (_) => NeuralPathDialog(
                            word: widget.word,
                            langCode: widget.sourceLang,
                          ),
                        );
                      },
                    ),
                  ],
                ),
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
  final dynamic c;

  const _PopupButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isActive ? c.gold : c.teal),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isActive ? c.gold : c.ink,
                  fontSize: 13,
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
