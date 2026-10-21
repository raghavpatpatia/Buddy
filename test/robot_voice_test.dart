import 'dart:math';
import 'dart:typed_data';

import 'package:buddy_app/features/talk/robot_voice.dart';
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

void main() {
  test('robotize keeps format/length, changes the sound, never clips', () {
    final input = sineWav(24000, 0.5);
    final out = robotize(input);
    final ib = ByteData.sublistView(input), ob = ByteData.sublistView(out);
    expect(out.length, input.length);
    expect(String.fromCharCodes(out.sublist(0, 4)), 'RIFF');
    expect(ob.getUint32(24, Endian.little), 24000);
    var diff = 0, peak = 0;
    for (var i = 44; i < out.length; i += 2) {
      diff += (ob.getInt16(i, Endian.little) - ib.getInt16(i, Endian.little)).abs();
      peak = max(peak, ob.getInt16(i, Endian.little).abs());
    }
    expect(diff, greaterThan(0));
    expect(peak, lessThanOrEqualTo(32767 * 0.91));
  });

  test('rejects non-16-bit audio instead of producing noise', () {
    final bad = sineWav(16000, 0.1);
    ByteData.sublistView(bad).setUint16(34, 8, Endian.little);
    expect(() => robotize(bad), throwsFormatException);
  });
}
