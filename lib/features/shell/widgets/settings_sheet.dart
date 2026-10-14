import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_font_sizes.dart';
import '../../../core/constants/app_fonts.dart';
import '../../../core/constants/app_languages.dart';
import '../../../core/constants/app_themes.dart';
import '../../../core/models/text_prefs.dart';
import '../../../core/providers/app_prefs_provider.dart';
import '../../../core/providers/text_prefs_provider.dart';
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
          initialChildSize: 0.88,
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
// Account — با پشتیبانی از مهمان (kSkipLogin)
// ═══════════════════════════════════════════════════════════════════
class _AccountSection extends ConsumerWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;

    // دسترسی امن به Supabase — اگر init نشده باشد، null برمی‌گردد.
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
    } catch (_) {
      // Supabase init نشده — مهمان.
    }

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
