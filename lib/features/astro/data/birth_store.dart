import 'package:geolocator/geolocator.dart';

import '../../../core/store.dart';
import '../model/jyotish.dart';

/// Saved birth details and chart preferences.
class BirthStore {
  static String get userName => Store.profile['name'] as String? ?? '';

  static BirthData? load() {
    final j = Store.getJson('birth');
    return j == null ? null : BirthData.fromJson(j);
  }

  static Future<void> save(BirthData b) => Store.setJson('birth', b.toJson());

  static bool get northChart => (Store.raw.getString('chart_style') ?? 'north') == 'north';
  static Future<void> setNorthChart(bool v) => Store.raw.setString('chart_style', v ? 'north' : 'south');

  /// Where "today" is computed: last known location, else the birth place.
  static Future<(double, double, Duration)> todayPlace(BirthData b) async {
    try {
      final p = await Geolocator.getLastKnownPosition().timeout(const Duration(seconds: 2));
      if (p != null) return (p.latitude, p.longitude, DateTime.now().timeZoneOffset);
    } catch (_) {}
    return (b.lat, b.lon, DateTime.now().timeZoneOffset);
  }
}

/// Saved birth details, or null before they're entered.
BirthData? loadBirth() => BirthStore.load();
