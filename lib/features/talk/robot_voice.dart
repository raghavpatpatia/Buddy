import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';

/// Buddy's robot voice: Android TTS → WAV file → ring modulator + metallic comb echo → playback.
/// Falls back to plain (lower-pitched) TTS if any step fails.
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
      await tts.setPitch(0.85);
      await tts.setSpeechRate(0.47);
      await tts.awaitSynthCompletion(true);
      await tts.synthesizeToFile(text, raw, true);
      final input = await File(raw).readAsBytes();
      final processed = await Isolate.run(() => robotize(input));
      await File(out).writeAsBytes(processed, flush: true);
      onStart?.call();
      await _player.play(DeviceFileSource(out));
    } catch (_) {
      await _plain(text);
    }
  }

  Future<void> _plain(String text) async {
    await tts.setPitch(robotic ? 0.7 : 1.05);
    await tts.setSpeechRate(0.5);
    onStart?.call();
    await tts.speak(text);
  }

  Future<void> stop() async {
    await _player.stop();
    await tts.stop();
  }

  void dispose() => _player.dispose();
}

/// Applies the robot effect to a 16-bit PCM WAV and returns a new WAV. Pure function (testable).
Uint8List robotize(Uint8List wav, {double carrierHz = 45, double wet = 0.55, double echoMs = 6, double feedback = 0.45}) {
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
  final ch = channels ?? 1;
  final y = Float64List(n);
  final delay = max(1, (sampleRate * echoMs / 1000).round()) * ch;
  var peak = 1e-9;
  for (var i = 0; i < n; i++) {
    final t = (i ~/ ch) / sampleRate;
    // Ring modulation: multiply the voice by a low sine (the classic sci-fi robot timbre), mixed with the dry voice.
    final ring = x[i] * sin(2 * pi * carrierHz * t);
    var v = wet * ring + (1 - wet) * x[i];
    // Short feedback comb filter gives the hollow, metallic resonance.
    if (i >= delay) v += feedback * y[i - delay];
    y[i] = v;
    if (v.abs() > peak) peak = v.abs();
  }
  final gain = 0.9 / peak;
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
