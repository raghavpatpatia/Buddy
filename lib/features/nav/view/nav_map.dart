import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../shared/ui.dart';
import '../controller/nav_controller.dart';
import 'road_layer.dart';

LatLng ll((double, double) p) => LatLng(p.$1, p.$2);

const minMapZoom = 3.0, maxMapZoom = 19.0;

/// The map itself: online tiles (cached as you browse), or the downloaded roads when offline,
/// with the route, you, the start and the target on top.
class NavMap extends StatelessWidget {
  final NavController c;
  final MapController? controller;
  final bool interactive;
  final void Function(LatLng)? onLongPress;
  const NavMap({super.key, required this.c, this.controller, this.interactive = true, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final r = c.region, plan = c.plan, g = c.roads;
    final h = c.here;
    final center = h != null && (r == null || r.contains(h.$1, h.$2)) ? ll(h) : r == null ? const LatLng(20.59, 78.96) : LatLng(r.centerLat, r.centerLon);
    final done = c.progress?.index ?? 0;
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: center,
        initialZoom: r == null && h == null ? 4 : 13,
        // Whole-country view out to street level (OpenStreetMap tiles stop at 19).
        minZoom: minMapZoom,
        maxZoom: maxMapZoom,
        initialCameraFit: plan == null || plan.points.length < 2
            ? null
            : CameraFit.coordinates(coordinates: [for (final p in plan.points) ll(p)], padding: const EdgeInsets.all(28)),
        backgroundColor: SystemColors.void_,
        interactionOptions: InteractionOptions(flags: interactive ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.none),
        onLongPress: onLongPress == null ? null : (_, p) => onLongPress!(p),
      ),
      children: [
        if (c.online)
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.raghav.buddy_app',
            tileBuilder: darkModeTileBuilder,
          )
        else if (g != null)
          RoadLayer(graph: g),
        if (plan != null)
          PolylineLayer(polylines: [
            // Other routes, dimmer, under the chosen one.
            for (final alt in c.alternatives)
              Polyline(points: [for (final p in alt.points) ll(p)], strokeWidth: 5, color: SystemColors.muted.withValues(alpha: 0.7), borderStrokeWidth: 1, borderColor: SystemColors.void_),
            // Already driven part fades out.
            if (done > 0) Polyline(points: [for (final p in plan.points.take(done + 1)) ll(p)], strokeWidth: 5, color: SystemColors.muted.withValues(alpha: 0.6)),
            Polyline(
              points: [for (final p in plan.points.skip(done)) ll(p)],
              strokeWidth: 6,
              color: SystemColors.mana,
              borderStrokeWidth: 2,
              borderColor: SystemColors.void_,
            ),
          ]),
        MarkerLayer(markers: [
          if (c.from != null) Marker(point: LatLng(c.from!.lat, c.from!.lon), width: 28, height: 28, child: const _Pin(Icons.trip_origin, Color(0xFFF472B6))),
          if (c.to != null)
            Marker(point: LatLng(c.to!.lat, c.to!.lon), width: 40, height: 40, alignment: Alignment.topCenter, child: const _Pin(Icons.location_on, SystemColors.danger, size: 40)),
          if (h != null) Marker(point: ll(h), width: 30, height: 30, child: _MeDot(heading: c.heading)),
        ]),
        if (c.online) const SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
      ],
    );
  }
}

class _Pin extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const _Pin(this.icon, this.color, {this.size = 28});
  @override
  Widget build(BuildContext context) => Icon(icon, color: color, size: size, shadows: const [Shadow(blurRadius: 6)]);
}

/// You: a glowing dot, or an arrow pointing where you're driving.
class _MeDot extends StatelessWidget {
  final double? heading;
  const _MeDot({this.heading});
  @override
  Widget build(BuildContext context) => heading == null
      ? Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: SystemColors.mana,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [BoxShadow(color: SystemColors.mana.withValues(alpha: 0.6), blurRadius: 12, spreadRadius: 4)],
          ),
        )
      : Transform.rotate(
          angle: heading! * 3.14159265 / 180,
          child: Icon(Icons.navigation, color: SystemColors.manaBright, size: 30, shadows: [Shadow(color: SystemColors.mana, blurRadius: 10)]),
        );
}
