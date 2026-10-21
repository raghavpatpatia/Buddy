import 'package:buddy_app/features/grow/pitch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime(2026, 1, 1, 10);
  DateTime ms(int m) => t0.add(Duration(milliseconds: m));
  const frame = 64; // ~hop size at 16 kHz / 1024

  test('steady note is timed; silence ends it and records best', () {
    final ended = <double>[];
    final h = NoteHold(onEnd: (_, s) => ended.add(s));
    for (var t = 0; t <= 5000; t += frame) {
      h.update(sound: true, heard: 'Pa', at: ms(t));
    }
    expect(h.current(), closeTo(5.0, 0.07));
    h.update(sound: false, at: ms(5500)); // > 300 ms gap
    expect(h.active, isFalse);
    expect(h.best, closeTo(5.0, 0.07));
    expect(ended.single, closeTo(5.0, 0.07));
  });

  test('short dropout and single glitch frames do not reset the hold', () {
    final h = NoteHold();
    var t = 0;
    for (; t <= 2000; t += frame) {
      h.update(sound: true, heard: 'Sa', at: ms(t));
    }
    h.update(sound: false, at: ms(t + 150)); // 150 ms wobble
    t += 200;
    h.update(sound: true, heard: 'Re', at: ms(t)); // one-frame octave/pitch glitch
    h.update(sound: true, heard: null, at: ms(t += frame)); // unclear pitch, still sounding
    for (; t <= 4000; t += frame) {
      h.update(sound: true, heard: 'Sa', at: ms(t));
    }
    expect(h.note, 'Sa');
    expect(h.current(), greaterThan(3.9));
  });

  test('a stable new note restarts the timer', () {
    final h = NoteHold();
    var t = 0;
    for (; t <= 3000; t += frame) {
      h.update(sound: true, heard: 'Ga', at: ms(t));
    }
    final switchAt = t;
    for (; t <= 4000; t += frame) {
      h.update(sound: true, heard: 'Ma', at: ms(t));
    }
    expect(h.note, 'Ma');
    expect(h.last, closeTo(3.0, 0.1)); // Ga hold was recorded
    expect(h.current(), closeTo((t - frame - switchAt) / 1000, 0.1));
  });

  test('reset clears everything', () {
    final h = NoteHold();
    for (var t = 0; t <= 1000; t += frame) {
      h.update(sound: true, heard: 'Pa', at: ms(t));
    }
    h.finish();
    expect(h.best, greaterThan(0));
    h.reset();
    expect(h.best, 0);
    expect(h.active, isFalse);
  });
}
