import 'dart:math';

import 'package:geolocator/geolocator.dart';

import '../../astro/model/places.dart';
import '../model/locations.dart';

/// Nearest known city to the phone's last location, else a timezone guess; asks for location only when [ask].
Future<(String city, String country)> nearUser({bool ask = false}) async {
  try {
    var perm = await Geolocator.checkPermission();
    if (ask && perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.whileInUse || perm == LocationPermission.always) {
      var pos = await Geolocator.getLastKnownPosition().timeout(const Duration(seconds: 3));
      if (pos == null && ask) {
        pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 8)));
      }
      if (pos != null) {
        final city = nearestCity(pos.latitude, pos.longitude);
        if (city != null) return (city, countryOfCity(city));
      }
    }
  } catch (_) {}
  return ('', countryFromOffset(DateTime.now().timeZoneOffset));
}

/// Closest city in the offline list within 150 km, or null.
String? nearestCity(double lat, double lon) {
  String? best;
  var bestKm = 150.0;
  for (final (name, plat, plon, _) in places) {
    final km = _km(lat, lon, plat, plon);
    if (km < bestKm) {
      bestKm = km;
      best = name;
    }
  }
  return best;
}

/// Best guess at the country from the UTC offset; empty when it's ambiguous.
String countryFromOffset(Duration d) => switch (d.inMinutes) {
      330 => 'India',
      345 => 'Nepal',
      360 => 'Bangladesh',
      480 => 'Singapore',
      240 => 'United Arab Emirates',
      _ => '',
    };

double _km(double a1, double o1, double a2, double o2) {
  const r = 6371.0;
  double rad(double d) => d * pi / 180;
  final h = pow(sin(rad(a2 - a1) / 2), 2) + cos(rad(a1)) * cos(rad(a2)) * pow(sin(rad(o2 - o1) / 2), 2);
  return 2 * r * asin(sqrt(h));
}
