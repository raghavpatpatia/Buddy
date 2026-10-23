import 'dart:math';

import 'cch.dart';
import 'road_graph.dart';
import 'route_plan.dart';

/// Routes between any two points on a downloaded map, using its [Cch].
class Router {
  final RoadGraph g;
  final Cch cch;
  Router(this.g, this.cch);

  /// Restriction copies of each tower (they share the tower's exits, minus banned turns).
  late final Map<int, List<int>> _copies = () {
    final m = <int, List<int>>{};
    for (var i = 0; i < g.copyOf.length; i++) {
      (m[g.copyOf[i]] ??= []).add(g.baseNodes + i);
    }
    return m;
  }();

  double _cost(int piece, double metres, bool fastest) => fastest ? metres * 3.6 / g.pieceSpeed[piece] : metres;

  /// The junction of a loop road that may be driven in direction [rev], else null.
  int? _loop(int piece, int rev) =>
      g.pieceA[piece] == g.pieceB[piece] && g.pieceDir[piece] & (rev == 0 ? dirForward : dirBackward) != 0 ? g.pieceA[piece] : null;

  /// Edges that drive along [piece] in direction [rev], from the tower itself and its copies.
  Iterable<int> _edgesOn(int piece, int rev) sync* {
    final from = rev == 0 ? g.pieceA[piece] : g.pieceB[piece];
    for (final u in [from, ...?_copies[from]]) {
      for (var e = g.edgeStart[u]; e < g.edgeStart[u + 1]; e++) {
        if (g.edgePiece[e] == piece && g.edgeRev[e] == rev) yield e;
      }
    }
  }

  /// Best route from [s] to [t], or null when no road connects them. [w] defaults to the plain metric.
  RoutePlan? route(Snap s, Snap t, {bool fastest = true, CchMetric? w}) {
    final metric = w ?? cch.metric(fastest);
    final len = g.pieceLen;
    // Leave the start piece towards either end it can be driven to; join the target piece from either end.
    final sources = <(int, double)>[], srcLegs = <(int, double)>[];
    for (final rev in [0, 1]) {
      // A loop road (both ends at one junction) has no edges: it is entered and left at that junction.
      final node = _loop(s.piece, rev) ?? _edgesOn(s.piece, rev).map((e) => g.edgeTo[e]).firstOrNull;
      if (node == null) continue;
      final m = rev == 0 ? len[s.piece] - s.fromA : s.fromA;
      sources.add((node, _cost(s.piece, m, fastest)));
      srcLegs.add((rev, m));
    }
    final targets = <(int, double)>[], dstLegs = <(int, double)>[];
    for (final rev in [0, 1]) {
      final m = rev == 0 ? t.fromA : len[t.piece] - t.fromA;
      final loop = _loop(t.piece, rev);
      for (final node in loop != null ? [loop] : _edgesOn(t.piece, rev).map(_sourceOf)) {
        targets.add((node, _cost(t.piece, m, fastest)));
        dstLegs.add((rev, m));
      }
    }
    if (sources.isEmpty || targets.isEmpty) return null;

    // Same road, driving straight there without touching a junction.
    (int, double)? direct;
    if (s.piece == t.piece) {
      for (final (rev, _) in srcLegs) {
        final ahead = rev == 0 ? t.fromA - s.fromA : s.fromA - t.fromA;
        if (ahead >= 0 && (direct == null || ahead < direct.$2)) direct = (rev, ahead);
      }
    }
    final p = cch.query(sources, targets, metric);
    if (direct != null && (p == null || _cost(s.piece, direct.$2, fastest) <= p.cost)) {
      return _plan(s, t, [(s.piece, direct.$1)]);
    }
    if (p == null) return null;
    final legs = <(int, int)>[for (final e in p.edges) (g.edgePiece[e], g.edgeRev[e])];
    // Start / end exactly on a junction: no stretch of the snapped road to drive.
    final cutStart = srcLegs[p.sourceIndex].$2 >= 0.5 || legs.isEmpty, cutEnd = dstLegs[p.targetIndex].$2 >= 0.5 || legs.isEmpty;
    if (cutStart) legs.insert(0, (s.piece, srcLegs[p.sourceIndex].$1));
    if (cutEnd) legs.add((t.piece, dstLegs[p.targetIndex].$1));
    return _plan(s, t, legs, cutStart: cutStart, cutEnd: cutEnd);
  }

  late final List<int> _src = () {
    final src = List<int>.filled(g.edgeCount, 0);
    for (var u = 0; u < g.nodeCount; u++) {
      for (var e = g.edgeStart[u]; e < g.edgeStart[u + 1]; e++) {
        src[e] = u;
      }
    }
    return src;
  }();
  int _sourceOf(int e) => _src[e];

  /// Up to [count] other good routes (Google-style alternatives): penalise the roads already used, re-run the
  /// cheap CCH customization, and keep a result that is different enough and not much slower.
  List<RoutePlan> alternatives(Snap s, Snap t, RoutePlan best, {bool fastest = true, int count = 2}) {
    final out = <RoutePlan>[];
    final penalty = <int, double>{};
    final bestCost = fastest ? best.seconds : best.metres;
    for (var round = 0; round < count + 2 && out.length < count; round++) {
      for (final r in [best, ...out]) {
        for (final p in r.pieces) {
          penalty[p] = (penalty[p] ?? 1) * 1.4;
        }
      }
      final w = cch.customize(g, (e) => g.edgeCost(e, fastest) * (penalty[g.edgePiece[e]] ?? 1));
      final alt = route(s, t, fastest: fastest, w: w);
      if (alt == null) continue;
      final cost = fastest ? alt.seconds : alt.metres;
      if (cost > bestCost * 1.35) continue;
      if ([best, ...out].any((r) => _shared(alt, r) > 0.7)) continue;
      out.add(alt);
    }
    return out;
  }

  /// Share of [a]'s length that is also on [b].
  double _shared(RoutePlan a, RoutePlan b) {
    final inB = b.pieces.toSet();
    var same = 0.0, all = 0.0;
    for (final p in a.pieces) {
      all += g.pieceLen[p];
      if (inB.contains(p)) same += g.pieceLen[p];
    }
    return all == 0 ? 1 : same / all;
  }

  // ---------- Building the plan ----------

  RoutePlan _plan(Snap s, Snap t, List<(int, int)> legs, {bool cutStart = true, bool cutEnd = true}) {
    final pts = <(double, double)>[];
    final legEnd = <int>[]; // index in pts where each leg ends
    var m = 0.0, sec = 0.0;
    for (var i = 0; i < legs.length; i++) {
      final (p, rev) = legs[i];
      var line = g.piecePoints(p, reverse: rev == 1);
      final segs = line.length - 1;
      // Cut the first leg at the start point and the last at the target point.
      final first = i == 0 && cutStart, last = i == legs.length - 1 && cutEnd;
      if (first) {
        final k = rev == 0 ? s.seg + 1 : segs - s.seg;
        line = [(s.lat, s.lon), ...line.sublist(k)];
      }
      if (last) {
        final k = rev == 0 ? t.seg + 1 : segs - t.seg;
        final keep = first ? k - (rev == 0 ? s.seg + 1 : segs - s.seg) + 1 : k;
        line = [...line.sublist(0, keep.clamp(1, line.length)), (t.lat, t.lon)];
      }
      pts.addAll(pts.isEmpty ? line : line.skip(1));
      legEnd.add(pts.length - 1);
      final full = g.pieceLen[p].toDouble();
      final used = first && last
          ? (t.fromA - s.fromA).abs()
          : first
              ? (rev == 0 ? full - s.fromA : s.fromA)
              : last
                  ? (rev == 0 ? t.fromA : full - t.fromA)
                  : full;
      m += used;
      sec += used * 3.6 / g.pieceSpeed[p];
    }
    final cum = <double>[0];
    for (var i = 1; i < pts.length; i++) {
      cum.add(cum.last + metres(pts[i - 1].$1, pts[i - 1].$2, pts[i].$1, pts[i].$2));
    }
    var flyovers = 0, tunnels = 0, prevFlags = 0;
    final streets = <String>[];
    for (final (p, _) in legs) {
      final f = g.pieceFlags[p];
      if (f & flagBridge != 0 && prevFlags & flagBridge == 0) flyovers++;
      if (f & flagTunnel != 0 && prevFlags & flagTunnel == 0) tunnels++;
      prevFlags = f;
      final name = g.nameOf(p);
      if (name.isNotEmpty && (streets.isEmpty || streets.last != name)) streets.add(name);
    }
    return RoutePlan(
      points: pts,
      cumMetres: cum,
      metres: m,
      seconds: sec,
      flyovers: flyovers,
      tunnels: tunnels,
      streets: streets,
      maneuvers: _maneuvers(legs, pts, legEnd, cum),
      pieces: [for (final (p, _) in legs) p],
    );
  }

  List<Maneuver> _maneuvers(List<(int, int)> legs, List<(double, double)> pts, List<int> legEnd, List<double> cum) {
    final out = <Maneuver>[Maneuver(Turn.depart, 0, g.nameOf(legs.first.$1))];
    var i = 1;
    while (i < legs.length) {
      final (p, rev) = legs[i];
      final prevP = legs[i - 1].$1;
      final at = legEnd[i - 1];
      final node = rev == 0 ? g.pieceA[p] : g.pieceB[p];
      final dist = cum[at];
      final name = g.nameOf(p), prevName = g.nameOf(prevP);
      // Roundabout: one instruction at the entry with the exit number.
      if (g.pieceFlags[p] & flagRoundabout != 0 && g.pieceFlags[prevP] & flagRoundabout == 0) {
        var exits = 0, j = i;
        while (j < legs.length && g.pieceFlags[legs[j].$1] & flagRoundabout != 0) {
          final (q, qr) = legs[j];
          final end = qr == 0 ? g.pieceB[q] : g.pieceA[q];
          if (_exitsRoundabout(end)) exits++;
          j++;
        }
        out.add(Maneuver(Turn.roundabout, dist, j < legs.length ? g.nameOf(legs[j].$1) : '', exit: max(1, exits)));
        i = j + 1;
        continue;
      }
      final turn = _turnAt(pts, at);
      final junction = g.degree(node) >= 3;
      final enteringFlyover = g.pieceFlags[p] & flagBridge != 0 && g.pieceFlags[prevP] & flagBridge == 0 && _bridgeRun(legs, i) >= 150 &&
          g.pieceClass[p] <= classTertiary;
      if (turn == Turn.uTurn || (junction && (turn != Turn.straight || name != prevName) && !(name == prevName && _slight(turn)))) {
        out.add(Maneuver(turn, dist, name));
      } else if (enteringFlyover) {
        out.add(Maneuver(Turn.flyover, dist, name));
      }
      i++;
    }
    out.add(Maneuver(Turn.arrive, cum.last, ''));
    return _merge(out);
  }

  /// Whether a car can leave the roundabout at tower [n] (entries from side roads don't count as exits).
  bool _exitsRoundabout(int n) {
    for (var e = g.edgeStart[n]; e < g.edgeStart[n + 1]; e++) {
      if (g.pieceFlags[g.edgePiece[e]] & flagRoundabout == 0) return true;
    }
    return false;
  }

  /// Instructions closer than 30 m (a jog across a divided road, a tiny link) become one: the real turn,
  /// onto the last road.
  static List<Maneuver> _merge(List<Maneuver> ms) {
    final out = <Maneuver>[];
    for (final m in ms) {
      final prev = out.isEmpty ? null : out.last;
      // "Continue onto X Flyover" followed by "Take the flyover on X Flyover": say it once, at the first.
      if (m.turn == Turn.flyover && prev != null && prev.street == m.street && m.at - prev.at < 200 && _slight(prev.turn)) {
        out[out.length - 1] = Maneuver(Turn.flyover, prev.at, m.street);
        continue;
      }
      if (m.turn == Turn.straight && m.street.isEmpty) continue;
      if (prev == null || m.at - prev.at >= 30 || const {Turn.depart, Turn.arrive}.contains(prev.turn) || m.turn == Turn.arrive) {
        out.add(m);
        continue;
      }
      final keep = prev.turn == Turn.roundabout || (!_slight(prev.turn) && prev.turn != Turn.flyover) ? prev : m;
      out[out.length - 1] = Maneuver(keep.turn, prev.at, m.street.isNotEmpty ? m.street : prev.street, exit: keep.exit);
    }
    return out;
  }

  static bool _slight(Turn t) => t == Turn.straight || t == Turn.slightLeft || t == Turn.slightRight;

  double _bridgeRun(List<(int, int)> legs, int i) {
    var m = 0.0;
    for (var j = i; j < legs.length && g.pieceFlags[legs[j].$1] & flagBridge != 0; j++) {
      m += g.pieceLen[legs[j].$1];
    }
    return m;
  }

  /// Turn at point [at] of the route line, from the bearing ~20 m before to ~20 m after.
  static Turn _turnAt(List<(double, double)> pts, int at) {
    if (at <= 0 || at >= pts.length - 1) return Turn.straight;
    var a = at - 1, b = at + 1;
    while (a > 0 && metres(pts[a].$1, pts[a].$2, pts[at].$1, pts[at].$2) < 20) {
      a--;
    }
    while (b < pts.length - 1 && metres(pts[at].$1, pts[at].$2, pts[b].$1, pts[b].$2) < 20) {
      b++;
    }
    final inB = bearing(pts[a].$1, pts[a].$2, pts[at].$1, pts[at].$2), outB = bearing(pts[at].$1, pts[at].$2, pts[b].$1, pts[b].$2);
    final d = (outB - inB + 540) % 360 - 180; // + right, − left
    final ad = d.abs();
    if (ad < 25) return Turn.straight;
    if (ad > 165) return Turn.uTurn;
    if (ad < 50) return d > 0 ? Turn.slightRight : Turn.slightLeft;
    if (ad < 130) return d > 0 ? Turn.right : Turn.left;
    return d > 0 ? Turn.sharpRight : Turn.sharpLeft;
  }
}
