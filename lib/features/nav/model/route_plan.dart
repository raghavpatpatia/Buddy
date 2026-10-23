import 'dart:math';

import 'road_graph.dart' as rg;

/// One spoken / shown instruction.
enum Turn { depart, straight, slightLeft, slightRight, left, right, sharpLeft, sharpRight, uTurn, roundabout, flyover, arrive }

class Maneuver {
  final Turn turn;

  /// Metres from the route start where it happens.
  final double at;
  final String street;

  /// Roundabout exit number (1-based).
  final int exit;

  /// Ready-made wording (from the online router); built from [turn] and [street] when empty.
  final String say;
  const Maneuver(this.turn, this.at, this.street, {this.exit = 0, this.say = ''});

  /// "Turn left onto Ring Road".
  String get text {
    // The arrival step is shown ahead of time, so it says where you'll arrive, not that you have.
    if (say.isNotEmpty && turn != Turn.arrive) return say.endsWith('.') ? say.substring(0, say.length - 1) : say;
    final onto = street.isEmpty ? '' : ' onto $street';
    return switch (turn) {
      Turn.depart => street.isEmpty ? 'Head out' : 'Head out on $street',
      Turn.straight => street.isEmpty ? 'Continue straight' : 'Continue onto $street',
      Turn.slightLeft => 'Keep left$onto',
      Turn.slightRight => 'Keep right$onto',
      Turn.left => 'Turn left$onto',
      Turn.right => 'Turn right$onto',
      Turn.sharpLeft => 'Turn sharp left$onto',
      Turn.sharpRight => 'Turn sharp right$onto',
      Turn.uTurn => 'Make a U-turn$onto',
      Turn.roundabout => 'At the roundabout, take the ${_ordinal(exit)} exit$onto',
      Turn.flyover => street.isEmpty ? 'Take the flyover' : 'Take the flyover on $street',
      Turn.arrive => 'Arrive at your destination',
    };
  }

  static String _ordinal(int n) => switch (n) { 1 => '1st', 2 => '2nd', 3 => '3rd', _ => '${n}th' };
}

/// A found route: its line, running distance at each point, and a summary.
class RoutePlan {
  final List<(double, double)> points;
  final List<double> cumMetres;
  final double metres, seconds;
  final int flyovers, tunnels;
  final List<String> streets;
  final List<Maneuver> maneuvers;

  /// Road pieces used (to compare alternatives).
  final List<int> pieces;
  const RoutePlan({
    required this.points,
    required this.cumMetres,
    required this.metres,
    required this.seconds,
    required this.flyovers,
    required this.tunnels,
    required this.streets,
    this.maneuvers = const [],
    this.pieces = const [],
  });

  /// Where (la, lo) sits on the route, searching from point [from] on: (point index, metres off route, metres left).
  RouteProgress progress(double la, double lo, {int from = 0}) {
    var best = from.clamp(0, points.length - 1);
    var bestD = double.infinity;
    var bestT = 0.0;
    for (var i = best; i < points.length - 1; i++) {
      final (t, d) = _toSegment(la, lo, points[i], points[i + 1]);
      if (d < bestD) {
        bestD = d;
        best = i;
        bestT = t;
      }
    }
    if (points.length == 1) bestD = rg.metres(la, lo, points[0].$1, points[0].$2);
    final seg = points.length > 1 ? cumMetres[best + 1] - cumMetres[best] : 0.0;
    final done = cumMetres[best] + seg * bestT;
    return RouteProgress(best, bestD, max(0.0, cumMetres.last - done), done);
  }

  /// Next instruction after [travelled] metres, or null.
  Maneuver? nextManeuver(double travelled) {
    for (final m in maneuvers) {
      if (m.at > travelled + 5) return m;
    }
    return null;
  }

  /// Fraction along a→b of the closest point to (la, lo), and the distance to it (flat-earth, fine at street scale).
  static (double, double) _toSegment(double la, double lo, (double, double) a, (double, double) b) {
    final k = cos(la * pi / 180) * 111320.0;
    final ax = a.$2 * k, ay = a.$1 * 110540.0, bx = b.$2 * k, by = b.$1 * 110540.0, px = lo * k, py = la * 110540.0;
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    final t = len2 == 0 ? 0.0 : (((px - ax) * dx + (py - ay) * dy) / len2).clamp(0.0, 1.0);
    final cx = ax + dx * t - px, cy = ay + dy * t - py;
    return (t, sqrt(cx * cx + cy * cy));
  }
}

class RouteProgress {
  final int index;
  final double offRoute, metresLeft, travelled;
  const RouteProgress(this.index, this.offRoute, this.metresLeft, this.travelled);
}

/// "12.4 km" / "850 m".
String fmtKm(double m) => m >= 1000 ? '${(m / 1000).toStringAsFixed(m >= 100000 ? 0 : 1)} km' : '${m.round()} m';

/// "1 h 05 min" / "12 min".
String fmtEta(double s) {
  final mins = (s / 60).ceil();
  return mins >= 60 ? '${mins ~/ 60} h ${(mins % 60).toString().padLeft(2, '0')} min' : '$mins min';
}
