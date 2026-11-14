// ابزارِ ترجمه‌ی SRT — معادلِ SrtTranslatorTool.jsx در Hope.
// فایلِ .srt را می‌خواند، متنِ هر بلوک را (بدونِ دست‌زدن به شماره/تایم‌کد) ترجمه می‌کند
// و فایلِ SRTِ جدید را ذخیره می‌کند.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../core/audio/srt_utils.dart';
import '../../core/constants/supported_languages.dart';
import '../../core/providers/language_selection_provider.dart';
import '../../core/providers/translation_provider.dart';
import '../../core/theme/app_theme_colors.dart';

class SrtTranslatorTool extends ConsumerStatefulWidget {
  const SrtTranslatorTool({super.key});

  @override
  ConsumerState<SrtTranslatorTool> createState() => _SrtTranslatorToolState();
}

class _SrtTranslatorToolState extends ConsumerState<SrtTranslatorTool> {
  bool _open = false;
  String _fileName = '';
  List<SrtEntry> _entries = const [];

  /// زبان‌های انتخاب‌شده برای ترجمه (چندتایی) و زبان‌های «همین اجرا» (برای ساختِ فایل).
  final List<String> _langs = [];
  bool _langsInit = false;
  List<String> _runLangs = const [];

  /// نتیجه‌ی هر خطِ ترجمه‌شده تا اینجا: {زبان: ترجمه}. خط‌به‌خط پر می‌شود تا هر لحظه بشود دانلود کرد.
  final List<Map<String, String>> _res = [];

  /// true = متنِ اصلی + ترجمه‌ها (زیرِ هر خط)؛ false = فقط ترجمه‌ها
  bool _bilingual = true;

  bool _translating = false;
  bool _cancel = false;
  String _error = '';
  String _info = '';

  int get _done => _res.length;

  @override
  void dispose() {
    _cancel = true;
    super.dispose();
  }

  bool get _fa => Localizations.localeOf(context).languageCode == 'fa';
  String _t(String fa, String en) => _fa ? fa : en;

  Future<void> _pick() async {
    setState(() {
      _error = '';
      _info = '';
    });
    try {
      final res = await FilePicker.platform
          .pickFiles(type: FileType.any, allowMultiple: false, withData: true);
      final f = res?.files.isNotEmpty == true ? res!.files.first : null;
      if (f == null || f.bytes == null) return;
      if (!f.name.toLowerCase().endsWith('.srt')) {
        setState(() => _error = context.l10n.srt_tool_err_not_srt);
        return;
      }
      final parsed = parseSrt(utf8.decode(f.bytes!, allowMalformed: true));
      if (parsed.isEmpty) {
        setState(() {
          _error = context.l10n.srt_tool_err_empty_file;
          _entries = const [];
        });
        return;
      }
      setState(() {
        _fileName = f.name;
        _entries = parsed;
        _res.clear();
        _runLangs = const [];
      });
    } catch (_) {
      setState(() => _error = context.l10n.srt_tool_err_read);
    }
  }

  /// ترجمه‌ی رایگان (مترجم‌های رایگان + ML Kit روی گوشی) — بدونِ بازبینی/ترجمه‌ی AI.
  Future<void> _translateAll() async {
    if (_entries.isEmpty || _translating || _langs.isEmpty) return;
    final langs = List<String>.from(_langs);
    setState(() {
      _translating = true;
      _cancel = false;
      _error = '';
      _info = '';
      _res.clear();
      _runLangs = langs;
    });
    final svc = ref.read(translationServiceProvider);
    for (var i = 0; i < _entries.length; i++) {
      if (_cancel || !mounted) break;
      final plain = _entries[i].text.replaceAll('\n', ' ').trim();
      final row = <String, String>{};
      if (plain.isNotEmpty) {
        await Future.wait(langs.map((l) async {
          try {
            // aiSettings: null → فقط سرویس‌های رایگان (بدونِ AI)
            final r = await svc.translate(
                text: plain, targetLang: l, sourceLang: 'auto');
            if (r.trim().isNotEmpty) row[l] = r.trim();
          } catch (_) {
            // ترجمه‌ی این زبان برای این خط شکست خورد؛ خط خالی می‌ماند
          }
        }));
      }
      if (_cancel || !mounted) break; // خطِ نیمه‌کاره ثبت نمی‌شود
      _res.add(row);
      if (mounted) setState(() {});
    }
    if (!mounted) return;
    setState(() {
      _translating = false;
      if (_res.length != _entries.length) _info = context.l10n.srt_tool_stopped;
    });
  }

  /// فایلِ خروجی از خط‌های ترجمه‌شده‌ی «تا همین لحظه».
  List<SrtEntry> _buildOut() {
    final out = <SrtEntry>[];
    for (var i = 0; i < _res.length && i < _entries.length; i++) {
      final e = _entries[i];
      final orig = e.text.trim();
      final origFlat = orig.replaceAll('\n', ' ').trim();
      final row = _res[i];
      final lines = <String>[];
      if (_bilingual && orig.isNotEmpty) lines.add(orig);
      for (final l in _runLangs) {
        final tr = row[l];
        if (tr == null || tr.isEmpty) continue;
        if (_bilingual && tr == origFlat) continue;
        lines.add(tr);
      }
      if (lines.isEmpty) lines.add(orig);
      out.add(e.withText(lines.join('\n')));
    }
    return out;
  }

  Future<void> _save() async {
    if (_res.isEmpty) return;
    final base = _fileName.replaceAll(RegExp(r'\.srt$', caseSensitive: false), '');
    final suffix = _runLangs.join('-');
    final name = '${base.isEmpty ? 'subtitles' : base}.$suffix.srt';
    final bytes = Uint8List.fromList(utf8.encode(serializeSrt(_buildOut())));
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: context.l10n.srt_tool_save_dialog,
        fileName: name,
        bytes: bytes,
      );
      if (mounted && path != null) setState(() => _info = context.l10n.srt_tool_saved(name));
    } catch (_) {
      if (mounted) setState(() => _error = context.l10n.srt_tool_err_save);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final sel = ref.watch(languageSelectionProvider);
    if (!_langsInit) {
      _langsInit = true;
      // پیش‌فرض: همان زبان‌هایی که کاربر در بقیه‌ی جاهای برنامه انتخاب کرده (مادری + مقصدها)
      final init = <String>[];
      if (sel.native.isNotEmpty && !sel.targets.contains(sel.native)) {
        init.add(sel.native);
      }
      init.addAll(sel.targets);
      _langs.addAll(init.where((l) => kSupportedLanguages.any((x) => x.code == l)));
      if (_langs.isEmpty) _langs.add('en');
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: c.cardBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Row(
              children: [
                Expanded(
                  child: Text('🎬 ${context.l10n.srt_tool_title}',
                      style: TextStyle(
                          color: c.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                ),
                Icon(_open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: c.inkSoft),
              ],
            ),
          ),
          if (_open) ...[
            const SizedBox(height: 8),
            Text(
              _t(
                'یه فایلِ srt وارد کن، یک یا چند زبانِ مقصد رو انتخاب کن و ترجمه کن. هر لحظه می‌تونی همون خط‌هایی که تا الان ترجمه شده رو دانلود کنی — لازم نیست تا آخر صبر کنی. ترجمه رایگانه (بدونِ هوش مصنوعی).',
                'Upload an srt file, pick one or more target languages and translate. You can download the lines translated so far at any moment — no need to wait for the end. Translation is free (no AI).',
              ),
              style: TextStyle(color: c.inkSoft, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: _translating ? null : _pick,
                  style: OutlinedButton.styleFrom(
                      side: BorderSide(color: c.cardBorder)),
                  child: Text(context.l10n.srt_tool_choose_file,
                      style: TextStyle(color: c.ink, fontSize: 13)),
                ),
                if (_fileName.isNotEmpty)
                  Text('$_fileName (${context.l10n.srt_tool_lines_count('${_entries.length}')})',
                      textDirection: TextDirection.ltr,
                      style: TextStyle(color: c.inkSoft, fontSize: 12)),
              ],
            ),
            if (_entries.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(_t('زبان‌های ترجمه (چندتایی)', 'Target languages (multiple)'),
                  style: TextStyle(
                      color: c.ink, fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final l in kSupportedLanguages)
                    FilterChip(
                      label: Text(langDisplayName(context, l.code),
                          style: const TextStyle(fontSize: 12.5)),
                      selected: _langs.contains(l.code),
                      onSelected: _translating
                          ? null
                          : (v) => setState(() {
                                if (v) {
                                  _langs.add(l.code);
                                } else if (_langs.length > 1) {
                                  _langs.remove(l.code);
                                }
                              }),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(_t('محتوای فایل خروجی', 'Output file content'),
                  style: TextStyle(
                      color: c.ink, fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    label: Text(
                        _t('متنِ اصلی + ترجمه‌ها', 'Original + translations'),
                        style: const TextStyle(fontSize: 12.5)),
                    selected: _bilingual,
                    onSelected: (_) => setState(() => _bilingual = true),
                  ),
                  ChoiceChip(
                    label: Text(_t('فقط ترجمه‌ها', 'Translations only'),
                        style: const TextStyle(fontSize: 12.5)),
                    selected: !_bilingual,
                    onSelected: (_) => setState(() => _bilingual = false),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (!_translating)
                    ElevatedButton(
                      onPressed: _langs.isEmpty ? null : _translateAll,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: c.gold,
                          foregroundColor: c.headerTo,
                          elevation: 0),
                      child: Text(context.l10n.srt_tool_translate),
                    )
                  else
                    ElevatedButton(
                      onPressed: () => setState(() => _cancel = true),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: c.rose,
                          foregroundColor: Colors.white,
                          elevation: 0),
                      child: Text(context.l10n.srt_tool_stop('$_done', '${_entries.length}')),
                    ),
                  // دانلود در هر لحظه: همان خط‌هایی که تا الان ترجمه شده‌اند
                  if (_res.isNotEmpty)
                    OutlinedButton(
                      onPressed: _save,
                      style: OutlinedButton.styleFrom(
                          side: BorderSide(color: c.teal)),
                      child: Text(
                        _res.length == _entries.length
                            ? context.l10n.srt_tool_download
                            : _t('دانلود تا اینجا ($_done/${_entries.length})',
                                'Download so far ($_done/${_entries.length})'),
                        style: TextStyle(color: c.teal),
                      ),
                    ),
                ],
              ),
            ],
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error, style: TextStyle(color: c.rose, fontSize: 12)),
              ),
            if (_info.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_info, style: TextStyle(color: c.teal, fontSize: 12)),
              ),
          ],
        ],
      ),
    );
  }
}
