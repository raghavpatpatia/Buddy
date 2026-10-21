import 'package:buddy_app/features/astro/model/jyotish.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 2026-10-20 15:00 UTC (Nagpur) — Swiss Ephemeris: Moon 294.592° (Makara), Sun 183.005°, Asc 49.513° (Vrishabha).
  final b = BirthData(name: 't', place: 'Nagpur', year: 2026, month: 10, day: 20, hour: 20, minute: 30, second: 0, tz: 5.5, lat: 21.1458, lon: 79.0882);

  test('chart basics match Swiss Ephemeris reference', () {
    final c = Chart(b);
    expect(b.utc, DateTime.utc(2026, 10, 20, 15));
    expect(rashis[c.moonSign].english, 'Capricorn'); // 294.6° → Makara
    expect(nakshatras[c.nak].name, 'Dhanishta'); // 293°20′–306°40′
    expect(c.pada, 1); // 294.59 − 293.33 = 1.26° → pada 1
    expect(rashis[c.lagnaSign].english, 'Taurus'); // Asc 49.5°
  });

  test('dashas cover 120 years contiguously and contain birth', () {
    final c = Chart(b);
    final md = c.mahadashas();
    expect(md.first.contains(b.utc), isTrue);
    for (var i = 1; i < md.length; i++) {
      expect(md[i].start, md[i - 1].end);
    }
    final total = md.take(9).fold<int>(0, (a, d) => a + d.end.difference(d.start).inMinutes);
    expect(total / 1440 / 365.2425, closeTo(120, 0.001));
    final ad = Chart.antardashas(md[1]);
    expect(ad.first.start, md[1].start);
    expect(ad.last.end.difference(md[1].end).inMinutes.abs(), lessThan(10));
  });

  test('panchang values are in range', () {
    final p = Panchang.at(DateTime(2026, 10, 20, 12), 28.61, 77.21, const Duration(hours: 5, minutes: 30));
    expect(p.tithi, inInclusiveRange(1, 30));
    expect(p.rahuKaal, isNotNull);
    expect(p.sun!.$1.hour, inInclusiveRange(5, 7)); // Delhi sunrise in October ~6:2x
    expect(p.sun!.$2.hour, inInclusiveRange(17, 18));
  });

  test('Mangal dosha: houses from Lagna/Moon/Venus are consistent and verdict is well-formed', () {
    final c = Chart(b);
    final m = c.mangal;
    expect(m.fromLagna, c.house('mars'));
    expect(['none', 'cancelled', 'low', 'present'], contains(m.level));
    if (!m.present) expect(m.level, 'none');
    if (m.present && m.cancellations.isNotEmpty) expect(m.level, 'cancelled');
  });

  test('US vs Indian date reading changes the chart (the bug this fixes)', () {
    // Typed "05/08/1999": Indian = 5 Aug, US = 8 May.
    final india = Chart(BirthData(name: '', place: '', year: 1999, month: 8, day: 5, hour: 10, minute: 0, second: 0, tz: 5.5, lat: 28.6139, lon: 77.2090));
    final us = Chart(BirthData(name: '', place: '', year: 1999, month: 5, day: 8, hour: 10, minute: 0, second: 0, tz: 5.5, lat: 28.6139, lon: 77.2090));
    expect(india.nak == us.nak && india.lagnaSign == us.lagnaSign, isFalse);
  });
}
