import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../../core/format.dart';
import '../../../shared/ui.dart';
import '../controller/nav_controller.dart';
import '../data/osm_api.dart';
import '../data/tile_api.dart';
import '../model/region.dart';
import 'nav_map.dart';

/// Google-Maps-style offline download: move and zoom the map until the box covers the area you want.
class AreaPicker extends StatefulWidget {
  final NavController c;
  const AreaPicker({super.key, required this.c});
  @override
  State<AreaPicker> createState() => _AreaPickerState();
}

class _AreaPickerState extends State<AreaPicker> {
  static const _inset = 28.0;
  final _map = MapController();
  (double, double, double, double)? _box;
  final _q = TextEditingController();
  List<Place> _hits = const [];
  Timer? _debounce;

  NavController get c => widget.c;

  @override
  void initState() {
    super.initState();
    if (c.manifest == null) c.loadManifest().then((_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    _map.dispose();
    super.dispose();
  }

  void _onMove(MapCamera cam) {
    final s = cam.nonRotatedSize;
    final nw = cam.screenOffsetToLatLng(const Offset(_inset, _inset)),
        se = cam.screenOffsetToLatLng(Offset(s.width - _inset, s.height - _inset));
    setState(() => _box = (se.latitude, nw.longitude, nw.latitude, se.longitude));
  }

  void _search(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) return setState(() => _hits = const []);
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final ctr = _map.camera.center;
        final hits = await OsmApi.searchPlaces(q, near: (ctr.latitude, ctr.longitude));
        if (mounted) setState(() => _hits = hits);
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final m = c.manifest, b = _box;
    final est = m == null || b == null ? null : m.estimate(b);
    final km2 = b == null ? 0.0 : areaKm2(b);
    final String? problem = !c.online
        ? 'Connect to the internet to download maps.'
        : m == null
        ? null
        : b == null
        ? null
        : est!.$1 == 0
        ? 'No map data here yet. Maps cover ${m.country}.'
        : km2 > maxAreaKm2
        ? 'Area too large. Zoom in to pick a smaller area.'
        : null;
    final h = c.here;
    final start = c.region == null ? const LatLng(28.61, 77.21) : LatLng(c.region!.centerLat, c.region!.centerLon);
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      // The keyboard covers the map instead of squeezing the box and buttons up under the search field.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: const Text('Download area')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Material(
              color: SystemColors.panelHigh,
              borderRadius: BorderRadius.circular(12),
              child: TextField(
                controller: _q,
                onChanged: _search,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Find a city or place',
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: h == null ? start : ll(h),
                    initialZoom: 11,
                    minZoom: 5,
            maxZoom: 19,
                    backgroundColor: SystemColors.void_,
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                    onMapReady: () => _onMove(_map.camera),
                    onPositionChanged: (cam, _) => _onMove(cam),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.raghav.buddy_app',
                      tileBuilder: darkModeTileBuilder,
                    ),
                    const SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
                  ],
                ),
                // The box: everything inside it is downloaded.
                const Positioned.fill(
                  child: IgnorePointer(child: CustomPaint(painter: _FramePainter(_inset))),
                ),
                if (_hits.isNotEmpty)
                  Positioned(
                    left: 12,
                    right: 12,
                    top: 0,
                    child: Material(
                      color: SystemColors.panelHigh,
                      borderRadius: BorderRadius.circular(12),
                      child: Column(
                        children: [
                          for (final p in _hits.take(5))
                            ListTile(
                              dense: true,
                              title: Text(p.name),
                              subtitle: Text(p.detail, maxLines: 1, overflow: TextOverflow.ellipsis),
                              onTap: () {
                                _map.move(LatLng(p.lat, p.lon), 11);
                                FocusScope.of(context).unfocus();
                                setState(() => _hits = const []);
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (!typing)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(8),
                // Never taller than half the space left (e.g. with the keyboard up); the texts shrink, not the button.
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: (MediaQuery.sizeOf(context).height - MediaQuery.viewInsetsOf(context).bottom) * 0.5,
                  ),
                  child: AppCard(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Flexible(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text('Download the area inside the box?', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 4),
                                Text(
                                  problem ??
                                      (est == null
                                          ? 'Checking the map server…'
                                          : 'About ${fmtBytes(est.$1)} to download · ${km2.round()} km². Routing then works offline.'),
                                  style: tt.bodySmall?.copyWith(color: problem == null ? null : SystemColors.danger),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: problem != null || est == null || c.download != null
                              ? null
                              : () {
                                  c.downloadArea(b!);
                                  Navigator.pop(context);
                                },
                          icon: const Icon(Icons.download),
                          label: const Text('Download'),
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                        ),
                        if (m != null && m.dataDate.length >= 10) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Map data from ${m.dataDate.substring(0, 10)} · © OpenStreetMap contributors',
                            textAlign: TextAlign.center,
                            style: tt.labelSmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Darkens everything outside the download box and draws its glowing edge.
class _FramePainter extends CustomPainter {
  final double inset;
  const _FramePainter(this.inset);

  @override
  void paint(Canvas canvas, Size size) {
    final box = Rect.fromLTRB(inset, inset, size.width - inset, size.height - inset);
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRect(box)),
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );
    canvas.drawRect(
      box,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = SystemColors.mana,
    );
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.inset != inset;
}
