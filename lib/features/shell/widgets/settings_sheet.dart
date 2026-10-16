import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/bridge/linlearn_bridge.dart';
import '../../../core/constants/app_font_sizes.dart';
import '../../../core/constants/app_fonts.dart';
import '../../../core/constants/app_languages.dart';
import '../../../core/constants/app_themes.dart';
import '../../../core/models/text_prefs.dart';
import '../../../core/providers/ai_settings_provider.dart';
import '../../../core/providers/app_prefs_provider.dart';
import '../../../core/providers/linlearn_provider.dart';
import '../../../core/providers/text_prefs_provider.dart';
import '../../../core/storage/local_storage.dart' show sharedPrefsProvider;
import '../../../core/theme/app_theme_colors.dart';
import '../../auth/providers/auth_provider.dart';

class SettingsSheet extends ConsumerWidget {
  const SettingsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SettingsSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;

    return Container(
      decoration: BoxDecoration(
        color: c.paper,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (_, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: const [
              _DragHandle(),
              SizedBox(height: 8),
              _AccountSection(),
              SizedBox(height: 24),
              _LanguageSection(),
              SizedBox(height: 24),
              _ThemeSection(),
              SizedBox(height: 24),
              _FontSection(),
              SizedBox(height: 24),
              _FontSizeSection(),
              SizedBox(height: 24),
              _TargetTextSection(),
              SizedBox(height: 24),
              _CalendarSection(),
              SizedBox(height: 24),
              _HighlightSection(),
              SizedBox(height: 24),
              _FloatingBubbleSection(),
              SizedBox(height: 24),
              _BackendUrlSection(),
              SizedBox(height: 24),
              _FooterVersion(),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: c.inkSoft.withOpacity(0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
class _SectionTitle extends StatelessWidget {
  final IconData? icon;
  final String label;

  const _SectionTitle({this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: c.inkSoft),
          const SizedBox(width: 8),
        ],
        Text(
          label,
          style: TextStyle(
            color: c.inkSoft,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Account
// ═══════════════════════════════════════════════════════════════════
class _AccountSection extends ConsumerWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;

    String displayName = 'مهمان';
    String displayEmail = 'حساب متصل نیست';
    bool isSignedIn = false;

    try {
      final repo = ref.read(authRepositoryProvider);
      final user = repo.currentSession?.user;
      if (user != null) {
        isSignedIn = true;
        displayEmail = user.email ?? '—';
        final meta = user.userMetadata;
        displayName = (meta?['name'] as String?) ??
            (displayEmail.contains('@')
                ? displayEmail.split('@').first
                : displayEmail);
      }
    } catch (_) {}

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(label: 'حساب کاربری'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.paperDark.withOpacity(0.6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.cardBorder),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [c.teal, c.headerFrom],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      displayName.isNotEmpty
                          ? displayName[0].toUpperCase()
                          : '؟',
                      style: TextStyle(
                        color: c.headerText,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: TextStyle(
                            color: c.ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          displayEmail,
                          style: TextStyle(
                            color: c.inkSoft,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (isSignedIn)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        await ref.read(authRepositoryProvider).signOut();
                      } catch (_) {}
                      if (context.mounted) Navigator.pop(context);
                    },
                    icon: Icon(Icons.logout, size: 16, color: c.rose),
                    label: Text(
                      'خروج از حساب',
                      style: TextStyle(color: c.rose, fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: c.rose.withOpacity(0.4)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                )
              else
                Text(
                  'برای ذخیره‌ی پیشرفت، وارد حساب شوید.',
                  style: TextStyle(color: c.inkSoft, fontSize: 12),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Language
// ═══════════════════════════════════════════════════════════════════
class _LanguageSection extends ConsumerWidget {
  const _LanguageSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(appPrefsProvider);
    final notifier = ref.read(appPrefsProvider.notifier);
    final c = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(icon: Icons.language, label: 'زبان نرم‌افزار'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.cardBorder),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: prefs.uiLang,
              isExpanded: true,
              icon: Icon(Icons.keyboard_arrow_down, color: c.inkSoft),
              dropdownColor: Colors.white,
              style: TextStyle(color: c.ink, fontSize: 15),
              items: kAppLanguages.values
                  .map((l) => DropdownMenuItem(
                        value: l.code,
                        child: Text(l.label),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) notifier.setUiLang(v);
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Theme
// ═══════════════════════════════════════════════════════════════════
class _ThemeSection extends ConsumerWidget {
  const _ThemeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(appPrefsProvider);
    final notifier = ref.read(appPrefsProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(icon: Icons.palette_outlined, label: 'رنگ و تم'),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            const cols = 6;
            const spacing = 10.0;
            final size =
                (constraints.maxWidth - spacing * (cols - 1)) / cols;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: kAppThemes.values.map((t) {
                final selected = t.key == prefs.theme;
                return _ThemeSwatch(
                  preset: t,
                  selected: selected,
                  size: size,
                  onTap: () => notifier.setTheme(t.key),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  final AppThemePreset preset;
  final bool selected;
  final double size;
  final VoidCallback onTap;

  const _ThemeSwatch({
    required this.preset,
    required this.selected,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [preset.colors.headerFrom, preset.colors.headerTo],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? c.gold : Colors.black.withOpacity(0.06),
            width: selected ? 2.5 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: c.gold.withOpacity(0.35),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: selected
            ? const Icon(Icons.check, color: Colors.white, size: 22)
            : null,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Font
// ═══════════════════════════════════════════════════════════════════
class _FontSection extends ConsumerWidget {
  const _FontSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(appPrefsProvider);
    final notifier = ref.read(appPrefsProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(icon: Icons.text_format, label: 'نوع فونت'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: kAppFonts.values.map((f) {
            final selected = f.key == prefs.font;
            return _ChoiceChip(
              label: f.label['fa'] ?? f.key,
              selected: selected,
              onTap: () => notifier.setFont(f.key),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Font Size
// ═══════════════════════════════════════════════════════════════════
class _FontSizeSection extends ConsumerWidget {
  const _FontSizeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(appPrefsProvider);
    final notifier = ref.read(appPrefsProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(icon: Icons.format_size, label: 'اندازه‌ی فونت'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: kAppFontSizes.values.map((s) {
            final selected = s.key == prefs.fontSize;
            return _ChoiceChip(
              label: s.label['fa'] ?? s.key,
              selected: selected,
              onTap: () => notifier.setFontSize(s.key),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
class _ChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Material(
      color: selected ? c.gold.withOpacity(0.85) : Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? c.gold : c.cardBorder,
              width: 1.2,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: selected ? Colors.white : c.ink,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Target Text
// ═══════════════════════════════════════════════════════════════════
class _TargetTextSection extends ConsumerWidget {
  const _TargetTextSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textPrefs = ref.watch(textPrefsProvider);
    final notifier = ref.read(textPrefsProvider.notifier);
    final c = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          icon: Icons.format_size,
          label: 'اندازه‌ی فونت زبان‌های مقصد',
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            IconButton(
              onPressed: () {
                final next = (textPrefs.scale - 5).clamp(50, 250);
                notifier.setScale(next);
              },
              icon: Icon(Icons.remove_circle_outline, color: c.inkSoft),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: c.gold,
                  inactiveTrackColor: c.cardBorder,
                  thumbColor: c.gold,
                  overlayColor: c.gold.withOpacity(0.15),
                  trackHeight: 4,
                ),
                child: Slider(
                  value: textPrefs.scale.toDouble(),
                  min: 50,
                  max: 250,
                  divisions: 40,
                  onChanged: (v) => notifier.setScale(v.toInt()),
                ),
              ),
            ),
            IconButton(
              onPressed: () {
                final next = (textPrefs.scale + 5).clamp(50, 250);
                notifier.setScale(next);
              },
              icon: Icon(Icons.add_circle_outline, color: c.inkSoft),
            ),
            SizedBox(
              width: 52,
              child: Text(
                '${textPrefs.scale}%',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: c.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const _SectionTitle(label: 'بولد شدن متن زبان مقصد'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _BoldChip(
              label: 'هر دو',
              value: TargetBoldMode.both,
              current: textPrefs.bold,
              onTap: () => notifier.setBold(TargetBoldMode.both),
            ),
            _BoldChip(
              label: 'فقط متن',
              value: TargetBoldMode.text,
              current: textPrefs.bold,
              onTap: () => notifier.setBold(TargetBoldMode.text),
            ),
            _BoldChip(
              label: 'فقط ترجمه',
              value: TargetBoldMode.translation,
              current: textPrefs.bold,
              onTap: () => notifier.setBold(TargetBoldMode.translation),
            ),
            _BoldChip(
              label: 'هیچ‌کدام',
              value: TargetBoldMode.none,
              current: textPrefs.bold,
              onTap: () => notifier.setBold(TargetBoldMode.none),
            ),
          ],
        ),
      ],
    );
  }
}

class _BoldChip extends StatelessWidget {
  final String label;
  final TargetBoldMode value;
  final TargetBoldMode current;
  final VoidCallback onTap;

  const _BoldChip({
    required this.label,
    required this.value,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _ChoiceChip(
      label: label,
      selected: value == current,
      onTap: onTap,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Calendar — تقویم تاریخ‌ها (معادل settings_calendar_title در Hope)
// ═══════════════════════════════════════════════════════════════════
class _CalendarSection extends ConsumerWidget {
  const _CalendarSection();

  static const Map<CalendarSystem, String> _labels = {
    CalendarSystem.gregorian: 'میلادی',
    CalendarSystem.jalali: 'شمسی',
    CalendarSystem.both: 'هر دو',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current =
        ref.watch(appPrefsProvider.select((p) => p.calendarSystem));
    final notifier = ref.read(appPrefsProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          icon: Icons.calendar_month_outlined,
          label: 'تقویم تاریخ‌ها',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _labels.entries
              .map((e) => _ChoiceChip(
                    label: e.value,
                    selected: e.key == current,
                    onTap: () => notifier.setCalendarSystem(e.key),
                  ))
              .toList(),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Highlight color — رنگ هایلایت موقع خواندن خودکار
// ═══════════════════════════════════════════════════════════════════
const List<String> _kHighlightPalette = [
  '#F7E98E', '#FBD9AE', '#F7C48C', '#F1968E',
  '#DCE07E', '#9AD98A', '#8DE0BE', '#A6DEE9',
  '#A9C7F0', '#C7B6EC', '#F0AEEC', '#F4AAC0',
];

Color _hexToColor(String hex) {
  final h = hex.replaceFirst('#', '');
  return Color(int.parse('FF$h', radix: 16));
}

class _HighlightSection extends ConsumerWidget {
  const _HighlightSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final current =
        ref.watch(appPrefsProvider.select((p) => p.highlightColor));
    final notifier = ref.read(appPrefsProvider.notifier);

    Widget swatch({
      required Color color,
      required bool selected,
      required VoidCallback onTap,
      Widget? child,
      String? tooltip,
    }) {
      return Tooltip(
        message: tooltip ?? '',
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? c.gold : c.cardBorder,
                width: selected ? 2.5 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: child,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          icon: Icons.highlight_outlined,
          label: 'رنگ هایلایت موقع خواندن',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            swatch(
              color: Colors.white,
              selected: current == 'none',
              tooltip: 'بدون هایلایت',
              onTap: () => notifier.setHighlightColor('none'),
              child: Icon(Icons.close, size: 16, color: c.inkSoft),
            ),
            for (final hex in _kHighlightPalette)
              swatch(
                color: _hexToColor(hex),
                selected: current.toUpperCase() == hex,
                tooltip: hex,
                onTap: () => notifier.setHighlightColor(hex),
              ),
          ],
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Floating bubble — حباب شناور (ذره‌بین / ترجمه‌ی زنده) — فقط اندروید
// ═══════════════════════════════════════════════════════════════════
class _FloatingBubbleSection extends ConsumerStatefulWidget {
  const _FloatingBubbleSection();

  @override
  ConsumerState<_FloatingBubbleSection> createState() =>
      _FloatingBubbleSectionState();
}

class _FloatingBubbleSectionState
    extends ConsumerState<_FloatingBubbleSection> {
  static const String _kKindKey = 'phrasebook-bubble-kind';
  static const String _kSrcKey = 'phrasebook-live-src-lang';
  static const String _kDispKey = 'phrasebook-live-display-mode';
  static const String _kColorKey = 'phrasebook-bubble-panel-color';

  static const String _defaultColor = '#1C2541';
  static const List<String> _colors = [
    '#1C2541', '#14342B', '#3A1F2B', '#2B2B33', '#2E2352', '#0F3A44',
  ];

  static const Map<String, String> _kinds = {
    'magnifier': 'ذره‌بین',
    'live': 'ترجمه‌ی زنده',
    'both': 'هر دو',
  };

  static const Map<String, String> _displayModes = {
    'both': 'متن + ترجمه',
    'translation': 'فقط ترجمه',
    'original': 'فقط متن اصلی',
  };

  static const Map<String, String> _srcLangs = {
    'en': 'English', 'de': 'Deutsch', 'fr': 'Français', 'es': 'Español',
    'it': 'Italiano', 'tr': 'Türkçe', 'ar': 'العربية', 'ru': 'Русский',
    'ja': '日本語', 'ko': '한국어', 'zh': '中文', 'hi': 'हिन्दी',
    'pt': 'Português', 'nl': 'Nederlands', 'ur': 'اردو', 'fa': 'فارسی',
  };

  late String _kind;
  late String _src;
  late String _disp;
  late String _color;
  bool _busy = false;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    final sp = ref.read(sharedPrefsProvider);
    final kind = sp.getString(_kKindKey);
    final src = sp.getString(_kSrcKey);
    final disp = sp.getString(_kDispKey);
    final color = sp.getString(_kColorKey);
    _kind = _kinds.containsKey(kind) ? kind! : 'both';
    _src = _srcLangs.containsKey(src) ? src! : 'en';
    _disp = _displayModes.containsKey(disp) ? disp! : 'both';
    _color = (color != null && RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(color))
        ? color.toUpperCase()
        : _defaultColor;
  }

  Future<void> _save(String key, String value) async {
    await ref.read(sharedPrefsProvider).setString(key, value);
  }

  /// رنگ‌های روشن را تیره می‌کند تا متن سفیدِ حباب خوانا بماند (مثل Hope).
  String _ensureDark(String hex) {
    try {
      var r = int.parse(hex.substring(1, 3), radix: 16);
      var g = int.parse(hex.substring(3, 5), radix: 16);
      var b = int.parse(hex.substring(5, 7), radix: 16);
      final lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
      if (lum > 0.42) {
        final k = 0.42 / lum;
        r = (r * k).round();
        g = (g * k).round();
        b = (b * k).round();
      }
      String h(int x) => x.toRadixString(16).padLeft(2, '0');
      return '#${h(r)}${h(g)}${h(b)}'.toUpperCase();
    } catch (_) {
      return _defaultColor;
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  /// رنگ/حالت نمایش را (اگر سمت نیتیو پشتیبانی کند) به حباب می‌فرستد.
  Future<void> _pushOptions() =>
      LinLearnBridge.setBubbleOptions(panelColor: _color, displayMode: _disp);

  Future<bool> _ensureOverlay() async {
    if (await LinLearnBridge.canDrawOverlays()) return true;
    await LinLearnBridge.requestOverlayPermission();
    _toast('اجازه‌ی «نمایش روی سایر برنامه‌ها» را بدهید و دوباره امتحان کنید.');
    return false;
  }

  Future<void> _toggleBubble() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final notifier = ref.read(bubbleProvider.notifier);
      if (ref.read(bubbleProvider).running) {
        await notifier.stop();
      } else {
        if (!await _ensureOverlay()) return;
        await _pushOptions();
        await notifier.start(mode: _kind == 'live' ? 'translator' : _kind);
      }
    } catch (e) {
      _toast('خطا: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleLive() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final notifier = ref.read(liveTranslatorProvider.notifier);
      if (ref.read(liveTranslatorProvider)) {
        await notifier.stop();
      } else {
        if (!await _ensureOverlay()) return;
        await _pushOptions();
        await notifier.start(
          sourceLang: _src,
          targetLang: ref.read(appPrefsProvider).uiLang,
        );
      }
    } catch (e) {
      _toast('خطا: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final bubbleRunning = ref.watch(bubbleProvider.select((s) => s.running));
    final liveRunning = ref.watch(liveTranslatorProvider);
    final showLive = _kind != 'magnifier';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          icon: Icons.bubble_chart_outlined,
          label: 'دکمه‌های شناور (ذره‌بین و ترجمه‌ی زنده)',
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.paperDark.withOpacity(0.6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.cardBorder),
          ),
          child: !_isAndroid
              ? Text(
                  'حباب شناور فقط در نسخه‌ی اندروید کار می‌کند.',
                  style: TextStyle(color: c.inkSoft, fontSize: 12.5),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _kinds.entries
                          .map((e) => _ChoiceChip(
                                label: e.value,
                                selected: _kind == e.key,
                                onTap: () {
                                  setState(() => _kind = e.key);
                                  _save(_kKindKey, e.key);
                                },
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'رنگ کادر حباب',
                      style: TextStyle(
                        color: c.inkSoft,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final hex in _colors)
                          GestureDetector(
                            onTap: () {
                              final v = _ensureDark(hex);
                              setState(() => _color = v);
                              _save(_kColorKey, v);
                              _pushOptions();
                            },
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: _hexToColor(hex),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _color == hex ? c.gold : c.cardBorder,
                                  width: _color == hex ? 2.5 : 1,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _BubbleButton(
                      icon: bubbleRunning ? Icons.stop_circle_outlined : Icons.search,
                      label: bubbleRunning
                          ? 'بستن حباب'
                          : (_kind == 'live'
                              ? 'نمایش حباب ترجمه'
                              : 'نمایش حباب ذره‌بین'),
                      busy: _busy,
                      onTap: _toggleBubble,
                    ),
                    if (showLive) ...[
                      const SizedBox(height: 16),
                      Text(
                        'زبان صدایی که پخش می‌شود',
                        style: TextStyle(
                          color: c.inkSoft,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _DropBox(
                        value: _src,
                        items: _srcLangs,
                        onChanged: (v) {
                          setState(() => _src = v);
                          _save(_kSrcKey, v);
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'نمایش در حباب',
                        style: TextStyle(
                          color: c.inkSoft,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _DropBox(
                        value: _disp,
                        items: _displayModes,
                        onChanged: (v) {
                          setState(() => _disp = v);
                          _save(_kDispKey, v);
                          _pushOptions();
                        },
                      ),
                      const SizedBox(height: 12),
                      _BubbleButton(
                        icon: liveRunning ? Icons.stop_circle_outlined : Icons.mic_none,
                        label: liveRunning
                            ? 'توقف ترجمه‌ی زنده'
                            : 'شروع ترجمه‌ی زنده‌ی صدا',
                        busy: _busy,
                        onTap: _toggleLive,
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _BubbleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback onTap;

  const _BubbleButton({
    required this.icon,
    required this.label,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: busy ? null : onTap,
        icon: Icon(icon, size: 18, color: c.ink),
        label: Text(
          label,
          style: TextStyle(
            color: c.ink,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: c.goldSoft.withOpacity(0.5),
          side: BorderSide(color: c.gold),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

class _DropBox extends StatelessWidget {
  final String value;
  final Map<String, String> items;
  final ValueChanged<String> onChanged;

  const _DropBox({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.cardBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down, color: c.inkSoft),
          dropdownColor: Colors.white,
          style: TextStyle(color: c.ink, fontSize: 14),
          items: items.entries
              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Backend URL — آدرس Cloudflare Worker
// ═══════════════════════════════════════════════════════════════════
class _BackendUrlSection extends ConsumerStatefulWidget {
  const _BackendUrlSection();

  @override
  ConsumerState<_BackendUrlSection> createState() => _BackendUrlSectionState();
}

class _BackendUrlSectionState extends ConsumerState<_BackendUrlSection> {
  late final TextEditingController _ctrl;
  bool _saved = false;

  // URL پیش‌فرض — همون Worker خودت
  static const String _defaultUrl =
      'https://phrasebook-api.maryam-s-sharifiyan.workers.dev';

  @override
  void initState() {
    super.initState();
    final current = ref.read(aiSettingsProvider).backendUrl;
    _ctrl = TextEditingController(
      text: current.isEmpty ? _defaultUrl : current,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ref.read(aiSettingsProvider.notifier).setBackendUrl(_ctrl.text);
    if (mounted) {
      setState(() => _saved = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ آدرس ذخیره شد'),
          duration: Duration(seconds: 2),
        ),
      );
      // بعد از ۲ ثانیه، تیک رو برداشت
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _saved = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          icon: Icons.cloud_outlined,
          label: 'آدرس سرور هوش مصنوعی (Cloudflare Worker)',
        ),
        const SizedBox(height: 8),
        Text(
          'برای ترجمه‌ی دقیق‌تر و ساخت داستان با AI، آدرس Worker خودت را این‌جا وارد کن.',
          style: TextStyle(color: c.inkSoft, fontSize: 11.5, height: 1.6),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _ctrl,
          textAlign: TextAlign.left,
          keyboardType: TextInputType.url,
          textDirection: TextDirection.ltr,
          style: TextStyle(color: c.ink, fontSize: 12.5),
          decoration: InputDecoration(
            hintText: 'https://...',
            hintStyle: TextStyle(color: c.inkSoft.withOpacity(0.5)),
            filled: true,
            fillColor: Colors.white,
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
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _saved ? const Color(0xFF2E9E7B) : c.gold,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: _save,
            icon: Icon(
              _saved ? Icons.check : Icons.save_outlined,
              size: 18,
            ),
            label: Text(_saved ? 'ذخیره شد' : 'ذخیره'),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
class _FooterVersion extends StatelessWidget {
  const _FooterVersion();

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Center(
      child: Text(
        'LingoLearn · build 3',
        style: TextStyle(
          color: c.inkSoft.withOpacity(0.6),
          fontSize: 12,
        ),
      ),
    );
  }
}
