import '../../core/usage/free_limit.dart';
import '../../core/usage/conversations_index.dart';
import '../../core/usage/pro_i18n.dart';
import '../../core/widgets/locked_conversation_card.dart';
import '../../core/constants/level_colors.dart';
import '../../core/usage/pro_status.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../core/constants/topic_icons.dart';
import '../../core/constants/topic_titles.dart';
import '../../core/models/conversation.dart';
import '../../core/native/native_bridge.dart';
import '../../core/player_sync/playback_origin.dart';
import '../../core/player_sync/player_track.dart';
import '../../core/player_sync/sync_widgets.dart';
import '../../core/providers/conversation_provider.dart';
import '../../core/providers/language_selection_provider.dart';
import '../../core/providers/read_ids_provider.dart';
import '../../core/router/back_handlers.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../core/widgets/level_chips.dart';
import '../../core/widgets/range_card.dart';
import '../../core/widgets/sync_item_card.dart';
import '../shell/widgets/shell_header.dart';
import '_hope_panel.dart' show uiContentDirection;

class ConversationsTab extends ConsumerStatefulWidget {
  const ConversationsTab({super.key});

  @override
  ConsumerState<ConversationsTab> createState() => _ConversationsTabState();
}

class _ConversationsTabState extends ConsumerState<ConversationsTab> {
  String? _activeTopic;
  int? _openScenario;

  // 🎭 دو صدای متفاوت برای دو نفرِ مکالمه (A = «می‌شنوی»، B = «می‌گی») — هر بار که سناریو باز می‌شود تصادفی
  final math.Random _rng = math.Random();
  String? _voiceA, _voiceB;
  String? _voicesFor;
  bool _voicesBusy = false;

  /// برچسبِ صدا به F/M ختم می‌شود (مثلاً «Nicole · US · F»).
  static bool _isFemale(String label) => label.trim().endsWith('F');

  Future<void> _pickVoices(String scenarioKey) async {
    if (_voicesBusy || _voicesFor == scenarioKey) return;
    _voicesBusy = true;
    _voicesFor = scenarioKey;
    String? a, b;
    try {
      if (NativeBridge.instance.isSupported) {
        final r = await NativeBridge.instance.getTtsVoices(lang: 'en');
        final raw = r['voices'];
        final ok = <Map<String, dynamic>>[
          if (raw is List)
            for (final e in raw)
              if (e is Map && e['downloaded'] == true && '${e['id']}'.isNotEmpty)
                Map<String, dynamic>.from(e),
        ];
        if (ok.length >= 2) {
          ok.shuffle(_rng);
          final first = ok.first;
          // ترجیحاً یک زن و یک مرد؛ وگرنه دو صدای متفاوت
          final fFem = _isFemale('${first['label']}');
          final other = ok.skip(1).firstWhere(
                (v) => _isFemale('${v['label']}') != fFem,
                orElse: () => ok[1],
              );
          if (_rng.nextBool()) {
            a = '${first['id']}';
            b = '${other['id']}';
          } else {
            a = '${other['id']}';
            b = '${first['id']}';
          }
        }
      }
    } catch (_) {
      a = b = null;
    }
    _voicesBusy = false;
    if (!mounted) return;
    _voiceA = a;
    _voiceB = b;
  }

  String? _voiceForItem(String itemId) {
    if (itemId.startsWith('a')) return _voiceA;
    if (itemId.startsWith('b')) return _voiceB;
    return null;
  }
  String _query = '';
  Set<String> _levels = <String>{};

  /// 💎 کاربرِ رایگان داخلِ موضوع‌های باز فقط جمله‌های A1 را می‌بیند
  Set<String> get _effLevels {
    final t = _activeTopic;
    if (t != null && !ProStatus.isPro && kFreeConversationTopics.contains(t)) {
      return const <String>{kFreeConversationLevel};
    }
    return _levels;
  }

  bool _lvOk(String l) {
    final s = _effLevels;
    return s.isEmpty || s.contains(l);
  }

  /// 🔒 آیا این موضوع، با فیلترِ سطحِ فعلی، برای کاربرِ رایگان قفل است؟
  /// موضوعِ پولی همیشه قفل است؛ موضوعِ رایگان هم وقتی فیلتر فقط سطح‌های پولی
  /// (B1, B2, …) را می‌خواهد، چون جمله‌های رایگانش فقط A1 است.
  bool _lockedFor(String topic) {
    if (ProStatus.isPro) return false;
    if (ProStatus.topicLocked(topic)) return true;
    return _levels.isNotEmpty && !_levels.contains(kFreeConversationLevel);
  }

  /// آیا موضوع در سطح‌های انتخاب‌شده جمله دارد؟
  /// کاربرِ رایگان: از «ایندکسِ شمارش» (چون متنِ موضوع‌های پولی داخلِ اپ نیست)؛
  /// کاربرِ Pro (یا اگر ایندکس نبود): از خودِ سناریوها.
  bool _topicHasLevel(ConversationTopic t, ConversationsIndex? index) {
    // 📚 لود تنبل: متنِ موضوع‌ها هنوز لود نشده؛ شمارش از ایندکس می‌آید (برای Pro هم)
    final n = index?.of(t.topic)?.total(_levels);
    if (n != null) return n > 0;
    return t.scenarios.any((s) =>
        s.speakerA.any((l) => _lvOk(l.level)) ||
        s.speakerB.any((l) => _lvOk(l.level)));
  }

  int _countLines(ConversationTopic t) {
    var n = 0;
    for (final s in t.scenarios) {
      n += s.speakerA.where((l) => _lvOk(l.level)).length;
      n += s.speakerB.where((l) => _lvOk(l.level)).length;
    }
    return n;
  }
  int _rangeFrom = 1;
  int _rangeTo = 60;

  /// جای اسکرولِ لیستِ موضوع‌ها — وقتی موضوعی باز می‌شود ذخیره و با «بازگشت»
  /// دقیقاً همان‌جا برگردانده می‌شود (نه بالای لیست).
  ScrollController _gridScroll = ScrollController();
  double _gridOffset = 0;

  @override
  void initState() {
    super.initState();
    // دکمه‌ی «بازگشت» گوشی: اول از موضوعِ بازشده به لیستِ موضوع‌ها برمی‌گردد؛
    // اگر لیست باز بود، کار را به AppShell می‌سپارد (خروج از برنامه).
    BackHandlers.add(_onSystemBack);
    // لمسِ طولانیِ دکمه‌ی پخش از تبِ دیگر: موضوع/سناریوی در حال پخش را باز کن
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _applyRestore(ref.read(tabRestoreProvider));
    });
  }

  /// بازگرداندنِ موضوع + سناریویی که پخش از آن شروع شده بود.
  void _applyRestore(PlaybackOrigin? r) {
    if (r == null || r.route != '/conversations') return;
    final t = r.extra['topic'];
    if (t is! String || ProStatus.topicLocked(t)) return;
    ref.read(tabRestoreProvider.notifier).state = null;
    final sc = r.extra['scenario'];
    if (_gridScroll.hasClients) _gridOffset = _gridScroll.offset;
    setState(() {
      _activeTopic = t;
      _openScenario = sc is int ? sc : 0;
    });
  }

  @override
  void dispose() {
    BackHandlers.remove(_onSystemBack);
    _gridScroll.dispose();
    super.dispose();
  }

  bool _onSystemBack() {
    if (!mounted || _activeTopic == null) return false;
    _closeTopic();
    return true;
  }

  void _openTopic(String topic) {
    // 💎 موضوعِ پولی: به‌جای باز شدن، پیامِ «مخصوص Pro»
    if (_lockedFor(topic)) {
      FreeLimit.reportLocked();
      return;
    }
    if (_gridScroll.hasClients) _gridOffset = _gridScroll.offset;
    setState(() {
      _activeTopic = topic;
      _openScenario = 0;
    });
  }

  void _closeTopic() {
    final old = _gridScroll;
    // کنترلرِ تازه با آفستِ ذخیره‌شده: لیست بدونِ پرش/چشمک در همان جا باز می‌شود
    _gridScroll = ScrollController(initialScrollOffset: _gridOffset);
    setState(() {
      _activeTopic = null;
      _openScenario = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PlaybackOrigin?>(tabRestoreProvider, (prev, next) {
      if (next != null) _applyRestore(next);
    });
    return Directionality(
      // جهتِ محتوا طبقِ زبانِ رابط؛ ShellHeader خودش RTL می‌ماند
      textDirection: uiContentDirection(context),
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final c = context.appColors;
    ref.watch(isProProvider); // با عوض شدنِ وضعیتِ Pro قفل‌ها به‌روز شوند
    final topics = ref.watch(allTopicsProvider);
    // 📚 شمارشِ جمله‌ی هر موضوع به‌تفکیکِ سطح (همه لازم دارند: متنِ موضوع‌ها لود تنبل است)
    final index = ref.watch(conversationsIndexProvider).valueOrNull;

    if (topics.isEmpty) {
      final loading = ref.watch(conversationLoaderProvider).isLoading;
      return ListView(
        children: [
          const ShellHeader(),
          Padding(
            padding: const EdgeInsets.all(40),
            child: Center(
              child: loading
                  ? SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: c.gold),
                    )
                  : Text(context.l10n.dialogs_no_results,
                      style: TextStyle(color: c.inkSoft, fontSize: 15)),
            ),
          ),
        ],
      );
    }

    final filtered = topics.where((t) {
      // فیلتر سطح: موضوعی که دست‌کم یک جمله‌ی هم‌سطح دارد
      if (_levels.isNotEmpty && !_topicHasLevel(t, index)) {
        return false;
      }
      if (_query.trim().isEmpty) return true;
      final q = _query.trim().toLowerCase();
      if (t.topic.toLowerCase().contains(q)) return true;
      if (topicTitle(t.topic, Localizations.localeOf(context).languageCode)
          .toLowerCase()
          .contains(q)) {
        return true;
      }
      return t.scenarios.any((s) =>
          s.scenario.toLowerCase().contains(q) ||
          s.speakerA.any((l) => l.en.toLowerCase().contains(q)) ||
          s.speakerB.any((l) => l.en.toLowerCase().contains(q)));
    }).toList();

    if (_activeTopic != null) {
      final name = _activeTopic!;
      // 📚 لود تنبل: متنِ همین یک موضوع الان لود می‌شود (فایلِ کوچک)
      final loaded = ref.watch(conversationTopicProvider(name));
      final topic = loaded.valueOrNull;
      if (topic != null) return _buildTopicView(context, topic, index);
      return _buildTopicLoading(context, name, loading: loaded.isLoading);
    }
    return _buildTopicsGrid(context, filtered, index);
  }

  /// ردیف فیلتر سطح (A1–C2) بالای لیست موضوع‌ها.
  Widget _levelBar() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: LevelChipsMulti(
          selected: _levels,
          onChanged: (v) => setState(() {
            _levels = v;
            _rangeFrom = 1;
            _rangeTo = 60;
          }),
        ),
      );

  Widget _buildTopicsGrid(BuildContext context, List<ConversationTopic> topics,
      ConversationsIndex? index) {
    final c = context.appColors;
    final total = topics.length;

    if (total == 0) {
      return ListView(
        children: [
          const ShellHeader(),
          _levelBar(),
          Padding(
            padding: const EdgeInsets.all(40),
            child: Center(
              child: Text(context.l10n.dialogs_no_results,
                  style: TextStyle(color: c.inkSoft, fontSize: 14)),
            ),
          ),
        ],
      );
    }

    final from = _rangeFrom.clamp(1, total).toInt();
    final to = _rangeTo.clamp(from, total).toInt();
    final visible = topics.sublist(from - 1, to);
    // «خوانده‌شده‌ها» روی دستگاه ذخیره می‌شوند (مثل Hope)
    final topicRead = ref.watch(readIdsProvider('conv-topics'));
    final topicReadN = ref.read(readIdsProvider('conv-topics').notifier);
    final readInRange = visible.where((t) => topicRead.contains(t.topic)).length;
    final readTotal = topics.where((t) => topicRead.contains(t.topic)).length;
    final isPro = ProStatus.isPro;
    // 🔒 خلاصه‌ی قفل‌ها برای بنر (فقط کاربرِ رایگان)
    final lockSum = (isPro || index == null)
        ? null
        : index.summary(visible.map((t) => t.topic), _levels,
            isLocked: _lockedFor);

    return ListView(
      controller: _gridScroll,
      padding: const EdgeInsets.only(bottom: 90),
      children: [
        const ShellHeader(),
        _levelBar(),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
        RangeCard(
          label: context.l10n.dialogs_topics_label,
          max: total,
          from: from,
          to: to,
          totalInRange: visible.length,
          readInRange: readInRange,
          readTotal: readTotal,
          onFromChanged: (v) => setState(() {
            _rangeFrom = v;
            if (_rangeTo < v) _rangeTo = v;
          }),
          onToChanged: (v) => setState(() => _rangeTo = v),
          onMarkRead: () =>
              topicReadN.setMany(visible.map((t) => t.topic), true),
          onClear: () =>
              topicReadN.setMany(visible.map((t) => t.topic), false),
        ),
        const SizedBox(height: 14),
        if (lockSum != null && lockSum.locked > 0) ...[
          LockedConversationsBanner(
            lockedTopics: lockSum.lockedTopics,
            locked: lockSum.locked,
            total: lockSum.total,
            byLevel: lockSum.byLevel,
          ),
          const SizedBox(height: 14),
        ],
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.62,
          ),
          itemCount: visible.length,
          itemBuilder: (_, i) {
            final topic = visible[i];
            final visual = visualForTopic(topic.topic);
            final e = index?.of(topic.topic);
            final locked = _lockedFor(topic.topic);
            return _TopicCard(
              topic: topic,
              visual: visual,
              badgeColor: kTopicBadgeColors[i % kTopicBadgeColors.length],
              isRead: !locked && topicRead.contains(topic.topic),
              mode: locked
                  ? _CardMode.locked
                  : (isPro ? _CardMode.open : _CardMode.free),
              lineCount: e != null
                  ? e.total(_levels)
                  : (isPro ? _countLines(topic) : null),
              freeCount: e?.free(_levels) ?? 0,
              levels: e != null ? e.levels : conversationLevels(topic),
              onTap: () => _openTopic(topic.topic),
              onToggleRead: () => topicReadN.toggle(topic.topic),
            );
          },
        ),
            ],
          ),
        ),
      ],
    );
  }

  /// حالتِ «در حالِ لودِ موضوع» یا «لود نشد» (با تلاشِ دوباره).
  Widget _buildTopicLoading(BuildContext context, String name,
      {required bool loading}) {
    final c = context.appColors;
    return ListView(
      children: [
        const ShellHeader(),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: InkWell(
            onTap: _closeTopic,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.arrow_back, size: 18, color: c.teal),
                  const SizedBox(width: 6),
                  Text(context.l10n.dialogs_back_to_topics,
                      style: TextStyle(
                          color: c.teal,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(40),
          child: Center(
            child: loading
                ? SizedBox(
                    width: 26,
                    height: 26,
                    child:
                        CircularProgressIndicator(strokeWidth: 2.4, color: c.gold),
                  )
                : Column(
                    children: [
                      Text(context.l10n.dialogs_no_results,
                          style: TextStyle(color: c.inkSoft, fontSize: 15)),
                      const SizedBox(height: 12),
                      IconButton(
                        icon: Icon(Icons.refresh, color: c.teal),
                        onPressed: () =>
                            ref.invalidate(conversationTopicProvider(name)),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopicView(BuildContext context, ConversationTopic topic,
      ConversationsIndex? index) {
    final c = context.appColors;
    // 🔒 جمله‌های قفل‌شده‌ی این موضوعِ رایگان (غیر از A1) — برای کارتِ انتهای صفحه
    final topicCounts = (ProStatus.isPro || index == null)
        ? null
        : index.of(topic.topic);
    final lockedHere = topicCounts?.locked(_levels) ?? 0;
    final visual = visualForTopic(topic.topic);
    final scenarioRead = ref.watch(readIdsProvider('conv-scenarios'));
    final scenarioReadN = ref.read(readIdsProvider('conv-scenarios').notifier);

    // سناریوی بازشده = «متنِ کاملِ» پلیر (اول «می‌شنوی»، بعد «می‌گی» — همان
    // ترتیبِ Hope). همین یک ویجتِ مشترک هایلایت/اسکرول/پرش را برای همه‌ی
    // تب‌ها یکسان انجام می‌دهد.
    final openIdx = _openScenario;
    final openSc = (openIdx != null && openIdx < topic.scenarios.length)
        ? topic.scenarios[openIdx]
        : null;
    if (openSc != null) {
      final k = '${topic.topic}:$openIdx';
      if (_voicesFor != k) unawaited(_pickVoices(k));    // 🎭 صدای تازه برای هر بار بازشدنِ سناریو
    }

    return SyncPlayScope(
      revision: openSc ?? topic,
      originExtra: {'topic': topic.topic, 'scenario': openIdx},
      mode: TrackMode.lines,
      voiceForItem: _voiceForItem,
      itemsBuilder: () => openSc == null
          ? const <SyncItem>[]
          : [
              for (var i = 0; i < openSc.speakerA.length; i++)
                if (_lvOk(openSc.speakerA[i].level))
                  SyncItem('a$i', openSc.speakerA[i].en),
              for (var i = 0; i < openSc.speakerB.length; i++)
                if (_lvOk(openSc.speakerB[i].level))
                  SyncItem('b$i', openSc.speakerB[i].en),
            ],
      child: SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 90),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ShellHeader(),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
        InkWell(
          onTap: _closeTopic,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(Icons.arrow_back, size: 18, color: c.teal),
                const SizedBox(width: 6),
                Text(context.l10n.dialogs_back_to_topics,
                    style: TextStyle(
                        color: c.teal,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(visual.icon, size: 26, color: visual.color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                  topicTitle(
                      topic.topic, Localizations.localeOf(context).languageCode),
                  style: TextStyle(
                      color: c.ink,
                      fontSize: 19,
                      fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...List.generate(topic.scenarios.length, (i) {
          final sc = topic.scenarios[i];
          if (_effLevels.isNotEmpty &&
              !(sc.speakerA.any((l) => _lvOk(l.level)) ||
                  sc.speakerB.any((l) => _lvOk(l.level)))) {
            return const SizedBox.shrink();
          }
          final isOpen = _openScenario == i;
          final readKey = '${topic.topic}::$i';
          final isRead = scenarioRead.contains(readKey);
          return _ScenarioCard(
            scenario: sc,
            levelFilter: _effLevels,
            isOpen: isOpen,
            isRead: isRead,
            onToggle: () =>
                setState(() => _openScenario = isOpen ? null : i),
            onToggleRead: () => scenarioReadN.toggle(readKey),
          );
        }),
        if (topicCounts != null && lockedHere > 0) ...[
          const SizedBox(height: 4),
          LockedConversationCard(
            locked: lockedHere,
            total: topicCounts.total(_levels),
            byLevel: {
              for (final lv in topicCounts.levels)
                if ((_levels.isEmpty || _levels.contains(lv)) &&
                    topicCounts.lockedAt(lv) > 0)
                  lv: topicCounts.lockedAt(lv),
            },
            scopeLabel: topicTitle(
                topic.topic, Localizations.localeOf(context).languageCode),
          ),
        ],
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
// کارت موضوع
// ═══════════════════════════════════════════════════════════════════

/// open = Pro (همه‌چیز باز) · free = موضوعِ رایگان (فقط A1 باز) · locked = قفل
enum _CardMode { open, free, locked }

class _TopicCard extends StatelessWidget {
  final ConversationTopic topic;
  final TopicVisual visual;
  final Color badgeColor;
  final bool isRead;
  final _CardMode mode;

  /// تعدادِ جمله‌ها (با فیلترِ سطحِ فعلی)؛ null = نشان داده نشود
  final int? lineCount;

  /// تعدادِ جمله‌های رایگان (فقط برای mode == free)
  final int freeCount;

  /// سطح‌هایی که موضوع دارد (نقطه‌های رنگیِ زیرِ آیکون)
  final List<String> levels;
  final VoidCallback onTap, onToggleRead;

  const _TopicCard({
    required this.topic,
    required this.visual,
    required this.badgeColor,
    required this.isRead,
    required this.mode,
    required this.lineCount,
    required this.freeCount,
    required this.levels,
    required this.onTap,
    required this.onToggleRead,
  });

  static Widget _pill(
      AppThemeColorsExt c, Color color, IconData icon, String text) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Container(
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.16),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withOpacity(0.55)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 4),
            Text(text,
                style: TextStyle(
                    color: c.ink, fontSize: 11, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final locked = mode == _CardMode.locked;

    // فوترِ کارت: تعدادِ جمله‌ها
    Widget? footer;
    final n = lineCount;
    if (n != null && n > 0) {
      final unit = ProI18n.t(context, 'lines_unit');
      if (locked) {
        footer = _pill(c, c.gold, Icons.lock, '$n $unit');
      } else if (mode == _CardMode.free) {
        footer = _pill(c, c.teal, Icons.lock_open,
            ProI18n.t(context, 'free_of', {'free': freeCount, 'n': n}));
      } else {
        footer = Text('$n $unit',
            style: TextStyle(
                color: c.inkSoft, fontSize: 11, fontWeight: FontWeight.w600));
      }
    }

    final BoxDecoration deco = locked
        ? BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [c.goldSoft.withOpacity(0.55), c.surface],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.gold.withOpacity(0.55), width: 1.1),
          )
        : BoxDecoration(
            color: isRead ? c.surfaceRead : c.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isRead ? const Color(0xFFE3D2A2) : c.cardBorder,
              width: 1,
            ),
          );

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 16, 6, 8),
              decoration: deco,
              child: Column(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: locked
                          ? c.gold.withOpacity(0.14)
                          : (isRead
                              ? c.surface.withOpacity(0.7)
                              : badgeBgColor(visual.color)),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      visual.icon,
                      size: 24,
                      color: locked
                          ? visual.color.withOpacity(0.8)
                          : (isRead
                              ? const Color(0xFF2E7D6C)
                              : visual.color),
                    ),
                  ),
                  const SizedBox(height: 5),
                  SizedBox(
                    height: 5,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (final lv in levels)
                          Container(
                            width: 5,
                            height: 5,
                            margin: const EdgeInsets.symmetric(horizontal: 1.5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: levelColor(lv),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 5),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Text(
                        topicTitle(topic.topic,
                            Localizations.localeOf(context).languageCode),
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          height: 1.22,
                        ),
                      ),
                    ),
                  ),
                  if (footer != null) ...[
                    const SizedBox(height: 4),
                    SizedBox(height: 20, child: Center(child: footer)),
                  ],
                ],
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: locked
                ? Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.gold,
                      boxShadow: [
                        BoxShadow(
                          color: c.gold.withOpacity(0.35),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child:
                        const Icon(Icons.lock, size: 12, color: Colors.white),
                  )
                : GestureDetector(
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
  final Set<String> levelFilter;
  final bool isOpen, isRead;
  final VoidCallback onToggle, onToggleRead;

  const _ScenarioCard({
    required this.scenario,
    required this.levelFilter,
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
        color: isRead ? c.surfaceRead : c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isRead ? const Color(0xFFE3D2A2) : c.cardBorder),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(13),
              child: Row(
                children: [
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
                        Text(scenario.scenario,
                            style: TextStyle(
                                color: c.ink,
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700)),
                        if (scenario.context != null) ...[
                          const SizedBox(height: 2),
                          Text(scenario.context!,
                              style: TextStyle(
                                  color: c.inkSoft, fontSize: 13),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ],
                    ),
                  ),
                  Icon(isOpen ? Icons.expand_less : Icons.expand_more,
                      color: c.teal, size: 22),
                ],
              ),
            ),
          ),
          if (isOpen) ...[
            const Divider(height: 1),
            if (scenario.speakerA.isNotEmpty)
              _SpeakerBox(
                  title: context.l10n.dialogs_you_hear,
                  idPrefix: 'a',
                  color: c.teal,
                  levelFilter: levelFilter,
                  lines: scenario.speakerA),
            if (scenario.speakerB.isNotEmpty)
              _SpeakerBox(
                  title: context.l10n.dialogs_you_say,
                  idPrefix: 'b',
                  color: c.gold,
                  levelFilter: levelFilter,
                  lines: scenario.speakerB),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
class _SpeakerBox extends ConsumerWidget {
  final String title;

  /// 'a' (می‌شنوی) یا 'b' (می‌گی) — شناسه‌ی هر خط = '$idPrefix$index'
  final String idPrefix;
  final Color color;
  final Set<String> levelFilter;
  final List<ConversationLine> lines;

  const _SpeakerBox({
    required this.title,
    required this.idPrefix,
    required this.color,
    required this.levelFilter,
    required this.lines,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;

    // فقط جمله‌های سطحِ انتخاب‌شده (شناسه‌ها همان ایندکسِ اصلی می‌مانند)
    final shown = <int>[
      for (var i = 0; i < lines.length; i++)
        if (levelFilter.isEmpty || levelFilter.contains(lines[i].level)) i
    ];
    if (shown.isEmpty) return const SizedBox.shrink();

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
                    color: color, borderRadius: BorderRadius.circular(4)),
              ),
              const SizedBox(width: 6),
              Text(title,
                  style: TextStyle(
                      color: c.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          for (final i in shown)
            _LineRow(line: lines[i], id: '$idPrefix$i'),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// هر خطِ مکالمه = همان کارتِ مشترکِ برنامه (SyncItemCard) — دقیقاً مثل لغات
// ═══════════════════════════════════════════════════════════════════
class _LineRow extends ConsumerWidget {
  final ConversationLine line;
  final String id;
  const _LineRow({
    required this.line,
    required this.id,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sel = ref.watch(languageSelectionProvider);

    // مبدأ و مقصدِ یکسان (مثلاً هر دو عربی) → هر زبان فقط یک‌بار
    final langsToShow = <String>[
      if (sel.native != 'en' && !sel.targets.contains(sel.native)) sel.native,
      ...sel.targets.where((t) => t != 'en'),
    ].toSet().toList();

    return SyncItemCard(
      key: ValueKey('line-$id'),
      id: id,
      en: line.en,
      level: line.level,
      langsToShow: langsToShow,
      knownTranslations: line.fa.isNotEmpty
          ? <String, String>{'fa': line.fa}
          : const <String, String>{},
      compact: true,
    );
  }
}
