import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/speech_provider.dart' show speechControllerProvider;
import '../../core/theme/app_theme_colors.dart';
import '../../core/tts/speech_controller.dart' show SpeechController;
import '../../core/tts/speech_state.dart';

/// 🎧 تمرین درک شنیداری (Primary School ▸ A2)
/// یک متن کوتاه انگلیسی را گوش می‌دهی (صدای خودِ اپ)، بعد به سؤال‌های چهارگزینه‌ای جواب می‌دهی.
/// متن و ترجمه‌ی فارسی بعد از جواب دادن باز می‌شود تا ببینی کجا را اشتباه شنیده‌ای.
/// داده: assets/data/primary_a2_listening.json — بدونِ نیاز به اینترنت/AI (به‌جز صدای TTS).
class _LQuestion {
  final String en;
  final String fa;
  final List<String> options;
  final int answer;
  final String why;
  const _LQuestion(this.en, this.fa, this.options, this.answer, this.why);
}

class _LClip {
  final String title;
  final String titleFa;
  final String text;
  final String fa;
  final List<_LQuestion> questions;
  const _LClip(this.title, this.titleFa, this.text, this.fa, this.questions);
}

class _LSet {
  final String key;
  final String fa;
  final String en;
  final String tip;
  final List<_LClip> clips;
  const _LSet(this.key, this.fa, this.en, this.tip, this.clips);

  int get totalQuestions =>
      clips.fold<int>(0, (a, c) => a + c.questions.length);
}

Future<List<_LSet>> _loadListeningSets() async {
  try {
    final raw =
        await rootBundle.loadString('assets/data/primary_a2_listening.json');
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return [
      for (final s in (j['sets'] as List<dynamic>))
        _LSet(
          (s as Map)['key']?.toString() ?? '',
          s['fa']?.toString() ?? '',
          s['en']?.toString() ?? '',
          s['tip']?.toString() ?? '',
          [
            for (final c in (s['clips'] as List<dynamic>))
              _LClip(
                (c as Map)['title']?.toString() ?? '',
                c['titleFa']?.toString() ?? '',
                c['text']?.toString() ?? '',
                c['fa']?.toString() ?? '',
                [
                  for (final q in (c['questions'] as List<dynamic>))
                    _LQuestion(
                      (q as Map)['en']?.toString() ?? '',
                      q['fa']?.toString() ?? '',
                      [for (final o in (q['options'] as List<dynamic>)) o.toString()],
                      (q['answer'] as num?)?.toInt() ?? 0,
                      q['why']?.toString() ?? '',
                    ),
                ],
              ),
          ],
        ),
    ];
  } catch (_) {
    return const <_LSet>[];
  }
}

const _kGood = Color(0xFF2E9E7B);
const _kBad = Color(0xFFD14B4B);
const _kSlowRate = 0.7;

class ListeningPracticePage extends ConsumerStatefulWidget {
  const ListeningPracticePage({super.key});

  @override
  ConsumerState<ListeningPracticePage> createState() =>
      _ListeningPracticePageState();
}

class _ListeningPracticePageState extends ConsumerState<ListeningPracticePage> {
  List<_LSet>? _sets;
  _LSet? _set;
  int _clip = 0;
  int _q = 0;
  int _score = 0;

  // وضعیتِ سؤالِ فعلی
  final Set<int> _wrong = <int>{};
  bool _solved = false;
  bool _firstTry = true;

  // وضعیتِ متنِ فعلی
  bool _slow = false;
  bool _showScript = false;
  int _plays = 0;

  late final SpeechController _ctl;
  double _prevRate = 1.0;

  @override
  void initState() {
    super.initState();
    _ctl = ref.read(speechControllerProvider.notifier);
    _prevRate = ref.read(speechControllerProvider).rate;
    _loadListeningSets().then((v) {
      if (mounted) setState(() => _sets = v);
    });
  }

  @override
  void dispose() {
    final ctl = _ctl;
    final rate = _prevRate;
    // تغییر state در حین dispose ممکن است خطا بدهد؛ به بعد از فریم می‌اندازیم
    Future<void>.microtask(() async {
      try {
        await ctl.stop();
        await ctl.setRate(rate);
      } catch (_) {}
    });
    super.dispose();
  }

  bool get _isFa {
    final l = Localizations.localeOf(context).languageCode;
    return l == 'fa' || l == 'ar';
  }

  String _t(String fa, String en) => _isFa ? fa : en;

  _LClip get _cur => _set!.clips[_clip];

  Future<void> _stopAudio() async {
    try {
      await _ctl.stop();
    } catch (_) {}
  }

  Future<void> _play() async {
    final text = _cur.text;
    try {
      await _ctl.setRate(_slow ? _kSlowRate : 1.0);
      final st = ref.read(speechControllerProvider);
      final playingThis =
          st.status == SpeechStatus.playing && st.key == 'en-US::$text';
      if (!playingThis) _plays++;
      await _ctl.toggle(text, 'en');
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _toggleSlow() async {
    setState(() => _slow = !_slow);
    // اگر همین الان در حال پخش است، با سرعتِ تازه از اول بخوان
    final st = ref.read(speechControllerProvider);
    if (st.status == SpeechStatus.playing) {
      await _stopAudio();
      await _play();
    } else {
      try {
        await _ctl.setRate(_slow ? _kSlowRate : 1.0);
      } catch (_) {}
    }
  }

  void _resetClipState() {
    _q = 0;
    _wrong.clear();
    _solved = false;
    _firstTry = true;
    _showScript = false;
    _plays = 0;
  }

  void _openSet(_LSet s) {
    unawaited(_stopAudio());
    setState(() {
      _set = s;
      _clip = 0;
      _score = 0;
      _slow = false;
      _resetClipState();
    });
  }

  void _choose(int i) {
    if (_solved) return;
    final q = _cur.questions[_q];
    setState(() {
      if (i == q.answer) {
        _solved = true;
        if (_firstTry) _score++;
      } else {
        _wrong.add(i);
        _firstTry = false;
      }
    });
  }

  bool get _clipDone =>
      _solved && _q + 1 >= _cur.questions.length;

  void _nextQuestion() {
    setState(() {
      _q++;
      _wrong.clear();
      _solved = false;
      _firstTry = true;
    });
  }

  void _nextClip() {
    unawaited(_stopAudio());
    setState(() {
      _clip++;
      if (_clip < _set!.clips.length) _resetClipState();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Scaffold(
      backgroundColor: c.paper,
      appBar: AppBar(
        backgroundColor: c.paper,
        elevation: 0,
        foregroundColor: c.ink,
        title: Text(
          _t('تمرین درک شنیداری', 'Listening Practice'),
          style: TextStyle(
              color: c.ink, fontWeight: FontWeight.w800, fontSize: 17),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (_set != null) {
              unawaited(_stopAudio());
              setState(() => _set = null);
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      body: SafeArea(child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    final c = context.appColors;
    final sets = _sets;
    if (sets == null) {
      return Center(child: CircularProgressIndicator(color: c.gold));
    }
    if (sets.isEmpty) {
      return Center(
        child: Text(_t('تمرینی پیدا نشد', 'No exercises found'),
            style: TextStyle(color: c.inkSoft)),
      );
    }
    if (_set == null) return _setList(context, sets);
    if (_clip >= _set!.clips.length) return _summary(context);
    return _exercise(context);
  }

  // ───────────────────────── لیست مجموعه‌ها ─────────────────────────

  Widget _setList(BuildContext context, List<_LSet> sets) {
    final c = context.appColors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            _t('متن کوتاه را گوش بده و به سؤال‌ها جواب بده. هر چند بار خواستی می‌توانی دوباره بشنوی یا آهسته پخش کنی.',
                'Listen to a short text and answer the questions. Replay as often as you like, or slow it down.'),
            style: TextStyle(color: c.inkSoft, fontSize: 13.5, height: 1.5),
          ),
        ),
        for (final s in sets)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _openSet(s),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.cardBorder),
                ),
                child: Row(
                  children: [
                    Icon(Icons.headphones_rounded, color: c.gold),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_isFa ? s.fa : s.en,
                              style: TextStyle(
                                  color: c.ink,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15)),
                          const SizedBox(height: 2),
                          Text(
                            _isFa
                                ? '${s.en} · ${s.clips.length} متن · ${s.totalQuestions} سؤال'
                                : '${s.clips.length} texts · ${s.totalQuestions} questions',
                            style: TextStyle(color: c.inkSoft, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: c.inkSoft),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ───────────────────────── صفحه‌ی تمرین ─────────────────────────

  Widget _audioCard(BuildContext context) {
    final c = context.appColors;
    final st = ref.watch(speechControllerProvider);
    final playing = st.status == SpeechStatus.playing &&
        st.key == 'en-US::${_cur.text}';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.gold),
      ),
      child: Column(
        children: [
          Text(
            _isFa ? _cur.titleFa : _cur.title,
            style: TextStyle(
                color: c.ink, fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _play,
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.gold,
                boxShadow: [
                  BoxShadow(
                      color: c.gold.withOpacity(0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 4)),
                ],
              ),
              child: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 44,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              FilterChip(
                selected: _slow,
                onSelected: (_) => _toggleSlow(),
                avatar: const Icon(Icons.slow_motion_video_rounded, size: 18),
                label: Text(_t('آهسته', 'Slow')),
              ),
              ActionChip(
                avatar: const Icon(Icons.replay_rounded, size: 18),
                label: Text(_t('از اول', 'Replay')),
                onPressed: () async {
                  await _stopAudio();
                  await _play();
                },
              ),
            ],
          ),
          if (_plays > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _t('$_plays بار پخش شد', 'Played $_plays time${_plays == 1 ? '' : 's'}'),
                style: TextStyle(color: c.inkSoft, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _optionTile(int i, _LQuestion q) {
    final c = context.appColors;
    final isRight = _solved && i == q.answer;
    final isWrong = _wrong.contains(i);
    final tone = isRight ? _kGood : (isWrong ? _kBad : c.gold);
    final filled = isRight || isWrong;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: (_solved || isWrong) ? null : () => _choose(i),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: tone.withOpacity(filled ? 0.14 : 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: filled ? tone : c.cardBorder, width: filled ? 1.4 : 1),
          ),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    q.options[i],
                    style: TextStyle(
                        color: c.ink, fontWeight: FontWeight.w700, fontSize: 15.5),
                  ),
                ),
                if (isRight) const Icon(Icons.check_circle_rounded, color: _kGood),
                if (isWrong) const Icon(Icons.cancel_rounded, color: _kBad),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _scriptCard(BuildContext context) {
    final c = context.appColors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(_cur.text,
                style: TextStyle(
                    color: c.ink, fontSize: 15.5, height: 1.6)),
          ),
          const SizedBox(height: 8),
          Text(
            _cur.fa,
            textDirection: TextDirection.rtl,
            style: TextStyle(
                color: c.translationText, fontSize: 14.5, height: 1.7),
          ),
        ],
      ),
    );
  }

  Widget _exercise(BuildContext context) {
    final c = context.appColors;
    final s = _set!;
    final clip = _cur;
    final q = clip.questions[_q];
    final done = _clipDone;
    final lastClip = _clip + 1 >= s.clips.length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: _clip / s.clips.length,
            minHeight: 6,
            color: c.gold,
            backgroundColor: c.cardBorder,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _t('متن ${_clip + 1} از ${s.clips.length}',
              'Text ${_clip + 1} of ${s.clips.length}'),
          style: TextStyle(color: c.inkSoft, fontSize: 12.5),
        ),
        const SizedBox(height: 10),
        _audioCard(context),
        const SizedBox(height: 14),
        Text(
          _t('سؤال ${_q + 1} از ${clip.questions.length}',
              'Question ${_q + 1} of ${clip.questions.length}'),
          style: TextStyle(color: c.inkSoft, fontSize: 12.5),
        ),
        const SizedBox(height: 6),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text(q.en,
              style: TextStyle(
                  color: c.ink, fontWeight: FontWeight.w800, fontSize: 17)),
        ),
        if (_isFa)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 2),
            child: Text(q.fa,
                textDirection: TextDirection.rtl,
                style: TextStyle(color: c.translationText, fontSize: 13.5)),
          ),
        const SizedBox(height: 10),
        for (var i = 0; i < q.options.length; i++) _optionTile(i, q),
        if (_wrong.isNotEmpty && !_solved)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              _t('درست نیست. دوباره گوش بده و یک گزینه‌ی دیگر را امتحان کن.',
                  'Not quite. Listen again and try another answer.'),
              style: const TextStyle(
                  color: _kBad, fontWeight: FontWeight.w700, fontSize: 13.5),
            ),
          ),
        if (_solved) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              q.why,
              textDirection: _isFa ? TextDirection.rtl : TextDirection.ltr,
              style: TextStyle(color: c.inkSoft, fontSize: 13, height: 1.6),
            ),
          ),
        ],
        if (done || _showScript) ...[
          const SizedBox(height: 4),
          _scriptCard(context),
          const SizedBox(height: 10),
        ] else
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => setState(() => _showScript = true),
              icon: const Icon(Icons.subject_rounded, size: 18),
              label: Text(_t('نمایش متن', 'Show script')),
            ),
          ),
        if (_solved)
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: c.gold),
            onPressed: done ? _nextClip : _nextQuestion,
            child: Text(done
                ? (lastClip ? _t('پایان', 'Finish') : _t('متن بعدی', 'Next text'))
                : _t('سؤال بعدی', 'Next question')),
          ),
      ],
    );
  }

  // ───────────────────────── امتیاز ─────────────────────────

  Widget _summary(BuildContext context) {
    final c = context.appColors;
    final s = _set!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.emoji_events_rounded, size: 56, color: c.gold),
            const SizedBox(height: 12),
            Text('$_score / ${s.totalQuestions}',
                style: TextStyle(
                    color: c.ink, fontSize: 30, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(
              _t('درست در تلاش اول', 'correct on the first try'),
              style: TextStyle(color: c.inkSoft),
            ),
            const SizedBox(height: 10),
            Text(
              s.tip,
              textAlign: TextAlign.center,
              textDirection: _isFa ? TextDirection.rtl : TextDirection.ltr,
              style: TextStyle(color: c.inkSoft, fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: c.gold),
              onPressed: () => _openSet(s),
              child: Text(_t('دوباره', 'Again')),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() => _set = null),
              child: Text(_t('مجموعه‌های دیگر', 'More sets')),
            ),
          ],
        ),
      ),
    );
  }
}
