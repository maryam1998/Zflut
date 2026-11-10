import 'package:flutter/material.dart';

import '../constants/level_colors.dart';
import '../theme/app_theme_colors.dart';
import '../usage/free_limit.dart';
import '../usage/pro_i18n.dart';
import 'locked_words_card.dart' show LockedChipData;

String _n(int v) {
  final s = v.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

List<LockedChipData> _levelChips(Map<String, int> byLevel) => [
      for (final e in byLevel.entries)
        LockedChipData(e.key, e.value, color: levelColor(e.key)),
    ];

Widget _chipsWrap(AppThemeColorsExt c, List<LockedChipData> chips) {
  return Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final ch in chips)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: (ch.color ?? c.gold).withOpacity(0.14),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: (ch.color ?? c.gold).withOpacity(0.55)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock, size: 11, color: ch.color ?? c.gold),
              const SizedBox(width: 5),
              Text('${ch.label} · ${_n(ch.count)}',
                  style: TextStyle(
                      color: c.ink,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
    ],
  );
}

BoxDecoration _goldBox(AppThemeColorsExt c) => BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [c.goldSoft.withOpacity(0.55), c.goldSoft.withOpacity(0.18)],
      ),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: c.gold, width: 1.2),
    );

Widget _lockBadge(AppThemeColorsExt c) => Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: c.gold.withOpacity(0.18),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.lock, color: c.gold, size: 20),
    );

Widget _progress(AppThemeColorsExt c, double value, String text) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: value.clamp(0.0, 1.0),
            minHeight: 7,
            backgroundColor: c.gold.withOpacity(0.2),
            valueColor: AlwaysStoppedAnimation<Color>(c.gold),
          ),
        ),
        const SizedBox(height: 6),
        Text(text,
            style: TextStyle(
                color: c.inkSoft, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );

Widget _cta(AppThemeColorsExt c, String label) => FilledButton.icon(
      onPressed: FreeLimit.reportLocked,
      icon: const Icon(Icons.workspace_premium, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: c.gold,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 12),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

// ═══════════════════════════════════════════════════════════════════
// 🔒 بنرِ بالای لیستِ موضوع‌های مکالمه (کاربرِ رایگان)
// ═══════════════════════════════════════════════════════════════════
class LockedConversationsBanner extends StatelessWidget {
  /// موضوع‌هایی که با فیلترِ فعلی قفل‌اند
  final int lockedTopics;

  /// جمله‌های قفل‌شده / کلِ جمله‌ها در محدوده‌ی فعلی
  final int locked;
  final int total;

  /// قفل‌شده‌ها به‌تفکیکِ سطح
  final Map<String, int> byLevel;

  const LockedConversationsBanner({
    super.key,
    required this.lockedTopics,
    required this.locked,
    required this.total,
    required this.byLevel,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    String t(String k, [Map<String, Object> a = const <String, Object>{}]) =>
        ProI18n.t(context, k, a);
    final free = total - locked;

    final title = lockedTopics > 0
        ? t('conv_banner_title',
            {'locked': _n(locked), 'topics': _n(lockedTopics)})
        : t('conv_banner_title_short', {'locked': _n(locked)});
    final progressText =
        t('conv_progress', {'free': _n(free), 'total': _n(total)});
    final chipsTitle = t('locked_by_level');
    final cta = t('conv_cta');

    return InkWell(
      onTap: FreeLimit.reportLocked,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: _goldBox(c),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _lockBadge(c),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title,
                      style: TextStyle(
                          color: c.ink,
                          fontSize: 15,
                          height: 1.35,
                          fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _progress(c, total <= 0 ? 0.0 : free / total, progressText),
            if (byLevel.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(chipsTitle,
                  style: TextStyle(
                      color: c.inkSoft,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              _chipsWrap(c, _levelChips(byLevel)),
            ],
            const SizedBox(height: 14),
            _cta(c, cta),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 🔒 کارتِ «جمله‌های بیشتر با Pro» — انتهای یک موضوعِ رایگان
// ═══════════════════════════════════════════════════════════════════
class LockedConversationCard extends StatelessWidget {
  final int locked;
  final int total;
  final Map<String, int> byLevel;

  /// نامِ نمایشیِ موضوع
  final String scopeLabel;

  const LockedConversationCard({
    super.key,
    required this.locked,
    required this.total,
    required this.byLevel,
    required this.scopeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    String t(String k, [Map<String, Object> a = const <String, Object>{}]) =>
        ProI18n.t(context, k, a);
    final free = total - locked;

    final title = t('conv_card_title', {'n': _n(locked)});
    final subtitle = t('in_scope', {'scope': scopeLabel});
    final progressText =
        t('conv_progress', {'free': _n(free), 'total': _n(total)});
    final chipsTitle = t('locked_by_level');
    final cta = t('conv_cta_levels');

    // سه حبابِ «مکالمه‌ی محو» — نشان می‌دهد پشتِ قفل مکالمه‌ی واقعی هست
    Widget bubble(double w, bool start) => Align(
          alignment: start
              ? AlignmentDirectional.centerStart
              : AlignmentDirectional.centerEnd,
          child: FractionallySizedBox(
            widthFactor: w,
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: c.surface.withOpacity(0.72),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.cardBorder.withOpacity(0.7)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 10,
                          decoration: BoxDecoration(
                            color: c.inkSoft.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(height: 7),
                        FractionallySizedBox(
                          widthFactor: 0.7,
                          child: Container(
                            height: 8,
                            decoration: BoxDecoration(
                              color: c.inkSoft.withOpacity(0.11),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(Icons.lock_outline,
                      size: 17, color: c.gold.withOpacity(0.85)),
                ],
              ),
            ),
          ),
        );

    return InkWell(
      onTap: FreeLimit.reportLocked,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: _goldBox(c),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _lockBadge(c),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              color: c.ink,
                              fontSize: 15,
                              fontWeight: FontWeight.w800)),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(subtitle,
                            style: TextStyle(
                                color: c.inkSoft,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _progress(c, total <= 0 ? 0.0 : free / total, progressText),
            if (byLevel.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(chipsTitle,
                  style: TextStyle(
                      color: c.inkSoft,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              _chipsWrap(c, _levelChips(byLevel)),
            ],
            const SizedBox(height: 14),
            bubble(0.82, true),
            bubble(0.66, false),
            bubble(0.78, true),
            const SizedBox(height: 6),
            _cta(c, cta),
          ],
        ),
      ),
    );
  }
}
