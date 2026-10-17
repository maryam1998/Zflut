import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app.dart';
import '../../../core/bridge/linlearn_bridge.dart';
import '../../../core/constants/app_font_sizes.dart';
import '../../../core/constants/app_fonts.dart';
import '../../../core/constants/app_languages.dart';
import '../../../core/constants/app_themes.dart';
import '../../../core/constants/supported_languages.dart';
import '../../../core/mascot/mascot_pin_provider.dart';
import '../../../core/models/text_prefs.dart';
import '../../../core/providers/app_prefs_provider.dart';
import '../../../core/providers/linlearn_provider.dart';
import '../../../core/providers/text_prefs_provider.dart';
import '../../../core/storage/local_storage.dart' show sharedPrefsProvider;
import '../../../core/theme/app_theme_colors.dart';
import '../../auth/providers/auth_provider.dart';
import 'settings_packs.dart';

class SettingsSheet extends ConsumerWidget {
  const SettingsSheet({super.key});

  /// مثل Hope: یک پنل بازشونده‌ی کوچک زیر دکمه‌ی منو (نه تمام‌صفحه).
  /// اندازه و جای پنل از روی اسکرین‌شات‌های Hope: چپِ صفحه، حدود ۶۵٪ عرض و ۷۰٪ ارتفاع.
  static Future<void> show(BuildContext context) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: context.l10n.import_close,
      barrierColor: Colors.black26,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (ctx, _, __) {
        final size = MediaQuery.of(ctx).size;
        final width =
            (size.width * 0.648).clamp(240.0, size.width - 16).toDouble();
        return Stack(
          children: [
            Positioned(
              left: size.width * 0.037,
              top: size.height * 0.156,
              width: width,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: size.height * 0.70),
                child: const SettingsSheet(),
              ),
            ),
          ],
        );
      },
      transitionBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;

    return Material(
      color: c.paper,
      elevation: 14,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.cardBorder),
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: const [
            _AccountSection(),
            SizedBox(height: 22),
            _LanguageSection(),
            SizedBox(height: 22),
            _ThemeSection(),
            SizedBox(height: 22),
            _FontSection(),
            SizedBox(height: 22),
            _FontSizeSection(),
            SizedBox(height: 22),
            _TargetTextSection(),
            SizedBox(height: 22),
            _CalendarSection(),
            SizedBox(height: 22),
            _HighlightSection(),
            SizedBox(height: 22),
            _MascotSection(),
            SizedBox(height: 22),
            _VoiceEngineSection(),
            _OfflineTtsSection(),
            _AudioSyncSection(),
            SizedBox(height: 22),
            _FloatingBubbleSection(),
            SizedBox(height: 16),
            _OfflineWordsButton(),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
class _SectionTitle extends StatelessWidget {
  final IconData? icon;
  final String? emoji;
  final String label;

  const _SectionTitle({this.icon, this.emoji, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: c.inkSoft),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            emoji != null ? '$emoji $label' : label,
            style: TextStyle(
              color: c.ink,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
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
        _SectionTitle(label: context.l10n.settings_account),
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
                      context.l10n.settings_logout,
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
        _SectionTitle(icon: Icons.language, label: context.l10n.settings_language_title),
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
        _SectionTitle(icon: Icons.palette_outlined, label: context.l10n.settings_theme_title),
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
        _SectionTitle(icon: Icons.text_format, label: context.l10n.settings_font_title),
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
        _SectionTitle(icon: Icons.format_size, label: context.l10n.settings_font_size_title),
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

  /// داخل Expanded: متن وسط‌چین و در صورت طولانی بودن با «…» کوتاه می‌شود.
  final bool expand;

  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Material(
      color: selected ? c.gold.withOpacity(0.55) : Colors.white,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          alignment: expand ? Alignment.center : null,
          padding: EdgeInsets.symmetric(
              horizontal: expand ? 8 : 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? c.gold : c.cardBorder,
              width: 1.2,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: TextStyle(
              fontSize: 13,
              color: c.ink,
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
        _SectionTitle(
          icon: Icons.calendar_month_outlined,
          label: context.l10n.settings_calendar_title,
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
// Mascot — آدمکِ متحرک (معادل settings_mascot_* در Hope؛ فقط آدمک کلاسیک)
// ═══════════════════════════════════════════════════════════════════
class _MascotSection extends ConsumerWidget {
  const _MascotSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(appPrefsProvider.select((p) => p.mascotEnabled));
    final notifier = ref.read(appPrefsProvider.notifier);
    final c = context.appColors;
    final L = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          label: L.settings_mascot_walking_title,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ChoiceChip(
              label: L.settings_mascot_visible_show,
              selected: enabled,
              onTap: () => notifier.setMascotEnabled(true),
            ),
            _ChoiceChip(
              label: L.settings_mascot_visible_fade,
              selected: !enabled,
              onTap: () => notifier.setMascotEnabled(false),
            ),
          ],
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: c.ink,
            side: BorderSide(color: c.cardBorder),
          ),
          onPressed: () {
            ref.read(mascotPinProvider.notifier).reset();
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              SnackBar(content: Text(L.settings_mascot_reset_done)),
            );
          },
          icon: const Icon(Icons.restart_alt, size: 16),
          label: Text(
            L.settings_mascot_reset_button,
            style: const TextStyle(fontSize: 12.5),
          ),
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
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
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
        _SectionTitle(
          label: context.l10n.settings_highlight_color_title,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            swatch(
              color: Colors.white,
              selected: current == 'none',
              tooltip: context.l10n.settings_highlight_none,
              onTap: () => notifier.setHighlightColor('none'),
              child: Icon(Icons.close, size: 14, color: c.inkSoft),
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
// چیدمان دقیقاً مثل Hope: عنوان ← سه دکمه‌ی نوع ← رنگ ← ذره‌بین ←
// ترجمه‌ی زنده‌ی صدا (زبان صدا، بسته‌ی آفلاین، حالت آهنگ، نمایش، شروع، یوتیوب)
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

  static const List<String> _kinds = ['magnifier', 'live', 'both'];
  static const List<String> _displayModes = ['both', 'translation', 'original'];

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
  int _packEpoch = 0;

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
    _kind = _kinds.contains(kind) ? kind! : 'both';
    _src = _srcLangs.containsKey(src) ? src! : 'en';
    _disp = _displayModes.contains(disp) ? disp! : 'both';
    _color = (color != null && RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(color))
        ? color.toUpperCase()
        : _defaultColor;
  }

  Future<void> _save(String key, String value) async {
    await ref.read(sharedPrefsProvider).setString(key, value);
  }

  String _kindLabel(AppLocalizations L, String k) {
    switch (k) {
      case 'magnifier':
        return L.settings_bubble_kind_magnifier;
      case 'live':
        return L.settings_bubble_kind_live;
      default:
        return L.settings_bubble_kind_both;
    }
  }

  Map<String, String> _displayMap(AppLocalizations L) => {
        'both': L.settings_display_both,
        'translation': L.settings_display_translation_only,
        'original': L.settings_display_original_only,
      };

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

  void _setColor(String hex) {
    final v = _ensureDark(hex);
    setState(() => _color = v);
    _save(_kColorKey, v);
    _pushOptions();
  }

  Future<void> _pickCustomColor() async {
    final ctl = TextEditingController(text: _color);
    final ml = MaterialLocalizations.of(context);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.settings_bubble_color_custom),
        content: TextField(
          controller: ctl,
          autofocus: true,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(hintText: '#RRGGBB'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(ml.cancelButtonLabel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
              child: Text(ml.okButtonLabel)),
        ],
      ),
    );
    ctl.dispose();
    if (v == null) return;
    final hex = v.startsWith('#') ? v : '#$v';
    if (RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex)) _setColor(hex.toUpperCase());
  }

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
        // ترجمه‌ی زنده فقط آفلاین کار می‌کند: بسته‌ی زبانِ صدا باید روی گوشی باشد.
        final pack = await LinLearnBridge.packStatus('speech', _src);
        if (pack != null && pack['downloaded'] != true) {
          final yes = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('بسته‌ی آفلاین تشخیص گفتار'),
              content: Text(
                  'برای ترجمه‌ی زنده به بسته‌ی آفلاین «${_srcLangs[_src]}» نیاز است '
                  '(فقط یک‌بار دانلود می‌شود و بعدش بدون اینترنت کار می‌کند). دانلود شود؟'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('نه')),
                TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('دانلود')),
              ],
            ),
          );
          if (yes == true) {
            await LinLearnBridge.packDownload('speech', _src);
            _toast('دانلود شروع شد؛ وقتی تمام شد دوباره «شروع ترجمه‌ی زنده» را بزن.');
            if (mounted) setState(() => _packEpoch++);
          }
          return;
        }
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

  Future<void> _startYoutube() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!await _ensureOverlay()) return;
      if (!await LinLearnBridge.ytCheckAccess()) {
        await LinLearnBridge.ytRequestAccess();
        _toast('«دسترسی به اعلان‌ها» را برای برنامه روشن کن و دوباره امتحان کن.');
        return;
      }
      await _pushOptions();
      if (!ref.read(bubbleProvider).running) {
        await ref.read(bubbleProvider.notifier).start(mode: 'translator');
      }
      await LinLearnBridge.ytSetEnabled(true);
    } catch (e) {
      _toast('خطا: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final L = context.l10n;
    final bubbleRunning = ref.watch(bubbleProvider.select((s) => s.running));
    final liveRunning = ref.watch(liveTranslatorProvider);
    final showMagnifier = _kind != 'live';
    final showLive = _kind != 'magnifier';
    final note = TextStyle(color: c.inkSoft, fontSize: 11.5, height: 1.7);
    final head =
        TextStyle(color: c.ink, fontSize: 14, fontWeight: FontWeight.w700);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.45),
        borderRadius: BorderRadius.circular(20),
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
                Text('🫧 ${L.settings_floating_title}',
                    style: head.copyWith(fontSize: 15)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (var i = 0; i < _kinds.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: _ChoiceChip(
                          label: _kindLabel(L, _kinds[i]),
                          selected: _kind == _kinds[i],
                          expand: true,
                          onTap: () {
                            setState(() => _kind = _kinds[i]);
                            _save(_kKindKey, _kinds[i]);
                          },
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                Text('🎨 ${L.settings_bubble_color_title}',
                    style: head.copyWith(fontSize: 12.5)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 7,
                  runSpacing: 8,
                  children: [
                    for (final hex in _colors)
                      GestureDetector(
                        onTap: () => _setColor(hex),
                        child: Container(
                          width: 26,
                          height: 26,
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
                const SizedBox(height: 10),
                Row(
                  children: [
                    GestureDetector(
                      onTap: _pickCustomColor,
                      child: Container(
                        width: 40,
                        height: 30,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: c.cardBorder),
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            color: _hexToColor(_color),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(L.settings_bubble_color_custom, style: note),
                  ],
                ),
                if (showMagnifier) ...[
                  const SizedBox(height: 18),
                  Text('🔍 ${L.settings_magnifier_title}', style: head),
                  const SizedBox(height: 10),
                  _BubbleButton(
                    label:
                        '🔍 ${bubbleRunning ? L.settings_magnifier_stop : L.settings_magnifier_start}',
                    busy: _busy,
                    onTap: _toggleBubble,
                  ),
                  const SizedBox(height: 8),
                  Text(L.settings_magnifier_description, style: note),
                ],
                if (showLive) ...[
                  const SizedBox(height: 18),
                  Text('🎙️ ${L.settings_live_audio_title}', style: head),
                  const SizedBox(height: 10),
                  _LabeledDrop(
                    label: L.settings_audio_language,
                    value: _src,
                    items: _srcLangs,
                    onChanged: (v) {
                      setState(() => _src = v);
                      _save(_kSrcKey, v);
                    },
                  ),
                  PackTile(
                    key: ValueKey('speech-$_src-$_packEpoch'),
                    kind: 'speech',
                    id: _src,
                    title: '',
                    bare: true,
                    approxMb: 70,
                  ),
                  const SizedBox(height: 16),
                  const _SongModeSection(),
                  const SizedBox(height: 12),
                  Text(L.settings_live_audio_description, style: note),
                  const SizedBox(height: 10),
                  _LabeledDrop(
                    label: L.settings_display_mode_label,
                    value: _disp,
                    items: _displayMap(L),
                    onChanged: (v) {
                      setState(() => _disp = v);
                      _save(_kDispKey, v);
                      _pushOptions();
                    },
                  ),
                  const SizedBox(height: 12),
                  _BubbleButton(
                    label:
                        '🎙️ ${liveRunning ? L.settings_stop : L.settings_live_audio_start}',
                    busy: _busy,
                    onTap: _toggleLive,
                  ),
                  const SizedBox(height: 8),
                  _BubbleButton(
                    label: '▶️ ${L.settings_youtube_start}',
                    busy: _busy,
                    onTap: _startYoutube,
                  ),
                  const SizedBox(height: 8),
                  Text(L.settings_youtube_description, style: note),
                ],
              ],
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// حالت آهنگ (آفلاین) — کیفیت: سریع / متعادل / دقیق‌تر
// ═══════════════════════════════════════════════════════════════════
class _SongModeSection extends ConsumerStatefulWidget {
  const _SongModeSection();

  @override
  ConsumerState<_SongModeSection> createState() => _SongModeSectionState();
}

class _SongModeSectionState extends ConsumerState<_SongModeSection> {
  static const String _key = 'phrasebook-song-quality';
  static const List<String> _tiers = ['fast', 'balanced', 'accurate'];
  static const Map<String, int> _mb = {
    'fast': 100,
    'balanced': 160,
    'accurate': 360,
  };
  // «متعادل» همان بسته‌ی قبلی (base) است تا با سمت نیتیو سازگار بماند.
  static const Map<String, String> _packId = {
    'fast': 'fast',
    'balanced': 'base',
    'accurate': 'accurate',
  };

  late String _tier;
  bool _installed = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final v = ref.read(sharedPrefsProvider).getString(_key);
    _tier = _tiers.contains(v) ? v! : 'balanced';
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    final st = await LinLearnBridge.packStatus('song', _packId[_tier]!);
    if (!mounted) return;
    final v = st?['downloaded'] == true;
    if (v != _installed) setState(() => _installed = v);
  }

  String _name(AppLocalizations L, String t) {
    switch (t) {
      case 'fast':
        return L.settings_song_model_fast;
      case 'accurate':
        return L.settings_song_model_accurate;
      default:
        return L.settings_song_model_balanced;
    }
  }

  String _hint(AppLocalizations L, String t) {
    switch (t) {
      case 'fast':
        return L.settings_song_hint_fast;
      case 'accurate':
        return L.settings_song_hint_accurate;
      default:
        return L.settings_song_hint_balanced;
    }
  }

  Widget _tierCard(BuildContext context, String t) {
    final c = context.appColors;
    final L = context.l10n;
    final sel = _tier == t;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          setState(() => _tier = t);
          ref.read(sharedPrefsProvider).setString(_key, t);
          _poll();
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: sel ? c.gold : c.cardBorder,
              width: sel ? 2 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t == 'balanced'
                          ? '${_name(L, t)} ${L.settings_song_recommended_badge}'
                          : _name(L, t),
                      style: TextStyle(
                          color: c.ink,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(_hint(L, t),
                        style: TextStyle(
                            color: c.inkSoft, fontSize: 11.5, height: 1.6)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '~${_mb[t]}MB',
                textDirection: TextDirection.ltr,
                style: TextStyle(
                    color: c.inkSoft,
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final L = context.l10n;
    final note = TextStyle(color: c.inkSoft, fontSize: 11.5, height: 1.7);
    final body = TextStyle(color: c.ink, fontSize: 12, height: 1.7);
    final name = _name(L, _tier);
    final mb = _mb[_tier]!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('🎵 ${L.settings_song_title}',
                  style: TextStyle(
                      color: c.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.6),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: c.cardBorder),
              ),
              child: Text(
                _installed ? '✅ ${L.settings_tts_offline}' : L.settings_not_installed,
                style: TextStyle(color: c.ink, fontSize: 11.5),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.gold.withOpacity(0.22),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(L.settings_song_intro, style: body),
              const SizedBox(height: 10),
              Text('✅ ${L.settings_song_on_title}',
                  style: const TextStyle(
                      color: Color(0xFF2E7D32),
                      fontSize: 13,
                      fontWeight: FontWeight.w800)),
              Text(L.settings_song_on_list, style: body),
              const SizedBox(height: 10),
              Text('⛔ ${L.settings_song_off_title}',
                  style: const TextStyle(
                      color: Color(0xFFB3261E),
                      fontSize: 13,
                      fontWeight: FontWeight.w800)),
              Text(L.settings_song_off_list, style: body),
              const SizedBox(height: 10),
              Text(L.settings_song_on_note, style: body),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(L.settings_quality,
            style: TextStyle(
                color: c.ink, fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        for (final t in _tiers) _tierCard(context, t),
        PackTile(
          key: ValueKey('song-$_tier'),
          kind: 'song',
          id: _packId[_tier]!,
          title: '',
          bare: true,
          filled: true,
          approxMb: mb,
          toggleTitle: L.settings_song_use,
          downloadLabel: (m) => L.settings_song_download(name, '$m'),
          resumeLabel: (have, m) => L.settings_song_resume(name, have, '$m'),
        ),
        const SizedBox(height: 10),
        Text(L.settings_song_tip, style: note),
      ],
    );
  }
}

class _BubbleButton extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback onTap;

  const _BubbleButton({
    required this.label,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: busy ? null : onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: c.gold.withOpacity(0.55),
          side: BorderSide(color: c.gold),
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: c.ink,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// دکمه‌ی ساده با کادر (بدون رنگ طلایی) — مثل «دانلودِ همه‌ی صداها».
class _PlainButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _PlainButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white.withOpacity(0.35),
          side: BorderSide(color: c.cardBorder),
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: c.ink,
            fontSize: 13,
            fontWeight: FontWeight.w700,
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
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.cardBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          isDense: true,
          icon: Icon(Icons.keyboard_arrow_down, color: c.inkSoft),
          dropdownColor: Colors.white,
          style: TextStyle(color: c.ink, fontSize: 13),
          items: items.entries
              .map((e) => DropdownMenuItem(
                    value: e.key,
                    child: Text(e.value, overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

/// «برچسب + لیست کشویی» در یک ردیف (زبان صدا، کیفیت، نمایش).
class _LabeledDrop extends StatelessWidget {
  final String label;
  final String value;
  final Map<String, String> items;
  final ValueChanged<String> onChanged;

  const _LabeledDrop({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Row(
      children: [
        Text(label,
            style: TextStyle(
                color: c.ink, fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(width: 10),
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: _DropBox(value: value, items: items, onChanged: onChanged),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// صدای خوانش / صدای آفلاین باکیفیت / همگام‌سازی متن و صوت — معادل Hope
// پیش‌فرض: صدای خودِ گوشی. بسته‌های باکیفیت فقط با دکمه‌ی خودِ کاربر دانلود
// می‌شوند (هیچ دانلود خودکاری وجود ندارد).
// ═══════════════════════════════════════════════════════════════════
bool get _isAndroidApp =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

class _VoiceEngineSection extends ConsumerStatefulWidget {
  const _VoiceEngineSection();

  @override
  ConsumerState<_VoiceEngineSection> createState() =>
      _VoiceEngineSectionState();
}

class _VoiceEngineSectionState extends ConsumerState<_VoiceEngineSection> {
  static const String _key = 'voiceEnginePref';
  late String _pref;

  @override
  void initState() {
    super.initState();
    // پیش‌فرض = صدای گوشی؛ فقط اگر کاربر خودش «صدای اپ» را زده باشد 'model' است.
    _pref = ref.read(sharedPrefsProvider).getString(_key) == 'model'
        ? 'model'
        : 'phone';
  }

  void _set(String v) {
    setState(() => _pref = v);
    ref.read(sharedPrefsProvider).setString(_key, v);
  }

  Widget _option(BuildContext context, String label, bool selected,
      VoidCallback onTap) {
    final c = context.appColors;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        height: 62,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? c.gold : Colors.white.withOpacity(0.4),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? c.gold : c.cardBorder),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: c.ink,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAndroidApp) return const SizedBox.shrink();
    final c = context.appColors;
    final L = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(emoji: '🔊', label: L.settings_voice_engine_title),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _option(context, L.settings_voice_engine_app,
                    _pref == 'model', () => _set('model')),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _option(context, L.settings_voice_engine_phone,
                    _pref == 'phone', () => _set('phone')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            L.settings_voice_engine_hint,
            style: TextStyle(color: c.inkSoft, fontSize: 11.5, height: 1.7),
          ),
        ],
      ),
    );
  }
}

class _OfflineTtsSection extends StatefulWidget {
  const _OfflineTtsSection();

  @override
  State<_OfflineTtsSection> createState() => _OfflineTtsSectionState();
}

class _OfflineTtsSectionState extends State<_OfflineTtsSection> {
  /// زبان‌هایی که بسته‌ی صدای آفلاین دارند (ترتیب مثل Hope).
  static const List<String> _downloadable = [
    'fa', 'en', 'it', 'hi', 'tr', 'ar', 'es', 'de', 'fr', 'zh',
  ];
  static const List<String> _extraDownloadable = ['ru'];
  static const List<String> _phoneOnly = ['ko'];

  bool _allRunning = false;
  bool _allCancel = false;
  String? _current;
  int _epoch = 0;

  List<String> get _all => [
        ..._downloadable,
        ..._phoneOnly,
        ..._extraDownloadable,
      ];

  List<String> get _toDownload => [..._downloadable, ..._extraDownloadable];

  String _label(BuildContext context, String code) {
    final fa = Localizations.localeOf(context).languageCode == 'fa';
    for (final l in kSupportedLanguages) {
      if (l.code == code) return fa ? l.faLabel : l.enLabel;
    }
    return code.toUpperCase();
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  /// فقط با دکمه‌ی خودِ کاربر: بسته‌ها یکی‌یکی دانلود می‌شوند.
  Future<void> _downloadAll() async {
    if (_allRunning) {
      _allCancel = true;
      final cur = _current;
      if (cur != null) await LinLearnBridge.packCancel('tts', cur);
      return;
    }
    setState(() {
      _allRunning = true;
      _allCancel = false;
    });
    try {
      for (final code in _toDownload) {
        if (_allCancel || !mounted) break;
        final st = await LinLearnBridge.packStatus('tts', code);
        if (st == null) {
          _toast('دانلود شروع نشد.');
          break;
        }
        if (st['downloaded'] == true) continue;
        _current = code;
        final ok = await LinLearnBridge.packDownload('tts', code);
        if (!ok) {
          _toast('دانلود شروع نشد.');
          break;
        }
        if (mounted) setState(() => _epoch++);
        while (mounted && !_allCancel) {
          await Future<void>.delayed(const Duration(seconds: 2));
          final s = await LinLearnBridge.packStatus('tts', code);
          if (s == null || s['downloading'] != true) break;
        }
      }
    } finally {
      _current = null;
      if (mounted) {
        setState(() {
          _allRunning = false;
          _epoch++;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAndroidApp) return const SizedBox.shrink();
    final c = context.appColors;
    final L = context.l10n;
    final n = '${_toDownload.length}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(emoji: '🔊', label: L.settings_tts_title),
          const SizedBox(height: 8),
          Text(
            L.settings_tts_intro,
            style: TextStyle(color: c.inkSoft, fontSize: 11.5, height: 1.7),
          ),
          const SizedBox(height: 12),
          _PlainButton(
            label: _allRunning
                ? '⏹ ${L.settings_tts_stop_all(n)}'
                : '📥 ${L.settings_tts_download_all(n)}',
            onTap: _downloadAll,
          ),
          for (final code in _all)
            TtsPackRow(
              key: ValueKey('tts-$code-$_epoch'),
              code: code,
              label: _label(context, code),
              phoneOnly: _phoneOnly.contains(code),
            ),
        ],
      ),
    );
  }
}

class _AudioSyncSection extends ConsumerStatefulWidget {
  const _AudioSyncSection();

  @override
  ConsumerState<_AudioSyncSection> createState() => _AudioSyncSectionState();
}

class _AudioSyncSectionState extends ConsumerState<_AudioSyncSection> {
  static const String _key = 'syncModelSize';
  late String _size;

  @override
  void initState() {
    super.initState();
    final v = ref.read(sharedPrefsProvider).getString(_key);
    _size = (v == 'fast' || v == 'balanced') ? v! : 'balanced';
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAndroidApp) return const SizedBox.shrink();
    final c = context.appColors;
    final L = context.l10n;
    final sizes = {
      'fast': '${L.settings_sync_model_fast} ~45MB',
      'balanced': '${L.settings_sync_model_balanced} ~85MB',
    };
    final mb = _size == 'fast' ? 45 : 85;
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(emoji: '🎧', label: L.settings_sync_title),
          const SizedBox(height: 10),
          _LabeledDrop(
            label: L.settings_quality,
            value: _size,
            items: sizes,
            onChanged: (v) {
              setState(() => _size = v);
              ref.read(sharedPrefsProvider).setString(_key, v);
            },
          ),
          PackTile(
            kind: 'sync',
            id: _size,
            title: '',
            bare: true,
            approxMb: mb,
            downloadLabel: (m) => L.settings_sync_download('$m'),
          ),
          const SizedBox(height: 10),
          Text(
            L.settings_sync_description,
            style: TextStyle(color: c.inkSoft, fontSize: 11.5, height: 1.7),
          ),
        ],
      ),
    );
  }
}

class _OfflineWordsButton extends StatelessWidget {
  const _OfflineWordsButton();

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => OfflineWordsDialog.show(context),
        icon: Icon(Icons.menu_book_outlined, size: 18, color: c.ink),
        label: Text(
          context.l10n.settings_offline_download,
          style: TextStyle(
              color: c.ink, fontSize: 13, fontWeight: FontWeight.w700),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: c.cardBorder),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
