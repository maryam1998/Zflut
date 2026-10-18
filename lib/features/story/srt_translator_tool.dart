// ابزارِ ترجمه‌ی SRT — معادلِ SrtTranslatorTool.jsx در Hope.
// فایلِ .srt را می‌خواند، متنِ هر بلوک را (بدونِ دست‌زدن به شماره/تایم‌کد) ترجمه می‌کند
// و فایلِ SRTِ جدید را ذخیره می‌کند.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/srt_utils.dart';
import '../../core/constants/supported_languages.dart';
import '../../core/providers/ai_settings_provider.dart';
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
  List<SrtEntry>? _translated;
  String _target = '';
  bool _translating = false;
  bool _cancel = false;
  int _done = 0;
  String _error = '';
  String _info = '';

  @override
  void dispose() {
    _cancel = true;
    super.dispose();
  }

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
        setState(() => _error = 'فایلِ انتخابی با پسوندِ .srt نیست');
        return;
      }
      final parsed = parseSrt(utf8.decode(f.bytes!, allowMalformed: true));
      if (parsed.isEmpty) {
        setState(() {
          _error = 'این فایل زیرنویسِ معتبری نداشت';
          _entries = const [];
        });
        return;
      }
      setState(() {
        _fileName = f.name;
        _entries = parsed;
        _translated = null;
        _done = 0;
      });
    } catch (_) {
      setState(() => _error = 'خوندنِ فایل انجام نشد');
    }
  }

  Future<void> _translateAll(String target) async {
    if (_entries.isEmpty || _translating) return;
    setState(() {
      _translating = true;
      _cancel = false;
      _error = '';
      _info = '';
      _done = 0;
    });
    final svc = ref.read(translationServiceProvider);
    final ai = ref.read(aiSettingsProvider);
    final out = <SrtEntry>[];
    for (var i = 0; i < _entries.length; i++) {
      if (_cancel || !mounted) break;
      final e = _entries[i];
      final plain = e.text.replaceAll('\n', ' ').trim();
      var tr = plain;
      if (plain.isNotEmpty) {
        try {
          final r = await svc.translate(
              text: plain, targetLang: target, sourceLang: 'auto', aiSettings: ai);
          if (r.trim().isNotEmpty) tr = r.trim();
        } catch (_) {
          // اگه ترجمه‌ی یه خط شکست خورد، متنِ اصلی می‌مونه (بهتر از خالی)
        }
      }
      out.add(e.withText(tr));
      if (mounted) setState(() => _done = i + 1);
    }
    if (!mounted) return;
    setState(() {
      _translated = out.length == _entries.length ? out : null;
      _translating = false;
      if (out.length != _entries.length) _info = 'ترجمه متوقف شد';
    });
  }

  Future<void> _save(String target) async {
    final t = _translated;
    if (t == null) return;
    final base = _fileName.replaceAll(RegExp(r'\.srt$', caseSensitive: false), '');
    final name = '${base.isEmpty ? 'subtitles' : base}.$target.srt';
    final bytes = Uint8List.fromList(utf8.encode(serializeSrt(t)));
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'ذخیره‌ی زیرنویسِ ترجمه‌شده',
        fileName: name,
        bytes: bytes,
      );
      if (mounted && path != null) setState(() => _info = 'ذخیره شد: $name');
    } catch (_) {
      if (mounted) setState(() => _error = 'ذخیره‌ی فایل انجام نشد');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final sel = ref.watch(languageSelectionProvider);
    if (_target.isEmpty) {
      _target = sel.targets.isNotEmpty ? sel.targets.first : 'en';
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
                  child: Text('🎬 ترجمه‌ی فایلِ زیرنویس (SRT)',
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
              'یه فایلِ .srt وارد کن؛ متنِ هر خط ترجمه می‌شه و تایم‌کدها دست‌نخورده می‌مونن. '
              'بعد فایلِ جدید رو ذخیره کن تا تو پلیرِ خودت بازش کنی.',
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
                  child: Text('انتخابِ فایل SRT',
                      style: TextStyle(color: c.ink, fontSize: 13)),
                ),
                if (_fileName.isNotEmpty)
                  Text('$_fileName (${_entries.length} خط)',
                      textDirection: TextDirection.ltr,
                      style: TextStyle(color: c.inkSoft, fontSize: 12)),
              ],
            ),
            if (_entries.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DropdownButton<String>(
                    value: kSupportedLanguages.any((l) => l.code == _target)
                        ? _target
                        : 'en',
                    items: [
                      for (final l in kSupportedLanguages)
                        DropdownMenuItem(value: l.code, child: Text(l.faLabel)),
                    ],
                    onChanged: _translating
                        ? null
                        : (v) => setState(() {
                              _target = v ?? 'en';
                              _translated = null;
                            }),
                  ),
                  if (!_translating)
                    ElevatedButton(
                      onPressed: () => _translateAll(_target),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: c.paper,
                          foregroundColor: c.ink,
                          elevation: 0,
                          side: BorderSide(color: c.gold, width: 1.6)),
                      child: const Text('ترجمه کن'),
                    )
                  else
                    ElevatedButton(
                      onPressed: () => setState(() => _cancel = true),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: c.paper,
                          foregroundColor: c.rose,
                          elevation: 0,
                          side: BorderSide(color: c.rose, width: 1.6)),
                      child: Text('توقف ($_done از ${_entries.length})'),
                    ),
                  if (_translated != null && !_translating)
                    OutlinedButton(
                      onPressed: () => _save(_target),
                      style: OutlinedButton.styleFrom(
                          side: BorderSide(color: c.teal)),
                      child: Text('ذخیره‌ی فایلِ ترجمه‌شده',
                          style: TextStyle(color: c.teal)),
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
