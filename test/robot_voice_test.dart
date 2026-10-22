import 'dart:math';
import 'dart:typed_data';

import 'package:buddy_app/features/talk/data/robot_voice.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List sineWav(int sr, double secs) {
  final n = (sr * secs).round();
  final b = ByteData(44 + n * 2);
  void s(int o, String t) => b.buffer.asUint8List().setRange(o, o + 4, t.codeUnits);
  s(0, 'RIFF'); b.setUint32(4, 36 + n * 2, Endian.little); s(8, 'WAVE'); s(12, 'fmt ');
  b.setUint32(16, 16, Endian.little); b.setUint16(20, 1, Endian.little); b.setUint16(22, 1, Endian.little);
  b.setUint32(24, sr, Endian.little); b.setUint32(28, sr * 2, Endian.little); b.setUint16(32, 2, Endian.little); b.setUint16(34, 16, Endian.little);
  s(36, 'data'); b.setUint32(40, n * 2, Endian.little);
  for (var i = 0; i < n; i++) {
    b.setInt16(44 + i * 2, (sin(2 * pi * 220 * i / sr) * 12000).round(), Endian.little);
  }
  return b.buffer.asUint8List();
}

/// Strongest frequency in [lo, hi] Hz (coarse DFT scan), to check the pitch really went down.
double dominantHz(Uint8List wav, double lo, double hi) {
  final b = ByteData.sublistView(wav);
  final sr = b.getUint32(24, Endian.little);
  final n = min(4096, (wav.length - 44) ~/ 2);
  final x = [for (var i = 0; i < n; i++) b.getInt16(44 + i * 2 + 4000, Endian.little).toDouble()];
  var best = lo, bestP = -1.0;
  for (var f = lo; f <= hi; f += 2) {
    var re = 0.0, im = 0.0;
    for (var i = 0; i < n; i++) {
      re += x[i] * cos(2 * pi * f * i / sr);
      im += x[i] * sin(2 * pi * f * i / sr);
    }
    final p = re * re + im * im;
    if (p > bestP) {
      bestP = p;
      best = f;
    }
  }
  return best;
}

void main() {
  test('shadowize keeps the format, adds a short echo tail and never clips', () {
    final input = sineWav(24000, 0.5);
    final out = shadowize(input);
    final ob = ByteData.sublistView(out);
    expect(String.fromCharCodes(out.sublist(0, 4)), 'RIFF');
    expect(ob.getUint32(24, Endian.little), 24000);
    expect(out.length, greaterThan(input.length));
    expect(out.length - input.length, lessThan(24000 * 0.2 * 2 + 4));
    var peak = 0;
    for (var i = 44; i < out.length; i += 2) {
      peak = max(peak, ob.getInt16(i, Endian.little).abs());
    }
    expect(peak, lessThanOrEqualTo(32767 * 0.91));
    expect(peak, greaterThan(32767 * 0.5));
  });

  test('the voice really gets deeper (220 Hz tone comes out near 185 Hz)', () {
    final out = shadowize(sineWav(24000, 0.6));
    expect(dominantHz(out, 120, 260), inInclusiveRange(175, 195));
  });

  test('rejects non-16-bit audio instead of producing noise', () {
    final bad = sineWav(16000, 0.1);
    ByteData.sublistView(bad).setUint16(34, 8, Endian.little);
    expect(() => shadowize(bad), throwsFormatException);
  });
}
