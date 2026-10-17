// نوارِ صوتِ آپلودیِ داستان — معادلِ UserAudioBar.jsx + AudioSyncSettings.jsx در Hope.
import 'package:flutter/material.dart';

import '../../core/audio/story_audio_controller.dart';
import '../../core/theme/app_theme_colors.dart';

String _fmt(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

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
              _header(c),
              if (ctrl.error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(ctrl.error,
                      style: TextStyle(color: c.rose, fontSize: 11)),
                ),
              if (ctrl.hasAudio && !ctrl.saving) ...[
                const SizedBox(height: 8),
                _player(c),
                const SizedBox(height: 8),
                _sync(c),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _header(AppThemeColorsExt c) {
    return Row(
      children: [
        Icon(Icons.headphones, size: 16, color: c.inkSoft),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            ctrl.saving
                ? 'در حال ذخیره‌ی صدا روی گوشی...'
                : ctrl.hasAudio
                    ? 'صوتِ شما وصل شد: ${ctrl.fileName}'
                    : 'فایلِ صوتیِ خودت رو برای این داستان آپلود کن',
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
            child: Text('آپلود صوت',
                style: TextStyle(color: c.ink, fontSize: 13)),
          )
        else
          TextButton(
            onPressed: ctrl.removeAudio,
            child: Text('حذف', style: TextStyle(color: c.rose, fontSize: 12)),
          ),
      ],
    );
  }

  Widget _iconBtn(AppThemeColorsExt c, IconData icon, VoidCallback onTap,
      {String? tip, double size = 22, Color? color}) {
    return IconButton(
      onPressed: onTap,
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, size: size, color: color ?? c.ink),
    );
  }

  Widget _player(AppThemeColorsExt c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ValueListenableBuilder<Duration>(
          valueListenable: ctrl.position,
          builder: (_, pos, __) {
            final total = ctrl.duration.inMilliseconds.toDouble();
            final cur = pos.inMilliseconds.toDouble().clamp(0, total > 0 ? total : 1).toDouble();
            return Row(
              textDirection: TextDirection.ltr,
              children: [
                Text(_fmt(pos), style: TextStyle(color: c.inkSoft, fontSize: 11)),
                Expanded(
                  child: Slider(
                    value: cur,
                    min: 0,
                    max: total > 0 ? total : 1,
                    activeColor: c.teal,
                    onChanged: total > 0
                        ? (v) => ctrl.seek(Duration(milliseconds: v.round()))
                        : null,
                  ),
                ),
                Text(_fmt(ctrl.duration),
                    style: TextStyle(color: c.inkSoft, fontSize: 11)),
              ],
            );
          },
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          textDirection: TextDirection.ltr,
          children: [
            _iconBtn(c, Icons.skip_previous, ctrl.prevLine, tip: 'جمله‌ی قبل'),
            _iconBtn(c, Icons.replay_10, () => ctrl.skip(-10), tip: '۱۰ ثانیه عقب'),
            Material(
              color: c.teal,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: ctrl.toggle,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(ctrl.isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white, size: 26),
                ),
              ),
            ),
            _iconBtn(c, Icons.forward_10, () => ctrl.skip(10), tip: '۱۰ ثانیه جلو'),
            _iconBtn(c, Icons.skip_next, ctrl.nextLine, tip: 'جمله‌ی بعد'),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final r in const [0.75, 1.0, 1.25, 1.5])
              _chip(c, '${r == 1.0 ? '1' : r}×', (ctrl.rate - r).abs() < 0.01,
                  () => ctrl.setRate(r)),
            _chip(
              c,
              ctrl.abState == AbState.idle
                  ? 'تکرارِ A-B'
                  : ctrl.abState == AbState.waitingB
                      ? 'A ثبت شد — B رو بزن'
                      : 'در حال تکرار (خاموش)',
              ctrl.abState != AbState.idle,
              ctrl.markAB,
            ),
          ],
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

  Widget _sync(AppThemeColorsExt c) {
    final n = ctrl.sentenceCount;
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
                  'همگام‌سازیِ متن با صدا'
                  '${ctrl.syncTimes == null ? '' : ' — ${ctrl.syncedCount} از $n جمله'}',
                  style: TextStyle(
                      color: c.ink, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              if (ctrl.syncTimes != null) ...[
                Text('دنبال کن',
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
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _chip(c, 'تخمینِ خودکار', false, ctrl.estimateSync),
              _chip(c, 'ثبتِ شروعِ این جمله و رفتن به بعدی', false,
                  ctrl.markCurrentLine),
              if (ctrl.syncTimes != null)
                _chip(c, 'پاک کردنِ همگام‌سازی', false, ctrl.clearSync),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'برای دقت: صدا رو پخش کن و هر وقت یه جمله شروع شد دکمه‌ی «ثبتِ شروعِ این جمله» رو بزن.',
              style: TextStyle(color: c.inkSoft, fontSize: 10.5),
            ),
          ),
        ],
      ),
    );
  }
}
