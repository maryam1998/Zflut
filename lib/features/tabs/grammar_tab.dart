import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../core/constants/supported_languages.dart' show langDisplayName;
import '../../core/models/grammar_note.dart';
import '../../core/models/saved_word.dart';
import '../../core/providers/language_selection_provider.dart';
import '../../core/providers/reader_providers.dart';
import '../../core/theme/app_theme_colors.dart';
import '_hope_panel.dart';

/// تب «گرامر» — هم‌شکل GrammarPanel در Hope.
/// حالتِ خالی: عنوان + توضیح + «هنوز نکته‌ی گرامری‌ای ذخیره نکردی...»
class GrammarTab extends ConsumerStatefulWidget {
  const GrammarTab({super.key});

  @override
  ConsumerState<GrammarTab> createState() => _GrammarTabState();
}

class _GrammarTabState extends ConsumerState<GrammarTab> {
  String? _expanded;
  bool _selectMode = false;
  final Set<String> _selected = {};

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _dayLabel(DateTime d) =>
      '${d.year}/${_two(d.month)}/${_two(d.day)}';
  static String _timeLabel(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

  void _exitSelect() => setState(() {
        _selectMode = false;
        _selected.clear();
      });

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final n = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(context.l10n.grammar_confirm_delete_notes('$n')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.l10n.cancel_button),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.l10n.grammar_delete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final notifier = ref.read(grammarNotesProvider.notifier);
    for (final id in _selected.toList()) {
      notifier.removeNote(id);
    }
    _exitSelect();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final notes = ref.watch(grammarNotesProvider);
    final savedWords = ref.watch(savedWordsProvider);

    // گروه‌بندی بر اساس روز (جدیدترین اول)
    final groups = <String, List<GrammarNote>>{};
    for (final n in notes) {
      groups.putIfAbsent(_dayLabel(n.savedAt), () => []).add(n);
    }
    final labels = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    return HopePanel(
      contentDirection: uiContentDirection(context),
      title: context.l10n.grammar_title,
      intro: context.l10n.grammar_intro,
      children: [
        if (notes.isEmpty)
          HopeEmptyText(context.l10n.grammar_empty_notes),
        if (notes.isNotEmpty && !_selectMode)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: HopeTextAction(
              icon: Icons.checklist_rounded,
              label: context.l10n.grammar_select_delete,
              color: c.rose,
              onTap: () => setState(() => _selectMode = true),
            ),
          ),
        if (notes.isNotEmpty && _selectMode)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: c.goldSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(
                  _selected.isNotEmpty
                      ? context.l10n.grammar_n_selected('${_selected.length}')
                      : context.l10n.grammar_select_items,
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HopeTextAction(
                      icon: Icons.checklist_rounded,
                      label: context.l10n.select_all,
                      color: c.teal,
                      onTap: () => setState(() {
                        _selected
                          ..clear()
                          ..addAll(notes.map((n) => n.id));
                      }),
                    ),
                    const SizedBox(width: 12),
                    HopeTextAction(
                      icon: Icons.delete_outline,
                      label: context.l10n.grammar_delete,
                      color: _selected.isEmpty
                          ? c.rose.withOpacity(0.5)
                          : c.rose,
                      onTap: _selected.isEmpty ? null : _deleteSelected,
                    ),
                    const SizedBox(width: 12),
                    HopeTextAction(
                      label: context.l10n.cancel_button,
                      color: c.inkSoft,
                      onTap: _exitSelect,
                    ),
                  ],
                ),
              ],
            ),
          ),
        for (final label in labels)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Row(
                  children: [
                    if (_selectMode)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: GestureDetector(
                          onTap: () => setState(() {
                            final ids = groups[label]!.map((n) => n.id);
                            final all = ids.every(_selected.contains);
                            if (all) {
                              _selected.removeAll(ids);
                            } else {
                              _selected.addAll(ids);
                            }
                          }),
                          child: Icon(
                            groups[label]!
                                    .every((n) => _selected.contains(n.id))
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                            size: 18,
                            color: groups[label]!
                                    .every((n) => _selected.contains(n.id))
                                ? c.gold
                                : c.inkSoft,
                          ),
                        ),
                      ),
                    Text(
                      label,
                      style: TextStyle(
                        color: c.inkSoft,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              for (final n in groups[label]!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _NoteCard(
                    note: n,
                    timeLabel: _timeLabel(n.savedAt),
                    open: _expanded == n.id && !_selectMode,
                    selectMode: _selectMode,
                    selected: _selected.contains(n.id),
                    wordSaved: n.word.trim().isNotEmpty &&
                        savedWords.any((w) =>
                            w.langCode == n.langCode &&
                            normWord(w.word) == normWord(n.word)),
                    onTap: () => setState(() {
                      if (_selectMode) {
                        if (!_selected.add(n.id)) _selected.remove(n.id);
                      } else {
                        _expanded = _expanded == n.id ? null : n.id;
                      }
                    }),
                    onToggleSaved: () {
                      if (n.word.trim().isEmpty) return;
                      ref.read(savedWordsProvider.notifier).toggleSave(
                            SavedWord(
                              word: n.word,
                              langCode: n.langCode,
                              meaning: '',
                              savedAt: DateTime.now(),
                            ),
                          );
                    },
                    onDelete: () =>
                        ref.read(grammarNotesProvider.notifier).removeNote(n.id),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _NoteCard extends StatelessWidget {
  final GrammarNote note;
  final String timeLabel;
  final bool open;
  final bool selectMode;
  final bool selected;
  final bool wordSaved;
  final VoidCallback onTap;
  final VoidCallback onToggleSaved;
  final VoidCallback onDelete;

  const _NoteCard({
    required this.note,
    required this.timeLabel,
    required this.open,
    required this.selectMode,
    required this.selected,
    required this.wordSaved,
    required this.onTap,
    required this.onToggleSaved,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final title = note.word.trim().isEmpty
        ? context.l10n.grammar_conversation_correction
        : note.word;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: selected ? c.gold : c.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onTap,
            child: Row(
              children: [
                if (selectMode)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: Icon(
                      selected ? Icons.check_box : Icons.check_box_outline_blank,
                      size: 18,
                      color: selected ? c.gold : c.inkSoft,
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        textDirection: autoDir(title),
                        style: TextStyle(
                          color: c.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${langDisplayName(context, note.langCode)} · $timeLabel',
                        style: TextStyle(color: c.inkSoft, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                if (!selectMode) ...[
                  if (note.word.trim().isNotEmpty)
                    GestureDetector(
                      onTap: onToggleSaved,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          wordSaved ? Icons.bookmark : Icons.bookmark_border,
                          size: 18,
                          color: wordSaved ? c.gold : c.inkSoft,
                        ),
                      ),
                    ),
                  GestureDetector(
                    onTap: onDelete,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.close, size: 18, color: c.inkSoft),
                    ),
                  ),
                  Icon(
                    open ? Icons.keyboard_arrow_down : Icons.chevron_left,
                    size: 20,
                    color: c.inkSoft,
                  ),
                ],
              ],
            ),
          ),
          if (open)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.cardBorder)),
              ),
              child: MiniMarkdown(text: note.markdown),
            ),
        ],
      ),
    );
  }
}
