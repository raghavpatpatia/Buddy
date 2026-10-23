import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../../shared/ui.dart';
import '../model/road_graph.dart';

/// Draws the downloaded streets themselves, so the map still shows roads with no internet.
class RoadLayer extends StatelessWidget {
  final RoadGraph graph;
  const RoadLayer({super.key, required this.graph});

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return MobileLayerTransformer(child: CustomPaint(size: camera.size, painter: _RoadPainter(graph, camera)));
  }
}

class _RoadPainter extends CustomPainter {
  final RoadGraph g;
  final MapCamera camera;
  _RoadPainter(this.g, this.camera);

  @override
  void paint(Canvas canvas, Size size) {
    final z = camera.zoom;
    // Fewer, bigger roads when zoomed out.
    final maxClass = z < 10 ? classTrunk : z < 11.5 ? classSecondary : z < 13 ? classTertiary : z < 14.5 ? classMinor : classService;
    final b = camera.visibleBounds;
    final y0 = RoadGraph.cellY(b.south), y1 = RoadGraph.cellY(b.north), x0 = RoadGraph.cellX(b.west), x1 = RoadGraph.cellX(b.east);
    if ((y1 - y0 + 1) * (x1 - x0 + 1) > 20000) return;
    final drawn = Uint8List(g.pieceCount);
    final paths = List.generate(classService + 1, (_) => Path());
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        for (final p in g.piecesInCell(y, x)) {
          if (drawn[p] == 1 || g.pieceClass[p] > maxClass) continue;
          drawn[p] = 1;
          final path = paths[g.pieceClass[p]];
          var first = true;
          for (final (la, lo) in g.piecePoints(p)) {
            final o = camera.getOffsetFromOrigin(LatLng(la, lo));
            first ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
            first = false;
          }
        }
      }
    }
    final scale = (z - 10).clamp(0.6, 6.0);
    for (var k = classService; k >= 0; k--) {
      final major = k <= classSecondary;
      canvas.drawPath(
        paths[k],
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = (major ? 1.6 : k == classService ? 0.6 : 1.0) * scale
          ..color = major ? SystemColors.mana.withValues(alpha: 0.75) : SystemColors.muted.withValues(alpha: k == classService ? 0.35 : 0.6),
      );
    }
  }

  @override
  bool shouldRepaint(_RoadPainter old) => old.camera != camera || old.g != g;
}
