import 'dart:math';
import 'dart:typed_data';

/// YIN pitch detector (de Cheveigné & Kawahara 2002), tuned for flute/voice (80–2000 Hz).
class PitchDetector {
  final int sampleRate;
  final double threshold;
  PitchDetector({this.sampleRate = 16000, this.threshold = 0.12});

  /// Returns frequency in Hz or null if no clear pitch.
  double? detect(Float32List x) {
    final w = x.length ~/ 2;
    final minTau = sampleRate ~/ 2000, maxTau = min(sampleRate ~/ 80, w - 1);
    final d = Float32List(maxTau + 1);
    for (var tau = 1; tau <= maxTau; tau++) {
      var s = 0.0;
      for (var i = 0; i < w; i++) {
        final delta = x[i] - x[i + tau];
        s += delta * delta;
      }
      d[tau] = s;
    }
    // Cumulative mean normalised difference
    var running = 0.0;
    d[0] = 1;
    for (var tau = 1; tau <= maxTau; tau++) {
      running += d[tau];
      d[tau] = running == 0 ? 1 : d[tau] * tau / running;
    }
    var tau = -1;
    for (var t = minTau; t <= maxTau; t++) {
      if (d[t] < threshold) {
        while (t + 1 <= maxTau && d[t + 1] < d[t]) {
          t++;
        }
        tau = t;
        break;
      }
    }
    if (tau < 1) return null;
    // Parabolic interpolation for sub-sample accuracy
    var better = tau.toDouble();
    if (tau > 1 && tau < maxTau) {
      final a = d[tau - 1], b = d[tau], c = d[tau + 1];
      final denom = 2 * (2 * b - a - c);
      if (denom != 0) better = tau + (c - a) / denom;
    }
    return sampleRate / better;
  }
}

const _western = ['C', 'C♯', 'D', 'D♯', 'E', 'F', 'F♯', 'G', 'G♯', 'A', 'A♯', 'B'];
const _sargam = ['Sa', 're', 'Re', 'ga', 'Ga', 'ma', 'Ma', 'Pa', 'dha', 'Dha', 'ni', 'Ni'];
const keyNames = _western;

class Note {
  final String western, sargam;
  final int cents; // -50..50
  final double hz;
  const Note(this.western, this.sargam, this.cents, this.hz);

  /// [saKey] 0 = C … 11 = B (the pitch the player calls "Sa").
  factory Note.fromHz(double hz, int saKey) {
    final midi = 69 + 12 * log(hz / 440) / ln2;
    final n = midi.round();
    final octave = n ~/ 12 - 1;
    return Note('${_western[n % 12]}$octave', _sargam[(n - saKey) % 12], ((midi - n) * 100).round(), hz);
  }
}

/// Measures how long one note is held continuously ("long tone" practice).
/// Tolerates short dropouts and one-off pitch glitches so a steady note isn't reset unfairly.
class NoteHold {
  final Duration gap; // silence shorter than this keeps the hold alive
  final int switchFrames; // a new note must be heard this many frames in a row to count
  final void Function(String note, double seconds)? onEnd;
  NoteHold({this.gap = const Duration(milliseconds: 300), this.switchFrames = 3, this.onEnd});

  String? note;
  DateTime? _start, _lastHeard; // timing of the held note
  DateTime? _lastSound; // any sound (incl. unclear/glitch frames); drives the silence gap
  String? _candidate;
  DateTime? _candidateSince;
  int _candidateFrames = 0;
  double best = 0, last = 0;

  bool get active => _start != null;

  /// Seconds of the note being held right now (0 if none).
  double current() => _start == null ? 0 : _lastHeard!.difference(_start!).inMilliseconds / 1000;

  /// Feed every analysed frame. [sound] = above the noise threshold; [heard] = detected note name or null if unclear.
  void update({required bool sound, String? heard, required DateTime at}) {
    if (!sound) {
      if (_lastSound != null && at.difference(_lastSound!) > gap) _end();
      _candidate = null;
      _candidateFrames = 0;
      return;
    }
    if (_start == null) {
      if (heard == null) return;
      _begin(heard, at);
      return;
    }
    if (at.difference(_lastSound!) > gap) {
      // Came back after a real silence: that's a new breath.
      _end();
      if (heard != null) _begin(heard, at);
      return;
    }
    _lastSound = at;
    if (heard == null || heard == note) {
      // Same note (or a frame where pitch was unclear but sound continues).
      _lastHeard = at;
      _candidate = null;
      _candidateFrames = 0;
      return;
    }
    // A different note: only switch once it's stable.
    if (heard == _candidate) {
      _candidateFrames++;
    } else {
      _candidate = heard;
      _candidateSince = at;
      _candidateFrames = 1;
    }
    if (_candidateFrames >= switchFrames) {
      final since = _candidateSince!;
      _end();
      _begin(heard, since);
      _lastHeard = at;
    }
  }

  void _begin(String n, DateTime at) {
    note = n;
    _start = at;
    _lastHeard = at;
    _lastSound = at;
    _candidate = null;
    _candidateFrames = 0;
  }

  void _end() {
    if (_start == null) return;
    final s = current();
    last = s;
    if (s > best) best = s;
    if (s > 0) onEnd?.call(note!, s);
    _start = null;
    _lastHeard = null;
    _lastSound = null;
    note = null;
  }

  /// Finish the current hold (e.g. when the session stops).
  void finish() => _end();

  void reset() {
    _start = null;
    _lastHeard = null;
    _lastSound = null;
    note = null;
    _candidate = null;
    _candidateFrames = 0;
    best = 0;
    last = 0;
  }
}
