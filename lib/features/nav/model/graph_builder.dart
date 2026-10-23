import 'dart:typed_data';

import 'road_graph.dart';
import 'road_tile.dart';

/// Box to keep: (south, west, north, east) in degrees.
typedef GeoBox = (double, double, double, double);

/// Road networks with fewer junctions than this are islands (not routed).
const minIsland = 100;

/// Joins downloaded tiles into a routable [RoadGraph], keeping roads inside [box] plus [margin] degrees.
///
/// Turn restrictions become restriction copies: for "from road F, at junction V, you may not turn onto road T",
/// traffic arriving on F goes to a copy of V whose exits leave out T (or, for "only" rules, keep only T).
/// Plain shortest-path search then never makes the banned turn, and the CCH needs no special cases.
RoadGraph buildGraph(List<RoadTile> tiles, GeoBox box, {double margin = 0.02, int minIsland = minIsland, void Function(String)? stage}) {
  // ---- Join nodes from all tiles by OSM id (each tile's ids are sorted: k-way merge) ----
  stage?.call('Joining tiles');
  final total = tiles.fold<int>(0, (a, t) => a + t.nodeIds.length);
  final gLat = Int32List(total), gLon = Int32List(total);
  final local2g = [for (final t in tiles) Int32List(t.nodeIds.length)];
  final pos = List.filled(tiles.length, 0);
  var g = 0, lastId = -1;
  var started = false;
  while (true) {
    var best = -1;
    for (var i = 0; i < tiles.length; i++) {
      if (pos[i] < tiles[i].nodeIds.length && (best < 0 || tiles[i].nodeIds[pos[i]] < tiles[best].nodeIds[pos[best]])) best = i;
    }
    if (best < 0) break;
    final t = tiles[best], p = pos[best]++;
    if (!started || t.nodeIds[p] != lastId) {
      started = true;
      lastId = t.nodeIds[p];
      gLat[g] = t.lat[p];
      gLon[g] = t.lon[p];
      g++;
    }
    local2g[best][p] = g - 1;
  }
  final nG = g;
  final s7 = ((box.$1 - margin) * 1e7).round(), w7 = ((box.$2 - margin) * 1e7).round();
  final n7 = ((box.$3 + margin) * 1e7).round(), e7 = ((box.$4 + margin) * 1e7).round();
  bool inside(int x) => gLat[x] >= s7 && gLat[x] <= n7 && gLon[x] >= w7 && gLon[x] <= e7;

  // ---- Ways (each once), refs as joined node indexes, -1 where missing or outside the box ----
  final seenWays = <int>{};
  final wayId = <int>[], wayKind = <int>[], waySpeed = <int>[], wayFlags = <int>[], wayDir = <int>[], wayName = <int>[];
  final wayRefStart = <int>[0], wayRefs = <int>[];
  final names = <String>[], nameIdx = <String, int>{};
  final restrictions = <(int, int, int, bool)>{};
  for (var ti = 0; ti < tiles.length; ti++) {
    final t = tiles[ti];
    for (var j = 0; j < t.wayIds.length; j++) {
      if (!seenWays.add(t.wayIds[j])) continue;
      for (var i = t.refStart[j]; i < t.refStart[j + 1]; i++) {
        final r = t.refs[i];
        final x = r < 0 ? -1 : local2g[ti][r];
        wayRefs.add(x >= 0 && inside(x) ? x : -1);
      }
      wayRefStart.add(wayRefs.length);
      wayId.add(t.wayIds[j]);
      wayKind.add(t.kind[j]);
      waySpeed.add(t.speed[j]);
      wayFlags.add(t.flags[j]);
      wayDir.add(t.dir[j]);
      final nm = t.name[j] < 0 ? '' : t.names[t.name[j]];
      wayName.add(nm.isEmpty ? -1 : nameIdx.putIfAbsent(nm, () => (names..add(nm)).length - 1));
    }
    for (var r = 0; r < t.restrOnly.length; r++) {
      final via = local2g[ti][t.restrVia[r]];
      if (inside(via)) restrictions.add((t.wayIds[t.restrFrom[r]], via, t.wayIds[t.restrTo[r]], t.restrOnly[r] == 1));
    }
  }

  // ---- Towers: way ends, nodes shared by 2+ ways (or twice by one), restriction junctions ----
  stage?.call('Finding junctions');
  final occ = Uint8List(nG), tower = Uint8List(nG);
  for (var w = 0; w < wayId.length; w++) {
    final a = wayRefStart[w], b = wayRefStart[w + 1];
    for (var i = a; i < b; i++) {
      final x = wayRefs[i];
      if (x < 0) continue;
      if (occ[x] < 2) occ[x]++;
      if (i == a || wayRefs[i - 1] < 0 || i == b - 1 || wayRefs[i + 1] < 0) tower[x] = 1;
    }
  }
  for (final r in restrictions) {
    if (occ[r.$2] > 0) tower[r.$2] = 1;
  }
  final towerOf = Int32List(nG)..fillRange(0, nG, -1), pillarOf = Int32List(nG)..fillRange(0, nG, -1);
  final tLat = <int>[], tLon = <int>[], pLat = <int>[], pLon = <int>[];
  for (var x = 0; x < nG; x++) {
    if (occ[x] == 0) continue;
    if (tower[x] == 1 || occ[x] >= 2) {
      towerOf[x] = tLat.length;
      tLat.add(gLat[x]);
      tLon.add(gLon[x]);
    } else {
      pillarOf[x] = pLat.length;
      pLat.add(gLat[x]);
      pLon.add(gLon[x]);
    }
  }
  final baseNodes = tLat.length;

  // ---- Pieces: road between consecutive towers along a way ----
  stage?.call('Building roads');
  final pA = <int>[], pB = <int>[], pGeo = <int>[0], geo = <int>[], pWay = <int>[];
  final pLen = <double>[];
  for (var w = 0; w < wayId.length; w++) {
    var t0 = -1, prev = -1;
    var len = 0.0;
    final pillars = <int>[];
    for (var i = wayRefStart[w]; i < wayRefStart[w + 1]; i++) {
      final x = wayRefs[i];
      if (x < 0) {
        t0 = -1;
        continue;
      }
      if (t0 >= 0) len += metres(gLat[prev] / 1e7, gLon[prev] / 1e7, gLat[x] / 1e7, gLon[x] / 1e7);
      prev = x;
      if (towerOf[x] < 0) {
        pillars.add(pillarOf[x]);
        continue;
      }
      final t1 = towerOf[x];
      if (t0 >= 0 && !(t0 == t1 && pillars.isEmpty)) {
        pA.add(t0);
        pB.add(t1);
        geo.addAll(pillars);
        pGeo.add(geo.length);
        pLen.add(len);
        pWay.add(w);
      }
      t0 = t1;
      len = 0;
      pillars.clear();
    }
  }
  final nP = pA.length;

  // ---- Road islands: pieces cut off from the network (e.g. a car park whose driveways aren't mapped as roads)
  // are drawn but never routed or snapped to, or a start there would find no way out. ----
  final root = Int32List(baseNodes);
  for (var i = 0; i < baseNodes; i++) {
    root[i] = i;
  }
  int find(int x) {
    while (root[x] != x) {
      root[x] = root[root[x]];
      x = root[x];
    }
    return x;
  }

  for (var p = 0; p < nP; p++) {
    final a = find(pA[p]), b = find(pB[p]);
    if (a != b) root[a] = b;
  }
  final compSize = Int32List(baseNodes);
  for (var i = 0; i < baseNodes; i++) {
    compSize[find(i)]++;
  }
  final routable = Uint8List(nP);
  for (var p = 0; p < nP; p++) {
    if (compSize[find(pA[p])] >= minIsland) routable[p] = 1;
  }

  // ---- Directed edges ----
  final eFrom = <int>[], eTo = <int>[], ePiece = <int>[], eRev = <int>[];
  for (var p = 0; p < nP; p++) {
    if (pA[p] == pB[p] || routable[p] == 0) continue;
    final d = wayDir[pWay[p]];
    if (d >= 0) {
      eFrom.add(pA[p]);
      eTo.add(pB[p]);
      ePiece.add(p);
      eRev.add(0);
    }
    if (d <= 0) {
      eFrom.add(pB[p]);
      eTo.add(pA[p]);
      ePiece.add(p);
      eRev.add(1);
    }
  }

  // ---- Turn restrictions → restriction copies ----
  stage?.call('Applying turn rules');
  final copyOf = <int>[];
  if (restrictions.isNotEmpty) {
    final wanted = {for (final r in restrictions) ...[r.$1, r.$3]};
    final recOf = <int, int>{};
    for (var w = 0; w < wayId.length; w++) {
      if (wanted.contains(wayId[w])) recOf[wayId[w]] = w;
    }
    // via tower → from way → (banned to-ways, only-allowed to-ways)
    final rules = <int, Map<int, (Set<int>, Set<int>)>>{};
    for (final (from, via, to, only) in restrictions) {
      final v = towerOf[via], f = recOf[from], tw = recOf[to];
      if (v < 0 || f == null || tw == null) continue;
      final r = (rules[v] ??= {})[f] ??= (<int>{}, <int>{});
      (only ? r.$2 : r.$1).add(tw);
    }
    final outOf = <int, List<int>>{};
    for (var e = 0; e < eFrom.length; e++) {
      if (rules.containsKey(eFrom[e])) (outOf[eFrom[e]] ??= []).add(e);
    }
    final copyFor = <(int, int), int>{};
    for (final MapEntry(key: v, value: byFrom) in rules.entries) {
      for (final MapEntry(key: f, value: (no, only)) in byFrom.entries) {
        final c = baseNodes + copyOf.length;
        copyOf.add(v);
        tLat.add(tLat[v]);
        tLon.add(tLon[v]);
        for (final e in outOf[v] ?? const <int>[]) {
          final tw = pWay[ePiece[e]];
          if (only.isNotEmpty ? !only.contains(tw) : no.contains(tw)) continue;
          eFrom.add(c);
          eTo.add(eTo[e]);
          ePiece.add(ePiece[e]);
          eRev.add(eRev[e]);
        }
        copyFor[(v, f)] = c;
      }
    }
    // Arrivals on a restricted "from" road now end at its copy (also those leaving other copies).
    for (var e = 0; e < eTo.length; e++) {
      final c = copyFor[(eTo[e], pWay[ePiece[e]])];
      if (c != null) eTo[e] = c;
    }
  }
  final nR = tLat.length;

  // ---- Edges grouped by source (CSR) ----
  final m = eFrom.length;
  final start = Int32List(nR + 1);
  for (final u in eFrom) {
    start[u + 1]++;
  }
  for (var i = 0; i < nR; i++) {
    start[i + 1] += start[i];
  }
  final fill = Int32List.fromList(start.sublist(0, nR));
  final to = Int32List(m), piece = Int32List(m), rev = Uint8List(m);
  for (var e = 0; e < m; e++) {
    final at = fill[eFrom[e]]++;
    to[at] = eTo[e];
    piece[at] = ePiece[e];
    rev[at] = eRev[e];
  }

  // ---- Piece attributes, names, spatial grid ----
  stage?.call('Indexing streets');
  final pName = Int32List(nP), pClass = Uint8List(nP), pSpeed = Uint8List(nP), pFlags = Uint8List(nP), pDir = Uint8List(nP);
  final namePiece = Int32List(names.length)..fillRange(0, names.length, -1);
  final cells = <int, List<int>>{};
  for (var p = 0; p < nP; p++) {
    final w = pWay[p];
    pName[p] = wayName[w];
    pClass[p] = wayKind[w];
    pSpeed[p] = waySpeed[w].clamp(1, 255);
    pFlags[p] = wayFlags[w];
    pDir[p] = routable[p] == 0 ? 0 : wayDir[w] > 0 ? dirForward : wayDir[w] < 0 ? dirBackward : dirForward | dirBackward;
    if (wayName[w] >= 0 && namePiece[wayName[w]] < 0) namePiece[wayName[w]] = p;
    var s = tLat[pA[p]], n = s, west = tLon[pA[p]], e = west;
    void grow(int la, int lo) {
      if (la < s) s = la;
      if (la > n) n = la;
      if (lo < west) west = lo;
      if (lo > e) e = lo;
    }

    grow(tLat[pB[p]], tLon[pB[p]]);
    for (var i = pGeo[p]; i < pGeo[p + 1]; i++) {
      grow(pLat[geo[i]], pLon[geo[i]]);
    }
    for (var y = RoadGraph.cellY(s / 1e7); y <= RoadGraph.cellY(n / 1e7); y++) {
      for (var x = RoadGraph.cellX(west / 1e7); x <= RoadGraph.cellX(e / 1e7); x++) {
        (cells[RoadGraph.cellKey(y, x)] ??= []).add(p);
      }
    }
  }
  final keys = cells.keys.toList()..sort();
  final cellStart = Int32List(keys.length + 1);
  final cellPieces = Int32List(cells.values.fold(0, (a, l) => a + l.length));
  var at = 0;
  for (var i = 0; i < keys.length; i++) {
    for (final p in cells[keys[i]]!) {
      cellPieces[at++] = p;
    }
    cellStart[i + 1] = at;
  }

  return RoadGraph(
    lat: Int32List.fromList(tLat), lon: Int32List.fromList(tLon), copyOf: Int32List.fromList(copyOf), baseNodes: baseNodes,
    pLat: Int32List.fromList(pLat), pLon: Int32List.fromList(pLon),
    pieceA: Int32List.fromList(pA), pieceB: Int32List.fromList(pB), pieceGeo: Int32List.fromList(pGeo), geo: Int32List.fromList(geo),
    pieceName: pName, pieceLen: Float32List.fromList(pLen), pieceClass: pClass, pieceSpeed: pSpeed, pieceFlags: pFlags, pieceDir: pDir,
    edgeStart: start, edgeTo: to, edgePiece: piece, edgeRev: rev,
    names: names, namePiece: namePiece,
    cellKeys: Int64List.fromList(keys), cellStart: cellStart, cellPieces: cellPieces,
  );
}
