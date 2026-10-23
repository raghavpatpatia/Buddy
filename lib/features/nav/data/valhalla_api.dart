import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../model/road_graph.dart' show metres;
import '../model/route_plan.dart';

/// Online routing on OpenStreetMap Germany's free public Valhalla server (no key; fair use, so one request at a
/// time and only when the user asks or leaves the route). Works anywhere, nothing to download.
class ValhallaApi {
  static const _url = 'https://valhalla1.openstreetmap.de/route';
  static const _ua = {'User-Agent': 'BuddyApp/1.0 (personal Android app)', 'Content-Type': 'application/json'};

  /// Best route first, then up to two alternatives. [heading] (degrees) helps it start on the right side of the road.
  static Future<List<RoutePlan>> route((double, double) from, (double, double) to, {bool fastest = true, double? heading}) async {
    final res = await http
        .post(
          Uri.parse(_url),
          headers: _ua,
          body: jsonEncode({
            'locations': [
              {'lat': from.$1, 'lon': from.$2, if (heading != null) 'heading': heading.round()},
              {'lat': to.$1, 'lon': to.$2},
            ],
            'costing': 'auto',
            'costing_options': {
              'auto': {if (!fastest) 'shortest': true},
            },
            'alternates': 2,
            'directions_options': {'units': 'kilometers', 'language': 'en-US'},
          }),
        )
        .timeout(const Duration(seconds: 20));
    final body = jsonDecode(res.body) as Map;
    if (res.statusCode != 200) {
      // 442: no route between the points (e.g. across water); 171: point too far from any road.
      throw HttpException(body['error'] as String? ?? 'Routing server error ${res.statusCode}');
    }
    final plans = [_plan(body['trip'] as Map), for (final a in (body['alternates'] as List? ?? [])) _plan((a as Map)['trip'] as Map)];
    plans.sort((a, b) => (fastest ? a.seconds.compareTo(b.seconds) : a.metres.compareTo(b.metres)));
    return plans;
  }

  static RoutePlan _plan(Map trip) {
    final pts = <(double, double)>[];
    final ms = <Maneuver>[];
    final cum = <double>[];
    for (final leg in (trip['legs'] as List).cast<Map>()) {
      final base = pts.length;
      pts.addAll(decodePolyline6(leg['shape'] as String));
      while (cum.length < pts.length) {
        final i = cum.length;
        cum.add(i == 0 ? 0 : cum.last + metres(pts[i - 1].$1, pts[i - 1].$2, pts[i].$1, pts[i].$2));
      }
      for (final m in (leg['maneuvers'] as List).cast<Map>()) {
        final at = cum[(base + (m['begin_shape_index'] as int)).clamp(0, cum.length - 1)];
        final streets = (m['street_names'] as List?)?.cast<String>() ?? const [];
        ms.add(Maneuver(_turn(m['type'] as int), at, streets.isEmpty ? '' : streets.first,
            exit: (m['roundabout_exit_count'] as int?) ?? 0, say: m['instruction'] as String? ?? ''));
      }
    }
    final names = <String>[];
    for (final m in ms) {
      if (m.street.isNotEmpty && (names.isEmpty || names.last != m.street)) names.add(m.street);
    }
    final s = trip['summary'] as Map;
    return RoutePlan(
      points: pts,
      cumMetres: cum,
      metres: (s['length'] as num) * 1000,
      seconds: (s['time'] as num).toDouble(),
      flyovers: names.where((n) => n.toLowerCase().contains('flyover')).length,
      tunnels: 0,
      streets: names,
      maneuvers: ms,
    );
  }

  /// Valhalla maneuver types → ours.
  static Turn _turn(int t) => switch (t) {
        1 || 2 || 3 => Turn.depart,
        4 || 5 || 6 => Turn.arrive,
        9 || 18 || 20 || 23 || 37 => Turn.slightRight,
        16 || 19 || 21 || 24 || 38 => Turn.slightLeft,
        10 => Turn.right,
        15 => Turn.left,
        11 => Turn.sharpRight,
        14 => Turn.sharpLeft,
        12 || 13 => Turn.uTurn,
        26 || 27 => Turn.roundabout,
        _ => Turn.straight,
      };

  /// Google-style encoded polyline with 6 decimals (Valhalla's shape format).
  static List<(double, double)> decodePolyline6(String s) {
    final out = <(double, double)>[];
    var i = 0, lat = 0, lon = 0;
    int next() {
      var r = 0, shift = 0, b = 0;
      do {
        b = s.codeUnitAt(i++) - 63;
        r |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      return (r & 1) != 0 ? ~(r >> 1) : r >> 1;
    }

    while (i < s.length) {
      lat += next();
      lon += next();
      out.add((lat / 1e6, lon / 1e6));
    }
    return out;
  }
}
