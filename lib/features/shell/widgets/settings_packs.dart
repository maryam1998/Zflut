// 📁 مسیر: lib/features/shell/widgets/settings_packs.dart
//
// بخش‌های «بسته‌های آفلاین» و «دانلود آفلاین لغات» تنظیمات — معادل
// OfflineSpeechSettings / VoiceSettings / AudioSyncSettings / OfflineWordsModal در Hope.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/bridge/linlearn_bridge.dart';
import '../../../core/constants/supported_languages.dart';
import '../../../core/data/data_repository.dart';
import '../../../core/models/filter_state.dart';
import '../../../core/providers/ai_settings_provider.dart';
import '../../../core/providers/translation_provider.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/translate/translation_service.dart'
    show looksLikelyMistranslated;

// ═══════════════════════════════════════════════════════════════════
// یک بستهٔ آفلاین (دانلود / توقف / حذف) — وضعیت از سمت نیتیو خوانده می‌شود
// ═══════════════════════════════════════════════════════════════════
class PackTile extends StatefulWidget {
  /// 'tts' | 'speech' | 'song' | 'sync'
  final String kind;
  final String id;
  final String title;
  final String? hint;
  final int approxMb;

  /// فقط برای حالت آهنگ: کلید روشن/خاموش بعد از دانلود
  final String? toggleTitle;

  const PackTile({
    super.key,
    required this.kind,
    required this.id,
    required this.title,
    this.hint,
    this.approxMb = 0,
    this.toggleTitle,
  });

  @override
  State<PackTile> createState() => _PackTileState();
}

class _PackTileState extends State<PackTile> {
  Map<String, dynamic>? _st;
  bool _loaded = false;
  bool _stopping = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant PackTile old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id || old.kind != widget.kind) {
      _timer?.cancel();
      _stopping = false;
      _refresh();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool get _downloading => _st?['downloading'] == true;
  bool get _downloaded => _st?['downloaded'] == true;

  Future<void> _refresh() async {
    final st = await LinLearnBridge.packStatus(widget.kind, widget.id);
    if (!mounted) return;
    setState(() {
      _st = st;
      _loaded = true;
      if (!_downloading) _stopping = false;
    });
    _timer?.cancel();
    if (_downloading) {
      _timer = Timer(const Duration(seconds: 1), _refresh);
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _download() async {
    final ok = await LinLearnBridge.packDownload(widget.kind, widget.id);
    if (!ok) _toast('دانلود شروع نشد.');
    await _refresh();
  }

  Future<void> _cancel() async {
    setState(() => _stopping = true);
    await LinLearnBridge.packCancel(widget.kind, widget.id);
    await _refresh();
  }

  Future<void> _delete() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text('بسته‌ی آفلاین حذف بشه؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('نه')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (yes != true) return;
    await LinLearnBridge.packDelete(widget.kind, widget.id);
    await _refresh();
  }

  Future<void> _setEnabled(bool v) async {
    await LinLearnBridge.packSetEnabled(widget.kind, widget.id, v);
    await _refresh();
  }

  static String _mb(num bytes) => (bytes / (1024 * 1024)).round().toString();

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final note = TextStyle(color: c.inkSoft, fontSize: 11.5, height: 1.7);

    Widget btn(String label, VoidCallback? onTap, {Color? color}) => SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: color ?? c.cardBorder),
              padding: const EdgeInsets.symmetric(vertical: 11),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(label,
                style: TextStyle(
                    color: color ?? c.ink,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700)),
          ),
        );

    Widget body;
    if (!_loaded) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: LinearProgressIndicator(minHeight: 2),
      );
    } else if (_st == null) {
      body = Text(
          'این بسته هنوز در نسخه‌ی نیتیو فعال نشده (سمت اندروید باید اضافه شود).',
          style: note);
    } else if (_downloading) {
      final bytes = (_st!['bytes'] as num?) ?? 0;
      final total = (_st!['total'] as num?) ?? 0;
      final pct = total > 0 ? (bytes / total).clamp(0, 1).toDouble() : null;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              '📥 در حال دانلود... ${_mb(bytes)} مگابایت'
              '${total > 0 ? ' (~${(pct! * 100).round()}٪)' : ''}',
              style: note),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: pct, minHeight: 4, color: c.teal),
          const SizedBox(height: 8),
          btn(_stopping ? 'در حال توقف...' : 'توقف (بعداً ادامه می‌دهم)',
              _stopping ? null : _cancel),
        ],
      );
    } else if (_downloaded) {
      final enabled = _st!['enabled'] == true;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('✅ بسته دانلود شده و آماده‌ست', style: note),
          if (widget.toggleTitle != null && _st!.containsKey('enabled'))
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              activeColor: c.teal,
              title: Text(widget.toggleTitle!,
                  style: TextStyle(
                      color: c.ink,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700)),
              value: enabled,
              onChanged: _setEnabled,
            ),
          const SizedBox(height: 6),
          btn('🗑 حذف بسته', _delete, color: c.inkSoft),
        ],
      );
    } else {
      final have = (_st!['partialBytes'] as num?) ?? 0;
      final mb = ((_st!['approxMb'] as num?) ?? widget.approxMb).round();
      final label = have > 0
          ? 'ادامه دانلود (${_mb(have)} از ~$mb مگابایت دانلود شده)'
          : 'دانلود بسته‌ی آفلاین${mb > 0 ? ' (~$mb مگابایت، فقط یک بار)' : ''}';
      body = btn('📥 $label', _download);
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title,
              style: TextStyle(
                  color: c.ink, fontSize: 13, fontWeight: FontWeight.w800)),
          if (widget.hint != null) ...[
            const SizedBox(height: 4),
            Text(widget.hint!, style: note),
          ],
          const SizedBox(height: 8),
          body,
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// دانلود آفلاین لغات — ترجمه‌ی همه‌ی لغات و ذخیره در کش گوشی
// ═══════════════════════════════════════════════════════════════════
class OfflineWordsDialog extends ConsumerStatefulWidget {
  const OfflineWordsDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const OfflineWordsDialog(),
      );

  @override
  ConsumerState<OfflineWordsDialog> createState() => _OfflineWordsDialogState();
}

class _OfflineWordsDialogState extends ConsumerState<OfflineWordsDialog> {
  final Set<String> _selected = {};
  List<String> _words = const [];
  bool _running = false;
  bool _finished = false;
  bool _cancel = false;
  int _done = 0, _total = 0, _failed = 0, _bytes = 0;
  String _current = '';
  int _cached = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  int _countCached() => ref.read(translationServiceProvider).cachedCount;

  Future<void> _load() async {
    await DataRepository.instance.load();
    final all = DataRepository.instance
        .filterWords(const WordsFilterState())
        .map((w) => w.en.trim())
        .where((w) => w.isNotEmpty)
        .toSet()
        .toList();
    if (!mounted) return;
    setState(() {
      _words = all;
      _cached = _countCached();
    });
  }

  static String _size(int bytes) {
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb < 10 ? kb.toStringAsFixed(1) : kb.round()} کیلوبایت';
    return '${(kb / 1024).toStringAsFixed(1)} مگابایت';
  }

  Future<void> _start() async {
    if (_selected.isEmpty || _running) return;
    final service = ref.read(translationServiceProvider);
    final ai = ref.read(aiSettingsProvider);
    final jobs = <(String, String)>[
      for (final l in _selected)
        for (final w in _words) (w, l),
    ];
    setState(() {
      _running = true;
      _finished = false;
      _cancel = false;
      _done = 0;
      _failed = 0;
      _bytes = 0;
      _total = jobs.length;
    });

    var cursor = 0;
    Future<void> worker() async {
      while (cursor < jobs.length) {
        if (_cancel || !mounted) return;
        final (word, lang) = jobs[cursor++];
        _current = word;
        try {
          final r = await service.translate(
            text: word,
            targetLang: lang,
            sourceLang: 'en',
            aiSettings: ai,
          );
          if (r.isNotEmpty &&
              !looksLikelyMistranslated(word, r, lang, sourceLang: 'en')) {
            _bytes += r.length * 2;
          } else {
            _failed++;
          }
        } catch (_) {
          _failed++;
        }
        _done++;
        if (mounted && _done % 5 == 0) setState(() {});
      }
    }

    await Future.wait(List.generate(8, (_) => worker()));
    if (!mounted) return;
    setState(() {
      _running = false;
      _finished = !_cancel;
      _cached = _countCached();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final note = TextStyle(color: c.inkSoft, fontSize: 12, height: 1.8);
    final pct = _total == 0 ? 0 : ((_done / _total) * 100).round();
    final langs = kSupportedLanguages.where((l) => l.code != 'en').toList();

    return Dialog(
      backgroundColor: c.paper,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('دانلود آفلاین لغات',
                        style: TextStyle(
                            color: c.ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w800)),
                  ),
                  if (!_running)
                    InkWell(
                      onTap: () => Navigator.pop(context),
                      child: Icon(Icons.close, size: 18, color: c.inkSoft),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'زبان‌های موردنظرت رو انتخاب کن. برنامه ${_words.length} لغت رو '
                'یکی‌یکی با سرویس‌های ترجمه ترجمه و روی گوشی ذخیره می‌کنه — فقط '
                'همین یک‌بار به اینترنت نیاز داره؛ بعدش این لغات آفلاین در دسترسن.',
                style: note,
              ),
              const SizedBox(height: 14),
              if (!_running && !_finished) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final l in langs)
                      InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => setState(() {
                          if (!_selected.remove(l.code)) _selected.add(l.code);
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: _selected.contains(l.code)
                                ? c.goldSoft
                                : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: _selected.contains(l.code)
                                    ? c.gold
                                    : c.cardBorder,
                                width: 1.5),
                          ),
                          child: Text(l.faLabel,
                              style: TextStyle(
                                  color: c.ink,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _selected.isEmpty || _words.isEmpty ? null : _start,
                    style: FilledButton.styleFrom(
                      backgroundColor: c.ink,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                        'شروع دانلود${_selected.isNotEmpty ? ' (${_words.length * _selected.length} ترجمه)' : ''}'),
                  ),
                ),
                if (_cached > 0) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                        '$_cached ترجمه از قبل ذخیره شده (این‌ها دوباره دانلود نمی‌شن)',
                        style: note.copyWith(fontSize: 11)),
                  ),
                ],
              ],
              if (_running) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                      value: _total == 0 ? null : _done / _total,
                      minHeight: 10,
                      color: c.gold),
                ),
                const SizedBox(height: 8),
                Text('$_done از $_total ($pct٪) · ${_size(_bytes)}', style: note),
                if (_failed > 0)
                  Text('$_failed تا هنوز جواب نگرفتن (بعداً دوباره امتحان می‌شن)',
                      style: note.copyWith(color: c.rose, fontSize: 11)),
                Text(_current,
                    textDirection: TextDirection.ltr,
                    style: note.copyWith(fontSize: 11)),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => setState(() {
                      _cancel = true;
                    }),
                    style: OutlinedButton.styleFrom(
                        side: BorderSide(color: c.rose)),
                    child: Text('لغو', style: TextStyle(color: c.rose)),
                  ),
                ),
              ],
              if (_finished) ...[
                Center(
                  child: Column(
                    children: [
                      Text('✅ تمام شد',
                          style: TextStyle(
                              color: c.ink,
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(
                          'الان $_cached ترجمه روی گوشی ذخیره‌ست و آفلاین در دسترسه.',
                          style: note,
                          textAlign: TextAlign.center),
                      if (_failed > 0)
                        Text(
                            '$_failed تا ترجمه نشدن — می‌تونی دوباره «شروع دانلود» رو بزنی، فقط همین‌ها امتحان می‌شن.',
                            style: note.copyWith(color: c.rose, fontSize: 11),
                            textAlign: TextAlign.center),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => Navigator.pop(context),
                          style: FilledButton.styleFrom(backgroundColor: c.ink),
                          child: const Text('باشه'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
