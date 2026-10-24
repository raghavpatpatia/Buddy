import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/store.dart';

// OSM's usage policy asks for an identifying User-Agent; results are cached so we query rarely.
const _ua = {'User-Agent': 'BuddyApp/1.0 (personal Android app)'};
const _overpass = 'https://overpass-api.de/api/interpreter';
const _photon = 'https://photon.komoot.io/reverse';
const _radiusM = 1500;

/// Restaurants, cafés and fast food around you from OpenStreetMap (free, no key), as place maps the
/// food engine understands: {name, lat, lng, visits: 0, cuisines: [...], vegOnly, nearby: true}.
/// Overpass has cuisine tags but is often overloaded, so Photon (fast, names only) is asked at the same time.
class NearbyFood {
  static Future<List<Map<String, dynamic>>> around(double lat, double lng) async {
    // Always fetched live; the last result is kept only as an offline fallback.
    final cached = Store.getJson('nearby_food') as Map?;
    final (tagged, named) = await (_overpassPlaces(lat, lng), _photonPlaces(lat, lng)).wait;
    // Overpass entries win (they know the cuisine); Photon fills in the rest.
    final byName = <String, Map<String, dynamic>>{};
    for (final p in [...tagged, ...named]) {
      byName.putIfAbsent((p['name'] as String).toLowerCase(), () => p);
    }
    final places = byName.values.toList();
    if (places.isEmpty) return cached != null ? _places(cached) : [];
    await Store.setJson('nearby_food', {'at': DateTime.now().toIso8601String(), 'lat': lat, 'lng': lng, 'places': places});
    return places;
  }

  static Future<List<Map<String, dynamic>>> _overpassPlaces(double lat, double lng) async {
    try {
      final q = '[out:json][timeout:8];'
          'nwr(around:$_radiusM,$lat,$lng)[amenity~"^(restaurant|fast_food|cafe|food_court)\$"][name];'
          'out center 60;';
      final res = await http.post(Uri.parse(_overpass), headers: _ua, body: {'data': q}).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return [];
      return [
        for (final el in ((jsonDecode(res.body) as Map)['elements'] as List).cast<Map>())
          if ((el['lat'] ?? el['center']?['lat']) != null)
            _place(
              (el['tags'] as Map)['name'] as String,
              ((el['lat'] ?? el['center']['lat']) as num).toDouble(),
              ((el['lon'] ?? el['center']['lon']) as num).toDouble(),
              (el['tags'] as Map).cast<String, dynamic>(),
            ),
      ];
    } catch (_) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> _photonPlaces(double lat, double lng) async {
    try {
      final uri = Uri.parse('$_photon?lat=$lat&lon=$lng&radius=${_radiusM / 1000}&limit=60'
          '&osm_tag=amenity:restaurant&osm_tag=amenity:fast_food&osm_tag=amenity:cafe&osm_tag=amenity:food_court');
      final res = await http.get(uri, headers: _ua).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return [];
      return [
        for (final f in ((jsonDecode(res.body) as Map)['features'] as List).cast<Map>())
          if (f['properties']['name'] != null)
            _place(
              f['properties']['name'] as String,
              ((f['geometry']['coordinates'] as List)[1] as num).toDouble(),
              ((f['geometry']['coordinates'] as List)[0] as num).toDouble(),
              {'amenity': f['properties']['osm_value']},
            ),
      ];
    } catch (_) {
      return [];
    }
  }

  static Map<String, dynamic> _place(String name, double lat, double lng, Map<String, dynamic> tags) => {
        'name': name,
        'lat': lat,
        'lng': lng,
        'visits': 0,
        'cuisines': cuisinesFor(tags['amenity'] as String? ?? '', tags['cuisine'] as String? ?? '', name),
        'vegOnly': tags['diet:vegetarian'] == 'only' || tags['diet:vegan'] == 'only' || _has(name, _vegHints),
        'noBreakfast': _has(name, _noBreakfastHints),
        'nearby': true,
      };

  static bool _has(String name, List<String> words) => words.any(name.toLowerCase().contains);

  static List<Map<String, dynamic>> _places(Map cached) =>
      [for (final p in cached['places'] as List) Map<String, dynamic>.from(p as Map)];

  /// Maps OSM `amenity` + `cuisine` tags ("north_indian;chinese") to Buddy's cuisines, guessing from
  /// the [name] ("Donne Biriyani Palace", "Dosa Time") when there's no cuisine tag.
  static List<String> cuisinesFor(String amenity, String cuisine, [String name = '']) {
    final out = <String>{};
    if (_has(name, _dessertHints)) return []; // sweets and ice cream, not meals
    if (cuisine.isEmpty) {
      final n = name.toLowerCase();
      for (final (words, c) in _nameHints) {
        if (words.any(n.contains)) out.add(c);
      }
    }
    for (final c in cuisine.toLowerCase().split(RegExp(r'[;,]')).map((s) => s.trim())) {
      switch (c) {
        case 'north_indian' || 'punjabi' || 'mughlai' || 'biryani' || 'kebab' || 'rajasthani' || 'gujarati' || 'bengali':
          out.add('North Indian');
        case 'south_indian' || 'udupi' || 'kerala' || 'chettinad' || 'andhra' || 'tamil' || 'karnataka' || 'hyderabadi':
          out.add('South Indian');
        case 'indian' || 'regional' || 'thali':
          out.addAll(['North Indian', 'South Indian']);
        case 'chinese' || 'asian' || 'tibetan' || 'momos' || 'thai' || 'japanese' || 'korean' || 'indo_chinese':
          out.add('Chinese');
        case 'pizza' || 'burger' || 'sandwich' || 'american' || 'chicken' || 'fried_chicken' || 'street_food':
          out.add('Fast food');
        case 'italian' || 'continental' || 'european' || 'french' || 'mediterranean' || 'coffee_shop' || 'cafe' || 'breakfast':
          out.add('Continental');
        case 'salad' || 'healthy' || 'vegan' || 'juice' || 'smoothie':
          out.add('Healthy');
      }
    }
    if (out.isEmpty) {
      if (amenity == 'fast_food') {
        out.add('Fast food');
      } else if (amenity == 'cafe') {
        out.add('Continental');
      } else {
        out.addAll(['North Indian', 'South Indian']);
      }
    }
    return out.toList();
  }

  static const _nameHints = [
    (['biryani', 'biriyani', 'mandi', 'kebab', 'kabab', 'punjab', 'dhaba', 'tandoor', 'mughlai', 'delhi', 'paratha', 'kashmiri'], 'North Indian'),
    (['dosa', 'idli', 'udupi', 'bhavan', 'darshini', 'andhra', 'telugu', 'kerala', 'thalassery', 'chettinad', 'tiffin', 'meals', 'military', 'naivedyam', 'sagar', 'seafood', 'coastal', 'mangalore'], 'South Indian'),
    (['chinese', 'wok', 'dragon', 'momo', 'noodle', 'wah', 'szechuan', 'sichuan', 'thai', 'asian', 'sushi'], 'Chinese'),
    (['pizz', 'pino', 'burrito', 'taco', 'mexican', 'burger', 'domino', 'kfc', 'mcdonald', 'subway', 'shawarma', 'laffah', 'roll', 'fries', 'sandwich'], 'Fast food'),
    (['cafe', 'café', 'coffee', 'bakery', 'bistro', 'pasta', 'italian', 'continental', 'nonna', 'trattoria', 'sourdough'], 'Continental'),
    (['salad', 'healthy', 'juice', 'smoothie', 'bowl', 'vegan', 'protein'], 'Healthy'),
  ];
  static const _vegHints = ['pure veg', 'veg restaurant', 'naivedyam', 'bhavan', 'sagar', 'udupi', 'darshini', 'haldiram', 'saravana', 'jain'];
  static const _noBreakfastHints = ['biryani', 'biriyani', 'mandi', 'kebab', 'kabab', 'barbeque', 'bbq', 'bar ', 'pub', 'brew', 'pizz'];
  static const _dessertHints = ['dessert', 'ice cream', 'creamery', 'gelato', 'sweets', 'cake', 'waffle', 'kulfi', 'falooda'];
}
