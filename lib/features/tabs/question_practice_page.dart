import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/theme/app_theme_colors.dart';

/// 🧩 تمرین ساخت سؤال (Primary School ▸ A2)
/// کلمه‌های بهم‌ریخته‌ی یک سؤال انگلیسی را به ترتیب بچین. معنی فارسی بالای صفحه است.
/// داده: assets/data/primary_a2_questions.json — بدونِ نیاز به اینترنت/AI.
class _QItem {
  final String en;
  final String fa;
  const _QItem(this.en, this.fa);
}

class _QSet {
  final String key;
  final String fa;
  final String en;
  final String tip;
  final List<_QItem> items;
  const _QSet(this.key, this.fa, this.en, this.tip, this.items);
}

class _Tile {
  final int id;
  final String text;
  const _Tile(this.id, this.text);
}

Future<List<_QSet>> _loadQuestionSets([String level = 'A2']) async {
  try {
    final raw = await rootBundle.loadString('assets/data/primary_${level.toLowerCase()}_questions.json');
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return [
      for (final s in (j['sets'] as List<dynamic>))
        _QSet(
          (s as Map)['key']?.toString() ?? '',
          s['fa']?.toString() ?? '',
          s['en']?.toString() ?? '',
          s['tip']?.toString() ?? '',
          [
            for (final i in (s['items'] as List<dynamic>))
              _QItem((i as Map)['en']?.toString() ?? '', i['fa']?.toString() ?? ''),
          ],
        ),
    ];
  } catch (_) {
    return const <_QSet>[];
  }
}

class QuestionPracticePage extends StatefulWidget {
  /// 'A1' (Preschool) یا 'A2' (Primary School)
  final String level;
  const QuestionPracticePage({super.key, this.level = 'A2'});

  @override
  State<QuestionPracticePage> createState() => _QuestionPracticePageState();
}

class _QuestionPracticePageState extends State<QuestionPracticePage> {
  List<_QSet>? _sets;
  _QSet? _set;
  int _index = 0;
  int _score = 0;
  bool _firstTry = true;
  bool? _correct; // null = هنوز چک نشده
  List<_Tile> _bank = [];
  List<_Tile> _answer = [];

  @override
  void initState() {
    super.initState();
    _loadQuestionSets(widget.level).then((v) {
      if (mounted) setState(() => _sets = v);
    });
  }

  bool get _isFa {
    final l = Localizations.localeOf(context).languageCode;
    return l == 'fa' || l == 'ar';
  }

  String _t(String fa, String en) => _isFa ? fa : en;

  /// «?» و نقطه‌ی آخر حذف می‌شود؛ فقط کلمه‌ی اول کوچک می‌شود (به‌جز I).
  List<String> _tokens(String en) {
    final words = en
        .replaceAll('?', '')
        .replaceAll('.', '')
        .trim()
        .split(RegExp(r'\s+'));
    if (words.isNotEmpty) {
      final w = words.first;
      if (w != 'I' && !w.startsWith("I'")) {
        words[0] = w[0].toLowerCase() + w.substring(1);
      }
    }
    return words;
  }

  void _startItem() {
    final s = _set!;
    final tokens = _tokens(s.items[_index].en);
    final tiles = [for (var i = 0; i < tokens.length; i++) _Tile(i, tokens[i])];
    final rnd = Random(s.key.hashCode + _index * 31);
    var shuffled = List<_Tile>.of(tiles);
    for (var tries = 0; tries < 12; tries++) {
      shuffled.shuffle(rnd);
      var same = true;
      for (var i = 0; i < tiles.length; i++) {
        if (shuffled[i].id != tiles[i].id) {
          same = false;
          break;
        }
      }
      if (!same || tiles.length < 2) break;
    }
    _bank = shuffled;
    _answer = [];
    _correct = null;
    _firstTry = true;
  }

  void _open(_QSet s) {
    setState(() {
      _set = s;
      _index = 0;
      _score = 0;
      _startItem();
    });
  }

  void _pick(_Tile t) {
    if (_correct == true) return;
    setState(() {
      _bank.remove(t);
      _answer.add(t);
      _correct = null;
    });
  }

  void _unpick(_Tile t) {
    if (_correct == true) return;
    setState(() {
      _answer.remove(t);
      _bank.add(t);
      _correct = null;
    });
  }

  void _reset() {
    setState(() {
      _bank = [..._answer, ..._bank];
      _answer = [];
      _correct = null;
    });
  }

  void _check() {
    final want = _tokens(_set!.items[_index].en).join(' ').toLowerCase();
    final got = _answer.map((e) => e.text).join(' ').toLowerCase();
    final ok = want == got;
    setState(() {
      _correct = ok;
      if (ok && _firstTry) _score++;
      if (!ok) _firstTry = false;
    });
  }

  void _next() {
    setState(() {
      _index++;
      if (_index < _set!.items.length) _startItem();
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
          _t('تمرین ساخت سؤال', 'Build the Question'),
          style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 17),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (_set != null) {
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
    if (_index >= _set!.items.length) return _summary(context);
    return _exercise(context);
  }

  Widget _setList(BuildContext context, List<_QSet> sets) {
    final c = context.appColors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            _t('کلمه‌های بهم‌ریخته را به ترتیب بزن تا سؤال درست ساخته شود.',
                'Tap the scrambled words in the right order to build the question.'),
            style: TextStyle(color: c.inkSoft, fontSize: 13.5, height: 1.5),
          ),
        ),
        for (final s in sets)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _open(s),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.cardBorder),
                ),
                child: Row(
                  children: [
                    Icon(Icons.quiz_rounded, color: c.gold),
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
                            _isFa ? '${s.en} · ${s.items.length} سؤال' : '${s.items.length} questions',
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

  Widget _tile(_Tile t, VoidCallback onTap, {Color? tone}) {
    final c = context.appColors;
    final col = tone ?? c.gold;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: col.withOpacity(0.14),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: col, width: 1.2),
        ),
        child: Text(t.text,
            style: TextStyle(
                color: c.ink, fontWeight: FontWeight.w700, fontSize: 16)),
      ),
    );
  }

  Widget _exercise(BuildContext context) {
    final c = context.appColors;
    final s = _set!;
    final item = s.items[_index];
    final ok = _correct;
    final tone = ok == null
        ? c.gold
        : (ok ? const Color(0xFF2E9E7B) : const Color(0xFFD14B4B));
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: _index / s.items.length,
            minHeight: 6,
            color: c.gold,
            backgroundColor: c.cardBorder,
          ),
        ),
        const SizedBox(height: 6),
        Text('${_index + 1} / ${s.items.length}',
            style: TextStyle(color: c.inkSoft, fontSize: 12.5)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.cardBorder),
          ),
          child: Text(
            item.fa,
            textDirection: TextDirection.rtl,
            style: TextStyle(
                color: c.translationText,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                height: 1.5),
          ),
        ),
        const SizedBox(height: 14),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Container(
            constraints: const BoxConstraints(minHeight: 70),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: tone.withOpacity(0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: tone, width: 1.4),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in _answer) _tile(t, () => _unpick(t), tone: tone),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in _bank) _tile(t, () => _pick(t)),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (ok == true) ...[
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(item.en,
                style: TextStyle(
                    color: const Color(0xFF2E9E7B),
                    fontWeight: FontWeight.w800,
                    fontSize: 17)),
          ),
          const SizedBox(height: 4),
          Text(s.tip,
              textDirection: _isFa ? TextDirection.rtl : TextDirection.ltr,
              style: TextStyle(color: c.inkSoft, fontSize: 13, height: 1.6)),
          const SizedBox(height: 12),
        ],
        if (ok == false) ...[
          Text(_t('درست نیست. دوباره امتحان کن.', 'Not quite. Try again.'),
              style: const TextStyle(
                  color: Color(0xFFD14B4B), fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(s.tip,
              textDirection: _isFa ? TextDirection.rtl : TextDirection.ltr,
              style: TextStyle(color: c.inkSoft, fontSize: 13, height: 1.6)),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            if (ok != true)
              Expanded(
                child: OutlinedButton(
                  onPressed: _answer.isEmpty ? null : _reset,
                  child: Text(_t('پاک کردن', 'Reset')),
                ),
              ),
            if (ok != true) const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: c.gold),
                onPressed: ok == true
                    ? _next
                    : (_bank.isEmpty ? _check : null),
                child: Text(ok == true
                    ? (_index + 1 >= s.items.length
                        ? _t('پایان', 'Finish')
                        : _t('بعدی', 'Next'))
                    : _t('بررسی', 'Check')),
              ),
            ),
          ],
        ),
      ],
    );
  }

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
            Text('$_score / ${s.items.length}',
                style: TextStyle(
                    color: c.ink, fontSize: 30, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(
              _t('درست در تلاش اول', 'correct on the first try'),
              style: TextStyle(color: c.inkSoft),
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: c.gold),
              onPressed: () => _open(s),
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
