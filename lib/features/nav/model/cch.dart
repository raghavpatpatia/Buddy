import 'dart:math';
import 'dart:typed_data';

import 'bin_io.dart';
import 'road_graph.dart';

/// Weights of every CCH arc for one way of costing roads (distance, time, or a penalised copy).
/// via ≥ 0: the original edge; via < 0: a shortcut through the arc's middle node rank (-via - 1).
class CchMetric {
  final Float32List upW, downW;
  final Int32List upVia, downVia;
  CchMetric(this.upW, this.downW, this.upVia, this.downVia);
}

/// Result of a CCH query: total cost and the original edges driven, in order.
class CchPath {
  final double cost;
  final List<int> edges;
  final int sourceIndex, targetIndex;
  const CchPath(this.cost, this.edges, this.sourceIndex, this.targetIndex);
}

/// Customizable Contraction Hierarchy (Dibbelt, Strasser, Wagner 2016) over a [RoadGraph]'s junctions.
///
/// 1. Order (weights not needed): pass-through and dead-end junctions first, the rest by nested dissection.
/// 2. Contract: eliminate nodes in that order, adding every shortcut needed (no witness search), so the result
///    works for any weights. Only this part is saved in the map file.
/// 3. Customize: fill in arc weights for a metric with one sweep over lower triangles (about a second for a city).
///    Done when a map opens, and again for alternatives (or, later, traffic).
/// 4. Query: walk up the elimination tree from both ends; no priority queue.
class Cch {
  final Int32List rank, upStart, upHead, arcTail;

  /// Elimination-tree parent of each rank (from the full, unpruned shortcuts), -1 for roots.
  final Int32List parent;
  late CchMetric distance, time;
  Cch(this.rank, this.upStart, this.upHead, this.parent) : arcTail = _tails(upStart, upHead.length);

  static Int32List _tails(Int32List upStart, int arcs) {
    final t = Int32List(arcs);
    for (var r = 0; r + 1 < upStart.length; r++) {
      t.fillRange(upStart[r], upStart[r + 1], r);
    }
    return t;
  }

  /// Weights for driving distance and driving time.
  void customizeAll(RoadGraph g) {
    distance = customize(g, (e) => g.edgeCost(e, false));
    time = customize(g, (e) => g.edgeCost(e, true));
  }

  int get nodes => rank.length;
  int get arcs => upHead.length;
  CchMetric metric(bool fastest) => fastest ? time : distance;

  // ---------- Build ----------

  static Cch build(RoadGraph g, {void Function(String)? stage}) {
    stage?.call('Ordering junctions');
    final n = g.nodeCount;
    final adj = _undirected(g);
    final order = _order(g, adj);
    final rank = Int32List(n);
    for (var r = 0; r < n; r++) {
      rank[order[r]] = r;
    }

    stage?.call('Adding shortcuts');
    // Symbolic elimination in rank space: a node's higher neighbours become a clique; it is enough to hand them
    // to the lowest of them (its elimination-tree parent).
    final nb = List<List<int>>.generate(n, (r) {
      final v = order[r];
      return [for (var i = adj.$1[v]; i < adj.$1[v + 1]; i++) rank[adj.$2[i]]];
    });
    final stamp = Int32List(n);
    final upStart = Int32List(n + 1);
    final heads = <int>[];
    for (var r = 0; r < n; r++) {
      final up = <int>[];
      for (final x in nb[r]) {
        if (x > r && stamp[x] != r + 1) {
          stamp[x] = r + 1;
          up.add(x);
        }
      }
      nb[r] = const [];
      up.sort();
      heads.addAll(up);
      upStart[r + 1] = heads.length;
      if (up.length > 1) nb[up[0]].addAll(up.skip(1));
    }
    final upHead = Int32List.fromList(heads);
    final parent = Int32List(n);
    for (var r = 0; r < n; r++) {
      parent[r] = upStart[r] == upStart[r + 1] ? -1 : upHead[upStart[r]];
    }
    final full = Cch(rank, upStart, upHead, parent);

    // Shortcuts no car can use in either direction stay impassable for every metric we use (same roads, other
    // costs), so they are dropped.
    stage?.call('Pruning shortcuts');
    final d = full.customize(g, (e) => g.edgeCost(e, false));
    final keepStart = Int32List(n + 1), keepHead = <int>[];
    for (var r = 0; r < n; r++) {
      for (var a = upStart[r]; a < upStart[r + 1]; a++) {
        if (d.upW[a] != double.infinity || d.downW[a] != double.infinity) keepHead.add(upHead[a]);
      }
      keepStart[r + 1] = keepHead.length;
    }
    stage?.call('Customizing');
    // The query still walks the full elimination tree, so pruning can't skip a node on the way up.
    return Cch(rank, keepStart, Int32List.fromList(keepHead), parent)..customizeAll(g);
  }

  /// Undirected simple graph of routing nodes as CSR (start, neighbours).
  static (Int32List, Int32List) _undirected(RoadGraph g) {
    final n = g.nodeCount;
    final keys = <int>[];
    for (var u = 0; u < n; u++) {
      for (var e = g.edgeStart[u]; e < g.edgeStart[u + 1]; e++) {
        final v = g.edgeTo[e];
        if (u != v) keys.add(min(u, v) * n + max(u, v));
      }
    }
    keys.sort();
    final deg = Int32List(n + 1);
    final pairs = <int>[];
    for (var i = 0; i < keys.length; i++) {
      if (i > 0 && keys[i] == keys[i - 1]) continue;
      pairs.add(keys[i]);
      deg[keys[i] ~/ n + 1]++;
      deg[keys[i] % n + 1]++;
    }
    for (var i = 0; i < n; i++) {
      deg[i + 1] += deg[i];
    }
    final fill = Int32List.fromList(deg.sublist(0, n)), out = Int32List(deg[n]);
    for (final k in pairs) {
      final a = k ~/ n, b = k % n;
      out[fill[a]++] = b;
      out[fill[b]++] = a;
    }
    return (deg, out);
  }

  /// Elimination order: nodes with ≤ 2 neighbours first (eliminating them only links their two neighbours),
  /// then nested dissection of the remaining junction graph.
  static Int32List _order(RoadGraph g, (Int32List, Int32List) adj) {
    final n = g.nodeCount;
    final (st, nb) = adj;
    final chain = Uint8List(n);
    final order = <int>[];
    for (var v = 0; v < n; v++) {
      if (st[v + 1] - st[v] <= 2) {
        chain[v] = 1;
        order.add(v);
      }
    }
    // Junction graph: chains of pass-through nodes collapse into one link between the junctions at their ends.
    final jAdj = <int, Set<int>>{};
    for (var a = 0; a < n; a++) {
      if (chain[a] == 1) continue;
      final set = jAdj[a] ??= <int>{};
      for (var i = st[a]; i < st[a + 1]; i++) {
        var prev = a, cur = nb[i];
        while (chain[cur] == 1) {
          var next = -1;
          for (var j = st[cur]; j < st[cur + 1]; j++) {
            if (nb[j] != prev) next = nb[j];
          }
          if (next < 0 || next == cur) break;
          prev = cur;
          cur = next;
          if (cur == a) break;
        }
        if (chain[cur] == 0 && cur != a) set.add(cur);
      }
    }
    final junctions = jAdj.keys.toList();
    final mark = Int32List(n), side = Uint8List(n), pos = Int32List(n);
    final key = Float64List(n);
    var stampId = 0;
    final k = cos((g.lat.isEmpty ? 0 : g.latOf(0)) * pi / 180);
    // Eight cut directions, every 22.5°.
    final dirs = [
      for (var d = 0; d < 8; d++)
        (int v) => g.lon[v] * k * cos(d * pi / 8) + g.lat[v] * sin(d * pi / 8),
    ];

    void nd(List<int> s) {
      if (s.length <= 64) {
        order.addAll(s);
        return;
      }
      final id = ++stampId;
      for (final v in s) {
        mark[v] = id;
      }
      List<int>? bestSorted;
      Set<int>? bestSep;
      var bestHalf = 0;
      for (final f in dirs) {
        for (final v in s) {
          key[v] = f(v);
        }
        final sorted = List.of(s)..sort((a, b) => key[a].compareTo(key[b]));
        for (var i = 0; i < sorted.length; i++) {
          pos[sorted[i]] = i;
        }
        // Sweep the split point through the middle 30–70 % and keep the one cutting the fewest roads.
        final lo = (sorted.length * 0.3).floor(), hi = (sorted.length * 0.7).ceil();
        var cut = 0, half = sorted.length ~/ 2;
        var bestCut = 1 << 60;
        for (var i = 0; i < hi; i++) {
          for (final w in jAdj[sorted[i]]!) {
            if (mark[w] == id) pos[w] < i ? cut-- : cut++;
          }
          if (i + 1 >= lo && cut < bestCut) {
            bestCut = cut;
            half = i + 1;
          }
        }
        for (var i = 0; i < sorted.length; i++) {
          side[sorted[i]] = i < half ? 0 : 1;
        }
        final sepA = <int>{}, sepB = <int>{};
        for (final v in sorted.take(half)) {
          for (final w in jAdj[v]!) {
            if (mark[w] == id && side[w] == 1) {
              sepA.add(v);
              sepB.add(w);
            }
          }
        }
        final sep = sepA.length <= sepB.length ? sepA : sepB;
        if (bestSep == null || sep.length < bestSep.length) {
          bestSep = sep;
          bestSorted = sorted;
          bestHalf = half;
        }
      }
      final half = bestHalf;
      final a = [for (final v in bestSorted!.take(half)) if (!bestSep!.contains(v)) v];
      final b = [for (final v in bestSorted.skip(half)) if (!bestSep!.contains(v)) v];
      nd(a);
      nd(b);
      order.addAll(bestSep!);
    }

    nd(junctions);
    return Int32List.fromList(order);
  }

  // ---------- Customize ----------

  /// Index of the arc between ranks lo < hi, or -1 when it was pruned.
  int arc(int lo, int hi) {
    var a = upStart[lo], b = upStart[lo + 1];
    final end = b;
    while (a < b) {
      final m = (a + b) >> 1;
      upHead[m] < hi ? a = m + 1 : b = m;
    }
    return a < end && upHead[a] == hi ? a : -1;
  }

  /// Weights for [cost] (per original edge): cheapest original edge per arc, then every triangle, lowest first.
  CchMetric customize(RoadGraph g, double Function(int edge) cost) {
    final m = arcs;
    final up = Float32List(m)..fillRange(0, m, double.infinity), down = Float32List(m)..fillRange(0, m, double.infinity);
    final upVia = Int32List(m)..fillRange(0, m, -1), downVia = Int32List(m)..fillRange(0, m, -1);
    for (var u = 0; u < g.nodeCount; u++) {
      for (var e = g.edgeStart[u]; e < g.edgeStart[u + 1]; e++) {
        final v = g.edgeTo[e];
        if (u == v) continue;
        final ru = rank[u], rv = rank[v];
        final a = arc(min(ru, rv), max(ru, rv));
        final c = cost(e);
        if (ru < rv) {
          if (c < up[a]) {
            up[a] = c;
            upVia[a] = e;
          }
        } else if (c < down[a]) {
          down[a] = c;
          downVia[a] = e;
        }
      }
    }
    // Arc (w1, w2) via lower v: w1→v→w2 and w2→v→w1. Processing v upwards finalises arcs from v first.
    for (var v = 0; v < nodes; v++) {
      final s = upStart[v], t = upStart[v + 1];
      for (var i = s; i < t; i++) {
        final w1 = upHead[i];
        final dIn1 = down[i], uOut1 = up[i];
        if (dIn1 == double.infinity && uOut1 == double.infinity) continue;
        for (var j = i + 1; j < t; j++) {
          final a = arc(w1, upHead[j]);
          if (a < 0) continue;
          final viaUp = dIn1 + up[j], viaDown = down[j] + uOut1;
          if (viaUp < up[a]) {
            up[a] = viaUp;
            upVia[a] = -v - 1;
          }
          if (viaDown < down[a]) {
            down[a] = viaDown;
            downVia[a] = -v - 1;
          }
        }
      }
    }
    return CchMetric(up, down, upVia, downVia);
  }

  // ---------- Query ----------

  Float64List? _df, _db;
  Int32List? _fa, _ba;

  /// Cheapest route from any source (node, cost already spent) to any target (node, cost still to go).
  CchPath? query(List<(int, double)> sources, List<(int, double)> targets, CchMetric w) {
    final df = _df ??= Float64List(nodes)..fillRange(0, nodes, double.infinity);
    final db = _db ??= Float64List(nodes)..fillRange(0, nodes, double.infinity);
    final fa = _fa ??= Int32List(nodes)..fillRange(0, nodes, -1);
    final ba = _ba ??= Int32List(nodes)..fillRange(0, nodes, -1);
    final fSeen = <int>[], bSeen = <int>[];
    final srcAt = <int, int>{}, dstAt = <int, int>{};

    // Each walk only raises values of the start's ancestors, so walking several starts one after another is exact.
    void walk(List<(int, double)> ends, Float64List d, Int32List via, List<int> seen, Map<int, int> at, Float32List weight) {
      for (var i = 0; i < ends.length; i++) {
        final r = rank[ends[i].$1];
        if (ends[i].$2 < d[r]) {
          if (d[r] == double.infinity) seen.add(r);
          d[r] = ends[i].$2;
          via[r] = -1;
          at[r] = i;
        }
        for (var x = r; x >= 0; x = parent[x]) {
          final dx = d[x];
          if (dx == double.infinity) continue;
          for (var a = upStart[x]; a < upStart[x + 1]; a++) {
            final y = upHead[a], c = dx + weight[a];
            if (c < d[y]) {
              if (d[y] == double.infinity) seen.add(y);
              d[y] = c;
              via[y] = a;
            }
          }
        }
      }
    }

    walk(sources, df, fa, fSeen, srcAt, w.upW);
    walk(targets, db, ba, bSeen, dstAt, w.downW);
    var best = double.infinity, meet = -1;
    for (final x in fSeen) {
      final c = df[x] + db[x];
      if (c < best) {
        best = c;
        meet = x;
      }
    }
    CchPath? result;
    if (meet >= 0) {
      final up = <int>[];
      var x = meet;
      while (fa[x] >= 0) {
        up.add(fa[x]);
        x = arcTail[fa[x]];
      }
      final src = srcAt[x] ?? 0;
      final edges = <int>[];
      for (final a in up.reversed) {
        _unpack(a, true, w, edges);
      }
      x = meet;
      while (ba[x] >= 0) {
        _unpack(ba[x], false, w, edges);
        x = arcTail[ba[x]];
      }
      result = CchPath(best, edges, src, dstAt[x] ?? 0);
    }
    for (final r in fSeen) {
      df[r] = double.infinity;
      fa[r] = -1;
    }
    for (final r in bSeen) {
      db[r] = double.infinity;
      ba[r] = -1;
    }
    return result;
  }

  /// Original edges of arc [a] driven upwards (tail → head) or downwards.
  void _unpack(int a, bool upwards, CchMetric w, List<int> out) {
    final stack = <(int, bool)>[(a, upwards)];
    while (stack.isNotEmpty) {
      final (arc0, upw) = stack.removeLast();
      final via = upw ? w.upVia[arc0] : w.downVia[arc0];
      if (via >= 0) {
        out.add(via);
        continue;
      }
      final mid = -via - 1, lo = arcTail[arc0], hi = upHead[arc0];
      final aLo = arc(mid, lo), aHi = arc(mid, hi);
      // Up: lo → mid → hi. Down: hi → mid → lo. Pushed in reverse so they pop in driving order.
      if (upw) {
        stack.add((aHi, true));
        stack.add((aLo, false));
      } else {
        stack.add((aLo, true));
        stack.add((aHi, false));
      }
    }
  }

  // ---------- File ----------

  /// Saves the weight-free part; weights are recomputed by [customizeAll] after reading.
  void write(BinWriter w) {
    for (final a in <TypedData>[rank, upStart, upHead, parent]) {
      w.array(a);
    }
  }

  static Cch read(BinReader r, RoadGraph g) => Cch(r.i32(), r.i32(), r.i32(), r.i32())..customizeAll(g);
}
