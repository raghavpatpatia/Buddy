import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/arch/load_state.dart';
import '../../../core/arch/safe_notifier.dart';
import '../data/map_store.dart';
import '../data/nav_voice.dart';
import '../data/osm_api.dart';
import '../data/route_worker.dart';
import '../data/tile_api.dart';
import '../data/valhalla_api.dart';
import '../model/region.dart';
import '../model/road_graph.dart';
import '../model/route_plan.dart';

/// An area download in progress.
class MapDownload {
  final String name;
  final DownloadStep step;
  const MapDownload(this.name, this.step);
}

/// Map tab: downloaded maps, live position, from/to, routes and spoken directions.
class NavController extends SafeNotifier {
  Region? region;
  LoadState<RoadGraph> graph = const Idle();
  RouteWorker? _worker;
  MapDownload? download;
  String? downloadError;
  bool online = true;
  MapManifest? manifest;

  /// Raw GPS fix and the point on the road it snaps to (when within ~40 m of one).
  (double, double)? me;
  (double, double)? onRoad;
  double? heading;
  String? gpsProblem;
  String myStreet = '';

  /// Start point; null means "my location".
  Place? from;
  Place? to;
  bool fastest = true;
  LoadState<RoutePlan> route = const Idle();
  List<RoutePlan> alternatives = const [];
  bool findingAlternatives = false;
  RouteProgress? progress;
  bool arrived = false;
  bool get voiceOn => NavVoice.enabled;

  StreamSubscription<Position>? _gps;
  Timer? _onlineTimer;
  DateTime _lastReroute = DateTime(0);
  final _voice = NavVoice();
  final _spoken = <String>{};
  int _routeTicket = 0;

  List<Region> get regions => MapStore.regions.all.toList()..sort((a, b) => a.name.compareTo(b.name));
  RoadGraph? get roads => graph.data;
  RoutePlan? get plan => route.data;

  /// Where you are for display: on the road when snapped, else the raw fix.
  (double, double)? get here => onRoad ?? me;

  /// Where the route starts: the chosen place, else you.
  (double, double)? get origin => from == null ? here : (from!.lat, from!.lon);

  /// A newer weekly map build exists for the open map.
  bool get updateAvailable => region != null && manifest != null && region!.built.isNotEmpty && manifest!.built != region!.built;

  Maneuver? get nextManeuver => plan?.nextManeuver(progress?.travelled ?? 0);
  double? get toNextManeuver => nextManeuver == null ? null : nextManeuver!.at - (progress?.travelled ?? 0);

  Future<void> start() async {
    final last = MapStore.regions[MapStore.lastRegionId ?? ''] ?? (regions.isEmpty ? null : regions.first);
    if (last != null) unawaited(selectRegion(last));
    unawaited(_checkOnline());
    _onlineTimer = Timer.periodic(const Duration(seconds: 45), (_) => _checkOnline());
    await startGps();
  }

  Future<void> _checkOnline() async {
    final v = await OsmApi.online();
    if (v && manifest == null) unawaited(loadManifest());
    if (v != online) {
      online = v;
      notifyListeners();
    }
  }

  /// What the map server has; null (and a message) when it can't be reached.
  Future<MapManifest?> loadManifest() async {
    try {
      manifest = await TileApi.manifest();
      notifyListeners();
    } catch (e) {
      debugPrint('[Nav] manifest: $e');
    }
    return manifest;
  }

  // ---------- GPS ----------

  /// Asks for location and follows it; every fix snaps to the road, updates the distance left, speaks the next
  /// turn and re-routes when you leave the route.
  Future<void> startGps() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        gpsProblem = 'Turn on location to see where you are.';
        notifyListeners();
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm != LocationPermission.whileInUse && perm != LocationPermission.always) {
        gpsProblem = 'Allow location so Buddy can show you on the map.';
        notifyListeners();
        return;
      }
      gpsProblem = null;
      await _gps?.cancel();
      _gps = Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5))
          .listen(_onFix, onError: (e) {
        gpsProblem = 'Location unavailable';
        notifyListeners();
      });
    } catch (e) {
      debugPrint('[Nav] gps: $e');
      gpsProblem = 'Location unavailable';
      notifyListeners();
    }
  }

  void _onFix(Position p) {
    me = (p.latitude, p.longitude);
    // Compass heading is only meaningful while moving.
    heading = p.speed > 1.5 && p.heading >= 0 ? p.heading : null;
    final g = roads;
    final s = g?.snap(p.latitude, p.longitude, heading: heading, maxM: 40);
    onRoad = s == null ? null : (s.lat, s.lon);
    myStreet = s == null ? '' : g!.nameOf(s.piece);
    final r = plan;
    if (r != null && from == null && !arrived) {
      final h = here!;
      final pr = r.progress(h.$1, h.$2, from: progress?.index ?? 0);
      progress = pr;
      if (pr.metresLeft < 25) {
        arrived = true;
        _say('arrive', 'You have arrived.');
      } else {
        _announce();
      }
      // Off the line (missed a turn, closed road): plan again from here, at most every 15 s.
      if (!arrived && pr.offRoute > 50 && !route.isLoading && DateTime.now().difference(_lastReroute).inSeconds >= 15) {
        _lastReroute = DateTime.now();
        unawaited(findRoute(rerouting: true));
      }
    }
    notifyListeners();
  }

  /// "In 500 metres, turn left onto …" well before a turn, then the instruction itself just before it.
  void _announce() {
    final m = nextManeuver, d = toNextManeuver;
    if (m == null || d == null || m.turn == Turn.arrive) return;
    final key = '${m.at.round()}';
    if (d <= 90) {
      _say('near$key', '${m.text}.');
    } else if (d <= 550 && d >= 300) {
      _say('far$key', 'In ${(d / 100).round() * 100} metres, ${m.text[0].toLowerCase()}${m.text.substring(1)}.');
    }
  }

  void _say(String key, String text) {
    if (_spoken.add(key)) unawaited(_voice.say(text));
  }

  Future<void> setVoice(bool on) async {
    await NavVoice.setEnabled(on);
    if (!on) await _voice.stop();
    notifyListeners();
  }

  // ---------- Maps ----------

  Future<void> selectRegion(Region r) async {
    region = r;
    graph = const Loading();
    _clearRoute(notify: false);
    notifyListeners();
    await MapStore.setLastRegion(r.id);
    _worker?.close();
    _worker = null;
    try {
      final w = await RouteWorker.open(await MapStore.pathFor(r.id));
      if (region?.id != r.id) return w.close();
      _worker = w;
      graph = Ready(w.graph);
    } catch (e) {
      debugPrint('[Nav] open ${r.id}: $e');
      if (region?.id == r.id) graph = const Failed('This map is missing or from an older version of Buddy. Download it again.');
    }
    notifyListeners();
  }

  /// Downloads the roads in [box] (Google-style rectangle). [replacing] updates that map in place.
  Future<void> downloadArea((double, double, double, double) box, {Region? replacing}) async {
    if (download != null) return;
    downloadError = null;
    download = MapDownload(replacing?.name ?? 'this area', const DownloadStep('Contacting map server'));
    notifyListeners();
    try {
      final m = manifest ?? await TileApi.manifest();
      manifest = m;
      final name = replacing?.name ?? await OsmApi.placeName((box.$1 + box.$3) / 2, (box.$2 + box.$4) / 2) ??
          'Area at ${((box.$1 + box.$3) / 2).toStringAsFixed(2)}, ${((box.$2 + box.$4) / 2).toStringAsFixed(2)}';
      final id = replacing?.id ?? 'map_${DateTime.now().millisecondsSinceEpoch}';
      download = MapDownload(name, const DownloadStep('Downloading roads', 0));
      notifyListeners();
      if (replacing != null && region?.id == replacing.id) {
        // The worker holds the old file open; close it before replacing.
        _worker?.close();
        _worker = null;
      }
      final (bytes, nodes, roads) = await TileApi.downloadArea(m, box, await MapStore.pathFor(id), await MapStore.tileDir(), (s) {
        download = MapDownload(name, s);
        notifyListeners();
      });
      final saved = Region(
        id: id, name: name, south: box.$1, west: box.$2, north: box.$3, east: box.$4,
        bytes: bytes, nodes: nodes, roads: roads, downloadedAt: DateTime.now(), built: m.built, dataDate: m.dataDate,
      );
      await MapStore.regions.put(saved);
      download = null;
      await selectRegion(saved);
    } catch (e) {
      debugPrint('[Nav] download: $e');
      download = null;
      downloadError = e is FormatException ? e.message : 'Download failed: $e';
      if (replacing != null && region?.id == replacing.id && _worker == null) unawaited(selectRegion(replacing));
      notifyListeners();
    }
  }

  Future<void> deleteRegion(Region r) async {
    if (region?.id == r.id) {
      _worker?.close();
      _worker = null;
      region = null;
      graph = const Idle();
      _clearRoute(notify: false);
    }
    await MapStore.delete(r.id);
    notifyListeners();
  }

  // ---------- Places and routes ----------

  /// Streets from the downloaded map (works offline), plus addresses and landmarks when online.
  /// Places anywhere when online (nearest first); street names from the downloaded map, which also work offline.
  Future<List<Place>> search(String q) async {
    final r = region, g = roads;
    if (q.trim().length < 2) return const [];
    final out = <Place>[];
    if (online) {
      try {
        final near = origin ?? (r == null ? null : (r.centerLat, r.centerLon));
        final hits = await OsmApi.searchPlaces(q, near: near);
        // Nearest first; nothing too far to drive to (the routing server's 1,500 km limit).
        if (near != null) {
          hits.retainWhere((p) => metres(near.$1, near.$2, p.lat, p.lon) < 1500000);
          hits.sort((a, b) => metres(near.$1, near.$2, a.lat, a.lon).compareTo(metres(near.$1, near.$2, b.lat, b.lon)));
        }
        out.addAll(hits);
      } catch (e) {
        debugPrint('[Nav] search: $e');
      }
    }
    if (r != null && g != null) {
      for (final (name, la, lo) in g.searchStreets(q)) {
        if (!out.any((p) => p.name == name)) out.add(Place(name, 'Street · ${r.name}', la, lo));
      }
    }
    return out;
  }

  /// Routing is possible: online (server), or offline with a downloaded map.
  bool get canRoute => online || roads != null;

  void setFrom(Place? p) {
    from = p;
    _clearRoute();
  }

  void setTo(Place? p) {
    to = p;
    _clearRoute();
  }

  /// Removes the target pin and its route (the start stays).
  void clearTarget() {
    to = null;
    _clearRoute();
  }

  void swap() {
    final h = here;
    if (from == null && h != null) {
      from = to;
      to = Place('My location', '', h.$1, h.$2);
    } else {
      final t = to;
      to = from;
      from = t;
    }
    _clearRoute();
  }

  void setFastest(bool v) {
    fastest = v;
    if (plan != null) unawaited(findRoute());
    notifyListeners();
  }

  /// Makes alternative [i] the route (the old route becomes an alternative).
  void chooseAlternative(int i) {
    final cur = plan;
    if (cur == null || i >= alternatives.length) return;
    route = Ready(alternatives[i]);
    alternatives = [...alternatives]..[i] = cur;
    _spoken.clear();
    final h = here;
    progress = h != null && from == null ? plan!.progress(h.$1, h.$2) : null;
    notifyListeners();
  }

  void _clearRoute({bool notify = true}) {
    _routeTicket++;
    route = const Idle();
    alternatives = const [];
    findingAlternatives = false;
    progress = null;
    arrived = false;
    _spoken.clear();
    if (notify) notifyListeners();
  }

  /// Snaps both ends to the road network and asks the route worker; alternatives follow in the background.
  /// Online: the routing server, anywhere, with alternatives in the same answer. Offline (or if the server
  /// fails): the downloaded map.
  Future<void> findRoute({bool rerouting = false}) async {
    final s = origin, t = to;
    if (t == null) return;
    if (s == null) {
      route = const Failed('Waiting for your location. Or pick a start point.');
      notifyListeners();
      return;
    }
    final ticket = ++_routeTicket;
    route = Loading(plan);
    alternatives = const [];
    arrived = false;
    notifyListeners();
    if (online) {
      try {
        final plans = await ValhallaApi.route(s, (t.lat, t.lon), fastest: fastest, heading: from == null ? heading : null);
        if (ticket != _routeTicket) return;
        _show(plans.first, s, rerouting);
        alternatives = rerouting ? const [] : plans.skip(1).toList();
        notifyListeners();
        return;
      } catch (e) {
        debugPrint('[Nav] online route: $e');
        if (ticket != _routeTicket) return;
        if (roads == null) {
          route = Failed(_routeError(e, s, t));
          notifyListeners();
          return;
        }
      }
    }
    await _offlineRoute(s, t, ticket, rerouting);
  }

  /// Plain words for what the routing server said.
  static String _routeError(Object e, (double, double) s, Place t) {
    final km = metres(s.$1, s.$2, t.lat, t.lon) / 1000;
    final msg = e is HttpException ? e.message.toLowerCase() : '';
    if (msg.contains('exceeds')) {
      return '${t.name} is about ${km.round()} km away in a straight line. The free routing server plans trips up to 1,500 km; '
          'check it\'s the right place, or route to a stop on the way first.';
    }
    if (msg.contains('no path') || msg.contains('no suitable edges') || msg.contains('442')) {
      return 'No road route found to ${t.name}. Try a point on a road nearby (long-press the map).';
    }
    if (e is HttpException) return 'Couldn\'t plan this route: ${e.message}';
    return 'Could not reach the routing server. Check your internet, or download this area for offline use.';
  }

  void _show(RoutePlan r, (double, double) s, bool rerouting) {
    route = Ready(r);
    _spoken.clear();
    progress = from == null ? r.progress(s.$1, s.$2) : null;
    if (from == null && r.maneuvers.length > 1) {
      _say('start${r.metres.round()}', rerouting ? 'Rerouting. ${r.maneuvers[1].text}.' : '${fmtKm(r.metres)}, about ${fmtEta(r.seconds)}. ${r.maneuvers.first.text}.');
    }
  }

  Future<void> _offlineRoute((double, double) s, Place t, int ticket, bool rerouting) async {
    final g = roads, w = _worker;
    if (g == null || w == null) {
      route = const Failed('You\'re offline. Download an area in Maps to route without internet.');
      notifyListeners();
      return;
    }
    final a = g.snap(s.$1, s.$2, heading: from == null ? heading : null), b = g.snap(t.lat, t.lon);
    if (a == null || b == null) {
      final r = region!;
      final (la, lo) = a == null ? s : (t.lat, t.lon);
      final km = r.kmOutside(la, lo);
      final who = a == null ? (from == null ? 'You are' : 'The start is') : '${t.name} is';
      route = Failed(km >= 1
          ? '$who ${km.round()} km outside the ${r.name} map. Download an area that covers both points (Maps → Download a new area)${a == null && from == null ? ', or pick a start inside ${r.name}' : ''}.'
          : '$who too far from any road in the ${r.name} map. Pick a point on or near a road.');
      notifyListeners();
      return;
    }
    try {
      final r = await w.route(a, b, fastest);
      if (ticket != _routeTicket) return;
      if (r == null) {
        route = const Failed('No road connects these two points in this map.');
        notifyListeners();
        return;
      }
      _show(r, s, rerouting);
      notifyListeners();
      if (rerouting) return;
      findingAlternatives = true;
      notifyListeners();
      final alts = await w.alternatives(a, b, r, fastest);
      if (ticket != _routeTicket) return;
      alternatives = alts;
      findingAlternatives = false;
    } catch (e) {
      debugPrint('[Nav] route: $e');
      if (ticket == _routeTicket) route = const Failed('Could not plan this route.');
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _gps?.cancel();
    _onlineTimer?.cancel();
    _worker?.close();
    _voice.dispose();
    super.dispose();
  }
}
