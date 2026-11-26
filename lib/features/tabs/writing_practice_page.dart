import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/theme/app_theme_colors.dart';

/// ✍️ تمرین نوشتن پیام کوتاه و ایمیل (Primary School ▸ A2)
/// موقعیت به فارسی داده می‌شود؛ کاربر پیام انگلیسی را خودش می‌نویسد.
/// «بررسی» یک چک‌لیست نشان می‌دهد (سلام، دلیل، ساعت، ...) بدون AI و بدون اینترنت؛
/// بعد می‌شود جواب نمونه را دید. هیچ نوشته‌ای جایی ذخیره یا فرستاده نمی‌شود.
/// داده: assets/data/primary_a2_writing.json
class _WPoint {
  final String fa;
  final List<RegExp> any;
  const _WPoint(this.fa, this.any);
}

class _WPhrase {
  final String en;
  final String fa;
  const _WPhrase(this.en, this.fa);
}

class _WTask {
  final String kind;
  final String fa;
  final List<_WPoint> points;
  final int minWords;
  final String model;
  final String modelFa;
  final List<_WPhrase> phrases;
  const _WTask(this.kind, this.fa, this.points, this.minWords, this.model,
      this.modelFa, this.phrases);
}

class _WSet {
  final String key;
  final String fa;
  final String en;
  final String tip;
  final List<_WTask> tasks;
  const _WSet(this.key, this.fa, this.en, this.tip, this.tasks);
}

RegExp? _safeRx(String s) {
  try {
    return RegExp(s, caseSensitive: false);
  } catch (_) {
    return null;
  }
}

Future<List<_WSet>> _loadWritingSets([String level = 'A2']) async {
  try {
    final raw =
        await rootBundle.loadString('assets/data/primary_${level.toLowerCase()}_writing.json');
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return [
      for (final s in (j['sets'] as List<dynamic>))
        _WSet(
          (s as Map)['key']?.toString() ?? '',
          s['fa']?.toString() ?? '',
          s['en']?.toString() ?? '',
          s['tip']?.toString() ?? '',
          [
            for (final t in (s['tasks'] as List<dynamic>))
              _WTask(
                (t as Map)['kind']?.toString() ?? 'message',
                t['fa']?.toString() ?? '',
                [
                  for (final p in (t['points'] as List<dynamic>))
                    _WPoint(
                      (p as Map)['fa']?.toString() ?? '',
                      [
                        for (final r in (p['any'] as List<dynamic>))
                          if (_safeRx(r.toString()) != null)
                            _safeRx(r.toString())!,
                      ],
                    ),
                ],
                (t['minWords'] as num?)?.toInt() ?? 10,
                t['model']?.toString() ?? '',
                t['modelFa']?.toString() ?? '',
                [
                  for (final p in (t['phrases'] as List<dynamic>? ?? const []))
                    _WPhrase((p as Map)['en']?.toString() ?? '',
                        p['fa']?.toString() ?? ''),
                ],
              ),
          ],
        ),
    ];
  } catch (_) {
    return const <_WSet>[];
  }
}

const _kGood = Color(0xFF2E9E7B);
const _kBad = Color(0xFFD14B4B);

class WritingPracticePage extends StatefulWidget {
  /// 'A1' (Preschool) یا 'A2' (Primary School)
  final String level;
  const WritingPracticePage({super.key, this.level = 'A2'});

  @override
  State<WritingPracticePage> createState() => _WritingPracticePageState();
}

class _WritingPracticePageState extends State<WritingPracticePage> {
  List<_WSet>? _sets;
  _WSet? _set;
  int _index = 0;
  int _score = 0; // تعداد تکلیف‌های کامل بدون دیدنِ جواب نمونه

  final TextEditingController _ctl = TextEditingController();
  bool _checked = false;
  bool _peeked = false; // جواب نمونه دیده شده؟
  bool _counted = false; // امتیاز این تکلیف حساب شده؟
  List<bool> _hits = const [];
  int _words = 0;

  @override
  void initState() {
    super.initState();
    _loadWritingSets(widget.level).then((v) {
      if (mounted) setState(() => _sets = v);
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  bool get _isFa {
    final l = Localizations.localeOf(context).languageCode;
    return l == 'fa' || l == 'ar';
  }

  String _t(String fa, String en) => _isFa ? fa : en;

  _WTask get _task => _set!.tasks[_index];

  void _resetTask() {
    _ctl.clear();
    _checked = false;
    _peeked = false;
    _counted = false;
    _hits = const [];
    _words = 0;
  }

  void _openSet(_WSet s) {
    setState(() {
      _set = s;
      _index = 0;
      _score = 0;
      _resetTask();
    });
  }

  int _countWords(String s) => RegExp(r"[A-Za-z']+").allMatches(s).length;

  bool get _allOk =>
      _checked &&
      _hits.isNotEmpty &&
      !_hits.contains(false) &&
      _words >= _task.minWords;

  void _check() {
    final text = _ctl.text;
    final hits = [
      for (final p in _task.points) p.any.any((r) => r.hasMatch(text)),
    ];
    final words = _countWords(text);
    setState(() {
      _hits = hits;
      _words = words;
      _checked = true;
      if (!_counted && !_peeked && !hits.contains(false) && words >= _task.minWords) {
        _counted = true;
        _score++;
      }
    });
  }

  void _insert(String phrase) {
    final cur = _ctl.text;
    final sel = _ctl.selection;
    final pos = (sel.isValid && sel.start >= 0) ? sel.start : cur.length;
    final before = cur.substring(0, pos);
    final after = cur.substring(pos);
    final glue = (before.isEmpty || before.endsWith(' ') || before.endsWith('\n')) ? '' : ' ';
    final ins = '$glue$phrase';
    _ctl.value = TextEditingValue(
      text: '$before$ins$after',
      selection: TextSelection.collapsed(offset: before.length + ins.length),
    );
    if (_checked) setState(() => _checked = false);
  }

  void _next() {
    setState(() {
      _index++;
      if (_index < _set!.tasks.length) _resetTask();
    });
  }

  /// نکته‌های ظاهری (اجباری نیست): حرف بزرگ اول و نقطه‌ی آخر
  List<String> _styleTips() {
    final t = _ctl.text.trim();
    final tips = <String>[];
    if (t.isEmpty) return tips;
    final firstLetter = RegExp(r'[A-Za-z]').firstMatch(t);
    if (firstLetter != null) {
      final ch = t[firstLetter.start];
      if (ch == ch.toLowerCase()) {
        tips.add(_t('جمله را با حرف بزرگ شروع کن.', 'Start with a capital letter.'));
      }
    }
    if (!RegExp(r'[.!?]').hasMatch(t)) {
      tips.add(_t('آخر جمله نقطه یا علامت تعجب بگذار.',
          'End your sentences with . ! or ?'));
    }
    return tips;
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
          _t('تمرین نوشتن پیام و ایمیل', 'Writing Practice'),
          style: TextStyle(
              color: c.ink, fontWeight: FontWeight.w800, fontSize: 17),
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
    if (_index >= _set!.tasks.length) return _summary(context);
    return _exercise(context);
  }

  // ───────────────────────── لیست مجموعه‌ها ─────────────────────────

  Widget _setList(BuildContext context, List<_WSet> sets) {
    final c = context.appColors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            _t('موقعیت را بخوان و پیام یا ایمیل انگلیسی را خودت بنویس. چک‌لیست نشان می‌دهد چه چیزهایی را فراموش کرده‌ای.',
                'Read the situation and write the message or email yourself. A checklist shows what you forgot.'),
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
                    Icon(Icons.edit_note_rounded, color: c.gold),
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
                                ? '${s.en} · ${s.tasks.length} تمرین'
                                : '${s.tasks.length} tasks',
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

  String _kindLabel(String k) {
    switch (k) {
      case 'email':
        return _t('ایمیل', 'Email');
      case 'note':
        return _t('یادداشت', 'Note');
      default:
        return _t('پیام کوتاه', 'Text message');
    }
  }

  IconData _kindIcon(String k) {
    switch (k) {
      case 'email':
        return Icons.email_rounded;
      case 'note':
        return Icons.sticky_note_2_rounded;
      default:
        return Icons.sms_rounded;
    }
  }

  Widget _checklist(BuildContext context) {
    final c = context.appColors;
    final task = _task;
    final wordsOk = _words >= task.minWords;
    final tips = _styleTips();
    Widget row(bool ok, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
                  size: 20, color: ok ? _kGood : _kBad),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text,
                    style: TextStyle(color: c.ink, fontSize: 14, height: 1.4)),
              ),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _allOk ? _kGood : c.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < task.points.length; i++)
            row(_hits[i], task.points[i].fa),
          row(
              wordsOk,
              _t('حداقل ${task.minWords} کلمه (الان $_words کلمه)',
                  'At least ${task.minWords} words (now $_words)')),
          if (tips.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final tip in tips)
              Text('• $tip',
                  style: TextStyle(color: c.inkSoft, fontSize: 12.5, height: 1.5)),
          ],
          const SizedBox(height: 8),
          Text(
            _allOk
                ? _t('آفرین! همه‌ی موارد را داری.', 'Great! You have everything.')
                : _t('این چک‌لیست فقط کلمه‌های کلیدی را بررسی می‌کند. چیزهای قرمز را اضافه کن و دوباره بزن.',
                    'This checklist only looks for key words. Add the red items and check again.'),
            style: TextStyle(
                color: _allOk ? _kGood : c.inkSoft,
                fontSize: 13,
                fontWeight: _allOk ? FontWeight.w800 : FontWeight.w500,
                height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _modelCard(BuildContext context) {
    final c = context.appColors;
    final task = _task;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.gold),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_t('جواب نمونه', 'Model answer'),
              style: TextStyle(
                  color: c.gold, fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 6),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(task.model,
                style: TextStyle(color: c.ink, fontSize: 15.5, height: 1.6)),
          ),
          const SizedBox(height: 8),
          Text(
            task.modelFa,
            textDirection: TextDirection.rtl,
            style: TextStyle(
                color: c.translationText, fontSize: 14.5, height: 1.7),
          ),
          const SizedBox(height: 8),
          Text(
            _t('جواب تو لازم نیست دقیقاً مثل نمونه باشد؛ مهم این است که همه‌ی اطلاعات را داشته باشد.',
                'Your answer does not have to be the same. It just needs all the information.'),
            style: TextStyle(color: c.inkSoft, fontSize: 12.5, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _exercise(BuildContext context) {
    final c = context.appColors;
    final s = _set!;
    final task = _task;
    final lastTask = _index + 1 >= s.tasks.length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: _index / s.tasks.length,
            minHeight: 6,
            color: c.gold,
            backgroundColor: c.cardBorder,
          ),
        ),
        const SizedBox(height: 6),
        Text('${_index + 1} / ${s.tasks.length}',
            style: TextStyle(color: c.inkSoft, fontSize: 12.5)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(_kindIcon(task.kind), size: 18, color: c.gold),
                  const SizedBox(width: 6),
                  Text(_kindLabel(task.kind),
                      style: TextStyle(
                          color: c.gold,
                          fontWeight: FontWeight.w800,
                          fontSize: 13)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                task.fa,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                    color: c.translationText,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                    height: 1.6),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Directionality(
          textDirection: TextDirection.ltr,
          child: TextField(
            controller: _ctl,
            minLines: 5,
            maxLines: 10,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(color: c.ink, fontSize: 16, height: 1.5),
            onChanged: (_) {
              if (_checked) setState(() => _checked = false);
            },
            decoration: InputDecoration(
              hintText: _t('اینجا به انگلیسی بنویس…', 'Write here in English…'),
              hintStyle: TextStyle(color: c.inkSoft),
              filled: true,
              fillColor: c.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.cardBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.cardBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.gold, width: 1.5),
              ),
            ),
          ),
        ),
        if (task.phrases.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(_t('عبارت‌های کمکی (بزن تا اضافه شود):',
                  'Useful phrases (tap to add):'),
              style: TextStyle(color: c.inkSoft, fontSize: 12.5)),
          const SizedBox(height: 6),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in task.phrases)
                  Tooltip(
                    message: p.fa,
                    child: ActionChip(
                      label: Text(p.en, style: const TextStyle(fontSize: 13)),
                      onPressed: () => _insert(p.en),
                    ),
                  ),
              ],
            ),
          ),
          if (_isFa)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                task.phrases.map((p) => '${p.en} = ${p.fa}').join('\n'),
                style: TextStyle(color: c.inkSoft, fontSize: 12, height: 1.6),
              ),
            ),
        ],
        const SizedBox(height: 14),
        if (_checked) ...[
          _checklist(context),
          const SizedBox(height: 12),
        ],
        if (_peeked) ...[
          _modelCard(context),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: (_peeked || !_checked)
                    ? null
                    : () => setState(() => _peeked = true),
                child: Text(_t('جواب نمونه', 'Model answer')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: c.gold),
                onPressed: (_allOk || _peeked)
                    ? _next
                    : (_ctl.text.trim().isEmpty ? null : _check),
                child: Text((_allOk || _peeked)
                    ? (lastTask ? _t('پایان', 'Finish') : _t('بعدی', 'Next'))
                    : _t('بررسی', 'Check')),
              ),
            ),
          ],
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
            Text('$_score / ${s.tasks.length}',
                style: TextStyle(
                    color: c.ink, fontSize: 30, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(
              _t('کامل و بدون دیدن جواب نمونه', 'complete without the model answer'),
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
