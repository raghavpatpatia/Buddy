import 'package:buddy_app/features/astro/model/birth_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('degrees/minutes/seconds round-trip without 60-second overflow', () {
    expect(toDms(28.99999), (29, 0, 0.0));
    final (d, m, s) = toDms(28.9931);
    expect(parseDms('$d', '$m', fmtSeconds(s), 90)!, closeTo(28.9931, 1e-4));
  });

  test('out-of-range coordinates and offsets are rejected', () {
    expect(parseDms('91', '0', '0', 90), isNull);
    expect(parseDms('28', '60', '0', 90), isNull);
    expect(parseDecimalCoords('28.6', '181'), isNull);
    expect(parseTz(negative: false, hours: '5', minutes: '30'), 5.5);
    expect(parseTz(negative: true, hours: '3', minutes: ''), -3);
    expect(parseTz(negative: false, hours: '15', minutes: '0'), isNull);
  });

  test('the first missing piece is reported', () {
    expect(birthInputError(date: null, hour12: 5, minute: 15, second: 13, coords: (29, 77), tz: 5.5), contains('date'));
    expect(birthInputError(date: DateTime(2001, 7, 27), hour12: 13, minute: 15, second: 13, coords: (29, 77), tz: 5.5), contains('time'));
    expect(birthInputError(date: DateTime(2001, 7, 27), hour12: 5, minute: 15, second: 13, coords: null, tz: 5.5), contains('place'));
    expect(birthInputError(date: DateTime(2001, 7, 27), hour12: 5, minute: 15, second: 13, coords: (29, 77), tz: 5.5), isNull);
  });
}
