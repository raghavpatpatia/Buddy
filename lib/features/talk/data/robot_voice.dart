import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';

/// Buddy's shadow-knight voice: Android TTS → WAV file → [shadowize] (deeper, heavier, armoured) → playback.
/// Falls back to plain low-pitched TTS if any step fails.
class RobotVoice {
  final FlutterTts tts;
  final _player = AudioPlayer();
  void Function()? onStart, onDone;
  bool robotic = true;

  RobotVoice(this.tts) {
    _player.onPlayerComplete.listen((_) => onDone?.call());
  }

  Future<void> speak(String text) async {
    await stop();
    if (!robotic) return _plain(text);
    try {
      final dir = await getTemporaryDirectory();
      final raw = '${dir.path}/buddy_tts_raw.wav', out = '${dir.path}/buddy_tts_robot.wav';
      await tts.setPitch(0.72);
      await tts.setSpeechRate(0.44);
      await tts.awaitSynthCompletion(true);
      await tts.synthesizeToFile(text, raw, true);
      final input = await File(raw).readAsBytes();
      final processed = await Isolate.run(() => shadowize(input));
      await File(out).writeAsBytes(processed, flush: true);
      onStart?.call();
      await _player.play(DeviceFileSource(out));
    } catch (_) {
      await _plain(text);
    }
  }

  Future<void> _plain(String text) async {
    await tts.setPitch(robotic ? 0.55 : 1.05);
    await tts.setSpeechRate(robotic ? 0.44 : 0.5);
    onStart?.call();
    await tts.speak(text);
  }

  Future<void> stop() async {
    await _player.stop();
    await tts.stop();
  }

  void dispose() => _player.dispose();
}

/// Reads a 16-bit PCM WAV: (sample rate, channels, samples in -1..1).
(int, int, Float64List) _readWav(Uint8List wav) {
  final bd = ByteData.sublistView(wav);
  int? sampleRate, channels, bits, dataOff, dataLen;
  var off = 12; // skip RIFF header
  while (off + 8 <= wav.length) {
    final id = String.fromCharCodes(wav.sublist(off, off + 4));
    final size = bd.getUint32(off + 4, Endian.little);
    if (id == 'fmt ') {
      channels = bd.getUint16(off + 10, Endian.little);
      sampleRate = bd.getUint32(off + 12, Endian.little);
      bits = bd.getUint16(off + 22, Endian.little);
    } else if (id == 'data') {
      dataOff = off + 8;
      dataLen = min(size, wav.length - dataOff);
      break;
    }
    off += 8 + size + (size.isOdd ? 1 : 0);
  }
  if (sampleRate == null || dataOff == null || bits != 16) throw const FormatException('Unsupported WAV');
  final n = dataLen! ~/ 2;
  final x = Float64List(n);
  for (var i = 0; i < n; i++) {
    x[i] = bd.getInt16(dataOff + i * 2, Endian.little) / 32768.0;
  }
  return (sampleRate, channels ?? 1, x);
}

/// Writes mono/stereo 16-bit PCM, normalised to 90% of full scale.
Uint8List _writeWav(int sampleRate, int ch, Float64List y) {
  var peak = 1e-9;
  for (final v in y) {
    if (v.abs() > peak) peak = v.abs();
  }
  final gain = 0.9 / peak;
  final n = y.length;
  final out = Uint8List(44 + n * 2);
  final ob = ByteData.sublistView(out);
  void str(int o, String s) => out.setRange(o, o + 4, s.codeUnits);
  str(0, 'RIFF');
  ob.setUint32(4, 36 + n * 2, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  ob.setUint32(16, 16, Endian.little);
  ob.setUint16(20, 1, Endian.little); // PCM
  ob.setUint16(22, ch, Endian.little);
  ob.setUint32(24, sampleRate, Endian.little);
  ob.setUint32(28, sampleRate * ch * 2, Endian.little);
  ob.setUint16(32, ch * 2, Endian.little);
  ob.setUint16(34, 16, Endian.little);
  str(36, 'data');
  ob.setUint32(40, n * 2, Endian.little);
  for (var i = 0; i < n; i++) {
    ob.setInt16(44 + i * 2, (y[i] * gain * 32767).round().clamp(-32768, 32767), Endian.little);
  }
  return out;
}

/// Turns TTS speech into Buddy's shadow-knight voice and returns a new WAV (same format, a short echo tail added).
/// Pure function (testable). [pitch] < 1 lowers the voice without slowing it down.
Uint8List shadowize(Uint8List wav, {double pitch = 0.84}) {
  final (sr, ch, x) = _readWav(wav);
  final frames = x.length ~/ ch;
  final tail = (sr * 0.18).round();
  final y = Float64List((frames + tail) * ch);
  for (var c = 0; c < ch; c++) {
    double at(int f) => f >= 0 && f < frames ? x[f * ch + c] : 0;
    // 1. Pitch down: two delay-line read heads sweep at (1 - pitch) and cross-fade (Doppler pitch shifter).
    final window = sr * 0.05;
    final shifted = Float64List(frames + tail);
    for (var i = 0; i < shifted.length; i++) {
      var v = 0.0;
      for (final head in const [0.0, 0.5]) {
        final phase = (i * (1 - pitch) / window + head) % 1.0;
        final d = phase * window;
        final pos = i - d;
        final f0 = pos.floor();
        final frac = pos - f0;
        v += (at(f0) * (1 - frac) + at(f0 + 1) * frac) * sin(pi * phase);
      }
      shifted[i] = v;
    }
    // 2. Weight and darkness: boost below ~220 Hz, roll off above ~3.4 kHz.
    final aLow = 1 - exp(-2 * pi * 220 / sr), aHigh = 1 - exp(-2 * pi * 3400 / sr);
    var low = 0.0, h1 = 0.0, h2 = 0.0;
    // 3. Helmet resonance (short metallic comb) and 4. a dark two-tap echo.
    final comb = (sr * 0.0045).round(), e1 = (sr * 0.07).round(), e2 = (sr * 0.14).round();
    final wet = Float64List(shifted.length);
    for (var i = 0; i < shifted.length; i++) {
      final s = shifted[i];
      low += aLow * (s - low);
      var v = s + 1.3 * low;
      h1 += aHigh * (v - h1);
      h2 += aHigh * (h1 - h2);
      v = h2;
      // Soft drive for grit, then a faint 26 Hz tremble that reads as a growl.
      v = _tanh(1.9 * v) / _tanh(1.9);
      v *= 1 - 0.12 * (0.5 + 0.5 * sin(2 * pi * 26 * i / sr));
      if (i >= comb) v += 0.3 * wet[i - comb];
      wet[i] = v;
    }
    for (var i = 0; i < wet.length; i++) {
      var v = wet[i];
      if (i >= e1) v += 0.22 * wet[i - e1];
      if (i >= e2) v += 0.1 * wet[i - e2];
      y[i * ch + c] = v;
    }
  }
  return _writeWav(sr, ch, y);
}

double _tanh(double v) {
  final e = exp(2 * v.clamp(-20, 20));
  return (e - 1) / (e + 1);
}
