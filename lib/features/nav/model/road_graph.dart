import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'bin_io.dart';

/// Road flags and classes (same values as buddy-maps' roads.dart).
const flagBridge = 1, flagTunnel = 2, flagRoundabout = 4;
const classMotorway = 0, classTrunk = 1, classPrimary = 2, classSecondary = 3, classTertiary = 4, classMinor = 5, classService = 6;

/// Directions a piece can be driven: A→B, B→A.
const dirForward = 1, dirBackward = 2;

/// Grid cell size for the spatial index (≈1.1 km).
const _cell = 0.01;

/// Where a point sits on the road network.
class Snap {
  final int piece, seg;

  /// Fraction along segment [seg] of the piece's line (A → B).
  final double t;
  final double lat, lon;

  /// Metres from the asked point to the road, and from the piece's A end to the snapped point.
  final double dist, fromA;
  const Snap(this.piece, this.seg, this.t, this.lat, this.lon, this.dist, this.fromA);
}

/// A downloaded road network.
///
/// Routing runs on junctions only ("towers"): every place where roads meet or end, plus copies of junctions that
/// have turn restrictions. The shape points between them ("pillars") are only for drawing and snapping.
/// A "piece" is one stretch of road between two towers; directed edges drive along pieces.
/// Coordinates are degrees ×1e7.
class RoadGraph {
  // Routing nodes: towers [0, baseNodes), then restriction copies (copyOf[i - baseNodes] is the original tower).
  final Int32List lat, lon, copyOf;
  final int baseNodes;
  final Int32List pLat, pLon;
  final Int32List pieceA, pieceB, pieceGeo, geo, pieceName;
  final Float32List pieceLen;
  final Uint8List pieceClass, pieceSpeed, pieceFlags, pieceDir;
  final Int32List edgeStart, edgeTo, edgePiece;
  final Uint8List edgeRev;
  final List<String> names;
  final Int32List namePiece;
  final Int64List cellKeys;
  final Int32List cellStart, cellPieces;

  RoadGraph({
    required this.lat,
    required this.lon,
    required this.copyOf,
    required this.baseNodes,
    required this.pLat,
    required this.pLon,
    required this.pieceA,
    required this.pieceB,
    required this.pieceGeo,
    required this.geo,
    required this.pieceName,
    required this.pieceLen,
    required this.pieceClass,
    required this.pieceSpeed,
    required this.pieceFlags,
    required this.pieceDir,
    required this.edgeStart,
    required this.edgeTo,
    required this.edgePiece,
    required this.edgeRev,
    required this.names,
    required this.namePiece,
    required this.cellKeys,
    required this.cellStart,
    required this.cellPieces,
  });

  int get nodeCount => lat.length;
  int get edgeCount => edgeTo.length;
  int get pieceCount => pieceA.length;
  double latOf(int n) => lat[n] / 1e7;
  double lonOf(int n) => lon[n] / 1e7;

  /// The tower a routing node stands for (itself, or the junction a restriction copy was made from).
  int original(int n) => n < baseNodes ? n : copyOf[n - baseNodes];

  /// Cost of driving edge [e]: metres, or seconds when [fastest].
  double edgeCost(int e, bool fastest) {
    final p = edgePiece[e];
    return fastest ? pieceLen[p] * 3.6 / pieceSpeed[p] : pieceLen[p];
  }

  /// Points of piece [p] from A to B (or B to A when [reverse]).
  List<(double, double)> piecePoints(int p, {bool reverse = false}) {
    final pts = <(double, double)>[(latOf(pieceA[p]), lonOf(pieceA[p]))];
    for (var i = pieceGeo[p]; i < pieceGeo[p + 1]; i++) {
      pts.add((pLat[geo[i]] / 1e7, pLon[geo[i]] / 1e7));
    }
    pts.add((latOf(pieceB[p]), lonOf(pieceB[p])));
    return reverse ? pts.reversed.toList() : pts;
  }

  /// Number of road pieces meeting at tower [n] (3+ means a real junction).
  late final Uint8List _degree = () {
    final d = Uint8List(baseNodes);
    for (var p = 0; p < pieceCount; p++) {
      if (d[pieceA[p]] < 255) d[pieceA[p]]++;
      if (d[pieceB[p]] < 255) d[pieceB[p]]++;
    }
    return d;
  }();
  int degree(int n) => _degree[original(n)];

  // ---------- Spatial index ----------

  static int cellKey(int y, int x) => (y + 10000) * 100000 + (x + 20000);
  static int cellY(double la) => (la / _cell).floor();
  static int cellX(double lo) => (lo / _cell).floor();

  /// Pieces whose box touches cell (y, x).
  Iterable<int> piecesInCell(int y, int x) sync* {
    final k = cellKey(y, x);
    var lo = 0, hi = cellKeys.length;
    while (lo < hi) {
      final m = (lo + hi) >> 1;
      cellKeys[m] < k ? lo = m + 1 : hi = m;
    }
    if (lo == cellKeys.length || cellKeys[lo] != k) return;
    for (var i = cellStart[lo]; i < cellStart[lo + 1]; i++) {
      yield cellPieces[i];
    }
  }

  /// Closest point on any road to (la, lo) within [maxM] metres. With a GPS [heading] (degrees), roads you
  /// could be driving along in that direction win over a parallel road just as close.
  Snap? snap(double la, double lo, {double? heading, double maxM = 3000}) {
    final kx = cos(la * pi / 180) * 111320.0;
    const ky = 110540.0;
    final ringM = _cell * min(kx, ky);
    final cy = cellY(la), cx = cellX(lo);
    Snap? best;
    var bestScore = double.infinity;
    final seen = <int>{};
    final maxR = (maxM / ringM).ceil() + 1;
    for (var r = 0; r <= maxR; r++) {
      // Every road nearer than this ring has been looked at.
      if (best != null && (r - 1) * ringM > bestScore) break;
      for (var y = cy - r; y <= cy + r; y++) {
        for (var x = cx - r; x <= cx + r; x++) {
          if (max((y - cy).abs(), (x - cx).abs()) != r) continue;
          for (final p in piecesInCell(y, x)) {
            // Islands (not routable) are never snapped to.
            if (pieceDir[p] == 0 || !seen.add(p)) continue;
            final pts = piecePoints(p);
            var along = 0.0;
            for (var s = 0; s + 1 < pts.length; s++) {
              final ax = pts[s].$2 * kx, ay = pts[s].$1 * ky, bx = pts[s + 1].$2 * kx, by = pts[s + 1].$1 * ky;
              final dx = bx - ax, dy = by - ay;
              final len2 = dx * dx + dy * dy, segLen = sqrt(len2);
              final t = len2 == 0 ? 0.0 : (((lo * kx - ax) * dx + (la * ky - ay) * dy) / len2).clamp(0.0, 1.0);
              final ex = ax + dx * t - lo * kx, ey = ay + dy * t - la * ky;
              final d = sqrt(ex * ex + ey * ey);
              var score = d;
              if (heading != null && segLen > 0) {
                final brg = atan2(dx, dy) * 180 / pi;
                var turn = 180.0;
                if (pieceDir[p] & dirForward != 0) turn = min(turn, _angle(brg, heading));
                if (pieceDir[p] & dirBackward != 0) turn = min(turn, _angle(brg + 180, heading));
                score += 25 * (1 - cos(turn * pi / 180));
              }
              if (score < bestScore && d <= maxM) {
                bestScore = score;
                best = Snap(p, s, t, (ay + dy * t) / ky, (ax + dx * t) / kx, d, along + segLen * t);
              }
              along += segLen;
            }
          }
        }
      }
    }
    if (best == null) return null;
    // Flat-earth length → share of the piece's true length.
    final flat = _flatLen(best.piece, kx, ky);
    final fromA = flat == 0 ? 0.0 : best.fromA / flat * pieceLen[best.piece];
    return Snap(best.piece, best.seg, best.t, best.lat, best.lon, best.dist, fromA);
  }

  double _flatLen(int p, double kx, double ky) {
    final pts = piecePoints(p);
    var s = 0.0;
    for (var i = 0; i + 1 < pts.length; i++) {
      final dx = (pts[i + 1].$2 - pts[i].$2) * kx, dy = (pts[i + 1].$1 - pts[i].$1) * ky;
      s += sqrt(dx * dx + dy * dy);
    }
    return s;
  }

  static double _angle(double a, double b) {
    final d = ((a - b) % 360 + 360) % 360;
    return d > 180 ? 360 - d : d;
  }

  /// Street names containing [q] (case-insensitive), prefix matches first: (name, lat, lon).
  List<(String, double, double)> searchStreets(String q, {int limit = 8}) {
    final lq = q.trim().toLowerCase();
    if (lq.length < 2) return const [];
    final hits = <(String, int, bool)>[];
    for (var i = 0; i < names.length && hits.length < 200; i++) {
      final at = names[i].toLowerCase().indexOf(lq);
      if (at >= 0) hits.add((names[i], namePiece[i], at == 0));
    }
    hits.sort((a, b) => a.$3 == b.$3 ? a.$1.length.compareTo(b.$1.length) : (a.$3 ? -1 : 1));
    return [
      for (final h in hits.take(limit))
        (h.$1, (latOf(pieceA[h.$2]) + latOf(pieceB[h.$2])) / 2, (lonOf(pieceA[h.$2]) + lonOf(pieceB[h.$2])) / 2),
    ];
  }

  String nameOf(int piece) => pieceName[piece] < 0 ? '' : names[pieceName[piece]];

  // ---------- File format ----------
  static const _magic = 0x42524732; // "BRG2"

  void write(BinWriter w) {
    w.ints([_magic, baseNodes]);
    for (final a in <TypedData>[lat, lon, copyOf, pLat, pLon, pieceA, pieceB, pieceGeo, geo, pieceName, pieceLen, pieceClass,
      pieceSpeed, pieceFlags, pieceDir, edgeStart, edgeTo, edgePiece, edgeRev, namePiece, cellKeys, cellStart, cellPieces]) {
      w.array(a);
    }
    w.array(utf8.encode(names.join('\n')));
  }

  static RoadGraph read(BinReader r) {
    final h = r.ints(2);
    if (h[0] != _magic) throw const FormatException('Old or damaged map file. Download it again.');
    final la = r.i32(), lo = r.i32(), co = r.i32(), pla = r.i32(), plo = r.i32();
    final pa = r.i32(), pb = r.i32(), pg = r.i32(), g = r.i32(), pn = r.i32(), pl = r.f32();
    final pc = r.u8(), ps = r.u8(), pf = r.u8(), pd = r.u8();
    final es = r.i32(), et = r.i32(), ep = r.i32(), er = r.u8(), np = r.i32();
    final ck = r.i64(), cs = r.i32(), cp = r.i32();
    final text = utf8.decode(r.u8());
    return RoadGraph(
      lat: la, lon: lo, copyOf: co, baseNodes: h[1], pLat: pla, pLon: plo,
      pieceA: pa, pieceB: pb, pieceGeo: pg, geo: g, pieceName: pn, pieceLen: pl,
      pieceClass: pc, pieceSpeed: ps, pieceFlags: pf, pieceDir: pd,
      edgeStart: es, edgeTo: et, edgePiece: ep, edgeRev: er,
      names: text.isEmpty ? [] : text.split('\n'), namePiece: np,
      cellKeys: ck, cellStart: cs, cellPieces: cp,
    );
  }
}

/// Great-circle distance in metres.
double metres(double a1, double o1, double a2, double o2) {
  const r = 6371008.8, d = pi / 180;
  final s1 = sin((a2 - a1) * d / 2), s2 = sin((o2 - o1) * d / 2);
  final h = s1 * s1 + cos(a1 * d) * cos(a2 * d) * s2 * s2;
  return 2 * r * asin(sqrt(min(1.0, h)));
}

/// Compass bearing from point 1 to point 2, degrees 0..360.
double bearing(double a1, double o1, double a2, double o2) {
  const d = pi / 180;
  final y = sin((o2 - o1) * d) * cos(a2 * d);
  final x = cos(a1 * d) * sin(a2 * d) - sin(a1 * d) * cos(a2 * d) * cos((o2 - o1) * d);
  return (atan2(y, x) / d + 360) % 360;
}
