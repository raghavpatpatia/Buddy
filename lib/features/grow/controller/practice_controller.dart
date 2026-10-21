import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:record/record.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/arch/safe_notifier.dart';
import '../../../core/store.dart';
import '../data/pitch.dart';

/// Where a practice session is: not running, learning room noise, hearing you play, or waiting for sound.
enum PracticePhase { idle, calibrating, playing, paused }

/// Result of stopping a session: seconds counted and XP earned (0 when too short to save).
typedef PracticeResult = ({int seconds, int xp, bool saved});

/// Sound-activated practice timer: counts only while you're actually playing, plus tuner and long-tone trainer.
class PracticeController extends SafeNotifier {
  PracticeController({AudioRecorder? recorder}) : _rec = recorder ?? AudioRecorder();

  static const _sr = 16000, _frame = 2048;
  static const _silenceGrace = Duration(milliseconds: 2500);

  final AudioRecorder _rec;
  final _pitch = PitchDetector(sampleRate: _sr);
  StreamSubscription<Uint8List>? _sub;
  Timer? _ticker;
  final _buf = Float32List(_frame);
  int _bufFill = 0;

  String activity = Store.raw.getString('practice_activity') ?? Store.activities.first;
  bool running = false, newPb = false;
  double active = 0, level = -90;
  double _floor = -60;
  DateTime _lastSound = DateTime(2000);
  DateTime? _calibrateUntil;
  Note? note;
  late final hold = NoteHold(onEnd: _onHoldEnd);

  List<String> get activities => Store.activities;
  bool get auto => Store.raw.getBool('pauto_$activity') ?? true;
  bool get showNotes => Store.raw.getBool('pnotes_$activity') ?? !activity.toLowerCase().contains('dance');
  double get sensitivity => Store.raw.getDouble('psens') ?? 12;
  int get saKey => Store.raw.getInt('sa_key') ?? 0;
  int get goalMin => Store.practiceGoalMin(activity);
  double get personalBest => Store.raw.getDouble('hold_pb_$activity') ?? 0;
  int get todayMin => Store.practiceSeconds(dayKey(), activity) ~/ 60;
  int get streak => Store.practiceStreak(activity);

  /// Sound threshold; the floor is clamped to a realistic mic noise level so digital silence doesn't count as playing.
  double get threshold => max(_floor, -70) + sensitivity;
  bool get _playing => !auto || DateTime.now().difference(_lastSound) < _silenceGrace;
  bool get _calibrating => _calibrateUntil != null && DateTime.now().isBefore(_calibrateUntil!);

  PracticePhase get phase => !running
      ? PracticePhase.idle
      : (auto && _calibrating)
          ? PracticePhase.calibrating
          : _playing
              ? PracticePhase.playing
              : PracticePhase.paused;

  /// Practice minutes for each of the last 7 days, oldest first.
  List<(DateTime, int)> week() => [
        for (var i = 6; i >= 0; i--)
          () {
            final d = DateTime.now().subtract(Duration(days: i));
            return (d, Store.practiceSeconds(dayKey(d), activity) ~/ 60);
          }(),
      ];

  void select(String a) {
    if (running) return;
    Store.raw.setString('practice_activity', a);
    activity = a;
    notifyListeners();
  }

  /// Adds and selects a new activity; false if the name is empty or taken.
  Future<bool> addActivity(String name) async {
    if (name.isEmpty || activities.contains(name)) return false;
    await Store.setActivities([...activities, name]);
    select(name);
    return true;
  }

  Future<void> setAuto(bool v) => _set(() => Store.raw.setBool('pauto_$activity', v));
  Future<void> setShowNotes(bool v) => _set(() => Store.raw.setBool('pnotes_$activity', v));
  Future<void> setGoal(int min) => _set(() => Store.setPracticeGoal(activity, min));
  Future<void> setSensitivity(double v) => _set(() => Store.raw.setDouble('psens', v));
  Future<void> setSaKey(int i) => _set(() => Store.raw.setInt('sa_key', i));

  Future<void> _set(Future<void> Function() write) async {
    await write();
    notifyListeners();
  }

  /// Starts a session; returns false when sound mode needs a microphone permission that was refused.
  Future<bool> start() async {
    if (auto && !await _rec.hasPermission()) return false;
    running = true;
    active = 0;
    note = null;
    _lastSound = DateTime(2000);
    hold.reset();
    newPb = false;
    WakelockPlus.enable();
    if (auto) {
      _calibrateUntil = DateTime.now().add(const Duration(milliseconds: 1200));
      _floor = -60;
      final stream = await _rec.startStream(const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: _sr, numChannels: 1));
      _sub = stream.listen(_onAudio);
    }
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_playing && !_calibrating) active += 0.1;
      if (!_playing) note = null;
      notifyListeners();
    });
    notifyListeners();
    return true;
  }

  void _onAudio(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      _buf[_bufFill++] = data.getInt16(i, Endian.little) / 32768.0;
      if (_bufFill == _frame) {
        _analyse();
        _buf.setRange(0, _frame ~/ 2, _buf, _frame ~/ 2); // 50% overlap
        _bufFill = _frame ~/ 2;
      }
    }
  }

  void _analyse() {
    var sum = 0.0;
    for (final v in _buf) {
      sum += v * v;
    }
    final db = 20 * log(sqrt(sum / _frame) + 1e-9) / ln10;
    level = db;
    final now = DateTime.now();
    if (_calibrating) {
      _floor = _floor == -60 ? db : _floor * 0.8 + db * 0.2; // learn room noise
      return;
    }
    final sound = db > threshold;
    Note? heard;
    if (sound) {
      _lastSound = now;
      if (showNotes) {
        final hz = _pitch.detect(_buf);
        if (hz != null && hz > 80 && hz < 2200) heard = note = Note.fromHz(hz, saKey);
      }
    } else {
      _floor = _floor * 0.995 + db * 0.005; // slowly follow changing room noise
    }
    // The western name includes the octave, so low Sa and high Sa count as different notes.
    if (showNotes) hold.update(sound: sound, heard: heard?.western, at: now);
  }

  void _onHoldEnd(String note, double secs) {
    if (secs > personalBest && secs >= 1) {
      Store.raw.setDouble('hold_pb_$activity', secs);
      newPb = true;
    }
  }

  void resetHold() {
    hold.reset();
    newPb = false;
    notifyListeners();
  }

  /// Stops the session and saves it when at least 30 s were played.
  Future<PracticeResult> stop() async {
    hold.finish();
    _ticker?.cancel();
    await _sub?.cancel();
    _sub = null;
    if (await _rec.isRecording()) await _rec.stop();
    WakelockPlus.disable();
    final secs = active.round();
    running = false;
    final saved = secs >= 30;
    final xp = saved ? min(secs ~/ 60, 60) : 0;
    if (saved) {
      await Store.addPractice(activity, secs);
      await Store.addXp(xp);
    }
    notifyListeners();
    return (seconds: secs, xp: xp, saved: saved);
  }

  @override
  void dispose() {
    if (running) stop();
    _rec.dispose();
    super.dispose();
  }
}
