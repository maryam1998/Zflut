import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/supported_languages.dart';
import '../../core/practice/practice_follow.dart';
import '../../core/providers/speech_provider.dart' show speechControllerProvider;
import '../../core/storage/local_storage.dart';
import '../../core/theme/app_theme_colors.dart';
import '../tabs/speaking_call.dart';

// ═══════════════════════════════════════════════════════════════════
// 🎙️ «حالتِ تمرین» برای داستان‌ها (داستان‌ساز + داستان‌های ذخیره‌شده)
//
//  • داستانِ مکالمه‌ای: مثلِ تبِ Talk. پاراگراف‌ها نوبتِ دو نفر است؛ AI نفرِ اول،
//    کاربر نفرِ دوم (با «جابجایی نقش‌ها» برعکس).
//  • داستانِ معمولی: جمله‌ها یکی‌یکی در «راهنما» می‌آیند؛ کاربر می‌خواند؛ STT (بدونِ AI)
//    چک می‌کند. درست = جمله‌ی بعدی خودکار؛ غلط = AI همان جمله را درست می‌خواند و می‌رود جلو.
//  • «حالتِ گوش‌دادن» (swap): AI کلِ داستان را می‌خواند؛ بعد می‌پرسد «چند درصدش را فهمیدی؟»؛
//    عددِ کاربر ذخیره می‌شود و مبنای سنجش برای انتخابِ سطح است. رفتن به هر سطحی آزاد است.
// ═══════════════════════════════════════════════════════════════════

const String _kUnderstandKey = 'zflut-story-understanding-v1';
const List<String> _kLevels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

class _It {
  final String role; // 'ai' | 'user'
  final String text;
  final bool ask; // سؤالِ «چند درصد فهمیدی؟»

  /// شناسه‌ی همین جمله/پاراگراف در متنِ داستانِ پایین (برای هایلایت و اسکرول)
  final List<String> ids;
  const _It(this.role, this.text, {this.ask = false, this.ids = const []});
}

class StoryVoicePractice extends ConsumerStatefulWidget {
  final String storyId;
  final String title;

  /// متنِ داستان؛ پاراگراف‌ها با خطِ خالی جدا می‌شوند
  final String text;
  final String langCode;

  /// سطحِ داستان (A1..C2)
  final String level;

  /// داستانِ مکالمه‌ای (دو گوینده)؟
  final bool dialogue;
  final List<String> Function(String) splitSentences;

  /// انتخابِ سطح (بدونِ هیچ محدودیتی). null = انتخابِ سطح نشان داده نمی‌شود.
  final ValueChanged<String>? onLevelUp;

  const StoryVoicePractice({
    super.key,
    required this.storyId,
    required this.title,
    required this.text,
    required this.langCode,
    required this.splitSentences,
    this.level = 'B1',
    this.dialogue = false,
    this.onLevelUp,
  });

  @override
  ConsumerState<StoryVoicePractice> createState() =>
      _StoryVoicePracticeState();
}

class _StoryVoicePracticeState extends ConsumerState<StoryVoicePractice> {
  bool _mode = false;
  int _nonce = 0;
  bool _swap = false;
  late AiPersona _persona;

  List<_It> _items = const [];
  int _i = 0; // نوبتِ بعدی
  int _resumeI = 0; // آخرین نوبتی که شروع شد (برای ادامه بعد از تغییرِ آواتار)
  bool _asking = false;
  CallTurn? _lastTurn;
  int? _pct;

  bool get _fa => Localizations.localeOf(context).languageCode == 'fa';

  // 🎥 ویدیو کال بالای صفحه سنجاق می‌شود + جمله‌ی در حال خواندن در متنِ داستانِ پایین هایلایت/اسکرول می‌شود
  late final ProviderContainer _pc;
  late final PracticeFollow _follow;

  // ⛔ در حالت تمرین دیگر متنِ اصلی نه هایلایت می‌شود و نه خودکار اسکرول می‌کند
  void _hl(_It it) {}

  @override
  void initState() {
    super.initState();
    _persona = PersonaStore.builtIns.first;
    _pc = ProviderScope.containerOf(context, listen: false);
    _follow = PracticeFollow(_pc);
  }

  @override
  void dispose() {
    _follow.clear();
    super.dispose();
  }

  String _enName(String code) {
    for (final l in kSupportedLanguages) {
      if (l.code == code) return l.enLabel;
    }
    return code;
  }

  // ───────────── ساختنِ نوبت‌ها ─────────────
  String _clean(String s) =>
      s.replaceAll('*', '').replaceAll(RegExp(r'\s+'), ' ').trim();

  List<_It> _build(bool swap) {
    final paras = widget.text
        .split(RegExp(r'\n\s*\n'))
        .map(_clean)
        .where((e) => e.isNotEmpty)
        .toList();
    final out = <_It>[];
    // شناسه‌ی جمله‌ها/پاراگراف‌ها مثلِ StoryReaderPanel: '<id>-s<gi>' و '<id>-p<pi>'
    var gi = 0;
    List<String> sentsOf(String p) {
      List<String> ss;
      try {
        ss = widget.splitSentences(p);
      } catch (_) {
        ss = [p];
      }
      return ss.isEmpty ? [p] : ss;
    }

    if (widget.dialogue) {
      for (var k = 0; k < paras.length; k++) {
        final aIsAi = (k % 2 == 0) != swap; // بدونِ swap: نفرِ اول = AI
        final n = sentsOf(paras[k]).length;
        final ids = <String>[
          for (var s = 0; s < n; s++) '${widget.storyId}-s${gi + s}',
          '${widget.storyId}-p$k',
        ];
        gi += n;
        out.add(_It(aIsAi ? 'ai' : 'user', paras[k], ids: ids));
      }
    } else {
      for (var pi = 0; pi < paras.length; pi++) {
        final p = paras[pi];
        for (final x in sentsOf(p)) {
          final t = _clean(x);
          // جمله‌ی بدونِ هیچ حرفی (فقط نشانه‌گذاری) خوانده نمی‌شود
          if (RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(t)) {
            out.add(_It(swap ? 'ai' : 'user', t,
                ids: ['${widget.storyId}-s$gi', '${widget.storyId}-p$pi']));
          }
          gi++;
        }
      }
      if (swap && out.isNotEmpty) {
        out.add(const _It(
            'ai',
            'What percentage of the story do you think you understood? Say or type a number from 0 to 100.',
            ask: true));
      }
    }
    return out;
  }

  bool get _canPractice => widget.text.trim().isNotEmpty;

  // ───────────── شروع / پایان ─────────────
  Future<bool?> _pickSetup() {
    final c = context.appColors;
    final fa = _fa;
    var swap = false;
    final dialogue = widget.dialogue;
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: c.paper,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          Widget choice(bool value, IconData icon, String title, String sub) {
            final on = swap == value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: on ? c.goldSoft : c.surface,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => setS(() => swap = value),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: on ? c.gold : c.cardBorder),
                    ),
                    child: Row(
                      children: [
                        Icon(icon, color: c.gold, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title,
                                  style: TextStyle(
                                      color: c.ink,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w800)),
                              const SizedBox(height: 2),
                              Text(sub,
                                  style: TextStyle(
                                      color: c.inkSoft, fontSize: 11.5)),
                            ],
                          ),
                        ),
                        Icon(
                          on
                              ? Icons.check_circle_rounded
                              : Icons.circle_outlined,
                          color: on ? c.gold : c.inkSoft,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.8),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                children: [
                  PersonaChangeChip(
                    persona: _persona,
                    onTap: () async {
                      await _pickPersona();
                      setS(() {});
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    fa ? 'حالتِ تمرین' : 'Practice mode',
                    style: TextStyle(
                        color: c.ink, fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    dialogue
                        ? (fa
                            ? 'مثلِ تبِ Talk: نوبتِ هر گوینده را می‌خوانید و AI نفرِ دیگر است.'
                            : 'Like the Talk tab: you take one speaker\'s turns and the avatar plays the other.')
                        : (fa
                            ? 'جمله‌ها یکی‌یکی در راهنما می‌آیند؛ AI فقط تلفظِ شما را چک می‌کند.'
                            : 'Sentences appear one by one in the hint; the AI only checks your pronunciation.'),
                    style: TextStyle(color: c.inkSoft, fontSize: 12.5),
                  ),
                  const SizedBox(height: 12),
                  if (dialogue) ...[
                    choice(
                        false,
                        Icons.record_voice_over_rounded,
                        fa ? 'نقشِ دوم را من می‌خوانم' : 'I read the second speaker',
                        fa
                            ? 'آواتار نفرِ اول را می‌گوید.'
                            : 'The avatar says the first speaker\'s lines.'),
                    choice(
                        true,
                        Icons.swap_horiz_rounded,
                        fa ? 'جابجایی نقش‌ها' : 'Swap roles',
                        fa
                            ? 'من نفرِ اول را می‌خوانم و آواتار نفرِ دوم را.'
                            : 'I read the first speaker; the avatar reads the second.'),
                  ] else ...[
                    choice(
                        false,
                        Icons.mic_rounded,
                        fa ? 'من می‌خوانم' : 'I read aloud',
                        fa
                            ? 'هر جمله را بخوان؛ درست بود خودکار جمله‌ی بعد می‌آید.'
                            : 'Read each sentence; correct → the next one appears automatically.'),
                    choice(
                        true,
                        Icons.headphones_rounded,
                        fa ? 'AI می‌خواند، من گوش می‌دهم' : 'AI reads, I listen',
                        fa
                            ? 'آخرش AI می‌پرسد چند درصدش را فهمیدی.'
                            : 'At the end the AI asks what percent you understood.'),
                  ],
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: c.gold,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () => Navigator.of(ctx).pop(swap),
                      icon: const Icon(Icons.videocam_rounded, size: 20),
                      label: Text(
                        fa ? 'شروع تمرین' : 'Start practice',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _pickPersona() async {
    final ls = ref.read(localStorageProvider);
    final picked = await showPersonaSheet(context, ls, _persona.id);
    if (!mounted) return;
    final p = PersonaStore.byId(ls, picked ?? _persona.id);
    PersonaStore.setActive(ls, p.id);
    setState(() {
      _persona = p;
      if (_mode) {
        // تماس با آواتارِ جدید از همان نوبتی که بودیم ادامه می‌یابد
        _i = _resumeI;
        _asking = false;
        _lastTurn = null;
        _nonce++;
      }
    });
  }

  Future<void> _start() async {
    if (!_canPractice) return;
    _persona = PersonaStore.active(ref.read(localStorageProvider));
    final swap = await _pickSetup();
    if (swap == null || !mounted) return;
    try {
      unawaited(ref.read(speechControllerProvider.notifier).stop());
    } catch (_) {}
    setState(() {
      _swap = swap;
      _items = _build(swap);
      _i = 0;
      _resumeI = 0;
      _asking = false;
      _lastTurn = null;
      _pct = null;
      _mode = true;
      _nonce++;
    });
  }

  void _end() {
    _follow.clear();
    if (_mode && mounted) setState(() => _mode = false);
  }

  void _redial() {
    if (!mounted) return;
    _follow.clear();
    setState(() {
      _items = _build(_swap);
      _i = 0;
      _resumeI = 0;
      _asking = false;
      _lastTurn = null;
      _pct = null;
      _nonce++;
    });
  }

  // ───────────── درصدِ فهم ─────────────
  static const Map<String, int> _w = {
    'zero': 0, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5,
    'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10, 'eleven': 11,
    'twelve': 12, 'thirteen': 13, 'fourteen': 14, 'fifteen': 15,
    'sixteen': 16, 'seventeen': 17, 'eighteen': 18, 'nineteen': 19,
    'twenty': 20, 'thirty': 30, 'forty': 40, 'fifty': 50, 'sixty': 60,
    'seventy': 70, 'eighty': 80, 'ninety': 90,
  };

  int? _parsePct(String raw) {
    var s = raw.toLowerCase();
    const fa = '۰۱۲۳۴۵۶۷۸۹';
    const ar = '٠١٢٣٤٥٦٧٨٩';
    for (var k = 0; k < 10; k++) {
      s = s.replaceAll(fa[k], '$k').replaceAll(ar[k], '$k');
    }
    final m = RegExp(r'\d{1,3}').firstMatch(s);
    if (m != null) {
      final n = int.parse(m.group(0)!);
      return n.clamp(0, 100).toInt();
    }
    var total = 0;
    var found = false;
    for (final t in s.split(RegExp(r'[^a-z]+'))) {
      if (t == 'hundred') {
        total = total == 0 ? 100 : total * 100;
        found = true;
      } else if (_w.containsKey(t)) {
        total += _w[t]!;
        found = true;
      }
    }
    return found ? total.clamp(0, 100).toInt() : null;
  }

  List<Map<String, dynamic>> _records() {
    try {
      final raw = ref.read(localStorageProvider).readJson(_kUnderstandKey)['items'];
      if (raw is List) {
        return [
          for (final e in raw)
            if (e is Map) Map<String, dynamic>.from(e)
        ];
      }
    } catch (_) {}
    return [];
  }

  void _saveRecord(int pct) {
    final list = _records()
      ..add({
        'id': widget.storyId,
        'level': widget.level,
        'pct': pct,
        'ts': DateTime.now().toIso8601String(),
      });
    final keep = list.length > 120 ? list.sublist(list.length - 120) : list;
    try {
      unawaited(ref
          .read(localStorageProvider)
          .writeJson(_kUnderstandKey, {'items': keep}));
    } catch (_) {}
  }

  // ───────────── کال‌بک‌های پنلِ تماس ─────────────
  Future<String?> _greeting() async {
    if (_i < _items.length && _items[_i].role == 'ai') {
      _resumeI = _i;
      final it = _items[_i++];
      if (it.ask) _asking = true;
      _hl(it);
      return it.text;
    }
    return null;
  }

  /// نوبتِ بعدیِ AI بدونِ منتظر ماندن برای کاربر (جمله‌ی بعدیِ داستان).
  Future<CallTurn?> _continue() async {
    if (_asking) return null;
    if (_i < _items.length && _items[_i].role == 'ai') {
      _resumeI = _i;
      final it = _items[_i++];
      if (it.ask) _asking = true;
      _hl(it);
      return CallTurn(it.text, <CallFix>[], lang: it.ask ? 'en' : null);
    }
    return null;
  }

  Future<String?> _hint() async {
    if (_asking) return null;
    if (_i < _items.length && _items[_i].role == 'user') {
      _resumeI = _i;
      _hl(_items[_i]);
      return _items[_i].text;
    }
    return null;
  }

  Future<CallTurn?> _reply(String text, bool retry) async {
    // پاسخِ «چند درصد فهمیدی؟»
    if (_asking) {
      final n = _parsePct(text);
      if (n == null) {
        return CallTurn(
            'Sorry, I did not catch a number. Please say or type a number from 0 to 100.',
            <CallFix>[],
            lang: 'en');
      }
      _asking = false;
      _saveRecord(n);
      if (mounted) setState(() => _pct = n);
      return CallTurn(
          'Thank you! You understood about $n percent. You can choose your next level below.',
          <CallFix>[],
          lang: 'en');
    }
    if (retry && _lastTurn != null) return _lastTurn;
    if (_i < _items.length && _items[_i].role == 'user') _i++;
    CallTurn t;
    if (_i < _items.length && _items[_i].role == 'ai') {
      _resumeI = _i;
      final it = _items[_i++];
      _hl(it);
      t = CallTurn(it.text, <CallFix>[]);
    } else if (_i >= _items.length) {
      t = CallTurn('Great job! You finished the story.', <CallFix>[],
          lang: 'en');
    } else {
      t = CallTurn('', <CallFix>[]); // جمله‌ی بعدیِ کاربر: فقط راهنما
    }
    _lastTurn = t;
    return t;
  }

  // ───────────── UI ─────────────
  Widget _button(AppThemeColorsExt c) {
    final fa = _fa;
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: c.gold,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: _canPractice ? _start : null,
        icon: const Icon(Icons.videocam_rounded, size: 20),
        label: Text(
          fa ? 'حالتِ تمرین' : 'Practice mode',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  /// نتیجه‌ی «چند درصد فهمیدی؟» + انتخابِ سطح (بدونِ محدودیت)
  Widget _resultCard(AppThemeColorsExt c) {
    final fa = _fa;
    final pct = _pct!;
    final cur = _kLevels.contains(widget.level) ? widget.level : 'B1';
    final idx = _kLevels.indexOf(cur);
    final next = idx < _kLevels.length - 1 ? _kLevels[idx + 1] : cur;
    final sameLevel = [
      for (final r in _records())
        if (r['level'] == cur) (r['pct'] as num?)?.toInt() ?? 0
    ];
    final recent =
        sameLevel.length > 5 ? sameLevel.sublist(sameLevel.length - 5) : sameLevel;
    final avg = recent.isEmpty
        ? pct
        : (recent.reduce((a, b) => a + b) / recent.length).round();

    String tip;
    if (pct >= 80) {
      tip = fa
          ? 'عالی! بیشترِ داستان را فهمیدی؛ آماده‌ی سطحِ $next هستی.'
          : 'Great! You understood most of it — you look ready for $next.';
    } else if (pct >= 50) {
      tip = fa
          ? 'خوب است. می‌توانی در همین سطح بمانی یا به $next بروی.'
          : 'Good. You can stay at $cur or try $next.';
    } else {
      tip = fa
          ? 'هنوز سخت بود؛ چند داستانِ دیگر در همین سطح (یا آسان‌تر) کمک می‌کند. ولی انتخاب با خودت است.'
          : 'It was still hard — a few more stories at this level (or easier) will help. It\'s your call.';
    }

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_rounded, color: c.gold, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  fa ? 'میزانِ فهمِ تو: $pct٪' : 'Your understanding: $pct%',
                  style: TextStyle(
                      color: c.ink, fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: pct / 100,
              minHeight: 8,
              backgroundColor: c.goldSoft,
              valueColor: AlwaysStoppedAnimation<Color>(c.gold),
            ),
          ),
          const SizedBox(height: 8),
          Text(tip, style: TextStyle(color: c.ink, fontSize: 12.5, height: 1.5)),
          if (recent.length > 1) ...[
            const SizedBox(height: 4),
            Text(
              fa
                  ? 'میانگینِ ${recent.length} داستانِ اخیرِ سطحِ $cur: $avg٪'
                  : 'Average of your last ${recent.length} $cur stories: $avg%',
              style: TextStyle(color: c.inkSoft, fontSize: 11.5),
            ),
          ],
          if (widget.onLevelUp != null) ...[
            const SizedBox(height: 12),
            Text(
              fa
                  ? 'سطحِ داستان‌های بعدی (هر سطحی آزاد است):'
                  : 'Level for your next stories (any level is allowed):',
              style: TextStyle(
                  color: c.inkSoft, fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final lv in _kLevels)
                  ChoiceChip(
                    label: Text(lv == next && lv != cur ? '$lv ★' : lv),
                    selected: lv == cur,
                    selectedColor: c.goldSoft,
                    side: BorderSide(color: lv == cur ? c.gold : c.cardBorder),
                    labelStyle: TextStyle(
                        color: c.ink,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800),
                    onSelected: (_) {
                      widget.onLevelUp!(lv);
                      final m = ScaffoldMessenger.maybeOf(context);
                      m?.hideCurrentSnackBar();
                      m?.showSnackBar(SnackBar(
                        content: Text(fa
                            ? 'داستان‌های بعدی در سطحِ $lv ساخته می‌شوند.'
                            : 'Your next stories will be created at $lv.'),
                      ));
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _panel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PersonaChangeChip(persona: _persona, onTap: _pickPersona),
        const SizedBox(height: 8),
        SpeakingCallPanel(
          key: ValueKey('story-practice-${widget.storyId}-$_nonce'),
          persona: _persona,
          langCode: widget.langCode,
          langName: _enName(widget.langCode),
          onConnected: _greeting,
          onUserSaid: _reply,
          onEnd: _end,
          onHint: _hint,
          onRedial: _redial,
          onAiContinue: _continue,
          autoHint: true,
          practiceMatchRatio: 0.7, // نه خیلی سخت‌گیر، نه خیلی شل
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    // 🎥 ویدیو کال سنجاق نیست؛ کامل داخلِ همین صفحه می‌آید
    if (!_mode) return _button(c);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeepAliveCall(child: _panel()),
        if (_pct != null) _resultCard(c),
      ],
    );
  }
}
