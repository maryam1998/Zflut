// 📁 مسیر: lib/features/shell/widgets/settings_packs.dart
//
// بخش‌های «بسته‌های آفلاین» و «دانلود آفلاین لغات» تنظیمات — معادل
// OfflineSpeechSettings / VoiceSettings / AudioSyncSettings / OfflineWordsModal در Hope.

import '../../tabs/_hope_panel.dart' show uiContentDirection;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app.dart';
import '../../../core/bridge/linlearn_bridge.dart';
import '../../../core/native/native_bridge.dart';
import '../../../core/constants/supported_languages.dart';
import '../../../core/data/data_repository.dart';
import '../../../core/models/filter_state.dart';
import '../../../core/providers/ai_settings_provider.dart';
import '../../../core/providers/translation_provider.dart';
import '../../../core/storage/local_storage.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/tts/native_tts_bridge.dart';
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

  /// بدون کادر و عنوان: فقط دکمه/وضعیت (مثل Hope که زیر لیست‌ها فقط دکمه دارد)
  final bool bare;

  /// دکمه‌ی دانلود به‌صورت پر (سبزِ تیره، متن روشن)
  final bool filled;

  /// متن دلخواه دکمه‌ی دانلود / ادامه (وگرنه متن پیش‌فرض l10n)
  final String Function(int mb)? downloadLabel;
  final String Function(String have, int mb)? resumeLabel;

  const PackTile({
    super.key,
    required this.kind,
    required this.id,
    required this.title,
    this.hint,
    this.approxMb = 0,
    this.toggleTitle,
    this.bare = false,
    this.filled = false,
    this.downloadLabel,
    this.resumeLabel,
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
    if (!ok) _toast(context.l10n.st_download_failed);
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
      builder: (ctx) => _dirDialog(ctx, AlertDialog(
        content: Text(context.l10n.st_pack_delete_confirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.st_no)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.l10n.st_delete)),
        ],
      )),
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

    Widget btn(String label, VoidCallback? onTap,
            {Color? color, bool filled = false}) =>
        SizedBox(
          width: double.infinity,
          child: filled
              ? ElevatedButton(
                  onPressed: onTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.headerFrom,
                    foregroundColor: c.headerText,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        vertical: 13, horizontal: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700)),
                )
              : OutlinedButton(
                  onPressed: onTap,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.35),
                    side: BorderSide(color: color ?? c.cardBorder),
                    padding: const EdgeInsets.symmetric(
                        vertical: 13, horizontal: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(label,
                      textAlign: TextAlign.center,
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
      body = Text(context.l10n.st_pack_not_native, style: note);
    } else if (_downloading) {
      final bytes = (_st!['bytes'] as num?) ?? 0;
      final total = (_st!['total'] as num?) ?? 0;
      final pct = total > 0 ? (bytes / total).clamp(0, 1).toDouble() : null;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              context.l10n.st_pack_downloading(
                  _mb(bytes),
                  total > 0 ? ' (~${(pct! * 100).round()}%)' : ''),
              style: note),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: pct, minHeight: 4, color: c.teal),
          const SizedBox(height: 8),
          btn(_stopping ? context.l10n.st_pack_stopping : context.l10n.st_pack_stop,
              _stopping ? null : _cancel),
        ],
      );
    } else if (_downloaded) {
      final enabled = _st!['enabled'] == true;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.st_pack_ready, style: note),
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
          btn(context.l10n.st_pack_delete_btn, _delete, color: c.inkSoft),
        ],
      );
    } else {
      final have = (_st!['partialBytes'] as num?) ?? 0;
      final mb = ((_st!['approxMb'] as num?) ?? widget.approxMb).round();
      final L = context.l10n;
      final label = have > 0
          ? (widget.resumeLabel?.call(_mb(have), mb) ??
              L.settings_pack_resume(_mb(have), '$mb'))
          : (mb > 0
              ? (widget.downloadLabel?.call(mb) ??
                  L.settings_pack_download('$mb'))
              : L.settings_download);
      body = btn('📥 $label', _download, filled: widget.filled);
    }

    if (widget.bare) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: body,
      );
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

/// جمله‌ی کوتاهِ «تست صدا» برای هر زبان
const Map<String, String> _kVoiceSample = {
  'en': 'Hello! This is how this voice sounds when it reads your text.',
  'de': 'Hallo! So klingt diese Stimme, wenn sie deinen Text vorliest.',
  'fr': 'Bonjour ! Voici comment cette voix sonne quand elle lit ton texte.',
  'es': '¡Hola! Así suena esta voz cuando lee tu texto.',
  'it': 'Ciao! Ecco come suona questa voce quando legge il tuo testo.',
  'ru': 'Привет! Вот так звучит этот голос, когда он читает твой текст.',
  'tr': 'Merhaba! Bu ses, metnini okurken böyle duyuluyor.',
  'ar': 'مرحبًا! هكذا يبدو هذا الصوت عندما يقرأ نصك.',
  'fa': 'سلام! صدای من موقع خواندنِ متنِ تو این‌طوری است.',
  'hi': 'नमस्ते! जब यह आवाज़ आपका टेक्स्ट पढ़ती है तो ऐसी सुनाई देती है।',
  'zh': '你好！这个声音朗读你的文字时就是这样的。',
};

// ═══════════════════════════════════════════════════════════════════
// یک ردیف از «صدای آفلاینِ باکیفیت» — [نام زبان]  ........  [📥 دانلود]
// دانلود فقط وقتی شروع می‌شود که کاربر خودش دکمه را بزند.
// ═══════════════════════════════════════════════════════════════════
class TtsPackRow extends StatefulWidget {
  final String code;
  final String label;

  /// زبان‌هایی که بسته‌ی آفلاین ندارند و فقط با صدای خودِ گوشی خوانده می‌شوند
  final bool phoneOnly;

  /// 'tts' (صدای خوانش) | 'speech' (بسته‌ی تک‌زبانه‌ی ترجمه‌ی زنده)
  final String kind;

  const TtsPackRow({
    super.key,
    required this.code,
    required this.label,
    this.phoneOnly = false,
    this.kind = 'tts',
  });

  @override
  State<TtsPackRow> createState() => _TtsPackRowState();
}

class _TtsPackRowState extends State<TtsPackRow> {
  Map<String, dynamic>? _st;
  Timer? _timer;

  // ── چند صدا برای هر زبان (فقط kind == 'tts') ──
  bool _open = false;
  List<Map<String, dynamic>> _voices = const [];
  String _dlVoice = '';
  Timer? _voiceTimer;
  // صفِ دانلود: چند صدا را پشت‌سرهم انتخاب کن؛ یکی‌یکی (خودکار) دانلود می‌شوند
  final List<String> _queue = [];
  String? _restoreVoice; // صدای فعالِ قبل از شروعِ دانلودِ گروهی
  int _batch = 0;

  // ── تست صدا ──
  String _testing = ''; // شناسه‌ی صدایی که الان در حال تست است
  String? _testRestore; // صدای فعالِ قبل از تست (بعد از تست برمی‌گردد)
  StreamSubscription<Map<String, dynamic>>? _testSub;
  Timer? _testTimer;
  bool _testBusy = false;

  bool get _hasVoices => widget.kind == 'tts' && !widget.phoneOnly;

  @override
  void initState() {
    super.initState();
    if (!widget.phoneOnly) _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _voiceTimer?.cancel();
    _testSub?.cancel();
    _testTimer?.cancel();
    if (_testing.isNotEmpty) {
      NativeTtsBridge.stop();
      final r = _testRestore;
      if (r != null && r.isNotEmpty) {
        NativeBridge.instance
            .setTtsVoice(lang: widget.code, voice: r)
            .then((_) {}, onError: (_) {});
      }
    }
    super.dispose();
  }

  Future<void> _loadVoices() async {
    try {
      final r = await NativeBridge.instance.getTtsVoices(lang: widget.code);
      if (!mounted) return;
      final v = r['voices'];
      setState(() {
        _voices = v is List
            ? [
                for (final e in v)
                  if (e is Map) Map<String, dynamic>.from(e),
              ]
            : const [];
        _dlVoice = '${r['downloadingVoice'] ?? ''}';
      });
    } catch (_) {
      return;
    }
    _voiceTimer?.cancel();
    // نوبتِ بعدیِ صف
    if (_dlVoice.isEmpty && _queue.isNotEmpty) {
      final next = _queue.removeAt(0);
      await _startVoiceDownload(next);
      return;
    }
    // صف تمام شد: صدای فعالِ قبلی دوباره فعال شود (دانلودِ هر صدا آن را فعال می‌کرد)
    if (_dlVoice.isEmpty && _queue.isEmpty && _batch > 1) {
      final r = _restoreVoice;
      _batch = 0;
      _restoreVoice = null;
      if (r != null && r.isNotEmpty) {
        try {
          await NativeBridge.instance.setTtsVoice(lang: widget.code, voice: r);
        } catch (_) {}
        if (mounted) await _loadVoices();
        return;
      }
    }
    if (_dlVoice.isEmpty && _queue.isEmpty) _batch = 0;
    if (mounted && (_dlVoice.isNotEmpty || _queue.isNotEmpty)) {
      // تا وقتی دانلود/صف در جریان است پیشرفت و وضعیت هر ثانیه به‌روز شود
      _voiceTimer = Timer(const Duration(seconds: 1), () {
        _loadVoices();
        _refresh();
      });
    }
  }

  void _toggleOpen() {
    setState(() => _open = !_open);
    if (_open) {
      _loadVoices();
      // ⚡ موتورِ این زبان همین حالا (پس‌زمینه) لود و گرم شود تا «تست صدا» بدون تأخیر شروع شود
      unawaited(NativeTtsBridge.preload(lang: widget.code));
    } else if (_dlVoice.isEmpty && _queue.isEmpty) {
      _voiceTimer?.cancel();
    }
  }

  Future<void> _voiceDownload(String id) async {
    // اگر دانلودِ دیگری در جریان است، این صدا در صف می‌رود
    if (_dlVoice.isNotEmpty || _queue.isNotEmpty) {
      if (_dlVoice == id || _queue.contains(id)) return;
      setState(() {
        _queue.add(id);
        _batch++;
      });
      _voiceTimer?.cancel();
      _voiceTimer = Timer(const Duration(seconds: 1), _loadVoices);
      return;
    }
    _batch = 1;
    for (final v in _voices) {
      if (v['active'] == true && v['downloaded'] == true) {
        _restoreVoice = '${v['id']}';
      }
    }
    await _startVoiceDownload(id);
  }

  Future<void> _startVoiceDownload(String id) async {
    try {
      await NativeBridge.instance.downloadTtsModel(lang: widget.code, voice: id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.settings_sync_download_failed)),
        );
      }
    }
    await _loadVoices();
    await _refresh();
  }

  Future<void> _voiceSelect(String id) async {
    try {
      await NativeBridge.instance.setTtsVoice(lang: widget.code, voice: id);
    } catch (_) {}
    await _loadVoices();
    await _refresh();
  }

  Future<void> _voiceDelete(String id) async {
    final ml = MaterialLocalizations.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => _dirDialog(ctx, AlertDialog(
        content: Text(context.l10n.settings_tts_delete_confirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ml.cancelButtonLabel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ml.deleteButtonTooltip)),
        ],
      )),
    );
    if (yes != true) return;
    try {
      await NativeBridge.instance.deleteTtsModel(lang: widget.code, voice: id);
    } catch (_) {}
    await _loadVoices();
    await _refresh();
  }

  Future<void> _endTest() async {
    _testSub?.cancel();
    _testSub = null;
    _testTimer?.cancel();
    _testTimer = null;
    final r = _testRestore;
    _testRestore = null;
    if (r != null && r.isNotEmpty) {
      try {
        await NativeBridge.instance.setTtsVoice(lang: widget.code, voice: r);
      } catch (_) {}
    }
    if (mounted) {
      setState(() => _testing = '');
    } else {
      _testing = '';
    }
  }

  /// پخشِ یک جمله‌ی نمونه با همین صدا؛ بعد از تست صدای فعالِ قبلی دست‌نخورده برمی‌گردد.
  Future<void> _voiceTest(String id, bool active) async {
    if (_testBusy) return;
    _testBusy = true;
    try {
      if (_testing.isNotEmpty) {
        await NativeTtsBridge.stop();
        await _endTest();
        return;
      }
      setState(() => _testing = id);
      if (!active) {
        for (final v in _voices) {
          if (v['active'] == true && v['downloaded'] == true) {
            _testRestore = '${v['id']}';
          }
        }
        await NativeBridge.instance.setTtsVoice(lang: widget.code, voice: id);
      }
      final tid = 'voice-test-${DateTime.now().microsecondsSinceEpoch}';
      _testSub = NativeBridge.instance.on('ttsSpeakDone').listen((d) {
        if ('${d['id'] ?? ''}' == tid) _endTest();
      });
      _testTimer = Timer(const Duration(seconds: 40), _endTest);
      final ok = await NativeTtsBridge.speak(
        _kVoiceSample[widget.code] ?? _kVoiceSample['en']!,
        widget.code,
        1.0,
        id: tid,
      );
      if (!ok) await _endTest();
    } catch (_) {
      await _endTest();
    } finally {
      _testBusy = false;
    }
  }

  Widget _voiceRow(BuildContext context, Map<String, dynamic> v) {
    final c = context.appColors;
    final id = '${v['id']}';
    final downloaded = v['downloaded'] == true;
    final active = v['active'] == true;
    final downloading = v['downloading'] == true;
    final isDefault = v['isDefault'] == true;
    final label = '${v['label'] ?? id}${isDefault ? ' (پیش‌فرض)' : ''}';

    Widget action;
    if (downloading) {
      final bytes = (_st?['bytes'] as num?) ?? 0;
      final total = (_st?['total'] as num?) ?? 0;
      final pct = total > 0 ? (bytes / total * 100).clamp(0, 100).round() : null;
      action = _pill(context, '⏹ ${pct != null ? '$pct%' : 'توقف'}', _cancel);
    } else if (_queue.contains(id)) {
      action = _pill(context, '⏳ در صف', () {
        setState(() {
          _queue.remove(id);
          if (_batch > 0) _batch--;
        });
      });
    } else if (downloaded && active) {
      action = _pill(context, '✅ فعال', null);
    } else if (downloaded) {
      action = _pill(context, 'انتخاب', () => _voiceSelect(id));
    } else {
      action = _pill(context, '📥 دانلود', () => _voiceDownload(id));
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.start,
                style: TextStyle(
                    color: c.ink,
                    fontSize: 12.5,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w500)),
          ),
          const SizedBox(width: 6),
          if (downloaded && !downloading)
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _voiceTest(id, active),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                    _testing == id
                        ? Icons.stop_circle_outlined
                        : Icons.play_circle_outline,
                    size: 22,
                    color: c.ink),
              ),
            ),
          action,
          if (downloaded && !downloading)
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _voiceDelete(id),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.delete_outline, size: 18, color: c.inkSoft),
              ),
            ),
        ],
      ),
    );
  }

  bool get _downloading => _st?['downloading'] == true;
  bool get _downloaded => _st?['downloaded'] == true;

  Future<void> _refresh() async {
    final st = await LinLearnBridge.packStatus(widget.kind, widget.code);
    if (!mounted) return;
    setState(() => _st = st);
    _timer?.cancel();
    if (_downloading) {
      _timer = Timer(const Duration(seconds: 1), _refresh);
    }
  }

  Future<void> _download() async {
    final ok = await LinLearnBridge.packDownload(widget.kind, widget.code);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.settings_sync_download_failed)),
      );
    }
    await _refresh();
  }

  Future<void> _cancel() async {
    if (_queue.isNotEmpty) setState(_queue.clear); // توقف = کلِ صف هم لغو شود
    await LinLearnBridge.packCancel(widget.kind, widget.code);
    await _refresh();
  }

  Future<void> _delete() async {
    final ml = MaterialLocalizations.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => _dirDialog(ctx, AlertDialog(
        content: Text(widget.kind == 'tts'
            ? context.l10n.settings_tts_delete_confirm
            : context.l10n.st_pack_delete_confirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ml.cancelButtonLabel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ml.deleteButtonTooltip)),
        ],
      )),
    );
    if (yes != true) return;
    await LinLearnBridge.packDelete(widget.kind, widget.code);
    await _refresh();
  }

  Widget _pill(BuildContext context, String text, VoidCallback? onTap) {
    final c = context.appColors;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.7),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.cardBorder),
        ),
        child: Text(text,
            style: TextStyle(
                color: c.ink, fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final L = context.l10n;

    Widget trailing;
    if (widget.phoneOnly) {
      trailing = Text(L.settings_tts_phone_only,
          style: TextStyle(color: c.inkSoft, fontSize: 11.5));
    } else if (_downloading) {
      final bytes = (_st?['bytes'] as num?) ?? 0;
      final total = (_st?['total'] as num?) ?? 0;
      final pct = total > 0 ? (bytes / total * 100).clamp(0, 100).round() : null;
      trailing = _pill(
        context,
        '⏹ ${pct != null ? '$pct%' : L.settings_stop}',
        _cancel,
      );
    } else if (_downloaded) {
      trailing = _pill(context, '✅ ${L.settings_tts_offline}', _delete);
    } else {
      trailing = _pill(context, '📥 ${L.settings_download}', _download);
    }

    final head = Row(
      children: [
        Expanded(
          child: _hasVoices
              ? InkWell(
                  onTap: _toggleOpen,
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(widget.label,
                            style: TextStyle(
                                color: c.ink,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                      ),
                      Icon(_open ? Icons.expand_less : Icons.expand_more,
                          size: 20, color: c.inkSoft),
                    ],
                  ),
                )
              : Text(widget.label,
                  style: TextStyle(
                      color: c.ink, fontSize: 13, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 8),
        trailing,
      ],
    );

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.cardBorder),
      ),
      child: _hasVoices && _open
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                head,
                const SizedBox(height: 4),
                Text('صداهای بیشتر (چند صدا را پشت‌سرهم بزن؛ در صف قرار می‌گیرند و یکی‌یکی دانلود می‌شوند)',
                    style: TextStyle(color: c.inkSoft, fontSize: 11.5)),
                if (_voices.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('...',
                        style: TextStyle(color: c.inkSoft, fontSize: 12)),
                  )
                else
                  for (final v in _voices) _voiceRow(context, v),
              ],
            )
          : head,
    );
  }
}


// ═══════════════════════════════════════════════════════════════════
// 📦 بسته‌های آفلاین — همه‌ی بسته‌های تشخیص گفتار در یک برگه‌ی واحد
//   • بسته‌ی چندزبانه (سریع / متعادل / دقیق‌تر): زبان‌های بدون بسته‌ی اختصاصی،
//     حالت آهنگ و همگام‌سازی متن و صوت — فقط یک بار دانلود می‌شود.
//   • بسته‌های سریعِ تک‌زبانه (اختیاری) برای چند زبان.
// ═══════════════════════════════════════════════════════════════════

/// زبان‌هایی که بسته‌ی اختصاصیِ تک‌زبانه دارند (باید با SherpaModelManager.SPECS یکی باشد).
const List<String> kDedicatedPackLangs = [
  'en', 'es', 'fr', 'de', 'ru', 'zh', 'ko',
];

/// نام زبان‌ها به خطِ خودشان
const Map<String, String> _kPackLangNames = {
  'en': 'English',
  'es': 'Español',
  'fr': 'Français',
  'de': 'Deutsch',
  'ru': 'Русский',
  'zh': '中文',
  'ko': '한국어',
};

/// کیفیتِ بسته‌ی چندزبانه → شناسه‌ی بسته روی گوشی (tiny / base / small)
const Map<String, String> kMultiPackId = {
  'fast': 'tiny',
  'balanced': 'base',
  'accurate': 'small',
};
const Map<String, int> _kMultiPackMb = {
  'fast': 100,
  'balanced': 160,
  'accurate': 360,
};
const List<String> _kMultiTiers = ['fast', 'balanced', 'accurate'];
const String kSongQualityKey = 'phrasebook-song-quality';

/// آیا هر کدام از بسته‌های چندزبانه روی گوشی هست؟ (null = پشتیبانی نمی‌شود)
Future<bool?> anyMultiPackReady() async {
  for (final id in kMultiPackId.values) {
    final st = await LinLearnBridge.packStatus('song', id);
    if (st == null) return null;
    if (st['downloaded'] == true) return true;
  }
  return false;
}

/// کاشیِ بسته‌ی «زبان صدا» در ترجمه‌ی زنده:
///  • زبان با بسته‌ی اختصاصی ← همان بسته
///  • بقیه‌ی زبان‌ها ← بسته‌ی چندزبانه (اگر هیچ‌کدام نباشد، دکمه‌ی دانلود)
class LangPackTile extends StatefulWidget {
  final String lang;
  const LangPackTile({super.key, required this.lang});

  @override
  State<LangPackTile> createState() => _LangPackTileState();
}

class _LangPackTileState extends State<LangPackTile> {
  bool? _ready;
  Timer? _timer;

  bool get _dedicated => kDedicatedPackLangs.contains(widget.lang);

  @override
  void initState() {
    super.initState();
    if (!_dedicated) {
      _poll();
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    final v = await anyMultiPackReady();
    if (!mounted) return;
    if (v != _ready) setState(() => _ready = v);
  }

  @override
  Widget build(BuildContext context) {
    if (_dedicated) {
      return PackTile(
        key: ValueKey('lp-ded-${widget.lang}'),
        kind: 'speech',
        id: widget.lang,
        title: '',
        bare: true,
        approxMb: 70,
      );
    }
    final c = context.appColors;
    final L = context.l10n;
    if (_ready == true) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(L.packs_multi_ready,
                  style: TextStyle(color: c.inkSoft, fontSize: 11.5)),
            ),
            TextButton(
              onPressed: () => OfflinePacksSheet.show(context),
              child: Text(L.packs_manage,
                  style: TextStyle(
                      color: c.ink,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(L.packs_multi_desc,
              style: TextStyle(color: c.inkSoft, fontSize: 11.5, height: 1.7)),
        ),
        PackTile(
          key: const ValueKey('lp-multi-base'),
          kind: 'song',
          id: 'base',
          title: '',
          bare: true,
          filled: true,
          approxMb: 160,
        ),
      ],
    );
  }
}

/// برگه‌ی «بسته‌های آفلاین» (جمع‌وجور؛ نه تمام‌صفحه)
class OfflinePacksSheet extends ConsumerStatefulWidget {
  const OfflinePacksSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => Directionality(
          textDirection: uiContentDirection(ctx),
          child: const OfflinePacksSheet(),
        ),
      );

  @override
  ConsumerState<OfflinePacksSheet> createState() => _OfflinePacksSheetState();
}

class _OfflinePacksSheetState extends ConsumerState<OfflinePacksSheet> {
  late String _tier;

  @override
  void initState() {
    super.initState();
    final v = ref.read(sharedPrefsProvider).getString(kSongQualityKey);
    _tier = _kMultiTiers.contains(v) ? v! : 'balanced';
  }

  String _name(AppLocalizations L, String t) {
    switch (t) {
      case 'fast':
        return L.settings_song_model_fast;
      case 'accurate':
        return L.settings_song_model_accurate;
      default:
        return L.settings_song_model_balanced;
    }
  }

  String _hint(AppLocalizations L, String t) {
    switch (t) {
      case 'fast':
        return L.settings_song_hint_fast;
      case 'accurate':
        return L.settings_song_hint_accurate;
      default:
        return L.settings_song_hint_balanced;
    }
  }

  Widget _card(BuildContext context, {required List<Widget> children}) {
    final c = context.appColors;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _tierChip(BuildContext context, String t) {
    final c = context.appColors;
    final L = context.l10n;
    final sel = _tier == t;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() => _tier = t);
          ref.read(sharedPrefsProvider).setString(kSongQualityKey, t);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
          decoration: BoxDecoration(
            color: sel ? c.goldSoft : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: sel ? c.gold : c.cardBorder, width: sel ? 2 : 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t == 'balanced'
                    ? '${_name(L, t)} ★'
                    : _name(L, t),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: c.ink, fontSize: 12.5, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                '~${_kMultiPackMb[t]}MB',
                textDirection: TextDirection.ltr,
                style: TextStyle(color: c.inkSoft, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final L = context.l10n;
    final body = TextStyle(color: c.ink, fontSize: 12, height: 1.7);
    final note = TextStyle(color: c.inkSoft, fontSize: 11.5, height: 1.7);
    final title = TextStyle(
        color: c.ink, fontSize: 13.5, fontWeight: FontWeight.w800);
    final wid = kMultiPackId[_tier]!;
    final name = _name(L, _tier);
    final mb = _kMultiPackMb[_tier]!;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      builder: (ctx, scroll) => Container(
        decoration: BoxDecoration(
          color: c.paper,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: c.cardBorder,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 6, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text('📦 ${L.packs_hub_title}',
                        style: TextStyle(
                            color: c.ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: c.inkSoft),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                children: [
                  // ── بسته‌ی چندزبانه ──
                  _card(context, children: [
                    Text(L.packs_multi_title, style: title),
                    const SizedBox(height: 4),
                    Text(L.packs_multi_desc, style: note),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        for (var i = 0; i < _kMultiTiers.length; i++) ...[
                          if (i > 0) const SizedBox(width: 6),
                          _tierChip(context, _kMultiTiers[i]),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(_hint(L, _tier), style: note),
                    PackTile(
                      key: ValueKey('hub-multi-$wid'),
                      kind: 'song',
                      id: wid,
                      title: '',
                      bare: true,
                      filled: true,
                      approxMb: mb,
                      toggleTitle: L.settings_song_use,
                      downloadLabel: (m) => L.settings_song_download(name, '$m'),
                      resumeLabel: (have, m) =>
                          L.settings_song_resume(name, have, '$m'),
                    ),
                    Theme(
                      data: Theme.of(context)
                          .copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: const EdgeInsets.only(bottom: 4),
                        expandedCrossAxisAlignment: CrossAxisAlignment.start,
                        title: Text(L.settings_stt_when_to_use,
                            style: TextStyle(
                                color: c.ink,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700)),
                        children: [
                          Text(L.settings_song_intro, style: body),
                          const SizedBox(height: 8),
                          Text('✅ ${L.settings_song_on_title}',
                              style: const TextStyle(
                                  color: Color(0xFF2E7D32),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800)),
                          Text(L.settings_song_on_list, style: body),
                          const SizedBox(height: 8),
                          Text('⛔ ${L.settings_song_off_title}',
                              style: const TextStyle(
                                  color: Color(0xFFB3261E),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800)),
                          Text(L.settings_song_off_list, style: body),
                          const SizedBox(height: 8),
                          Text(L.settings_song_on_note, style: body),
                        ],
                      ),
                    ),
                  ]),
                  // ── بسته‌های تک‌زبانه ──
                  _card(context, children: [
                    Text(L.packs_lang_title, style: title),
                    const SizedBox(height: 4),
                    Text(L.packs_lang_desc, style: note),
                    for (final code in kDedicatedPackLangs)
                      TtsPackRow(
                        key: ValueKey('hub-lang-$code'),
                        kind: 'speech',
                        code: code,
                        label: _kPackLangNames[code] ?? code.toUpperCase(),
                      ),
                  ]),
                ],
              ),
            ),
          ],
        ),
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
        builder: (ctx) => Directionality(
          textDirection: uiContentDirection(ctx),
          child: const OfflineWordsDialog(),
        ),
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

  static const String _cachePrefix = 'tr3::';

  @override
  void initState() {
    super.initState();
    _load();
  }

  int _countCached() => ref
      .read(sharedPrefsProvider)
      .getKeys()
      .where((k) => k.startsWith(_cachePrefix))
      .length;

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

  static String _size(BuildContext context, int bytes) {
    final kb = bytes / 1024;
    if (kb < 1024) {
      return context.l10n
          .st_unit_kb('${kb < 10 ? kb.toStringAsFixed(1) : kb.round()}');
    }
    return context.l10n.st_unit_mb((kb / 1024).toStringAsFixed(1));
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
        // لغت‌ها خودشان انگلیسی‌اند؛ برای «انگلیسی» ترجمه‌ای لازم نیست (آماده است).
        if (lang == 'en') {
          _done++;
          if (mounted && _done % 5 == 0) setState(() {});
          continue;
        }
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
    final langs = kSupportedLanguages.toList(); // انگلیسی هم هست

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
                    child: Text(context.l10n.wd_title,
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
                context.l10n.wd_intro('${_words.length}'),
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
                          child: Text(langDisplayName(context, l.code),
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
                    child: Text(_selected.isNotEmpty
                        ? context.l10n
                            .wd_start_n('${_words.length * _selected.length}')
                        : context.l10n.wd_start),
                  ),
                ),
                if (_cached > 0) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                        context.l10n.wd_cached('$_cached'),
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
                Text(
                    context.l10n.wd_progress('$_done', '$_total', '$pct',
                        _size(context, _bytes)),
                    style: note),
                if (_failed > 0)
                  Text(context.l10n.wd_pending('$_failed'),
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
                    child: Text(context.l10n.wd_cancel,
                        style: TextStyle(color: c.rose)),
                  ),
                ),
              ],
              if (_finished) ...[
                Center(
                  child: Column(
                    children: [
                      Text(context.l10n.wd_done,
                          style: TextStyle(
                              color: c.ink,
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(
                          context.l10n.wd_done_body('$_cached'),
                          style: note,
                          textAlign: TextAlign.center),
                      if (_failed > 0)
                        Text(
                            context.l10n.wd_failed('$_failed'),
                            style: note.copyWith(color: c.rose, fontSize: 11),
                            textAlign: TextAlign.center),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => Navigator.pop(context),
                          style: FilledButton.styleFrom(backgroundColor: c.ink),
                          child: Text(context.l10n.wd_ok),
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

/// دیالوگ‌های تنظیمات هم طبقِ زبانِ رابط جهت می‌گیرند.
Widget _dirDialog(BuildContext ctx, Widget child) =>
    Directionality(textDirection: uiContentDirection(ctx), child: child);
