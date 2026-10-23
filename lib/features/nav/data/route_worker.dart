import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import '../model/bin_io.dart';
import '../model/cch.dart';
import '../model/road_graph.dart';
import '../model/route_plan.dart';
import '../model/router.dart';

/// A background isolate that owns a map's routing data. Opening a map customizes the CCH there (a second or two),
/// and routes and alternatives are computed there, so the UI never stalls.
class RouteWorker {
  final Isolate _iso;
  final SendPort _to;
  final ReceivePort _from;
  final _waiting = <int, Completer<Object?>>{};
  var _next = 0;

  /// The road network, for drawing and snapping on the UI side.
  final RoadGraph graph;

  RouteWorker._(this._iso, this._to, this._from, this.graph) {
    _from.listen((m) {
      final l = m as List;
      _waiting.remove(l[0])?.complete(l[1]);
    });
  }

  static Future<RouteWorker> open(String path) async {
    final rp = ReceivePort();
    final iso = await Isolate.spawn(_main, (rp.sendPort, path), errorsAreFatal: false);
    final first = Completer<List>();
    late StreamSubscription sub;
    final from = ReceivePort();
    sub = rp.listen((m) {
      if (!first.isCompleted) first.complete(m as List);
    });
    iso.addErrorListener(rp.sendPort);
    final l = await first.future;
    await sub.cancel();
    rp.close();
    if (l.length != 2 || l[0] is! SendPort) {
      iso.kill();
      throw StateError('Could not open map: ${l.first}');
    }
    (l[0] as SendPort).send(from.sendPort);
    return RouteWorker._(iso, l[0] as SendPort, from, l[1] as RoadGraph);
  }

  Future<T> _ask<T>(List msg) {
    final id = _next++;
    final c = Completer<Object?>();
    _waiting[id] = c;
    _to.send([id, ...msg]);
    return c.future.then((v) => v as T);
  }

  Future<RoutePlan?> route(Snap s, Snap t, bool fastest) => _ask(['route', s, t, fastest]);
  Future<List<RoutePlan>> alternatives(Snap s, Snap t, RoutePlan best, bool fastest) => _ask(['alts', s, t, best, fastest]);

  void close() {
    _from.close();
    _iso.kill(priority: Isolate.immediate);
  }

  static Future<void> _main((SendPort, String) args) async {
    final (out, path) = args;
    final Router router;
    try {
      final r = BinReader(await File(path).readAsBytes());
      final g = RoadGraph.read(r);
      router = Router(g, Cch.read(r, g));
    } catch (e) {
      out.send(['$e']);
      return;
    }
    final inbox = ReceivePort();
    out.send([inbox.sendPort, router.g]);
    SendPort? reply;
    await for (final m in inbox) {
      if (m is SendPort) {
        reply = m;
        continue;
      }
      final l = m as List;
      final Object? result = switch (l[1]) {
        'route' => router.route(l[2] as Snap, l[3] as Snap, fastest: l[4] as bool),
        'alts' => router.alternatives(l[2] as Snap, l[3] as Snap, l[4] as RoutePlan, fastest: l[5] as bool),
        _ => null,
      };
      reply?.send([l[0], result]);
    }
  }
}
