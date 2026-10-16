// 📁 مسیر: lib/features/shell/widgets/settings_panel.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_appearance.dart';
import '../../../core/providers/app_prefs_provider.dart';
import '../../../core/theme/app_theme_colors.dart';

/// پنل تنظیمات — بخش اول: زبان + تم + فونت
class SettingsPanel extends ConsumerStatefulWidget {
  const SettingsPanel({super.key});

  @override
  ConsumerState<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends ConsumerState<SettingsPanel> {
  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final prefs = ref.watch(appPrefsProvider);
    final notifier = ref.read(appPrefsProvider.notifier);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: c.paper,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // ═══ هدر پنل ═══
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.cardBorder)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'تنظیمات',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: c.ink,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: c.inkSoft),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // ═══ محتوای اسکرول‌شونده ═══
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    // ─── ۱. زبان نرم‌افزار ───
                    _SectionHeader(
                      title: 'زبان نرم‌افزار',
                      icon: Icons.language,
                      c: c,
                    ),
                    const SizedBox(height: 8),
                    _LanguageDropdown(
                      current: prefs.uiLang,
                      c: c,
                      onChanged: (code) => notifier.setUiLang(code),
                    ),
                    const SizedBox(height: 24),

                    // ─── ۲. رنگ و تم ───
                    _SectionHeader(
                      title: 'رنگ و تم',
                      icon: Icons.palette_outlined,
                      c: c,
                    ),
                    const SizedBox(height: 8),
                    _ThemeGrid(
                      current: prefs.theme,
                      c: c,
                      onChanged: (key) => notifier.setTheme(key),
                    ),
                    const SizedBox(height: 24),

                    // ─── ۳. نوع فونت ───
                    _SectionHeader(
                      title: 'نوع فونت',
                      icon: Icons.text_fields,
                      c: c,
                    ),
                    const SizedBox(height: 8),
                    _FontChoices(
                      current: prefs.font,
                      c: c,
                      onChanged: (key) => notifier.setFont(key),
                    ),
                    const SizedBox(height: 24),

                    // ─── ۴. اندازه فونت ───
                    _SectionHeader(
                      title: 'اندازه‌ی فونت',
                      icon: Icons.format_size,
                      c: c,
                    ),
                    const SizedBox(height: 8),
                    _FontSizeChoices(
                      current: prefs.fontSize,
                      c: c,
                      onChanged: (key) => notifier.setFontSize(key),
                    ),

                    const SizedBox(height: 60),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// کامپوننت‌های داخلی
// ═══════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final dynamic c;
  const _SectionHeader({
    required this.title,
    required this.icon,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: c.inkSoft),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: c.ink,
          ),
        ),
      ],
    );
  }
}

// ─── زبان نرم‌افزار: Dropdown ───
class _LanguageDropdown extends StatelessWidget {
  final String current;
  final dynamic c;
  final ValueChanged<String> onChanged;
  const _LanguageDropdown({
    required this.current,
    required this.c,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.cardBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: kAppLanguages.containsKey(current) ? current : 'fa',
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down, color: c.inkSoft),
          style: TextStyle(color: c.ink, fontSize: 14),
          items: kAppLanguages.values.map((lang) {
            return DropdownMenuItem<String>(
              value: lang.code,
              child: Text(lang.label),
            );
          }).toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

// ─── رنگ و تم: گرید سواچ‌ها ───
class _ThemeGrid extends StatelessWidget {
  final String current;
  final dynamic c;
  final ValueChanged<String> onChanged;
  const _ThemeGrid({
    required this.current,
    required this.c,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final themes = kAppThemes.values.toList();
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: themes.map((theme) {
        final isSelected = theme.key == current;
        return GestureDetector(
          onTap: () => onChanged(theme.key),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: theme.swatch,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected
                    ? c.gold
                    : Colors.black.withOpacity(0.16),
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: c.gold.withOpacity(0.5),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: isSelected
                ? const Icon(Icons.check, color: Colors.white, size: 20)
                : null,
          ),
        );
      }).toList(),
    );
  }
}

// ─── نوع فونت ───
class _FontChoices extends StatelessWidget {
  final String current;
  final dynamic c;
  final ValueChanged<String> onChanged;
  const _FontChoices({
    required this.current,
    required this.c,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: kAppFonts.values.map((font) {
        final isSelected = font.key == current;
        return GestureDetector(
          onTap: () => onChanged(font.key),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? c.goldSoft : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected ? c.gold : c.cardBorder,
              ),
            ),
            child: Text(
              font.labelFa,
              style: TextStyle(
                color: c.ink,
                fontSize: 13,
                fontWeight:
                    isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─── اندازه فونت ───
class _FontSizeChoices extends StatelessWidget {
  final String current;
  final dynamic c;
  final ValueChanged<String> onChanged;
  const _FontSizeChoices({
    required this.current,
    required this.c,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: kAppFontSizes.values.map((size) {
        final isSelected = size.key == current;
        return GestureDetector(
          onTap: () => onChanged(size.key),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? c.goldSoft : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected ? c.gold : c.cardBorder,
              ),
            ),
            child: Text(
              size.labelFa,
              style: TextStyle(
                color: c.ink,
                fontSize: 13,
                fontWeight:
                    isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
