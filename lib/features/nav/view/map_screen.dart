import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/arch/load_state.dart';
import '../../../shared/ui.dart';
import '../controller/nav_controller.dart';
import '../model/region.dart';
import 'nav_map.dart';
import 'nav_widgets.dart';

/// Full-screen live map: follows you, keeps "You" / "Target" and the km left on screen.
class MapScreen extends StatefulWidget {
  final NavController c;
  const MapScreen({super.key, required this.c});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _map = MapController();
  bool _follow = true;
  bool _ready = false;
  (double, double)? _lastMe;

  NavController get c => widget.c;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ready = true;
      _onChange();
    });
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    _map.dispose();
    super.dispose();
  }

  void _onChange() {
    final h = c.here;
    if (!_ready || !_follow || h == null || h == _lastMe) return;
    _lastMe = h;
    _map.move(ll(h), _map.camera.zoom < 15 ? 16 : _map.camera.zoom);
  }

  void _fitRoute() {
    final plan = c.plan;
    if (plan == null || plan.points.length < 2) return;
    setState(() => _follow = false);
    _map.fitCamera(CameraFit.coordinates(coordinates: [for (final p in plan.points) ll(p)], padding: const EdgeInsets.fromLTRB(40, 200, 40, 260)));
  }

  void _zoom(double by) {
    final cam = _map.camera;
    _map.move(cam.center, (cam.zoom + by).clamp(minMapZoom, maxMapZoom));
  }

  Future<void> _dropTarget(LatLng p) async {
    c.setTo(Place('Dropped pin', '', p.latitude, p.longitude));
    await c.findRoute();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: c,
        builder: (context, _) => Scaffold(
          appBar: AppBar(
            title: Text(c.region?.name ?? 'Map'),
            actions: [
              IconButton(
              tooltip: c.voiceOn ? 'Mute directions' : 'Speak directions',
              onPressed: () => c.setVoice(!c.voiceOn),
              icon: Icon(c.voiceOn ? Icons.volume_up : Icons.volume_off),
            ),
            if (c.plan != null) IconButton(tooltip: 'Whole route', onPressed: _fitRoute, icon: const Icon(Icons.zoom_out_map)),
            if (c.to != null || c.from != null)
              IconButton(
                tooltip: 'Clear pins',
                onPressed: () {
                  c.clearTarget();
                  c.setFrom(null);
                },
                icon: const Icon(Icons.wrong_location_outlined),
              ),
            ],
          ),
          body: Stack(children: [
            // Any drag on the map stops following, so you can look around.
            Listener(
              onPointerMove: (_) {
                if (_follow) setState(() => _follow = false);
              },
              child: NavMap(c: c, controller: _map, onLongPress: _dropTarget),
            ),
            // Cards on top and bottom, map controls in the free band between them, so nothing covers anything.
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: Column(children: [
                  // Driving: the next turn first, like Google Maps.
                  if (c.plan != null && c.from == null && c.nextManeuver != null) ManeuverBanner(c: c),
                  EndsCard(c: c),
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomRight,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          FloatingActionButton.small(
                            heroTag: 'follow',
                            tooltip: 'Follow me',
                            onPressed: c.here == null
                                ? null
                                : () {
                                    setState(() => _follow = true);
                                    _lastMe = null;
                                    _onChange();
                                  },
                            child: Icon(_follow ? Icons.navigation : Icons.my_location),
                          ),
                          const SizedBox(height: 8),
                          FloatingActionButton.small(heroTag: 'zoomIn', tooltip: 'Zoom in', onPressed: () => _zoom(1), child: const Icon(Icons.add)),
                          const SizedBox(height: 8),
                          FloatingActionButton.small(heroTag: 'zoomOut', tooltip: 'Zoom out', onPressed: () => _zoom(-1), child: const Icon(Icons.remove)),
                        ]),
                      ),
                    ),
                  ),
                  AppCard(
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (c.route case Failed(:final message)) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(message, style: const TextStyle(color: SystemColors.danger))),
                      if (c.plan != null) RouteSummary(c: c, compact: true) else Text(c.to == null ? 'Long-press the map to set a target.' : 'Finding the route…'),
                      const SizedBox(height: 10),
                      ModeSwitch(c: c),
                    ]),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      );
}
