import 'dart:convert';
import 'dart:io';

import 'package:buddy_app/features/astro/engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reference values: Swiss Ephemeris 2.10 (Moshier), Lahiri sidereal. See test/fixtures/swisseph_lahiri.json.
double diff(double a, double b) {
  final d = ((a - b) % 360 + 540) % 360 - 180;
  return d.abs();
}

void main() {
  final cases = (jsonDecode(File('test/fixtures/swisseph_lahiri.json').readAsStringSync()) as List).cast<Map>();
  // Max allowed error in degrees. Nakshatra pada = 3.333°, so the Moon must be very tight.
  const tol = {'sun': 0.01, 'moon': 0.02, 'mercury': 0.06, 'venus': 0.06, 'mars': 0.06, 'jupiter': 0.03, 'saturn': 0.04, 'rahu': 0.001};

  for (final c in cases) {
    test('positions ${c['utc']}', () {
      final when = DateTime.parse(c['utc']);
      final p = siderealPositions(when);
      final errs = <String, double>{};
      for (final k in tol.keys) {
        errs[k] = diff(p[k]!, (c[k] as num).toDouble());
        expect(errs[k], lessThan(tol[k]!), reason: '$k: ours ${p[k]} vs swe ${c[k]}');
      }
      expect(diff(lahiriAyanamsa(julianDay(when)), (c['ayanamsa'] as num).toDouble()), lessThan(0.001));
      final asc = siderealAscendant(when, (c['lat'] as num).toDouble(), (c['lon'] as num).toDouble());
      expect(diff(asc, (c['asc'] as num).toDouble()), lessThan(0.05), reason: 'asc ours $asc vs ${c['asc']}');
      // ignore: avoid_print
      print('${c['utc']}  ${errs.entries.map((e) => '${e.key} ${(e.value * 3600).toStringAsFixed(0)}″').join('  ')}  asc ${(diff(asc, (c['asc'] as num).toDouble()) * 3600).toStringAsFixed(0)}″');
    });
  }
}
