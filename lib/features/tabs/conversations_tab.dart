import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/conversation.dart';
import '../../core/providers/conversation_provider.dart';
import '../../core/providers/language_selection_provider.dart';
import '../../core/providers/speech_provider.dart';
import '../../core/theme/app_theme_colors.dart';

class ConversationsTab extends ConsumerWidget {
  const ConversationsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
      itemCount: topics.length,
      itemBuilder: (_, i) => _TopicCard(topic: topics[i]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
class _TopicCard extends StatefulWidget {
  final ConversationTopic topic;
  const _TopicCard({required this.topic});

  @override
  State<_TopicCard> createState() => _TopicCardState();
}

class _TopicCardState extends State<_TopicCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.cardBorder),
        boxShadow: [
          BoxShadow(
            color: c.ink.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // ═══ هدر موضوع ═══
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: c.gold.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.chat_bubble_outline,
                      size: 20,
                      color: c.gold,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.topic.topic,
                      style: TextStyle(
                        color: c.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: c.inkSoft,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),

          // ═══ سناریوها (اگه باز بود) ═══
          if (_expanded) ...[
            const Divider(height: 1),
            ...widget.topic.scenarios.map(
              (s) => _ScenarioCard(scenario: s),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
class _ScenarioCard extends StatefulWidget {
  final ConversationScenario scenario;
  const _ScenarioCard({required this.scenario});

  @override
  State<_ScenarioCard> createState() => _ScenarioCardState();
}

class _ScenarioCardState extends State<_ScenarioCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: BoxDecoration(
        color: c.paper.withOpacity(0.5),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: c.cardBorder, width: 0.8),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(11),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    _open ? Icons.expand_less : Icons.expand_more,
                    color: c.gold,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.scenario.scenario,
                          style: TextStyle(
                            color: c.ink,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (widget.scenario.context != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.scenario.context!,
                            style: TextStyle(
                              color: c.inkSoft,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_open) ...[
            const Divider(height: 1),
            // ═══ بخش A: می‌شنوی ═══
            if (widget.scenario.speakerA.isNotEmpty)
              _SpeakerSection(
                title: 'می‌شنوی',
                icon: Icons.hearing,
                lines: widget.scenario.speakerA,
                color: c.teal,
              ),
            // ═══ بخش B: می‌گی ═══
            if (widget.scenario.speakerB.isNotEmpty)
              _SpeakerSection(
                title: 'می‌گی',
                icon: Icons.record_voice_over,
                lines: widget.scenario.speakerB,
                color: c.gold,
              ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
class _SpeakerSection extends ConsumerWidget {
  final String title;
  final IconData icon;
  final List<ConversationLine> lines;
  final Color color;

  const _SpeakerSection({
    required this.title,
    required this.icon,
    required this.lines,
    required this.color,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final sel = ref.watch(languageSelectionProvider);

    final langsToShow = <String>[
      if (sel.native != 'en') sel.native,
      ...sel.targets.where((t) => t != 'en'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ═══ هدر بخش ═══
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // ═══ خطوط ═══
          ...lines.map((line) => _LineRow(
                line: line,
                langsToShow: langsToShow,
              )),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
class _LineRow extends ConsumerWidget {
  final ConversationLine line;
  final List<String> langsToShow;

  const _LineRow({required this.line, required this.langsToShow});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final ctrl = ref.read(speechControllerProvider.notifier);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: c.cardBorder, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ═══ متن انگلیسی + آیکون صدا (راست) ═══
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              children: [
                // سطح
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
                // متن
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
                // آیکون صدا — وصل به TTS
                InkWell(
                  onTap: () => ctrl.toggle(line.en, 'en'),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.volume_up_outlined,
                      size: 18,
                      color: c.gold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ═══ ترجمه‌ها ═══
          if (langsToShow.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...langsToShow.map((code) {
              final knownText = code == 'fa' ? line.fa : null;
              return _TranslationLine(
                en: line.en,
                knownText: knownText,
                langCode: code,
              );
            }),
          ],
        ],
      ),
    );
  }
}

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

    // اگه ترجمه آماده داریم (فارسی) — از دیتا
    if (knownText != null && knownText!.isNotEmpty) {
      return _build(c, ctrl, knownText!);
    }

    // برای بقیه: ترجمه از provider (فعلاً ساده نگه‌داشتم)
    return _build(c, ctrl, 'در حال ترجمه...');
  }

  Widget _build(dynamic c, dynamic ctrl, String text) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
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
                  color: const Color(0xFF0F5C34),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.left,
              ),
            ),
            InkWell(
              onTap: () => ctrl.toggle(text, langCode),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Icon(
                  Icons.volume_up_outlined,
                  size: 15,
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
