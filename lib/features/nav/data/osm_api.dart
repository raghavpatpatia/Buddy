import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../model/region.dart';

// OSM's usage policy asks for an identifying User-Agent and no more than one search a second.
const _ua = {'User-Agent': 'BuddyApp/1.0 (personal Android app)'};
const _nominatim = 'https://nominatim.openstreetmap.org';
const _photon = 'https://photon.komoot.io/api/';

/// Free, key-less OpenStreetMap place search. Needs internet; offline search uses the map's streets.
class OsmApi {
  /// Places, shops, landmarks and addresses matching [q] as you type, inside [box] (south, west, north, east)
  /// when given and ranked by distance from [near]. Photon matches word prefixes ("feli" → "Felicity");
  /// Nominatim (whole words only) is the fallback.
  static Future<List<Place>> searchPlaces(String q, {(double, double, double, double)? box, (double, double)? near, String countryCode = 'in'}) async {
    try {
      return await _photonSearch(q, box, near);
    } catch (_) {
      return _nominatimSearch(q, box, countryCode);
    }
  }

  /// India's bounding box: where searches look when there's no location to search near.
  static const _india = (6.5, 68.0, 37.2, 97.5);

  static Future<List<Place>> _photonSearch(String q, (double, double, double, double)? box, (double, double)? near) async {
    box ??= near == null ? _india : null;
    final res = await http.get(
      Uri.parse(_photon).replace(queryParameters: {
        'q': q, 'limit': '8',
        if (near != null) ...{'lat': '${near.$1}', 'lon': '${near.$2}'},
        if (box != null) 'bbox': '${box.$2},${box.$1},${box.$4},${box.$3}',
      }),
      headers: _ua,
    ).timeout(const Duration(seconds: 6));
    if (res.statusCode != 200) throw HttpException('Search failed (${res.statusCode})');
    return [
      for (final f in ((jsonDecode(res.body) as Map)['features'] as List).cast<Map>())
        if (f['properties']['name'] != null || f['properties']['street'] != null)
          Place(
            (f['properties']['name'] ?? '${f['properties']['housenumber'] ?? ''} ${f['properties']['street']}'.trim()) as String,
            _detail(f['properties'] as Map),
            ((f['geometry']['coordinates'] as List)[1] as num).toDouble(),
            ((f['geometry']['coordinates'] as List)[0] as num).toDouble(),
          ),
    ];
  }

  /// "Restaurant · Thanisandra Main Road, Kempapura, Bengaluru".
  static String _detail(Map p) {
    final kind = (p['osm_value'] as String? ?? '').replaceAll('_', ' ');
    final where = [p['street'], p['district'] ?? p['locality'], p['city']].whereType<String>().where((s) => s.isNotEmpty).join(', ');
    final k = kind.isEmpty || kind == 'yes' ? '' : '${kind[0].toUpperCase()}${kind.substring(1)}';
    return [k, where].where((s) => s.isNotEmpty).join(' · ');
  }

  static Future<List<Place>> _nominatimSearch(String q, (double, double, double, double)? box, String countryCode) async {
    final res = await http.get(
      Uri.parse('$_nominatim/search').replace(queryParameters: {
        'q': q, 'format': 'jsonv2', 'limit': '6', 'countrycodes': countryCode,
        if (box != null) ...{'bounded': '1', 'viewbox': '${box.$2},${box.$3},${box.$4},${box.$1}'},
      }),
      headers: _ua,
    ).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) throw HttpException('Search failed (${res.statusCode})');
    return [
      for (final m in (jsonDecode(res.body) as List).cast<Map>())
        Place(
          (m['name'] as String?)?.isNotEmpty == true ? m['name'] : (m['display_name'] as String).split(',').first,
          m['display_name'] ?? '',
          double.parse(m['lat']),
          double.parse(m['lon']),
        ),
    ];
  }

  /// Name of the city / district around a point, for naming a downloaded area; null when offline.
  static Future<String?> placeName(double lat, double lon) async {
    try {
      final res = await http.get(
        Uri.parse('$_nominatim/reverse').replace(queryParameters: {'lat': '$lat', 'lon': '$lon', 'zoom': '10', 'format': 'jsonv2'}),
        headers: _ua,
      ).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;
      final a = (jsonDecode(res.body) as Map)['address'] as Map? ?? {};
      return (a['city'] ?? a['town'] ?? a['state_district'] ?? a['county'] ?? a['state']) as String?;
    } catch (_) {
      return null;
    }
  }

  /// True when the map servers answer within a few seconds.
  static Future<bool> online() async {
    try {
      final res = await http.head(Uri.parse('https://tile.openstreetmap.org/0/0/0.png'), headers: _ua).timeout(const Duration(seconds: 4));
      return res.statusCode < 500;
    } catch (_) {
      return false;
    }
  }
}
