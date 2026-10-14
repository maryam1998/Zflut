import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/conversation.dart';
import '../../core/providers/conversation_provider.dart';
import '../../core/providers/language_selection_provider.dart';
import '../../core/providers/speech_provider.dart';
import '../../core/providers/translation_provider.dart';
import '../../core/theme/app_theme_colors.dart';

class ConversationsTab extends ConsumerStatefulWidget {
  const ConversationsTab({super.key});

  @override
  ConsumerState<ConversationsTab> createState() => _ConversationsTabState();
}

class _ConversationsTabState extends ConsumerState<ConversationsTab> {
  String? _activeTopic;
  int? _openScenario;
  String _levelFilter = 'all';
  String _query = '';

  // بازه نمایش
  int _rangeFrom = 1;
  int _rangeTo = 60;

  // خوانده‌شده
  final Set<String> _topicRead = {};
  final Set<String> _scenarioRead = {};

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final topics = ref.watch(allTopicsProvider);

    if (topics.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'داده‌ای بارگذاری نشد',
            style: TextStyle(color: c.inkSoft, fontSize: 15),
          ),
        ),
      );
    }

    // فیلتر سرچ
    final filtered = topics.where((t) {
      if (_query.trim().isEmpty) return true;
      final q = _query.trim().toLowerCase();
      if (t.topic.toLowerCase().contains(q)) return true;
      return t.scenarios.any((s) =>
          s.scenario.toLowerCase().contains(q) ||
          s.speakerA.any((l) => l.en.toLowerCase().contains(q)) ||
          s.speakerB.any((l) => l.en.toLowerCase().contains(q)));
    }).toList();

    if (_activeTopic != null) {
      final topic = topics.firstWhere(
        (t) => t.topic == _activeTopic,
        orElse: () => topics.first,
      );
      return _buildTopicView(context, topic);
    }

    return _buildTopicsGrid(context, filtered);
  }

  // ═══════════════════════════════════════════════════════════════════
  // صفحه‌ی شبکه‌ی موضوعات
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildTopicsGrid(BuildContext context, List<ConversationTopic> topics) {
    final c = context.appColors;
    final total = topics.length;

    if (total == 0) {
      return Center(
        child: Text(
          'چیزی پیدا نشد',
          style: TextStyle(color: c.inkSoft, fontSize: 14),
        ),
      );
    }

    // تنظیم محدوده
    final from = _rangeFrom.clamp(1, total);
    final to = _rangeTo.clamp(from, total);
    final visible = topics.sublist(from - 1, to);

    final readInRange = visible.where((t) => _topicRead.contains(t.topic)).length;
    final readTotal = topics.where((t) => _topicRead.contains(t.topic)).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
      children: [
        // ═══ کارت بازه + پیشرفت ═══
        _RangeCard(
          from: from,
          to: to,
          total: total,
          readInRange: readInRange,
          readTotal: readTotal,
          onFromChanged: (v) => setState(() => _rangeFrom = v),
          onToChanged: (v) => setState(() => _rangeTo = v),
          onMarkAllRead: () {
            setState(() {
              for (final t in visible) {
                _topicRead.add(t.topic);
              }
            });
          },
          onClearRange: () {
            setState(() {
              for (final t in visible) {
                _topicRead.remove(t.topic);
              }
            });
          },
        ),

        const SizedBox(height: 14),

        // ═══ شبکه‌ی موضوعات ═══
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.95,
          ),
          itemCount: visible.length,
          itemBuilder: (_, i) {
            final topic = visible[i];
            final isRead = _topicRead.contains(topic.topic);
            return _TopicCard(
              topic: topic,
              isRead: isRead,
              onTap: () => setState(() {
                _activeTopic = topic.topic;
                _openScenario = 0;
              }),
              onToggleRead: () => setState(() {
                if (isRead) {
                  _topicRead.remove(topic.topic);
                } else {
                  _topicRead.add(topic.topic);
                }
              }),
            );
          },
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // صفحه‌ی سناریوهای یک موضوع
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildTopicView(BuildContext context, ConversationTopic topic) {
    final c = context.appColors;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
      children: [
        // ═══ دکمه‌ی بازگشت ═══
        InkWell(
          onTap: () => setState(() {
            _activeTopic = null;
            _openScenario = null;
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(Icons.arrow_back, size: 18, color: c.teal),
                const SizedBox(width: 6),
                Text(
                  'بازگشت به موضوعات',
                  style: TextStyle(
                    color: c.teal,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // ═══ هدر موضوع ═══
        Row(
          children: [
            Icon(Icons.chat_bubble_outline, size: 22, color: c.teal),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                topic.topic,
                style: TextStyle(
                  color: c.ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ═══ سناریوها ═══
        ...List.generate(topic.scenarios.length, (i) {
          final sc = topic.scenarios[i];
          final isOpen = _openScenario == i;
          final isRead = _scenarioRead.contains('${topic.topic}::$i');
          return _ScenarioCard(
            scenario: sc,
            isOpen: isOpen,
            isRead: isRead,
            onToggle: () => setState(() => _openScenario = isOpen ? null : i),
            onToggleRead: () => setState(() {
              final key = '${topic.topic}::$i';
              if (isRead) {
                _scenarioRead.remove(key);
              } else {
                _scenarioRead.add(key);
              }
            }),
          );
        }),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// کارت بازه + پیشرفت
// ═══════════════════════════════════════════════════════════════════
class _RangeCard extends StatefulWidget {
  final int from;
  final int to;
  final int total;
  final int readInRange;
  final int readTotal;
  final ValueChanged<int> onFromChanged;
  final ValueChanged<int> onToChanged;
  final VoidCallback onMarkAllRead;
  final VoidCallback onClearRange;

  const _RangeCard({
    required this.from,
    required this.to,
    required this.total,
    required this.readInRange,
    required this.readTotal,
    required this.onFromChanged,
    required this.onToChanged,
    required this.onMarkAllRead,
    required this.onClearRange,
  });

  @override
  State<_RangeCard> createState() => _RangeCardState();
}

class _RangeCardState extends State<_RangeCard> {
  late TextEditingController _fromCtrl;
  late TextEditingController _toCtrl;

  @override
  void initState() {
    super.initState();
    _fromCtrl = TextEditingController(text: '${widget.from}');
    _toCtrl = TextEditingController(text: '${widget.to}');
  }

  @override
  void didUpdateWidget(covariant _RangeCard old) {
    super.didUpdateWidget(old);
    if (old.from != widget.from) _fromCtrl.text = '${widget.from}';
    if (old.to != widget.to) _toCtrl.text = '${widget.to}';
  }

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final pct = widget.total > 0 ? (widget.readTotal / widget.total) * 100 : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.cardBorder),
        boxShadow: [
          BoxShadow(
            color: c.ink.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ردیف بازه
          Row(
            children: [
              _NumberField(
                controller: _fromCtrl,
                onChanged: (v) {
                  final n = int.tryParse(v);
                  if (n != null && n >= 1 && n <= widget.total) {
                    widget.onFromChanged(n);
                  }
                },
              ),
              const SizedBox(width: 8),
              Text('تا', style: TextStyle(color: c.teal, fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              _NumberField(
                controller: _toCtrl,
                onChanged: (v) {
                  final n = int.tryParse(v);
                  if (n != null && n >= 1 && n <= widget.total) {
                    widget.onToChanged(n);
                  }
                },
              ),
              const Spacer(),
              Text(
                'موضوع‌ها از مجموع ${widget.total}',
                style: TextStyle(
                  color: c.inkSoft,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // نوار پیشرفت
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: pct / 100,
              minHeight: 8,
              backgroundColor: c.paperDark,
              valueColor: AlwaysStoppedAnimation(c.teal),
            ),
          ),

          const SizedBox(height: 12),

          // متن پیشرفت
          Text(
            'خوانده‌شده: ${widget.readTotal} از ${widget.total} • ${widget.readInRange} از ${widget.to - widget.from + 1} در این بازه',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: const Color(0xFF2E7D6C),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 12),

          // دکمه‌ها
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onMarkAllRead,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0xFFEAF4F1),
                    side: const BorderSide(color: Color(0xFFCFE6DF)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: Text(
                    'علامت‌گذاری همه به خوانده‌شده',
                    style: TextStyle(
                      color: c.teal,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onClearRange,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: c.paper,
                    side: BorderSide(color: c.cardBorder),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: Text(
                    'پاک کردن علامت این بازه',
                    style: TextStyle(
                      color: c.teal,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _NumberField({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return SizedBox(
      width: 52,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: c.teal,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: c.cardBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: c.cardBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: c.gold, width: 1.5),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// کارت موضوع
// ═══════════════════════════════════════════════════════════════════
class _TopicCard extends StatelessWidget {
  final ConversationTopic topic;
  final bool isRead;
  final VoidCallback onTap;
  final VoidCallback onToggleRead;

  const _TopicCard({
    required this.topic,
    required this.isRead,
    required this.onTap,
    required this.onToggleRead,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isRead ? const Color(0xFFF8F2DE) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isRead ? const Color(0xFFE3D2A2) : c.cardBorder,
                width: 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 6),
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isRead
                        ? Colors.white.withOpacity(0.7)
                        : const Color(0xFFEAF4F1),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.chat_bubble_outline,
                    size: 22,
                    color: isRead ? const Color(0xFF2E7D6C) : c.teal,
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: Text(
                    topic.topic,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.ink,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // دایره‌ی خوانده‌شده — بالا-راست
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: onToggleRead,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isRead ? const Color(0xFF3F9B72) : Colors.white,
                  border: Border.all(
                    color: isRead
                        ? const Color(0xFF276E4F)
                        : const Color(0xFFC8BE95),
                    width: 1.5,
                  ),
                ),
                alignment: Alignment.center,
                child: isRead
                    ? const Icon(Icons.check,
                        size: 11, color: Colors.white)
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// کارت سناریو
// ═══════════════════════════════════════════════════════════════════
class _ScenarioCard extends StatelessWidget {
  final ConversationScenario scenario;
  final bool isOpen;
  final bool isRead;
  final VoidCallback onToggle;
  final VoidCallback onToggleRead;

  const _ScenarioCard({
    required this.scenario,
    required this.isOpen,
    required this.isRead,
    required this.onToggle,
    required this.onToggleRead,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isRead ? const Color(0xFFF8F2DE) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isRead ? const Color(0xFFE3D2A2) : c.cardBorder,
        ),
      ),
      child: Column(
        children: [
          // هدر سناریو
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(13),
              child: Row(
                children: [
                  // چک‌باکس خوانده‌شده
                  GestureDetector(
                    onTap: onToggleRead,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isRead
                            ? const Color(0xFF3F9B72)
                            : Colors.transparent,
                        border: Border.all(
                          color: isRead
                              ? const Color(0xFF276E4F)
                              : const Color(0xFFC8BE95),
                          width: 1.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: isRead
                          ? const Icon(Icons.check,
                              size: 12, color: Colors.white)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          scenario.scenario,
                          style: TextStyle(
                            color: c.ink,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (scenario.context != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            scenario.context!,
                            style: TextStyle(
                              color: c.inkSoft,
                              fontSize: 11.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    isOpen ? Icons.expand_less : Icons.expand_more,
                    color: c.teal,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),

          // محتوای سناریو
          if (isOpen) ...[
            const Divider(height: 1),

            // speakerA
            if (scenario.speakerA.isNotEmpty)
              _SpeakerBox(
                title: 'می‌شنوی',
                color: c.teal,
                lines: scenario.speakerA,
              ),

            // speakerB
            if (scenario.speakerB.isNotEmpty)
              _SpeakerBox(
                title: 'می‌گی',
                color: c.gold,
                lines: scenario.speakerB,
              ),

            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// بخش speaker (می‌شنوی / می‌گی)
// ═══════════════════════════════════════════════════════════════════
class _SpeakerBox extends ConsumerWidget {
  final String title;
  final Color color;
  final List<ConversationLine> lines;

  const _SpeakerBox({
    required this.title,
    required this.color,
    required this.lines,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  color: c.ink,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...lines.map((l) => _LineRow(line: l)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// ردیف خط مکالمه — با آیکون صدا وصل
// ═══════════════════════════════════════════════════════════════════
class _LineRow extends ConsumerWidget {
  final ConversationLine line;
  const _LineRow({required this.line});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final ctrl = ref.read(speechControllerProvider.notifier);
    final sel = ref.watch(languageSelectionProvider);

    // زبان‌های نمایش
    final langsToShow = <String>[
      if (sel.native != 'en') sel.native,
      ...sel.targets.where((t) => t != 'en'),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.cardBorder, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // متن انگلیسی — LTR
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: c.paperDark,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    line.level,
                    style: TextStyle(
                      color: c.inkSoft,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    line.en,
                    style: TextStyle(
                      color: c.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.left,
                  ),
                ),
                // 🔊 — آیکون صدا وصل
                InkWell(
                  onTap: () => ctrl.toggle(line.en, 'en'),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.volume_up_outlined,
                      size: 20,
                      color: c.gold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ترجمه‌ها
          ...langsToShow.map((code) {
            final knownText = code == 'fa' ? line.fa : null;
            return _TranslationLine(
              en: line.en,
              knownText: knownText,
              langCode: code,
            );
          }),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// ردیف ترجمه — با 🔊 وصل
// ═══════════════════════════════════════════════════════════════════
class _TranslationLine extends ConsumerWidget {
  final String en;
  final String? knownText;
  final String langCode;

  const _TranslationLine({
    required this.en,
    this.knownText,
    required this.langCode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final ctrl = ref.read(speechControllerProvider.notifier);

    // فارسی — از دیتا
    if (knownText != null && knownText!.isNotEmpty) {
      return _build(c, ctrl, knownText!);
    }

    // بقیه — از provider
    final async = ref.watch(
      translationProvider(
          (text: en, to: langCode, from: 'en', verify: false)),
    );

    return async.when(
      loading: () => _build(c, ctrl, '...', loading: true),
      error: (_, __) => const SizedBox.shrink(),
      data: (text) {
        if (text.isEmpty) return const SizedBox.shrink();
        return _build(c, ctrl, text);
      },
    );
  }

  Widget _build(dynamic c, dynamic ctrl, String text, {bool loading = false}) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: c.paperDark,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: c.cardBorder, width: 0.5),
              ),
              child: Text(
                langCode.toUpperCase(),
                style: TextStyle(
                  color: c.gold,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: loading ? c.inkSoft : const Color(0xFF0F5C34),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.left,
              ),
            ),
            if (!loading)
              InkWell(
                onTap: () => ctrl.toggle(text, langCode),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Icon(
                    Icons.volume_up_outlined,
                    size: 17,
                    color: c.gold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
