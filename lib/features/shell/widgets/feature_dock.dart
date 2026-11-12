// 📁 مسیر: lib/features/shell/widgets/feature_dock.dart
//
// 💎 «داک ابزارها» — فقط اندروید.
// بار اول که کاربر وارد اپ می‌شود، سه آیکونِ ذره‌بین 🔍 / ترجمه‌ی زنده 🎙 / یوتیوب ▶
// از سمتِ راست اسلاید می‌شوند و کنارِ لبه‌ی راست می‌نشینند، با یک کارتِ معرفی و
// دکمه‌ی «فعال‌سازی همه» (یک لمس = مجوزها + روشن‌شدنِ هر سه).
// بعد از آن، داک به شکلِ یک زبانه‌ی باریک کنارِ لبه‌ی راست می‌ماند؛ با لمس باز می‌شود
// و هر آیکون یک کلیدِ روشن/خاموش است (نقطه‌ی سبز = روشن).
//
// این ویجت مستقل است: هیچ کدِ دیگری را تغییر نمی‌دهد و فقط از همان پلِ نیتیو و
// همان قانون‌های «سقفِ نسخه‌ی رایگان» (LinLearnBridge.startBubble) استفاده می‌کند.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app.dart';
import '../../../core/bridge/linlearn_bridge.dart';
import '../../../core/native/native_bridge.dart';
import '../../../core/providers/app_prefs_provider.dart';
import '../../../core/providers/linlearn_provider.dart';
import '../../../core/providers/native_sync_provider.dart';
import '../../../core/storage/local_storage.dart' show sharedPrefsProvider;
import '../../../core/theme/app_theme_colors.dart';
import 'settings_packs.dart' show kDedicatedPackLangs, kLatinPackLangs;

const String _kSeenKey = 'zflut-feature-dock-seen-v1';

// همان کلیدهای تنظیمات (تا رنگ/حالتِ نمایشِ انتخاب‌شده‌ی کاربر حفظ شود)
const String _kScreenInfoKey = 'phrasebook-screenrec-info-seen';
const String _kColorKey = 'phrasebook-bubble-panel-color';
const String _kDispKey = 'phrasebook-live-display-mode';

const String _kSrcKey = 'phrasebook-live-src-lang';
const String _kAutoKey = 'phrasebook-live-src-auto';
const String _kSpeechProviderKey = 'phrasebook-speech-provider';

const Map<String, String> _srcNames = {
  'en': 'English', 'de': 'Deutsch', 'fr': 'Français', 'es': 'Español',
  'it': 'Italiano', 'tr': 'Türkçe', 'ar': 'العربية', 'ru': 'Русский',
  'ja': '日本語', 'ko': '한국어', 'zh': '中文', 'hi': 'हिन्दी',
  'pt': 'Português', 'nl': 'Nederlands', 'ur': 'اردو', 'fa': 'فارسی',
};

const Map<String, Map<String, String>> _tx = {
  'show': {
    'fa': 'نمایش داکِ ابزارها (ذره‌بین، ترجمه‌ی زنده، یوتیوب) در لبه‌ی راست',
    'en': 'Show the tools dock (magnifier, live translation, YouTube) on the right edge',
    'es': 'Mostrar el dock de herramientas en el borde derecho',
    'de': 'Tool-Dock (Lupe, Live-Übersetzung, YouTube) am rechten Rand anzeigen',
    'fr': 'Afficher le dock d’outils (loupe, traduction, YouTube) sur le bord droit',
    'ar': 'إظهار شريط الأدوات (المكبّرة، الترجمة الفورية، يوتيوب) على الحافة اليمنى',
  },
  'title': {
    'fa': 'ابزارهای هوشمندت آماده‌اند',
    'en': 'Your smart tools are ready',
    'es': 'Tus herramientas inteligentes están listas',
    'de': 'Deine smarten Tools sind bereit',
    'fr': 'Tes outils intelligents sont prêts',
    'ar': 'أدواتك الذكية جاهزة',
  },
  'body': {
    'fa': 'ذره‌بین، ترجمه‌ی زنده و زیرنویس یوتیوب روی هر برنامه‌ای کار می‌کنند. با یک لمس هر سه را روشن کن.',
    'en': 'Magnifier, live translation and YouTube subtitles work over any app. Turn all three on with one tap.',
    'es': 'La lupa, la traducción en vivo y los subtítulos de YouTube funcionan sobre cualquier app. Actívalos con un toque.',
    'de': 'Lupe, Live-Übersetzung und YouTube-Untertitel funktionieren über jeder App. Schalte alle drei mit einem Tipp ein.',
    'fr': 'La loupe, la traduction en direct et les sous-titres YouTube fonctionnent sur toutes les applis. Active les trois d’un geste.',
    'ar': 'المكبّرة والترجمة الفورية وترجمة يوتيوب تعمل فوق أي تطبيق. فعّلها جميعًا بلمسة واحدة.',
  },
  'all': {
    'fa': 'فعال‌سازی همه',
    'en': 'Turn all on',
    'es': 'Activar todo',
    'de': 'Alle einschalten',
    'fr': 'Tout activer',
    'ar': 'تفعيل الكل',
  },
  'later': {
    'fa': 'بعداً',
    'en': 'Later',
    'es': 'Luego',
    'de': 'Später',
    'fr': 'Plus tard',
    'ar': 'لاحقًا',
  },
  'mag': {
    'fa': 'ذره‌بین',
    'en': 'Magnifier',
    'es': 'Lupa',
    'de': 'Lupe',
    'fr': 'Loupe',
    'ar': 'المكبّرة',
  },
  'live': {
    'fa': 'ترجمه‌ی زنده',
    'en': 'Live translation',
    'es': 'Traducción en vivo',
    'de': 'Live-Übersetzung',
    'fr': 'Traduction en direct',
    'ar': 'الترجمة الفورية',
  },
  'yt': {
    'fa': 'یوتیوب',
    'en': 'YouTube',
    'es': 'YouTube',
    'de': 'YouTube',
    'fr': 'YouTube',
    'ar': 'يوتيوب',
  },
  'done': {
    'fa': 'ابزارها روشن شدند ✓',
    'en': 'Tools are on ✓',
    'es': 'Herramientas activadas ✓',
    'de': 'Tools sind an ✓',
    'fr': 'Outils activés ✓',
    'ar': 'تم تفعيل الأدوات ✓',
  },
};


/// پیامِ دوستانه وقتی مدلِ تشخیص گفتار هنوز در حال آماده‌سازیِ خودکار است (بدونِ اشاره به «دانلود»).
String _packPreparingMsg(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'fa'
        ? 'دستیار تشخیص گفتار در حال آماده‌سازیِ نهایی است ✨ چند دقیقه‌ی دیگه دوباره امتحان کن.'
        : 'Speech recognition is getting ready ✨ Please try again in a few minutes.';

class FeatureDock extends ConsumerStatefulWidget {
  const FeatureDock({super.key});

  /// کلیدِ ذخیره‌ی «پنهان‌کردنِ داک» (از تنظیمات).
  static const String hiddenKey = 'zflut-feature-dock-hidden';

  /// true = کاربر داک را از تنظیمات پنهان کرده. تنظیمات و داک هر دو همین را می‌خوانند.
  static final ValueNotifier<bool> hidden = ValueNotifier<bool>(false);

  @override
  ConsumerState<FeatureDock> createState() => _FeatureDockState();
}

class _FeatureDockState extends ConsumerState<FeatureDock>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const double _pillW = 56;

  late final AnimationController _in = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100));
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400));

  bool _supported = false;
  bool _ready = false;
  bool _first = false;
  bool _expanded = false;
  bool _tip = false;
  bool _busy = false;
  bool _resumed = true;

  bool _mag = false;
  bool _live = false;
  bool _yt = false;

  Timer? _poll;
  Timer? _collapseTimer;

  @override
  void initState() {
    super.initState();
    _supported = NativeBridge.instance.isSupported;
    if (!_supported) return;
    WidgetsBinding.instance.addObserver(this);
    var seen = true;
    try {
      seen = ref.read(sharedPrefsProvider).getBool(_kSeenKey) ?? false;
    } catch (_) {}
    _first = !seen;
    try {
      FeatureDock.hidden.value =
          ref.read(sharedPrefsProvider).getBool(FeatureDock.hiddenKey) ?? false;
    } catch (_) {}
    FeatureDock.hidden.addListener(_onHidden);
    // کمی بعد از بالا آمدنِ صفحه، تا ورودِ اسلایدی کاملاً دیده شود
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() {
        _ready = true;
        _expanded = _first;
        _tip = _first;
      });
      _in.forward();
      if (_first) {
        _pulse.repeat(reverse: true);
        _armCollapse(14);
      }
      _refresh();
    });
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
  }

  void _onHidden() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (_supported) {
      WidgetsBinding.instance.removeObserver(this);
      FeatureDock.hidden.removeListener(_onHidden);
    }
    _poll?.cancel();
    _collapseTimer?.cancel();
    _in.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    if (_resumed) _refresh();
  }

  // ───────────────────────── وضعیت ─────────────────────────
  Future<void> _refresh() async {
    if (!mounted || !_ready || !_resumed) return;
    try {
      final n = NativeBridge.instance;
      final m = (await n.magnifierIsRunning())['running'] == true;
      final l = (await n.isRunning())['running'] == true;
      final y = (await n.ytIsActive())['active'] == true;
      if (mounted && (m != _mag || l != _live || y != _yt)) {
        setState(() {
          _mag = m;
          _live = l;
          _yt = y;
        });
      }
    } catch (_) {}
  }

  void _markSeen() {
    try {
      ref.read(sharedPrefsProvider).setBool(_kSeenKey, true);
    } catch (_) {}
  }

  void _armCollapse(int seconds) {
    _collapseTimer?.cancel();
    _collapseTimer = Timer(Duration(seconds: seconds), () {
      if (!mounted || _busy) return;
      _collapse();
    });
  }

  void _collapse() {
    _collapseTimer?.cancel();
    _markSeen();
    _pulse.stop();
    _pulse.reset();
    if (!mounted) return;
    setState(() {
      _expanded = false;
      _tip = false;
    });
  }

  void _expand() {
    setState(() => _expanded = true);
    _armCollapse(6);
  }

  // ───────────────────────── متن‌ها و گفتگوها ─────────────────────────
  String get _lang => ref.read(appPrefsProvider).uiLang;
  bool get _rtl => _lang == 'fa' || _lang == 'ar';
  String _s(String k) => _tx[k]![_lang] ?? _tx[k]!['en']!;

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  Future<bool> _ask(String title, Widget content) async {
    if (!mounted) return false;
    final ml = MaterialLocalizations.of(context);
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
        child: AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: content),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(ml.cancelButtonLabel)),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(ml.continueButtonLabel)),
          ],
        ),
      ),
    );
    return go == true;
  }

  // ───────────────────────── مجوزها (مثل تنظیمات) ─────────────────────────
  Future<bool> _ensureOverlay() async {
    if (await LinLearnBridge.canDrawOverlays()) return true;
    if (!mounted) return false;
    final ok =
        await _ask(context.l10n.st_overlay_title, Text(context.l10n.st_overlay_body));
    if (!ok) return false;
    await LinLearnBridge.requestOverlayPermission();
    for (var i = 0; i < 90 && mounted; i++) {
      await Future.delayed(const Duration(milliseconds: 700));
      if (await LinLearnBridge.canDrawOverlays()) return true;
    }
    return false;
  }

  Future<bool> _ensureScreenInfo() async {
    final sp = ref.read(sharedPrefsProvider);
    if (sp.getBool(_kScreenInfoKey) == true) return true;
    if (!mounted) return false;
    final ok = await _ask(
        context.l10n.st_screenrec_title, Text(context.l10n.st_screenrec_body));
    if (!ok) return false;
    await sp.setBool(_kScreenInfoKey, true);
    return true;
  }

  Future<bool> _ensureNotif() async {
    if (await LinLearnBridge.ytCheckAccess()) return true;
    if (!mounted) return false;
    final ok = await _ask(
      context.l10n.st_notif_title,
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.st_notif_trust),
          const SizedBox(height: 10),
          Text(context.l10n.settings_notification_access_needed),
        ],
      ),
    );
    if (!ok) return false;
    await LinLearnBridge.ytRequestAccess();
    for (var i = 0; i < 90 && mounted; i++) {
      await Future.delayed(const Duration(milliseconds: 700));
      if (await LinLearnBridge.ytCheckAccess()) return true;
    }
    return false;
  }

  /// مثل تنظیمات: اگر بسته‌ی آفلاینِ «زبان صدا» دانلود نشده، یک‌بار می‌پرسد و دانلود را شروع می‌کند.
  /// true = می‌شود ادامه داد؛ false = اول باید بسته دانلود شود.
  Future<bool> _ensureSpeechPack() async {
    final sp = ref.read(sharedPrefsProvider);
    final auto = sp.getBool(_kAutoKey) == true;
    var src = sp.getString(_kSrcKey);
    if (src == null || !_srcNames.containsKey(src)) src = 'en';
    // موتورِ Google انتخاب شده: بسته‌ی آفلاین شرطِ شروع نیست
    if (sp.getString(_kSpeechProviderKey) == 'google' && !auto) return true;
    String? packKind;
    if (!auto && kDedicatedPackLangs.contains(src)) {
      packKind = 'speech';
    } else if (!auto &&
        kLatinPackLangs.contains(src) &&
        await LinLearnBridge.latinAsrEngine() == 'vosk') {
      packKind = 'vosk';
    }
    if (packKind == null) {
      return _ensureAutoPack(auto ? null : _srcNames[src]);
    }
    final pack = await LinLearnBridge.packStatus(packKind, src);
    if (pack == null || pack['downloaded'] == true) return true;
    if (!mounted) return false;
    if (pack['downloading'] == true) {
      _toast(_packPreparingMsg(context));
      return false;
    }
    await LinLearnBridge.packDownload(packKind, src);
    if (mounted) _toast(_packPreparingMsg(context));
    return false;
  }

  /// حالتِ «خودکار» / زبان‌های بدونِ بسته‌ی اختصاصی: اگر هیچ مدلِ چندزبانه نیست «base» را دانلود می‌کند.
  Future<bool> _ensureAutoPack(String? langName) async {
    Map<String, dynamic>? baseSt;
    for (final id in const ['base', 'small', 'tiny']) {
      final st = await LinLearnBridge.packStatus('song', id);
      if (st == null) return true; // پشتیبانی نمی‌شود/خطا: مانعِ شروع نشو
      if (st['downloaded'] == true) return true;
      if (id == 'base') baseSt = st;
      if (st['downloading'] == true) {
        if (mounted) _toast(_packPreparingMsg(context));
        return false;
      }
    }
    if (baseSt == null || !mounted) return false;
    await LinLearnBridge.packDownload('song', 'base');
    if (mounted) _toast(_packPreparingMsg(context));
    return false;
  }

  /// زبان‌ها + رنگ/حالتِ نمایشِ ذخیره‌شده‌ی کاربر را به حباب می‌رساند.
  Future<void> _prepare() async {
    try {
      await ref.read(nativeSyncProvider).pushLangs();
    } catch (_) {}
    final sp = ref.read(sharedPrefsProvider);
    var color = sp.getString(_kColorKey);
    if (color == null || !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(color)) {
      color = '#1C2541';
    }
    var disp = sp.getString(_kDispKey);
    if (disp != 'both' && disp != 'translation' && disp != 'original') {
      disp = 'both';
    }
    await LinLearnBridge.setBubbleOptions(
        panelColor: color.toUpperCase(), displayMode: disp);
  }

  // ───────────────────────── کنش‌ها ─────────────────────────
  Future<void> _guard(Future<void> Function() body) async {
    if (_busy) return;
    setState(() => _busy = true);
    _collapseTimer?.cancel();
    try {
      await body();
    } catch (e) {
      _toast(context.l10n.st_error('$e'));
    } finally {
      try {
        await ref.read(bubbleProvider.notifier).syncFromNative();
      } catch (_) {}
      if (mounted) {
        setState(() => _busy = false);
        await _refresh();
        if (_expanded && !_tip) _armCollapse(6);
      }
    }
  }

  Future<void> _toggleMag() => _guard(() async {
        if (_mag) {
          await NativeBridge.instance.magnifierStop();
          return;
        }
        if (!await _ensureOverlay()) return;
        if (!await _ensureScreenInfo()) return;
        await _prepare();
        await ref.read(bubbleProvider.notifier).start(mode: 'magnifier');
      });

  Future<void> _toggleLive() => _guard(() async {
        if (_live) {
          await NativeBridge.instance.hideBubble();
          return;
        }
        if (!await _ensureOverlay()) return;
        if (!await _ensureScreenInfo()) return;
        // ترجمه‌ی زنده آفلاین کار می‌کند: بسته‌ی زبانِ صدا باید روی گوشی باشد
        if (!await _ensureSpeechPack()) return;
        await _prepare();
        await ref.read(bubbleProvider.notifier).start(mode: 'translator');
      });

  Future<void> _toggleYt() => _guard(() async {
        if (_yt) {
          await LinLearnBridge.ytSetEnabled(false);
          return;
        }
        if (!await _ensureOverlay()) return;
        if (!await _ensureNotif()) return;
        await _prepare();
        if (!_live) {
          // زیرنویسِ یوتیوب «ترجمه‌ی زنده» حساب نمی‌شود (سقفِ جدا دارد)
          await ref
              .read(bubbleProvider.notifier)
              .start(mode: 'translator', countLive: false);
        }
        await _prepare();
        await LinLearnBridge.ytSetEnabled(true);
      });

  Future<void> _activateAll() => _guard(() async {
        _markSeen();
        if (!await _ensureOverlay()) return;
        if (!await _ensureScreenInfo()) return;
        // اگر بسته‌ی صدا هنوز نیست: ذره‌بین و یوتیوب روشن می‌شوند، ترجمه‌ی زنده بعد از دانلود
        final packOk = await _ensureSpeechPack();
        await _prepare();
        await ref
            .read(bubbleProvider.notifier)
            .start(mode: packOk ? 'both' : 'magnifier');
        if (await _ensureNotif()) {
          await LinLearnBridge.ytSetEnabled(true);
        }
        if (mounted) {
          _toast(_s('done'));
          _collapse();
        }
      });

  // ───────────────────────── ظاهر ─────────────────────────
  @override
  Widget build(BuildContext context) {
    if (!_supported || !_ready || FeatureDock.hidden.value) {
      return const SizedBox.shrink();
    }
    ref.listen<bool>(
        bubbleProvider.select((s) => s.running), (_, __) => _refresh());
    final c = context.appColors;
    final size = MediaQuery.of(context).size;

    final pill = _buildPill(c);
    final tipW = (size.width - _pillW - 24).clamp(180.0, 250.0).toDouble();

    return Positioned(
      right: 0,
      top: size.height * 0.30,
      child: Directionality(
        textDirection: TextDirection.ltr, // جایگاهِ فیزیکی: همیشه لبه‌ی راست
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(1.4, 0), end: Offset.zero)
              .animate(CurvedAnimation(parent: _in, curve: Curves.easeOutBack)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                            begin: const Offset(0.25, 0), end: Offset.zero)
                        .animate(anim),
                    child: child,
                  ),
                ),
                child: _tip
                    ? _buildTip(c, tipW)
                    : const SizedBox.shrink(key: ValueKey('no-tip')),
              ),
              if (_tip) const SizedBox(width: 8),
              pill,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTip(AppThemeColorsExt c, double w) {
    final chips = <Widget>[
      _chip(c, Icons.search_rounded, _s('mag')),
      _chip(c, Icons.translate_rounded, _s('live')),
      _chip(c, Icons.smart_display_rounded, _s('yt')),
    ];
    return Directionality(
      key: const ValueKey('tip'),
      textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
      child: Material(
        color: c.paper,
        elevation: 8,
        shadowColor: Colors.black54,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: w,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.gold.withOpacity(0.55)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_s('title'),
                  style: TextStyle(
                      color: c.ink,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      height: 1.4)),
              const SizedBox(height: 6),
              Text(_s('body'),
                  style:
                      TextStyle(color: c.inkSoft, fontSize: 12.2, height: 1.65)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: chips),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: c.gold,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _busy ? null : _activateAll,
                      child: Text(_s('all'),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: _busy ? null : _collapse,
                    child: Text(_s('later'),
                        style: TextStyle(color: c.inkSoft, fontSize: 12.5)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(AppThemeColorsExt c, IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: c.goldSoft,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: c.gold),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: c.ink, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _buildPill(AppThemeColorsExt c) {
    final pill = Container(
      width: _pillW,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: c.paper,
        borderRadius:
            const BorderRadius.horizontal(left: Radius.circular(28)),
        border: Border.all(color: c.cardBorder),
        boxShadow: const [
          BoxShadow(
              color: Colors.black26, blurRadius: 14, offset: Offset(-2, 3)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _collapse,
            child: SizedBox(
              height: 22,
              width: _pillW,
              child: Icon(Icons.chevron_right_rounded,
                  size: 20, color: c.inkSoft),
            ),
          ),
          _dockIcon(c, 0, Icons.search_rounded, _s('mag'), _mag, _toggleMag),
          const SizedBox(height: 6),
          _dockIcon(
              c, 1, Icons.translate_rounded, _s('live'), _live, _toggleLive),
          const SizedBox(height: 6),
          _dockIcon(
              c, 2, Icons.smart_display_rounded, _s('yt'), _yt, _toggleYt),
          const SizedBox(height: 4),
        ],
      ),
    );

    // وقتی جمع است فقط یک زبانه‌ی باریک کنارِ لبه دیده می‌شود؛ لمسش داک را باز می‌کند.
    return AnimatedSlide(
      offset: Offset(_expanded ? 0 : 0.68, 0),
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _expanded ? null : _expand,
        child: AbsorbPointer(absorbing: !_expanded, child: pill),
      ),
    );
  }

  Widget _dockIcon(AppThemeColorsExt c, int i, IconData icon, String label,
      bool on, Future<void> Function() onTap) {
    final pop = CurvedAnimation(
      parent: _in,
      curve: Interval(0.35 + i * 0.15, (0.8 + i * 0.1).clamp(0.0, 1.0).toDouble(),
          curve: Curves.elasticOut),
    );
    return ScaleTransition(
      scale: pop,
      child: Tooltip(
        message: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _busy ? null : onTap,
          child: SizedBox(
            width: 46,
            height: 46,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                if (_tip)
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (_, __) => Container(
                      width: 42 + 10 * _pulse.value,
                      height: 42 + 10 * _pulse.value,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: c.gold.withOpacity(0.7 * (1 - _pulse.value)),
                            width: 2),
                      ),
                    ),
                  ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: on ? c.gold : c.goldSoft,
                  ),
                  child: Icon(icon,
                      size: 21, color: on ? Colors.white : c.gold),
                ),
                if (on)
                  Positioned(
                    top: 3,
                    right: 3,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2ECC71),
                        shape: BoxShape.circle,
                        border: Border.all(color: c.paper, width: 1.8),
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
}


/// ردیفِ تیک در تنظیمات: نمایش/پنهان‌کردنِ داکِ ابزارها (لبه‌ی راست).
class FeatureDockToggleRow extends ConsumerWidget {
  const FeatureDockToggleRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!NativeBridge.instance.isSupported) return const SizedBox.shrink();
    final c = context.appColors;
    final lang = ref.watch(appPrefsProvider).uiLang;
    final label = _tx['show']![lang] ?? _tx['show']!['en']!;
    return ValueListenableBuilder<bool>(
      valueListenable: FeatureDock.hidden,
      builder: (_, hidden, __) => InkWell(
        onTap: () {
          final v = !hidden;
          FeatureDock.hidden.value = v;
          try {
            ref.read(sharedPrefsProvider).setBool(FeatureDock.hiddenKey, v);
          } catch (_) {}
        },
        child: Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 10),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: !hidden,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  activeColor: c.gold,
                  onChanged: (_) {
                    final v = !hidden;
                    FeatureDock.hidden.value = v;
                    try {
                      ref
                          .read(sharedPrefsProvider)
                          .setBool(FeatureDock.hiddenKey, v);
                    } catch (_) {}
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        color: c.inkSoft,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
