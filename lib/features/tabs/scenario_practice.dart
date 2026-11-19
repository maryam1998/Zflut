import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/supported_languages.dart';
import '../../core/models/conversation.dart';
import '../../core/providers/ai_settings_provider.dart';
import '../../core/providers/language_selection_provider.dart';
import '../../core/providers/speech_provider.dart' show speechControllerProvider;
import '../../core/providers/translation_provider.dart';
import '../../core/storage/local_storage.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../core/utils/html_entities.dart';
import 'speaking_call.dart';

// ═══════════════════════════════════════════════════════════════════
// 🎯 «تمرینِ این مکالمه» برای سناریوهای تبِ Talk
//
// دقیقاً همان قابلیت‌هایی که در «تاریخچه‌ی مکالمه با AI» هست، با همان پنلِ
// ویدیو کال (SpeakingCallPanel):
//   • انتخابِ زبانِ تمرین (متنِ اصلی یا هر زبانِ دیگر با ترجمه)
//   • جابجایی نقش‌ها (کاربر خطوطِ «می‌شنوی» را می‌خواند و آواتار «می‌گی» را)
//   • راهنما (💡) = جمله‌ی بعدیِ خودِ کاربر
//   • تماس مجدد / قطع
// جواب‌ها از خودِ سناریو می‌آیند، نه از AI؛ چیزی ذخیره یا تغییر نمی‌کند.
//
// نقش‌ها: speakerA («می‌شنوی») = آواتار (ai) · speakerB («می‌گی») = کاربر (user)
// ═══════════════════════════════════════════════════════════════════

class _Grp {
  final String role; // 'ai' | 'user'
  final List<String> lines;
  _Grp(this.role, this.lines);
}

class _Turn {
  final String user; // نسخه‌ی خامِ جمله‌ی کاربر (چند خط با فاصله چسبیده)
  final _Grp userG;
  final _Grp reply;
  const _Turn(this.user, this.userG, this.reply);
}

class _Pick {
  final String lang;
  final bool swap;
  const _Pick(this.lang, this.swap);
}

class ScenarioPracticeSection extends ConsumerStatefulWidget {
  final ConversationScenario scenario;
  const ScenarioPracticeSection({super.key, required this.scenario});

  @override
  ConsumerState<ScenarioPracticeSection> createState() =>
      _ScenarioPracticeSectionState();
}

class _ScenarioPracticeSectionState
    extends ConsumerState<ScenarioPracticeSection> {
  static const String _srcLang = 'en'; // زبانِ متنِ اصلیِ سناریوها

  bool _mode = false;
  bool _prep = false;
  int _nonce = 0;
  int _k = 0; // تعدادِ نوبت‌هایی که تا حالا جواب داده شده
  String? _lang; // null = متنِ اصلی
  bool _swap = false;
  int _swapP = -1;
  int _swapLast = -1;
  final Map<String, String> _tr = {};
  late AiPersona _persona;

  bool get _fa => Localizations.localeOf(context).languageCode == 'fa';

  // ───────────── ساختنِ گروه‌ها و نوبت‌ها از سناریو ─────────────
  List<_Grp> _groups() {
    final a = widget.scenario.speakerA;
    final b = widget.scenario.speakerB;
    final out = <_Grp>[];
    void add(String role, String text) {
      final t = text.trim();
      if (t.isEmpty) return;
      if (out.isNotEmpty && out.last.role == role) {
        out.last.lines.add(t);
      } else {
        out.add(_Grp(role, [t]));
      }
    }

    final n = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      if (i < a.length) add('ai', a[i].en);
      if (i < b.length) add('user', b[i].en);
    }
    return out;
  }

  String _gText(_Grp g) => g.lines.map(_lineTr).join(' ');

  String _lineTr(String l) => _lang == null ? l : (_tr[l] ?? l);

  /// نوبت‌ها: جمله‌ی کاربر + جوابِ بعدیِ آواتار (اگر جوابی نمانده، دوباره از اول).
  List<_Turn> _turns() {
    final g = _groups();
    final firstAi = g.indexWhere((e) => e.role == 'ai');
    if (firstAi < 0) return const [];
    final out = <_Turn>[];
    for (var i = 0; i < g.length; i++) {
      if (g[i].role != 'user') continue;
      _Grp? reply;
      for (var j = i + 1; j < g.length; j++) {
        if (g[j].role == 'ai') {
          reply = g[j];
          break;
        }
      }
      reply ??= g[firstAi];
      out.add(_Turn(g[i].lines.join(' '), g[i], reply));
    }
    return out;
  }

  bool get _canPractice {
    final g = _groups();
    return g.any((e) => e.role == 'ai') && g.any((e) => e.role == 'user');
  }

  /// سلامِ اول: گروه‌های AI قبل از اولین جمله‌ی کاربر.
  List<String> _greetingLines() {
    final out = <String>[];
    for (final g in _groups()) {
      if (g.role == 'user') break;
      out.addAll(g.lines);
    }
    return out;
  }

  int _swapNext(List<_Grp> g, int from, String role) {
    for (var k = 1; k <= g.length; k++) {
      final i = (from + k) % g.length;
      if (g[i].role == role) return i;
    }
    return -1;
  }

  void _swapReset() {
    _swapLast = -1;
    _swapP = _swapNext(_groups(), -1, 'ai');
  }

  // ───────────── ترجمه ─────────────
  Future<String> _translateLine(String t, String to) async {
    final src = t.trim();
    if (src.isEmpty) return src;
    var r = '';
    try {
      r = decodeHtmlEntities((await ref.read(translationServiceProvider).translate(
              text: src,
              targetLang: to,
              sourceLang: _srcLang,
              aiSettings: ref.read(aiSettingsProvider)))
          .trim());
    } catch (_) {}
    return r.isEmpty ? src : r;
  }

  Future<bool> _prepareTr(String to) async {
    final src = <String>{
      for (final g in _groups()) ...g.lines,
    }.toList();
    final res = await Future.wait([for (final t in src) _translateLine(t, to)]);
    var changed = 0;
    _tr.clear();
    for (var i = 0; i < src.length; i++) {
      _tr[src[i]] = res[i];
      if (res[i].trim() != src[i].trim()) changed++;
    }
    // اگر هیچ‌چیز ترجمه نشد (مثلاً اینترنت قطع است) تمرین شروع نمی‌شود
    return src.isEmpty || changed > 0;
  }

  // ───────────── شروع / پایان ─────────────
  String _enName(String code) {
    for (final l in kSupportedLanguages) {
      if (l.code == code) return l.enLabel;
    }
    return code;
  }

  Future<_Pick?> _pickLang() {
    final c = context.appColors;
    var swap = false;
    final sel = ref.read(languageSelectionProvider);
    final codes = <String>[_srcLang];
    for (final x in [...sel.targets, sel.native]) {
      if (x.isNotEmpty && !codes.contains(x)) codes.add(x);
    }
    for (final l in kSupportedLanguages) {
      if (!codes.contains(l.code)) codes.add(l.code);
    }
    final fa = _fa;
    return showModalBottomSheet<_Pick>(
      context: context,
      backgroundColor: c.paper,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.72),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              children: [
                Text(
                  fa ? 'به کدام زبان تمرین کنی؟' : 'Choose practice language',
                  style: TextStyle(
                      color: c.ink, fontSize: 15, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  fa
                      ? 'همین مکالمه به زبانِ انتخابی پخش می‌شود؛ نوبتِ خودت را هم به همان زبان می‌خوانی.'
                      : 'The same conversation is played in the chosen language, and you read your lines in it too.',
                  style: TextStyle(color: c.inkSoft, fontSize: 12.5),
                ),
                const SizedBox(height: 10),
                // 🔁 جابجایی نقش‌ها
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsetsDirectional.fromSTEB(14, 4, 6, 4),
                  decoration: BoxDecoration(
                    color: swap ? c.goldSoft : c.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: swap ? c.gold : c.cardBorder),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.swap_horiz_rounded, size: 20, color: c.gold),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fa ? 'جابجایی نقش‌ها' : 'Swap roles',
                              style: TextStyle(
                                  color: c.ink,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800),
                            ),
                            Text(
                              fa
                                  ? 'تو نقشِ ${_persona.name} (خطوطِ «می‌شنوی») را می‌خوانی و آواتار جمله‌های «می‌گی» را می‌گوید.'
                                  : 'You read ${_persona.name}\'s lines (You Hear); the avatar says your lines (You Say).',
                              style:
                                  TextStyle(color: c.inkSoft, fontSize: 11.5),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: swap,
                        activeColor: c.gold,
                        onChanged: (v) => setS(() => swap = v),
                      ),
                    ],
                  ),
                ),
                for (final code in codes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: code == _srcLang ? c.goldSoft : c.surface,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.of(ctx).pop(_Pick(code, swap)),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: code == _srcLang
                                    ? c.gold
                                    : c.cardBorder),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  langDisplayName(ctx, code),
                                  style: TextStyle(
                                      color: c.ink,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                              if (code == _srcLang)
                                Text(
                                  fa ? 'متنِ اصلی' : 'Original',
                                  style: TextStyle(
                                      color: c.inkSoft,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _start() async {
    if (!_canPractice || _prep) return;
    _persona = PersonaStore.active(ref.read(localStorageProvider));
    final pick = await _pickLang();
    if (pick == null || !mounted) return;
    final lang = pick.lang == _srcLang ? null : pick.lang;
    if (lang != null) {
      setState(() => _prep = true);
      var ok = false;
      try {
        ok = await _prepareTr(lang);
      } catch (_) {
        ok = false;
      }
      if (!mounted) return;
      setState(() => _prep = false);
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_fa
              ? 'ترجمه انجام نشد؛ اینترنت را بررسی کن و دوباره امتحان کن.'
              : 'Translation failed. Check your connection and try again.'),
        ));
        return;
      }
    } else {
      _tr.clear();
    }
    // پخشِ جاریِ پلیرِ صفحه با صدای آواتار تداخل نکند
    try {
      unawaited(ref.read(speechControllerProvider.notifier).stop());
    } catch (_) {}
    setState(() {
      _lang = lang;
      _swap = pick.swap;
      _swapReset();
      _mode = true;
      _k = 0;
      _nonce++;
    });
  }

  void _end() {
    if (_mode && mounted) setState(() => _mode = false);
  }

  void _redial() {
    if (!mounted) return;
    setState(() {
      _k = 0;
      _swapReset();
      _nonce++;
    });
  }

  // ───────────── کال‌بک‌های پنلِ تماس ─────────────
  Future<String?> _greeting() async {
    if (_swap) {
      // آواتار نقشِ «کاربر» را بازی می‌کند: اگر مکالمه با جمله‌ی کاربر شروع شود، اول او می‌گوید
      final g = _groups();
      if (g.isNotEmpty && g.first.role == 'user') return _gText(g.first);
      return null;
    }
    final lines = _greetingLines();
    if (lines.isEmpty) return null;
    return lines.map(_lineTr).join(' ').trim();
  }

  Future<CallTurn?> _reply(String text, bool retry) async {
    if (_swap) {
      final g = _groups();
      if (g.isEmpty || _swapP < 0) return null;
      if (!(retry && _swapLast >= 0)) {
        _swapLast = _swapNext(g, _swapP, 'user');
        if (_swapLast < 0) return null;
        _swapP = _swapNext(g, _swapLast, 'ai');
      }
      return CallTurn(_gText(g[_swapLast]), <CallFix>[]);
    }
    final ts = _turns();
    if (ts.isEmpty) return null;
    if (!retry) _k++;
    final t = ts[(_k - 1) % ts.length];
    return CallTurn(_gText(t.reply), <CallFix>[]);
  }

  /// 💡 راهنما: جمله‌ی بعدیِ خودِ کاربر از سناریو.
  Future<String?> _hint() async {
    final g = _groups();
    if (_swap) {
      if (g.isEmpty || _swapP < 0 || _swapP >= g.length) return null;
      return _gText(g[_swapP]);
    }
    final ts = _turns();
    if (ts.isEmpty) return null;
    return _gText(ts[_k % ts.length].userG);
  }

  // ───────────── UI ─────────────
  Widget _button(AppThemeColorsExt c) {
    final fa = _fa;
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: c.gold,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      onPressed: (_canPractice && !_prep) ? _start : null,
      icon: _prep
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2.2, color: Colors.white))
          : const Icon(Icons.videocam_rounded, size: 20),
      label: Text(
        _prep
            ? (fa ? 'در حال آماده‌سازی ترجمه…' : 'Preparing translation…')
            : (fa ? 'تمرین این مکالمه' : 'Practice this conversation'),
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _persona = PersonaStore.builtIns.first;
  }

  @override
  Widget build(BuildContext context) {
    if (!_canPractice) return const SizedBox.shrink();
    final c = context.appColors;
    final lang = _lang ?? _srcLang;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: _mode
          ? SpeakingCallPanel(
              key: ValueKey('sc-practice-${widget.scenario.hashCode}-$_nonce'),
              persona: _persona,
              langCode: lang,
              langName: _enName(lang),
              onConnected: _greeting,
              onUserSaid: _reply,
              onEnd: _end,
              onHint: _hint,
              onRedial: _redial,
              // 🎯 بعد از حرفِ AI جمله‌ی بعدیِ کاربر نشان داده می‌شود و ضبط خودکار شروع می‌شود
              autoHint: true,
              practiceMatchRatio: 0.7,
            )
          : _button(c),
    );
  }
}
