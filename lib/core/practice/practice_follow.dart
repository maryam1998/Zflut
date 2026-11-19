
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../player_sync/playback_origin.dart'
    show ReadHighlight, readHighlightProvider, revealItemProvider;
import '../player_sync/sync_widgets.dart' show SyncAnchorRegistry;

// ═══════════════════════════════════════════════════════════════════
// 🎯 تمرینِ ویدیو کال (لغات / Talk / داستان):
//   1) ویدیو کال «بالای صفحه سنجاق» می‌شود (جایگاهِ ثابت در AppShell) تا با اسکرولِ متنِ
//      پایین آواتار همیشه دیده شود.
//   2) خطی که آواتار می‌گوید یا کاربر باید بخواند در «متنِ اصلیِ پایین» هایلایت و
//      خودکار اسکرول می‌شود (چیزی روی خودِ ویدیو هایلایت نمی‌شود).
// ═══════════════════════════════════════════════════════════════════

/// ویدیو کالِ سنجاق‌شده؛ [owner] = ویجتی که آن را گذاشته (فقط خودش می‌تواند بردارد).
class PinnedCall {
  final Object owner;
  final Widget child;
  const PinnedCall(this.owner, this.child);
}

final pinnedCallProvider = StateProvider<PinnedCall?>((ref) => null);

/// جایگاهِ ویدیو کال بالای محتوای تب (داخلِ AppShell). اگر بلندتر از حدِ مجاز باشد
/// کوچک می‌شود تا متنِ پایین هم جا داشته باشد.
class PinnedCallSlot extends ConsumerWidget {
  const PinnedCallSlot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(pinnedCallProvider);
    if (p == null) return const SizedBox.shrink();
    final mq = MediaQuery.of(context);
    final typing = mq.viewInsets.bottom > 0;
    final maxH = mq.size.height * (typing ? 0.55 : 0.4);
    return LayoutBuilder(
      builder: (ctx, cons) {
        final w = cons.maxWidth.isFinite ? cons.maxWidth : mq.size.width;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: ClipRect(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: w,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                  child: p.child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// هایلایت + اسکرولِ خودکارِ متنِ اصلی برای خطی که الان گفته/خوانده می‌شود.
class PracticeFollow {
  final ProviderContainer _c;
  PracticeFollow(this._c);

  ReadHighlight? _mine;
  int _token = 0;

  /// [ids] = شناسه‌ی آیتم‌های همان خط (هر کدام که روی صفحه هست هایلایت می‌شود)،
  /// [codes] = کدِ زبانِ لنگرها برای پیدا کردنِ ردیف، [lazy] = لیستِ تنبل (لغات).
  void show(List<String> ids,
      {List<String> codes = const ['en'], bool lazy = false}) {
    final list = [
      for (final i in ids)
        if (i.isNotEmpty) i
    ];
    if (list.isEmpty) return;
    final hl = ReadHighlight(list.toSet());
    _mine = hl;
    try {
      _c.read(readHighlightProvider.notifier).state = hl;
    } catch (_) {}
    final token = ++_token;
    _scroll(list, codes, lazy, token, 0);
  }

  void _scroll(
      List<String> ids, List<String> codes, bool lazy, int token, int attempt) {
    if (token != _token) return;
    for (final id in ids) {
      for (final code in codes) {
        final ctx = SyncAnchorRegistry.find(code, id);
        if (ctx != null && ctx.mounted) {
          final ro = ctx.findRenderObject();
          if (ro != null && ro.attached) {
            Scrollable.ensureVisible(ctx,
                alignment: 0.3,
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOut);
            return;
          }
        }
      }
    }
    // لیستِ تنبل: آیتم هنوز ساخته نشده → از سازوکارِ پرشِ پلیر کمک می‌گیریم
    if (lazy && attempt == 0) {
      try {
        _c.read(revealItemProvider.notifier).state = ids.first;
      } catch (_) {}
      Future.delayed(const Duration(seconds: 3), () {
        try {
          if (_c.read(revealItemProvider) == ids.first) {
            _c.read(revealItemProvider.notifier).state = null;
          }
        } catch (_) {}
      });
    }
    if (attempt < 8) {
      Future.delayed(const Duration(milliseconds: 150),
          () => _scroll(ids, codes, lazy, token, attempt + 1));
    }
  }

  /// هایلایتِ خودش را برمی‌دارد (اگر کسِ دیگری عوضش نکرده باشد).
  void clear() {
    _token++;
    final m = _mine;
    _mine = null;
    if (m == null) return;
    try {
      if (identical(_c.read(readHighlightProvider), m)) {
        _c.read(readHighlightProvider.notifier).state = null;
      }
    } catch (_) {}
  }
}

/// سنجاق/برداشتنِ ویدیو کال توسط یک میزبان (بعد از فریمِ جاری، تا وسطِ build تغییر ندهد).
void pinCallLater(ProviderContainer c, Object owner, Widget? child,
    bool Function() alive) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    try {
      final n = c.read(pinnedCallProvider.notifier);
      if (child != null) {
        if (alive()) n.state = PinnedCall(owner, child);
      } else if (c.read(pinnedCallProvider)?.owner == owner) {
        n.state = null;
      }
    } catch (_) {}
  });
}

/// خروجِ میزبان از درخت: اگر هنوز سنجاق است برداشته شود.
void unpinCall(ProviderContainer c, Object owner) {
  Future<void>.microtask(() {
    try {
      if (c.read(pinnedCallProvider)?.owner == owner) {
        c.read(pinnedCallProvider.notifier).state = null;
      }
    } catch (_) {}
  });
}
