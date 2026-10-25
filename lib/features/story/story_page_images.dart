// عکسِ صفحه‌های PDFِ داستانِ ذخیره‌شده (اصلی + ترجمه‌شده) در «کتابخانه‌ی داستان‌ساز»؛
// ضربه روی عکس = نمایشِ تمام‌صفحه با زوم، و دکمه‌ی ذخیره در گوشی.
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/storage/story_page_store.dart';
import '../../core/theme/app_theme_colors.dart';
import 'pdf_save_tools.dart';

class StoryPageImages extends StatefulWidget {
  final String storyId;
  final String title;
  final List<String> images; // نام‌ها: o3 / t3 …
  final AppThemeColorsExt colors;

  const StoryPageImages({
    super.key,
    required this.storyId,
    required this.title,
    required this.images,
    required this.colors,
  });

  @override
  State<StoryPageImages> createState() => _StoryPageImagesState();
}

class _StoryPageImagesState extends State<StoryPageImages> {
  static const int _kStep = 4;
  bool _open = false;
  int _shown = _kStep;

  List<int> get _pages {
    final s = <int>{};
    for (final n in widget.images) {
      final i = int.tryParse(n.substring(1));
      if (i != null) s.add(i);
    }
    return s.toList()..sort();
  }

  bool _has(String name) => widget.images.contains(name);

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final pages = _pages;
    if (pages.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.photo_library_outlined, size: 18, color: c.gold),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'عکس صفحه‌ها و ترجمه‌شان (${pages.length} صفحه)',
                      style: TextStyle(
                          color: c.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  Icon(_open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      color: c.inkSoft),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final p in pages.take(_shown)) _pageRow(c, p),
                  if (pages.length > _shown)
                    Center(
                      child: TextButton(
                        onPressed: () => setState(() => _shown += _kStep),
                        child: Text(
                            'نمایش بیشتر ($_shown از ${pages.length} صفحه)'),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _pageRow(AppThemeColorsExt c, int p) {
    final hasO = _has(StoryPageStore.origName(p));
    final hasT = _has(StoryPageStore.transName(p));
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('صفحه‌ی ${p + 1}',
              style: TextStyle(
                  color: c.inkSoft, fontSize: 11.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasO)
                Expanded(child: _thumb(c, p, StoryPageStore.origName(p), 'اصلی')),
              if (hasO && hasT) const SizedBox(width: 8),
              if (hasT)
                Expanded(child: _thumb(c, p, StoryPageStore.transName(p), 'ترجمه')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _thumb(AppThemeColorsExt c, int page, String name, String label) {
    return FutureBuilder<Uint8List?>(
      future: StoryPageStore.get(widget.storyId, name),
      builder: (context, snap) {
        final bytes = snap.data;
        return Column(
          children: [
            Text(label, style: TextStyle(color: c.inkSoft, fontSize: 10.5)),
            const SizedBox(height: 2),
            GestureDetector(
              onTap: bytes == null
                  ? null
                  : () => Navigator.of(context, rootNavigator: true).push(
                        MaterialPageRoute<void>(
                          fullscreenDialog: true,
                          builder: (_) => _FullImage(
                            bytes: bytes,
                            title: '${widget.title} — صفحه‌ی ${page + 1} ($label)',
                            fileName: '${_fileBase(widget.title)}_p${page + 1}'
                                '${name.startsWith('t') ? '_translated' : ''}.png',
                          ),
                        ),
                      ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 80),
                  color: Colors.white,
                  child: bytes == null
                      ? SizedBox(
                          height: 80,
                          child: Center(
                            child: snap.connectionState == ConnectionState.done
                                ? Icon(Icons.broken_image_outlined,
                                    color: c.inkSoft)
                                : const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2)),
                          ),
                        )
                      : Image.memory(bytes,
                          fit: BoxFit.fitWidth,
                          cacheWidth: 700,
                          gaplessPlayback: true),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static String _fileBase(String t) {
    var n = t.trim().replaceAll(RegExp(r'[\/:*?"<>|]'), '_');
    return n.isEmpty ? 'page' : n;
  }
}

class _FullImage extends StatefulWidget {
  final Uint8List bytes;
  final String title;
  final String fileName;
  const _FullImage(
      {required this.bytes, required this.title, required this.fileName});

  @override
  State<_FullImage> createState() => _FullImageState();
}

class _FullImageState extends State<_FullImage> {
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final ok = await saveBytesToDevice(
          fileName: widget.fileName, bytes: widget.bytes, ext: 'png');
      if (ok && mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(const SnackBar(content: Text('عکس ذخیره شد')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(const SnackBar(content: Text('ذخیره‌ی عکس نشد')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title, style: const TextStyle(fontSize: 13)),
        actions: [
          IconButton(
            tooltip: 'ذخیره در گوشی',
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.download_rounded),
          ),
        ],
      ),
      body: InteractiveViewer(
        minScale: 1,
        maxScale: 6,
        child: Center(child: Image.memory(widget.bytes, fit: BoxFit.contain)),
      ),
    );
  }
}
