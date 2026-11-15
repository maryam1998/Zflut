import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_prefs_provider.dart';
import '../../core/theme/app_theme_colors.dart';

// ═══════════════════════════════════════════════════════════════════
// «ببین چطور کار می‌کند» — نمونه‌ی آماده‌ی چت و ویدیو کال برای کاربرِ رایگان.
// کاملاً ثابت و بدونِ AI، اینترنت یا سهمیه؛ پس هیچ‌وقت به‌خاطرِ خرابیِ سرویس
// تجربه‌ی اولِ کاربر خراب نمی‌شود. متنِ گفتگو انگلیسی است؛ در رابطِ فارسی زیرِ
// هر جمله ترجمه‌اش هم می‌آید.
// ═══════════════════════════════════════════════════════════════════

class _Line {
  final String kind; // coach | user | fix
  final String en;
  final String fa;
  final String from;
  final String to;
  final String noteEn;
  final String noteFa;
  const _Line.say(this.kind, this.en, this.fa)
      : from = '',
        to = '',
        noteEn = '',
        noteFa = '';
  const _Line.fix(this.from, this.to, this.noteEn, this.noteFa)
      : kind = 'fix',
        en = '',
        fa = '';
}

const List<_Line> _kChatLines = [
  _Line.say('coach', 'Hi! How was your day?', 'سلام! امروزت چطور گذشت؟'),
  _Line.say('user', 'Yesterday I go to the park with my friend.',
      'دیروز با دوستم رفتم پارک.'),
  _Line.fix('Yesterday I go to the park', 'Yesterday I went to the park',
      'It happened in the past, so “go” becomes “went”.',
      'کار مربوط به گذشته است، پس go می‌شود went.'),
  _Line.say(
      'coach',
      'Sounds fun! What did you two do there?',
      'چه باحال! اونجا چیکار کردین؟'),
  _Line.say('user', 'We played football and drink coffee.',
      'فوتبال بازی کردیم و قهوه خوردیم.'),
  _Line.fix('drink coffee', 'drank coffee',
      'Past tense again: drink → drank.', 'باز هم گذشته: drink ← drank.'),
  _Line.say('coach', 'What a great day! Did your team win?',
      'چه روز خوبی! تیمتون برد؟'),
];

const List<_Line> _kCallLines = [
  _Line.say('coach', 'Hi! Great to see you. What did you do today?',
      'سلام! خوشحالم می‌بینمت. امروز چیکار کردی؟'),
  _Line.say('user', 'I go to the market and buy some fruit.',
      'رفتم بازار و کمی میوه خریدم.'),
  _Line.say(
      'coach',
      'Nice! Just a tiny thing — we say, “I went to the market and bought some fruit.” What fruit did you get?',
      'عالیه! فقط یه نکته‌ی کوچیک — می‌گیم: «I went to the market and bought some fruit.» چه میوه‌ای گرفتی؟'),
  _Line.say('user', 'I bought apples and oranges.',
      'سیب و پرتقال خریدم.'),
  _Line.say('coach', 'Perfect! That sentence was spot on.',
      'عالی! این جمله کاملاً درست بود.'),
];

Future<void> showAiDemoSheet(BuildContext context, {bool call = false}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AiDemoSheet(startWithCall: call),
  );
}

class _AiDemoSheet extends ConsumerStatefulWidget {
  final bool startWithCall;
  const _AiDemoSheet({required this.startWithCall});

  @override
  ConsumerState<_AiDemoSheet> createState() => _AiDemoSheetState();
}

class _AiDemoSheetState extends ConsumerState<_AiDemoSheet> {
  late bool _call = widget.startWithCall;
  Timer? _timer;
  Timer? _clock;
  int _shown = 0;
  int _secs = 0;

  List<_Line> get _lines => _call ? _kCallLines : _kChatLines;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  void _start() {
    _timer?.cancel();
    _clock?.cancel();
    _shown = 0;
    _secs = 0;
    _timer = Timer.periodic(Duration(milliseconds: _call ? 2800 : 1800), (t) {
      if (!mounted || _shown >= _lines.length) {
        t.cancel();
        _clock?.cancel();
        return;
      }
      setState(() => _shown++);
    });
    if (_call) {
      _clock = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted || _shown >= _lines.length) {
          t.cancel();
          return;
        }
        setState(() => _secs++);
      });
    }
  }

  void _restart({bool? call}) {
    setState(() {
      if (call != null) _call = call;
      _start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final fa = ref.watch(appPrefsProvider).uiLang == 'fa';
    final visible = _lines.take(_shown + 1 > _lines.length ? _lines.length : _shown + 1).toList();
    final done = _shown >= _lines.length - 1;

    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
      decoration: BoxDecoration(
        color: c.paper,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                  color: c.cardBorder, borderRadius: BorderRadius.circular(4)),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  fa ? 'ببین چطور کار می‌کند' : 'See how it works',
                  style: TextStyle(
                      color: c.ink, fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: Icon(Icons.close_rounded, color: c.inkSoft),
              ),
            ],
          ),
          Text(
            fa
                ? 'یک نمایشِ آماده؛ همین‌طوری با مربیِ هوشمند گفتگو می‌کنی و اشتباهاتت را همان لحظه می‌بینی.'
                : 'A ready-made preview: this is how you chat with your smart coach and see your mistakes on the spot.',
            style: TextStyle(color: c.inkSoft, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              ChoiceChip(
                label: Text(fa ? 'چت' : 'Chat'),
                selected: !_call,
                onSelected: (_) => _restart(call: false),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: Text(fa ? 'ویدیو کال' : 'Video call'),
                selected: _call,
                onSelected: (_) => _restart(call: true),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_call) _callHeader(c, fa, visible.isEmpty ? null : visible.last),
          Flexible(
            child: Container(
              decoration: BoxDecoration(
                color: c.paperDark,
                borderRadius: BorderRadius.circular(18),
              ),
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                reverse: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final l in visible) _lineWidget(c, fa, l),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (done)
            Center(
              child: TextButton.icon(
                onPressed: () => _restart(),
                icon: const Icon(Icons.replay_rounded, size: 18),
                label: Text(fa ? 'پخش دوباره' : 'Replay'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _callHeader(AppThemeColorsExt c, bool fa, _Line? last) {
    final coachSpeaking = last != null && last.kind == 'coach';
    final mm = (_secs ~/ 60).toString().padLeft(2, '0');
    final ss = (_secs % 60).toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: c.teal,
            child: const Icon(Icons.person_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fa ? 'مربی' : 'Coach',
                    style: TextStyle(
                        color: c.ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 15)),
                Row(
                  children: [
                    Icon(coachSpeaking ? Icons.graphic_eq_rounded : Icons.mic_rounded,
                        size: 16, color: c.teal),
                    const SizedBox(width: 4),
                    Text(
                      coachSpeaking
                          ? (fa ? 'در حال صحبت…' : 'Speaking…')
                          : (fa ? 'نوبتِ توست' : 'Your turn'),
                      style: TextStyle(color: c.inkSoft, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Text('$mm:$ss',
              style: TextStyle(
                  color: c.inkSoft,
                  fontSize: 14,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }

  Widget _lineWidget(AppThemeColorsExt c, bool fa, _Line l) {
    if (l.kind == 'fix') return _fixCard(c, fa, l);
    final isUser = l.kind == 'user';
    final bg = isUser ? c.teal : c.surface;
    final fg = isUser ? Colors.white : c.ink;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.74),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: isUser ? null : Border.all(color: c.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(l.en,
                  style: TextStyle(color: fg, fontSize: 15, height: 1.4)),
            ),
            if (fa) ...[
              const SizedBox(height: 4),
              Directionality(
                textDirection: TextDirection.rtl,
                child: Text(l.fa,
                    style: TextStyle(
                        color: fg.withOpacity(0.75), fontSize: 12.5, height: 1.4)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _fixCard(AppThemeColorsExt c, bool fa, _Line l) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.gold.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.auto_fix_high_rounded, size: 16, color: c.gold),
              const SizedBox(width: 6),
              Text(fa ? 'اصلاح' : 'Correction',
                  style: TextStyle(
                      color: c.gold, fontWeight: FontWeight.w800, fontSize: 12.5)),
            ],
          ),
          const SizedBox(height: 6),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(l.from,
                style: TextStyle(
                    color: Colors.red.shade400,
                    decoration: TextDecoration.lineThrough,
                    fontSize: 14)),
          ),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(l.to,
                style: TextStyle(
                    color: Colors.green.shade600,
                    fontWeight: FontWeight.w700,
                    fontSize: 14)),
          ),
          const SizedBox(height: 4),
          Text(fa ? l.noteFa : l.noteEn,
              style: TextStyle(color: c.inkSoft, fontSize: 12.5, height: 1.4)),
        ],
      ),
    );
  }
}
