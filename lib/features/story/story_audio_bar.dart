// نوارِ صوتِ آپلودیِ داستان — معادلِ UserAudioBar.jsx + AudioSyncSettings.jsx در Hope.
// فقط آپلود/حذفِ فایل + تنظیمِ همگام‌سازی؛ کنترل‌های پخش (پخش/توقف، جمله‌ی قبل/بعد،
// نوارِ زمان، سرعت، A-B) به پلیرِ اصلیِ پایینِ صفحه منتقل شد (سوییچِ «صدای اپ / صدای اپلودی»).
import 'package:flutter/material.dart';

import '../../app.dart' show AppL10nX;
import '../../core/audio/story_audio_controller.dart';
import '../../core/theme/app_theme_colors.dart';

class StoryAudioBar extends StatelessWidget {
  final StoryAudioController ctrl;
  const StoryAudioBar({super.key, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: c.cardBorder),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, c),
              if (ctrl.error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(ctrl.error,
                      style: TextStyle(color: c.rose, fontSize: 11)),
                ),
              if (ctrl.hasAudio && !ctrl.saving) ...[
                const SizedBox(height: 8),
                _sync(context, c),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context, AppThemeColorsExt c) {
    final L = context.l10n;
    return Row(
      children: [
        Icon(Icons.headphones, size: 16, color: c.inkSoft),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            ctrl.saving
                ? L.player_audio_saving
                : ctrl.hasAudio
                    ? '${L.player_audio_attached}: ${ctrl.fileName}'
                    : L.player_audio_upload_prompt,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: c.inkSoft, fontSize: 12),
          ),
        ),
        if (ctrl.saving)
          const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2))
        else if (!ctrl.hasAudio)
          OutlinedButton(
            onPressed: ctrl.pickAndAttach,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: c.cardBorder),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              visualDensity: VisualDensity.compact,
            ),
            child: Text(L.player_audio_upload,
                style: TextStyle(color: c.ink, fontSize: 13)),
          )
        else
          TextButton(
            onPressed: ctrl.removeAudio,
            child: Text(L.library_delete,
                style: TextStyle(color: c.rose, fontSize: 12)),
          ),
      ],
    );
  }

  Widget _chip(AppThemeColorsExt c, String label, bool on, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: on ? c.teal : Colors.transparent,
          border: Border.all(color: on ? c.teal : c.cardBorder),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: TextStyle(
                color: on ? Colors.white : c.ink,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ),
    );
  }

  String? _syncErrorText(BuildContext context) {
    final e = ctrl.syncError;
    if (e.isEmpty) return null;
    final L = context.l10n;
    if (e == 'need_pack') return L.player_sync_need_pack;
    if (e.startsWith('coverage:')) {
      return L.player_sync_coverage(e.substring(9));
    }
    return L.player_sync_failed;
  }

  Widget _sync(BuildContext context, AppThemeColorsExt c) {
    final n = ctrl.sentenceCount;
    final err = _syncErrorText(context);
    return Container(
      padding: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.cardBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${context.l10n.settings_sync_title}'
                  '${ctrl.syncTimes == null ? '' : ' — ${context.l10n.storyaudio_sync_count('${ctrl.syncedCount}', '$n')}'}',
                  style: TextStyle(
                      color: c.ink, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              if (ctrl.syncTimes != null) ...[
                Text(context.l10n.storyaudio_follow,
                    style: TextStyle(color: c.inkSoft, fontSize: 11)),
                Switch(
                  value: ctrl.syncOn,
                  onChanged: ctrl.setSyncOn,
                  activeColor: c.teal,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ],
          ),
          if (ctrl.syncBuilding) ...[
            LinearProgressIndicator(
              value: ctrl.syncFrac > 0 ? ctrl.syncFrac : null,
              minHeight: 3,
              color: c.teal,
              backgroundColor: c.cardBorder,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Text(
                '${context.l10n.storyaudio_syncing_phone}'
                '${ctrl.syncFrac > 0 ? ' — ${(ctrl.syncFrac * 100).round()}%' : '...'}\n'
                '${context.l10n.storyaudio_syncing_note}',
                style: TextStyle(color: c.inkSoft, fontSize: 10.5, height: 1.6),
              ),
            ),
          ],
          if (err != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(err, style: TextStyle(color: c.rose, fontSize: 11)),
            ),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (ctrl.syncBuilding)
                _chip(c, context.l10n.storyaudio_sync_stop, false, ctrl.cancelSyncBuild)
              else
                _chip(c, context.l10n.storyaudio_sync_auto, false, ctrl.buildSync),
              _chip(c, context.l10n.storyaudio_estimate, false, ctrl.estimateSync),
              _chip(c, context.l10n.storyaudio_mark_line, false,
                  ctrl.markCurrentLine),
              if (ctrl.syncTimes != null)
                _chip(c, context.l10n.storyaudio_sync_clear, false, ctrl.clearSync),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              context.l10n.storyaudio_sync_tip,
              style: TextStyle(color: c.inkSoft, fontSize: 10.5),
            ),
          ),
        ],
      ),
    );
  }
}
