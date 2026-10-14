import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/supported_languages.dart';
import '../../../core/providers/language_selection_provider.dart';
import '../../../core/theme/app_theme_colors.dart';

class LanguagePicker extends ConsumerWidget {
  const LanguagePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.appColors;
    final sel = ref.watch(languageSelectionProvider);
    final notifier = ref.read(languageSelectionProvider.notifier);

    return Container(
      color: c.headerFrom,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── زبان مادری ──
          _SectionLabel(text: 'زبان مادری', c: c),
          const SizedBox(height: 8),
          _ChipRow(
            languages: kSupportedLanguages,
            selectedCode: sel.native,
            c: c,
            onSelected: (code) => notifier.setNative(code),
          ),

          const SizedBox(height: 14),

          // ── زبان مقصد ──
          _SectionLabel(text: 'زبان مقصد', c: c),
          const SizedBox(height: 8),
          _ChipRow(
            languages: kSupportedLanguages,
            selectedCode: sel.primaryTarget,
            c: c,
            onSelected: (code) => notifier.setPrimaryTarget(code),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final dynamic c;
  const _SectionLabel({required this.text, required this.c});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Text(
          text,
          style: TextStyle(
            color: c.headerText.withOpacity(0.75),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ChipRow extends StatelessWidget {
  final List<SupportedLanguage> languages;
  final String? selectedCode;
  final dynamic c;
  final ValueChanged<String> onSelected;

  const _ChipRow({
    required this.languages,
    required this.selectedCode,
    required this.c,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: languages.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final lang = languages[i];
          final active = lang.code == selectedCode;
          return _LangCircle(
            code: lang.abbr,
            active: active,
            c: c,
            onTap: () => onSelected(lang.code),
          );
        },
      ),
    );
  }
}

class _LangCircle extends StatelessWidget {
  final String code;
  final bool active;
  final dynamic c;
  final VoidCallback onTap;

  const _LangCircle({
    required this.code,
    required this.active,
    required this.c,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active
              ? c.gold
              : c.headerText.withOpacity(0.04),
          border: Border.all(
            color: active
                ? c.gold
                : c.headerText.withOpacity(0.35),
            width: active ? 2 : 1,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: c.gold.withOpacity(0.45),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          code,
          style: TextStyle(
            color: active ? c.headerTo : c.headerText,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
