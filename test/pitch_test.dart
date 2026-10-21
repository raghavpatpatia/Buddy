import 'dart:math';
import 'dart:typed_data';

import 'package:buddy_app/features/grow/data/pitch.dart';
import 'package:flutter_test/flutter_test.dart';

/// Flute-like tone: fundamental + weaker harmonics + a little noise.
Float32List tone(double hz, {int sr = 16000, int n = 2048}) {
  final r = Random(1);
  return Float32List.fromList([
    for (var i = 0; i < n; i++)
      (0.6 * sin(2 * pi * hz * i / sr) + 0.2 * sin(4 * pi * hz * i / sr) + 0.08 * sin(6 * pi * hz * i / sr) + 0.02 * (r.nextDouble() - 0.5)),
  ]);
}

void main() {
  final det = PitchDetector();

  test('detects bansuri range notes within 5 cents', () {
    // C4 .. C6, the range of a medium bansuri
    for (final hz in [261.63, 293.66, 329.63, 392.00, 440.00, 523.25, 659.25, 880.00, 1046.50]) {
      final f = det.detect(tone(hz))!;
      final cents = 1200 * log(f / hz) / ln2;
      expect(cents.abs(), lessThan(5), reason: 'expected $hz got $f');
    }
  });

  test('names notes in Western and Sargam', () {
    expect(Note.fromHz(261.63, 0).western, 'C4');
    expect(Note.fromHz(261.63, 0).sargam, 'Sa');
    expect(Note.fromHz(392.0, 0).sargam, 'Pa');
    expect(Note.fromHz(311.13, 0).sargam, 'ga'); // komal Ga
    expect(Note.fromHz(369.99, 0).sargam, 'Ma'); // tivra Ma
    // Sa = D: D4 is Sa, A4 is Pa
    expect(Note.fromHz(293.66, 2).sargam, 'Sa');
    expect(Note.fromHz(440.0, 2).sargam, 'Pa');
    expect(Note.fromHz(445.0, 0).cents, greaterThan(15)); // sharp A4
  });

  test('silence / noise gives no pitch', () {
    final r = Random(2);
    final noise = Float32List.fromList([for (var i = 0; i < 2048; i++) (r.nextDouble() - 0.5) * 0.1]);
    expect(det.detect(noise), isNull);
  });
}
