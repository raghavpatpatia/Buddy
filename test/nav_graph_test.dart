import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:buddy_app/features/nav/model/bin_io.dart';
import 'package:buddy_app/features/nav/model/cch.dart';
import 'package:buddy_app/features/nav/model/graph_builder.dart';
import 'package:buddy_app/features/nav/model/road_graph.dart';
import 'package:buddy_app/features/nav/model/road_tile.dart';
import 'package:buddy_app/features/nav/model/router.dart';
import 'package:flutter_test/flutter_test.dart';

typedef W = ({int id, List<int> nodes, String hw, int dir, int flags, String name, int speed});

W way(int id, List<int> nodes, {String hw = 'residential', int dir = 0, int flags = 0, String name = '', int? speed}) =>
    (id: id, nodes: nodes, hw: hw, dir: dir, flags: flags, name: name, speed: speed ?? (hw == 'primary' ? 60 : hw == 'secondary' ? 50 : 25));

const _kind = {'motorway': 0, 'trunk': 1, 'primary': 2, 'secondary': 3, 'tertiary': 4, 'residential': 5, 'service': 6};

/// Encodes a tile exactly like buddy-maps' TileData.toBytes, then decodes it with the app's reader.
RoadTile tile(Map<int, (double, double)> nodes, List<W> ways, {List<(int, int, int, bool)> restr = const []}) {
  final ids = nodes.keys.toList()..sort();
  final idx = {for (var i = 0; i < ids.length; i++) ids[i]: i};
  final sorted = List.of(ways)..sort((a, b) => a.id.compareTo(b.id));
  final wIdx = {for (var i = 0; i < sorted.length; i++) sorted[i].id: i};
  final names = <String>[];
  final refStart = <int>[0], refs = <int>[];
  for (final w in sorted) {
    refs.addAll(w.nodes.map((n) => idx[n] ?? -1));
    refStart.add(refs.length);
  }
  final nameIdx = <int>[];
  for (final w in sorted) {
    if (w.name.isEmpty) {
      nameIdx.add(-1);
    } else {
      if (!names.contains(w.name)) names.add(w.name);
      nameIdx.add(names.indexOf(w.name));
    }
  }
  final nb = utf8.encode(names.join('\n'));
  final parts = <TypedData>[
    Int32List.fromList([0x42525431, 1, ids.length, sorted.length, refs.length, restr.length, names.length, nb.length]),
    Int64List.fromList(ids),
    Int32List.fromList([for (final i in ids) (nodes[i]!.$1 * 1e7).round()]),
    Int32List.fromList([for (final i in ids) (nodes[i]!.$2 * 1e7).round()]),
    Int64List.fromList([for (final w in sorted) w.id]),
    Int32List.fromList(refStart),
    Int32List.fromList(refs),
    Uint8List.fromList([for (final w in sorted) _kind[w.hw]!]),
    Uint8List.fromList([for (final w in sorted) w.speed]),
    Uint8List.fromList([for (final w in sorted) w.flags]),
    Int8List.fromList([for (final w in sorted) w.dir]),
    Int32List.fromList(nameIdx),
    Int32List.fromList([for (final r in restr) wIdx[r.$1]!]),
    Int32List.fromList([for (final r in restr) idx[r.$2]!]),
    Int32List.fromList([for (final r in restr) wIdx[r.$3]!]),
    Uint8List.fromList([for (final r in restr) r.$4 ? 1 : 0]),
    nb,
  ];
  final out = BytesBuilder();
  for (final p in parts) {
    out.add(p.buffer.asUint8List(p.offsetInBytes, p.lengthInBytes));
    final pad = (4 - p.lengthInBytes % 4) % 4;
    if (pad > 0) out.add(Uint8List(pad));
  }
  return RoadTile.decode(out.takeBytes());
}

const _box = (28.0, 77.0, 29.0, 78.0);

/// Square grid of junctions spaced ~110 m, with random road types and one-ways; every street has 1 shape point.
(Map<int, (double, double)>, List<W>) grid(int size, int seed) {
  final rnd = Random(seed);
  final nodes = <int, (double, double)>{};
  int id(int y, int x) => 1 + y * size + x;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      nodes[id(y, x)] = (28.5 + y * 0.001 + rnd.nextDouble() * 0.0002, 77.2 + x * 0.001);
    }
  }
  final ways = <W>[];
  var wid = 0, pillar = 100000;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      for (final (dy, dx) in [(0, 1), (1, 0)]) {
        if (y + dy >= size || x + dx >= size || rnd.nextDouble() < 0.1) continue;
        final a = id(y, x), b = id(y + dy, x + dx);
        final mid = pillar++;
        nodes[mid] = ((nodes[a]!.$1 + nodes[b]!.$1) / 2 + 0.0001, (nodes[a]!.$2 + nodes[b]!.$2) / 2);
        final r = rnd.nextDouble();
        ways.add(way(++wid, [a, mid, b],
            hw: ['residential', 'primary', 'secondary'][rnd.nextInt(3)], dir: r < 0.15 ? 1 : r < 0.25 ? -1 : 0, name: 'Street $wid'));
      }
    }
  }
  return (nodes, ways);
}

/// Plain Dijkstra over routing nodes, the reference answer.
List<double> dijkstra(RoadGraph g, int s, bool fastest) {
  final d = List.filled(g.nodeCount, double.infinity)..[s] = 0;
  final done = List.filled(g.nodeCount, false);
  while (true) {
    var u = -1;
    for (var i = 0; i < g.nodeCount; i++) {
      if (!done[i] && d[i] < double.infinity && (u < 0 || d[i] < d[u])) u = i;
    }
    if (u < 0) return d;
    done[u] = true;
    for (var e = g.edgeStart[u]; e < g.edgeStart[u + 1]; e++) {
      final c = d[u] + g.edgeCost(e, fastest);
      if (c < d[g.edgeTo[e]]) d[g.edgeTo[e]] = c;
    }
  }
}

int nodeAt(RoadGraph g, double la, double lo) {
  var best = 0;
  for (var i = 1; i < g.baseNodes; i++) {
    if ((g.latOf(i) - la).abs() + (g.lonOf(i) - lo).abs() < (g.latOf(best) - la).abs() + (g.lonOf(best) - lo).abs()) best = i;
  }
  return best;
}

void main() {
  test('CCH matches Dijkstra on random grids, both metrics, with valid unpacked paths', () {
    for (final seed in [1, 2, 3]) {
      final (nodes, ways) = grid(14, seed);
      final g = buildGraph(minIsland: 1, [tile(nodes, ways)], _box);
      final c = Cch.build(g);
      expect(g.baseNodes, lessThan(nodes.length), reason: 'shape points are not routing nodes');
      for (final fastest in [false, true]) {
        for (var s = 0; s < g.nodeCount; s += 17) {
          final want = dijkstra(g, s, fastest);
          for (var t = 0; t < g.nodeCount; t += 5) {
            final p = c.query([(s, 0)], [(t, 0)], c.metric(fastest));
            if (want[t].isInfinite) {
              expect(p, isNull, reason: 'seed $seed $s→$t');
              continue;
            }
            expect(p!.cost, closeTo(want[t], want[t] * 1e-5 + 1e-3), reason: 'seed $seed $s→$t fastest=$fastest');
            // The unpacked edges must be a connected chain from s to t that costs exactly that.
            var at = s, sum = 0.0;
            for (final e in p.edges) {
              expect(e, inInclusiveRange(g.edgeStart[at], g.edgeStart[at + 1] - 1));
              sum += g.edgeCost(e, fastest);
              at = g.edgeTo[e];
            }
            expect(at, t);
            expect(sum, closeTo(want[t], want[t] * 1e-5 + 1e-3));
          }
        }
      }
    }
  });

  test('tiles join by OSM id across a tile border', () {
    final nodes = {1: (28.5, 77.99), 2: (28.5, 78.0), 3: (28.5, 78.01), 4: (28.501, 78.01)};
    final road = way(10, [1, 2, 3], name: 'Border Road');
    final west = tile({1: nodes[1]!, 2: nodes[2]!, 3: nodes[3]!}, [road]);
    final east = tile({1: nodes[1]!, 2: nodes[2]!, 3: nodes[3]!, 4: nodes[4]!}, [road, way(11, [3, 4], name: 'Side Lane')]);
    final g = buildGraph(minIsland: 1, [west, east], (28.0, 77.5, 29.0, 78.5));
    final r = Router(g, Cch.build(g));
    final plan = r.route(g.snap(28.5, 77.9905)!, g.snap(28.5008, 78.01)!)!;
    expect(plan.streets, ['Border Road', 'Side Lane']);
    expect(g.pieceCount, 2, reason: 'the shared road is kept once');
  });

  group('turn restrictions', () {
    //      4
    //      |
    // 1 —— 2 —→ 3      Main: 1-2-3, Cross: 4-2-5, detour round the south. Main East and Cross North are one-way
    //                  away from / into 2, so the router can't dodge a ban by turning around in a dead end.
    //      |
    // 6 —— 5
    // |    |
    // 7 ———+ (7-5)
    final nodes = {
      1: (28.500, 77.200), 2: (28.500, 77.201), 3: (28.500, 77.202), 4: (28.501, 77.201), 5: (28.499, 77.201),
      6: (28.499, 77.200), 7: (28.498, 77.200), 8: (28.498, 77.201),
    };
    final ways = [
      way(1, [1, 2], name: 'Main West'), way(2, [2, 3], dir: 1, name: 'Main East'), way(3, [4, 2], dir: 1, name: 'Cross North'),
      way(4, [2, 5], name: 'Cross South'), way(5, [1, 6, 7, 8, 5], name: 'Detour'),
    ];

    test('a banned right turn is avoided, other turns still work', () {
      final free = buildGraph(minIsland: 1, [tile(nodes, ways)], _box);
      final banned = buildGraph(minIsland: 1, [tile(nodes, ways, restr: [(1, 2, 4, false)])], _box);
      for (final (g, want) in [(free, ['Main West', 'Cross South']), (banned, ['Main West', 'Detour', 'Cross South'])]) {
        final r = Router(g, Cch.build(g));
        expect(r.route(g.snap(28.5, 77.2003)!, g.snap(28.4995, 77.201)!, fastest: false)!.streets, want);
      }
      final r = Router(banned, Cch.build(banned));
      // Going straight through the same junction is still allowed.
      expect(r.route(banned.snap(28.5, 77.2003)!, banned.snap(28.5, 77.2018)!, fastest: false)!.streets, ['Main West', 'Main East']);
    });

    test('an "only straight on" rule bans the turns', () {
      final g = buildGraph(minIsland: 1, [tile(nodes, ways, restr: [(1, 2, 2, true)])], _box);
      final r = Router(g, Cch.build(g));
      // From Main West only straight on is allowed, so Cross South is reached the long way, from the south.
      expect(r.route(g.snap(28.5, 77.2003)!, g.snap(28.4995, 77.201)!, fastest: false)!.streets, ['Main West', 'Detour', 'Cross South']);
      expect(r.route(g.snap(28.5, 77.2003)!, g.snap(28.5, 77.2018)!, fastest: false)!.streets, ['Main West', 'Main East']);
    });
  });

  test('shortest vs fastest, snapping mid-road and driving along one road', () {
    // Direct slow street 1-2 vs fast detour 1-3-2.
    final nodes = {1: (28.5, 77.2), 2: (28.5, 77.21), 3: (28.503, 77.205)};
    final g = buildGraph(minIsland: 1, [
      tile(nodes, [way(1, [1, 2], name: 'Slow Lane'), way(2, [1, 3, 2], hw: 'primary', name: 'Fast Road')])
    ], _box);
    final r = Router(g, Cch.build(g));
    final s = g.snap(28.5, 77.2)!, t = g.snap(28.5, 77.21)!;
    final short = r.route(s, t, fastest: false)!, fast = r.route(s, t)!;
    expect(short.streets, ['Slow Lane']);
    expect(fast.streets, ['Fast Road']);
    expect(fast.seconds, lessThan(short.seconds));
    expect(short.metres, closeTo(977, 5));
    // Both points on Slow Lane: a partial stretch of it.
    final part = r.route(g.snap(28.50001, 77.202)!, g.snap(28.49999, 77.206)!, fastest: false)!;
    expect(part.metres, closeTo(391, 5));
    expect(part.streets, ['Slow Lane']);
    final pr = part.progress(28.5, 77.204);
    expect(pr.metresLeft, closeTo(195, 5));
  });

  test('maneuvers: turns, roundabout exit and flyover', () {
    final nodes = {
      1: (28.500, 77.200), 2: (28.500, 77.202), 3: (28.502, 77.202), 4: (28.498, 77.202), 5: (28.500, 77.204),
      // roundabout ring around (28.503, 77.202)
      10: (28.5025, 77.202), 11: (28.503, 77.2025), 12: (28.5035, 77.202), 13: (28.503, 77.2015),
      20: (28.503, 77.204), 21: (28.505, 77.202), 22: (28.503, 77.200),
      30: (28.507, 77.202), 31: (28.509, 77.202),
    };
    final g = buildGraph(minIsland: 1, [
      tile(nodes, [
        way(1, [1, 2], name: 'A Road'), way(2, [2, 3, 10], name: 'B Road'), way(3, [2, 4], name: 'C Road'), way(4, [2, 5], name: 'D Road'),
        way(5, [10, 11, 12, 13, 10], dir: 1, flags: flagRoundabout, name: 'Circle'),
        way(6, [11, 20], name: 'East Exit'), way(7, [12, 21, 30], name: 'North Exit'), way(8, [13, 22], name: 'West Exit'),
        way(9, [30, 31], hw: 'primary', flags: flagBridge, name: 'Flyover Rd'),
      ]),
    ], _box);
    final r = Router(g, Cch.build(g));
    final p = r.route(g.snap(28.5, 77.2005)!, g.snap(28.5085, 77.202)!, fastest: false)!;
    final turns = [for (final m in p.maneuvers) m.text];
    expect(turns.first, 'Head out on A Road');
    expect(turns, contains('Turn left onto B Road'));
    // Counter-clockwise ring 10→11→12: exits at 11 (East) then 12 (North).
    expect(turns, contains('At the roundabout, take the 2nd exit onto North Exit'));
    expect(turns, contains('Take the flyover on Flyover Rd'));
    expect(turns.last, 'Arrive at your destination');
  });

  test('alternatives differ from the best route and are not much slower', () {
    final (nodes, ways) = grid(12, 7);
    final g = buildGraph(minIsland: 1, [tile(nodes, ways)], _box);
    final r = Router(g, Cch.build(g));
    final s = g.snap(28.5, 77.2)!, t = g.snap(28.511, 77.211)!;
    final best = r.route(s, t)!;
    final alts = r.alternatives(s, t, best);
    expect(alts, isNotEmpty);
    for (final a in alts) {
      expect(a.seconds, lessThanOrEqualTo(best.seconds * 1.35));
      expect(a.seconds, greaterThanOrEqualTo(best.seconds - 1e-6));
      expect(a.pieces.toSet().difference(best.pieces.toSet()), isNotEmpty);
    }
  });

  test('map file round trip keeps routing identical', () {
    final (nodes, ways) = grid(10, 4);
    final g = buildGraph(minIsland: 1, [tile(nodes, ways)], _box);
    final c = Cch.build(g);
    final w = BinWriter();
    g.write(w);
    c.write(w);
    final rd = BinReader(w.take());
    final g2 = RoadGraph.read(rd), c2 = Cch.read(rd, g2);
    expect(g2.names, g.names);
    for (final fastest in [false, true]) {
      final a = c.query([(0, 0)], [(g.nodeCount - 1, 0)], c.metric(fastest)), b = c2.query([(0, 0)], [(g.nodeCount - 1, 0)], c2.metric(fastest));
      expect(b?.cost, a?.cost);
      expect(b?.edges, a?.edges);
    }
    expect(g2.searchStreets('street 1').first.$1, startsWith('Street 1'));
  });

  test('road islands are drawn but never snapped to or routed', () {
    final (nodes, ways) = grid(12, 5);
    // A car park lane 30 m off the grid, connected to nothing.
    nodes[900001] = (28.5, 77.1997);
    nodes[900002] = (28.501, 77.1997);
    ways.add(way(99999, [900001, 900002], hw: 'service', name: 'Car Park'));
    final g = buildGraph([tile(nodes, ways)], _box);
    expect(g.names, contains('Car Park'), reason: 'still drawn');
    final s = g.snap(28.5005, 77.1997)!;
    expect(g.nameOf(s.piece), isNot('Car Park'));
    expect(Router(g, Cch.build(g)).route(s, g.snap(28.505, 77.205)!), isNotNull);
  });

  test('snap prefers the road matching the GPS heading', () {
    // Two parallel one-way roads 20 m apart: eastbound north, westbound south.
    final nodes = {1: (28.50010, 77.200), 2: (28.50010, 77.203), 3: (28.49990, 77.203), 4: (28.49990, 77.200)};
    final g = buildGraph(minIsland: 1, [tile(nodes, [way(1, [1, 2], dir: 1, name: 'East'), way(2, [3, 4], dir: 1, name: 'West')])], _box);
    expect(g.nameOf(g.snap(28.49999, 77.201, heading: 270)!.piece), 'West');
    expect(g.nameOf(g.snap(28.49999, 77.201, heading: 90)!.piece), 'East');
    expect(nodeAt(g, 28.5001, 77.2), isNonNegative);
  });
}
