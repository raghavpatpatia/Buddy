import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../core/cleaner.dart';
import '../core/native.dart';
import '../core/store.dart';
import 'media_preview.dart';
import 'ui.dart';

/// Categories that are mostly photos/videos are shown as a thumbnail grid.
const _visualCats = {'dupes', 'statuses', 'shots', 'bigVideos', 'thumbs'};
const _inlineGrid = 9;

class CleanPage extends StatefulWidget {
  final bool embedded;
  const CleanPage({super.key, this.embedded = false});
  @override
  State<CleanPage> createState() => _CleanPageState();
}

class _CleanPageState extends State<CleanPage> {
  DateTime? _at;
  Map<String, List<CleanItem>> _cats = {};
  final _selected = <String>{};
  bool _scanning = false;
  int _seen = 0, _found = 0;
  String _dir = '';
  Map? _insights;
  bool _insightsLoading = true;
  bool _allFiles = true;

  @override
  void initState() {
    super.initState();
    _loadSaved();
    // Everything slow happens after the first frame, so the tab opens instantly.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final v = await Native.permissions();
      if (!mounted) return;
      setState(() => _allFiles = v['allFiles'] == true);
      // Fresh scan if we've never scanned or the last one is over 10 minutes old.
      if (_allFiles && (_at == null || DateTime.now().difference(_at!).inMinutes >= 10)) _scan();
      final ins = await Native.appInsights();
      if (mounted) {
        setState(() {
          _insights = ins;
          _insightsLoading = false;
        });
      }
    });
  }

  void _loadSaved() {
    final (at, cats) = Cleaner.load();
    _at = at;
    _cats = cats;
    // Pre-select only the categories that are always safe (caches, installers, exact copies).
    _selected
      ..clear()
      ..addAll([
        for (final e in cats.entries)
          if (cleanCategories[e.key]?.$3 == true) ...e.value.map((i) => i.path),
      ]);
  }

  Future<void> _scan() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _seen = 0;
      _found = 0;
      _dir = '';
    });
    final started = DateTime.now();
    List<(String, int, int)>? indexed;
    try {
      indexed = await Native.mediaFiles();
    } catch (_) {}
    Map<String, List<CleanItem>> r;
    try {
      r = await Cleaner.scan(indexed: indexed, onProgress: (seen, dir, found) {
        if (mounted) {
          setState(() {
            _seen = seen;
            _dir = dir;
            _found = found;
          });
        }
      });
    } catch (e, st) {
      // ignore: avoid_print
      print('[BuddyScan] failed: $e\n$st');
      // Never leave the radar spinning forever.
      if (mounted) {
        setState(() => _scanning = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Scan failed: $e')));
      }
      return;
    }
    await Cleaner.save(r);
    await Store.raw.setInt('clean_scan_ms', DateTime.now().difference(started).inMilliseconds);
    if (!mounted) return;
    setState(() {
      _loadSaved();
      _scanning = false;
    });
  }

  void _toggle(String path) => setState(() => _selected.contains(path) ? _selected.remove(path) : _selected.add(path));

  Future<void> _clean() async {
    final items = [for (final l in _cats.values) ...l.where((i) => _selected.contains(i.path))];
    final size = items.fold<int>(0, (a, i) => a + i.size);
    final media = items.where((i) => isImage(i.path) || isVideo(i.path)).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.delete_forever),
        title: Text('Delete ${items.length} files?'),
        content: Text('Frees ${fmtBytes(size)}.'
            '${media > 0 ? '\n\n$media of them are photos/videos. Make sure you\'ve reviewed them.' : ''}'
            '\n\nDeleted files can\'t be recovered.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final freed = await Cleaner.delete(items);
    for (final l in _cats.values) {
      l.removeWhere((i) => _selected.contains(i.path));
    }
    await Cleaner.save(_cats);
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    setState(() => _selected.clear());
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Freed ${fmtBytes(freed)} ✨')));
  }

  @override
  Widget build(BuildContext context) {
    final total = Cleaner.total(_cats);
    final sel = [for (final l in _cats.values) ...l].where((i) => _selected.contains(i.path)).toList();
    final selSize = sel.fold<int>(0, (a, i) => a + i.size);
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
        title: const Text('Cleaner'),
        actions: [
          IconButton(
            tooltip: 'Scan now',
            onPressed: _scanning ? null : _scan,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      bottomNavigationBar: sel.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: _clean,
                  icon: const Icon(Icons.cleaning_services),
                  label: Text('Clean ${sel.length} ${sel.length == 1 ? 'file' : 'files'} · ${fmtBytes(selSize)}'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                ),
              ),
            ),
      body: RefreshIndicator(
        onRefresh: _scan,
        child: ListView(padding: pagePadding, children: [
          if (!_allFiles)
            InfoBanner(
              icon: Icons.folder_off,
              text: 'Allow "All files access" so Buddy can scan your storage.',
              action: 'Allow',
              onTap: () => Native.open('allFiles'),
            ),
          HeroCard(
            child: Column(children: [
              if (_scanning) ...[
                const _Radar(size: 120),
                const SizedBox(height: 14),
                Text('Scanning your storage…', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('${_fmtCount(_seen)} files checked · ${fmtBytes(_found)} found so far',
                    style: tt.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                const SizedBox(height: 2),
                Text(_dir.isEmpty ? 'Starting…' : _dir, maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.bodySmall),
              ] else if (_at == null) ...[
                Icon(Icons.radar, size: 48, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 8),
                Text('Not scanned yet', style: tt.titleLarge),
                const SizedBox(height: 12),
                FilledButton.icon(onPressed: _allFiles ? _scan : null, icon: const Icon(Icons.radar), label: const Text('Scan now')),
              ] else ...[
                Text(fmtBytes(total), style: tt.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
                Text(total == 0 ? 'Nothing to clean, your storage is tidy ✨' : 'can be freed', style: tt.bodyLarge),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 4, alignment: WrapAlignment.center, children: [
                  StatChip(
                    icon: Icons.schedule,
                    label: 'Scanned ${_ago(_at!)}${Store.raw.getInt('clean_scan_ms') == null ? '' : ' in ${(Store.raw.getInt('clean_scan_ms')! / 1000).toStringAsFixed(1)} s'}',
                  ),
                  StatChip(icon: Icons.autorenew, label: 'Auto every 1–2 h'),
                  StatChip(icon: Icons.savings_outlined, label: 'Freed ${fmtBytes(Store.raw.getInt('freed_total') ?? 0)}'),
                ]),
              ],
            ]),
          ),
          if (!_scanning && total > 0) ...[
            const SectionTitle('Found', trailing: Text('Tap a photo to preview · long-press to mark', style: TextStyle(fontSize: 11))),
            for (final e in cleanCategories.entries)
              if ((_cats[e.key] ?? []).isNotEmpty) _category(e.key, e.value.$1, e.value.$2, _cats[e.key]!),
          ],
          if (_insightsLoading)
            const AppCard(
              child: Row(children: [
                SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 12),
                Expanded(child: Text('Checking apps for big caches & unused apps…')),
              ]),
            )
          else if (_insights != null) ...[
            if ((_insights!['bigCaches'] as List).isNotEmpty) ...[
              const SectionTitle('Apps with big caches'),
              Text('Android only lets you clear another app\'s cache yourself: tap → Storage → Clear cache.', style: tt.bodySmall),
              const SizedBox(height: 6),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  for (final a in _insights!['bigCaches'])
                    ListTile(
                      leading: const Icon(Icons.layers_outlined),
                      title: Text(a['label']),
                      trailing: Text('${a['cacheMB']} MB', style: const TextStyle(fontWeight: FontWeight.w600)),
                      onTap: () => Native.open('appDetails', pkg: a['pkg']),
                    ),
                ]),
              ),
            ],
            if ((_insights!['unused'] as List).isNotEmpty) ...[
              const SectionTitle('Apps you haven\'t opened in 30+ days'),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  for (final a in _insights!['unused'])
                    ListTile(
                      leading: const Icon(Icons.hourglass_bottom),
                      title: Text(a['label']),
                      subtitle: Text('${a['idleDays']} days idle · ${a['totalMB']} MB'),
                      trailing: TextButton(onPressed: () => Native.open('uninstall', pkg: a['pkg']), child: const Text('Uninstall')),
                    ),
                ]),
              ),
            ],
          ] else
            InfoBanner(
              icon: Icons.apps,
              text: 'Allow Usage access to find unused apps & big caches.',
              action: 'Allow',
              onTap: () => Native.open('usage'),
            ),
          const SizedBox(height: 12),
          const AppCard(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('💡', style: TextStyle(fontSize: 18)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Why no "RAM booster"? Android manages memory itself; force-killing apps makes them restart, '
                  'which costs battery and makes the phone feel slower. Keeping 10–15% storage free and removing '
                  'unused apps is what actually keeps a phone smooth.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _category(String id, String title, String desc, List<CleanItem> items) {
    final size = items.fold<int>(0, (a, i) => a + i.size);
    final selCount = items.where((i) => _selected.contains(i.path)).length;
    final allSel = selCount == items.length;
    void selectAll(bool v) => setState(() => v ? _selected.addAll(items.map((i) => i.path)) : _selected.removeAll(items.map((i) => i.path)));
    Future<void> openGallery() async {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CategoryGallery(title: title, items: items, selected: _selected, onToggle: _toggle, onSelectAll: selectAll),
      ));
      setState(() {});
    }

    final visual = _visualCats.contains(id);
    return AppCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: visual && id != 'thumbs',
          shape: const RoundedRectangleBorder(),
          leading: Checkbox(
            value: allSel ? true : selCount > 0 ? null : false,
            tristate: true,
            onChanged: (_) => selectAll(!allSel),
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${items.length} ${items.length == 1 ? 'file' : 'files'} · ${fmtBytes(size)}${selCount > 0 ? ' · $selCount marked' : ''}\n$desc',
              style: const TextStyle(fontSize: 12)),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: [
            if (visual)
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: [
                  for (final (i, it) in items.take(_inlineGrid).indexed)
                    SelectableThumb(
                      item: it,
                      selected: _selected.contains(it.path),
                      onToggle: () => _toggle(it.path),
                      onOpen: () async {
                        await MediaViewer.open(context, items, i, _selected, _toggle);
                        setState(() {});
                      },
                    ),
                ],
              )
            else
              for (final (i, it) in items.take(8).indexed)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: ClipRRect(borderRadius: BorderRadius.circular(8), child: MediaThumb(path: it.path, size: 44)),
                  title: Text(p.basename(it.path), maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${fmtBytes(it.size)}${it.note.isNotEmpty ? ' · ${it.note}' : ''}', maxLines: 1),
                  trailing: Checkbox(value: _selected.contains(it.path), onChanged: (_) => _toggle(it.path)),
                  onTap: () async {
                    await MediaViewer.open(context, items, i, _selected, _toggle);
                    setState(() {});
                  },
                ),
            if (items.length > (visual ? _inlineGrid : 8))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  onPressed: openGallery,
                  icon: const Icon(Icons.grid_view),
                  label: Text('Review all ${items.length}'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _fmtCount(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}k' : '$n';

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }
}

/// Rotating radar sweep shown while scanning.
class _Radar extends StatefulWidget {
  final double size;
  const _Radar({required this.size});
  @override
  State<_Radar> createState() => _RadarState();
}

class _RadarState extends State<_Radar> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => CustomPaint(painter: _RadarPainter(_c.value, cs.primary)),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double t;
  final Color color;
  _RadarPainter(this.t, this.color);

  @override
  void paint(Canvas c, Size s) {
    final center = s.center(Offset.zero);
    final r = s.width / 2;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color.withValues(alpha: 0.25);
    for (final f in [0.33, 0.66, 1.0]) {
      c.drawCircle(center, r * f - 1, ring);
    }
    final angle = t * 2 * pi;
    final sweep = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: pi / 2,
        colors: [color.withValues(alpha: 0), color.withValues(alpha: 0.55)],
        transform: GradientRotation(angle - pi / 2),
      ).createShader(Rect.fromCircle(center: center, radius: r));
    c.drawArc(Rect.fromCircle(center: center, radius: r - 1), angle - pi / 2, pi / 2, true, sweep);
    c.drawLine(center, center + Offset(cos(angle), sin(angle)) * (r - 1), Paint()
      ..color = color
      ..strokeWidth = 2);
    // A few "found" blips pulsing
    for (final (i, a) in [0.7, 2.4, 4.1].indexed) {
      final pulse = ((t * 3 + i / 3) % 1);
      c.drawCircle(center + Offset(cos(a), sin(a)) * r * (0.35 + i * 0.18), 3 + pulse * 3, Paint()..color = color.withValues(alpha: 1 - pulse));
    }
    c.drawCircle(center, 6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_RadarPainter o) => o.t != t;
}
