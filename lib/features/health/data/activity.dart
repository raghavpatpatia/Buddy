import 'package:geolocator/geolocator.dart';

import '../../../core/store.dart';

/// MET values (energy cost) per workout type.
const mets = {'Walk': 3.5, 'Run': 9.8, 'Gym': 6.0, 'Dance': 6.0, 'Yoga': 2.8, 'Cycling': 7.5, 'Sports': 7.0, 'HIIT': 8.0, 'Other': 4.0};

double get bodyWeightKg => (Store.profile['weight'] as num).toDouble();

/// kcal from today's steps (~0.035 kcal per step at 70 kg) and logged workouts (MET formula).
int burnedToday() {
  final w = bodyWeightKg;
  var k = Store.stepsToday * 0.0005 * w;
  for (final x in Store.workoutsOn(dayKey())) {
    k += (mets[x['type']] ?? 4) * w * (x['minutes'] as num) / 60;
  }
  return k.round();
}

/// Rough location for ranking nearby places; reuses a recent fix so it's instant. Null without permission.
Future<Position?> roughPosition() async {
  try {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
    final last = await Geolocator.getLastKnownPosition();
    if (last != null && DateTime.now().difference(last.timestamp).inMinutes < 30) return last;
    return await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 6)));
  } catch (_) {
    return await Geolocator.getLastKnownPosition();
  }
}
