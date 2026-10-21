import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';

import '../core/cleaner.dart';
import '../core/native.dart';

const _imageExt = {'.jpg', '.jpeg', '.png', '.webp', '.gif', '.heic', '.heif', '.bmp'};
const _videoExt = {'.mp4', '.mkv', '.mov', '.avi', '.webm', '.3gp', '.m4v'};

bool isImage(String path) => _imageExt.contains(p.extension(path).toLowerCase());
bool isVideo(String path) => _videoExt.contains(p.extension(path).toLowerCase());

final _videoThumbs = <String, Future<Uint8List?>>{};

IconData _iconFor(String path) => switch (p.extension(path).toLowerCase()) {
      '.apk' => Icons.android,
      '.pdf' => Icons.picture_as_pdf,
      '.zip' || '.rar' || '.7z' => Icons.folder_zip,
      '.mp3' || '.m4a' || '.wav' || '.opus' || '.aac' => Icons.audiotrack,
      '.doc' || '.docx' || '.txt' => Icons.description,
      _ => Icons.insert_drive_file,
    };

/// Square preview: real image, video frame with play badge, or a file-type icon.
class MediaThumb extends StatelessWidget {
  final String path;
  final double? size;
  const MediaThumb({super.key, required this.path, this.size});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget fallback() => Container(
          color: cs.surfaceContainerHighest,
          alignment: Alignment.center,
          child: Icon(_iconFor(path), color: cs.onSurfaceVariant),
        );
    Widget child;
    if (isImage(path)) {
      child = Image.file(File(path), fit: BoxFit.cover, cacheWidth: 300, gaplessPlayback: true, errorBuilder: (_, _, _) => fallback());
    } else if (isVideo(path)) {
      child = FutureBuilder<Uint8List?>(
        future: _videoThumbs.putIfAbsent(path, () => Native.videoThumb(path)),
        builder: (_, s) => Stack(fit: StackFit.expand, children: [
          if (s.data != null) Image.memory(s.data!, fit: BoxFit.cover, gaplessPlayback: true) else fallback(),
          const Center(child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 32)),
        ]),
      );
    } else {
      child = fallback();
    }
    return SizedBox(width: size, height: size, child: child);
  }
}

/// Grid tile with a selection badge. Tap = preview, tap badge = toggle.
class SelectableThumb extends StatelessWidget {
  final CleanItem item;
  final bool selected;
  final VoidCallback onToggle, onOpen;
  const SelectableThumb({super.key, required this.item, required this.selected, required this.onToggle, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onOpen,
      onLongPress: () {
        HapticFeedback.selectionClick();
        onToggle();
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(fit: StackFit.expand, children: [
          MediaThumb(path: item.path),
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              border: Border.all(color: selected ? cs.error : Colors.transparent, width: 3),
              borderRadius: BorderRadius.circular(12),
              color: selected ? cs.error.withValues(alpha: 0.18) : null,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: const BoxDecoration(
                gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black54, Colors.transparent]),
              ),
              child: Text(fmtBytes(item.size), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () {
                HapticFeedback.selectionClick();
                onToggle();
              },
              icon: Icon(
                selected ? Icons.delete : Icons.circle_outlined,
                color: selected ? cs.onError : Colors.white,
                shadows: const [Shadow(blurRadius: 4)],
              ),
              style: IconButton.styleFrom(backgroundColor: selected ? cs.error : Colors.black26),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Full-screen swipeable viewer: zoom photos, play videos, mark Keep / Delete.
class MediaViewer extends StatefulWidget {
  final List<CleanItem> items;
  final int initial;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  const MediaViewer({super.key, required this.items, required this.initial, required this.selected, required this.onToggle});

  static Future<void> open(BuildContext context, List<CleanItem> items, int index, Set<String> selected, ValueChanged<String> onToggle) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MediaViewer(items: items, initial: index, selected: selected, onToggle: onToggle),
      ));

  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> {
  late final _pc = PageController(initialPage: widget.initial);
  late int _i = widget.initial;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _mark(bool delete) {
    final path = widget.items[_i].path;
    if (widget.selected.contains(path) != delete) widget.onToggle(path);
    HapticFeedback.lightImpact();
    setState(() {});
    if (_i < widget.items.length - 1) {
      _pc.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.items[_i];
    final marked = widget.selected.contains(item.path);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        titleTextStyle: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
        systemOverlayStyle: SystemUiOverlayStyle.light,
        title: Text('${_i + 1} of ${widget.items.length}'),
      ),
      body: Column(children: [
        Expanded(
          child: PageView.builder(
            controller: _pc,
            itemCount: widget.items.length,
            onPageChanged: (i) => setState(() => _i = i),
            itemBuilder: (_, i) {
              final path = widget.items[i].path;
              if (isImage(path)) {
                return InteractiveViewer(
                  maxScale: 5,
                  child: Center(child: Image.file(File(path), errorBuilder: (_, _, _) => const _Unavailable())),
                );
              }
              if (isVideo(path)) return _VideoView(path: path, key: ValueKey(path));
              return Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_iconFor(path), size: 96, color: Colors.white54),
                  const SizedBox(height: 12),
                  const Text('No preview for this file type', style: TextStyle(color: Colors.white54)),
                ]),
              );
            },
          ),
        ),
        Container(
          color: const Color(0xFF111111),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: SafeArea(
            top: false,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.basename(item.path), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                '${fmtBytes(item.size)}${item.note.isNotEmpty ? ' · ${item.note}' : ''}\n${p.dirname(item.path).replaceFirst(Cleaner.root, 'Internal storage')}',
                maxLines: 3,
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _mark(false),
                    icon: const Icon(Icons.favorite_border),
                    label: const Text('Keep'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: marked ? Colors.white24 : Colors.greenAccent, width: marked ? 1 : 2),
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _mark(true),
                    icon: Icon(marked ? Icons.check : Icons.delete_outline),
                    label: Text(marked ? 'Marked' : 'Delete'),
                    style: FilledButton.styleFrom(
                      backgroundColor: marked ? Colors.redAccent : Colors.white12,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable();
  @override
  Widget build(BuildContext context) =>
      const Text('Preview unavailable', style: TextStyle(color: Colors.white54));
}

class _VideoView extends StatefulWidget {
  final String path;
  const _VideoView({super.key, required this.path});
  @override
  State<_VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<_VideoView> {
  late final VideoPlayerController _c = VideoPlayerController.file(File(widget.path));
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _c.initialize().then((_) {
      if (mounted) setState(() {});
    }).catchError((_) {
      if (mounted) setState(() => _error = true);
    });
    _c.addListener(() => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error) return const Center(child: _Unavailable());
    if (!_c.value.isInitialized) return const Center(child: CircularProgressIndicator());
    return GestureDetector(
      onTap: () => _c.value.isPlaying ? _c.pause() : _c.play(),
      child: Stack(alignment: Alignment.center, children: [
        AspectRatio(aspectRatio: _c.value.aspectRatio, child: VideoPlayer(_c)),
        if (!_c.value.isPlaying) const Icon(Icons.play_circle_fill, size: 72, color: Colors.white70),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: VideoProgressIndicator(_c, allowScrubbing: true, padding: const EdgeInsets.all(12)),
        ),
      ]),
    );
  }
}

/// Lazy full-screen grid for a whole category.
class CategoryGallery extends StatefulWidget {
  final String title;
  final List<CleanItem> items;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final void Function(bool all) onSelectAll;
  const CategoryGallery({super.key, required this.title, required this.items, required this.selected, required this.onToggle, required this.onSelectAll});

  @override
  State<CategoryGallery> createState() => _CategoryGalleryState();
}

class _CategoryGalleryState extends State<CategoryGallery> {
  @override
  Widget build(BuildContext context) {
    final sel = widget.items.where((i) => widget.selected.contains(i.path)).toList();
    final all = sel.length == widget.items.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: () => setState(() => widget.onSelectAll(!all)),
            child: Text(all ? 'Select none' : 'Select all'),
          ),
        ],
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8),
        itemCount: widget.items.length,
        itemBuilder: (context, i) => SelectableThumb(
          item: widget.items[i],
          selected: widget.selected.contains(widget.items[i].path),
          onToggle: () => setState(() => widget.onToggle(widget.items[i].path)),
          onOpen: () async {
            await MediaViewer.open(context, widget.items, i, widget.selected, widget.onToggle);
            setState(() {});
          },
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            child: Text(sel.isEmpty ? 'Done' : 'Done · ${sel.length} marked (${fmtBytes(sel.fold(0, (a, i) => a + i.size))})'),
          ),
        ),
      ),
    );
  }
}
