import 'dart:async';
import 'dart:math';

import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/arch/safe_notifier.dart';
import '../../../core/store.dart';
import '../model/workout_plan.dart';

/// Where a guided workout is: doing a move, resting between moves, or finished.
enum SessionPhase { exercise, rest, done }

/// Guided workout: steps through moves with timers and rests, then logs itself with XP.
class WorkoutSessionController extends SafeNotifier {
  WorkoutSessionController(this.workout, {required bool easy}) : steps = workout.steps(easy: easy) {
    left = current.timed ? current.seconds : 0;
    WakelockPlus.enable();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  final Workout workout;
  final List<Exercise> steps;
  final _started = DateTime.now();
  Timer? _timer;

  int index = 0, left = 0, xp = 0, minutes = 0;
  SessionPhase phase = SessionPhase.exercise;
  bool paused = false;

  /// Called on the last 3 seconds of a countdown and when a move or rest ends (for haptics).
  void Function(bool big)? onCue;

  Exercise get current => steps[index];
  int get movesDone => index + (phase == SessionPhase.rest ? 1 : 0);

  void _tick() {
    if (paused || phase == SessionPhase.done) return;
    if (phase == SessionPhase.exercise && !current.timed) return; // reps: waits for "Done"
    left--;
    if (left > 0 && left <= 3) onCue?.call(false);
    if (left <= 0) {
      next();
    } else {
      notifyListeners();
    }
  }

  /// Ends the current move or rest (also the "Done" button for rep-based moves).
  void next() {
    onCue?.call(true);
    if (phase == SessionPhase.rest) {
      phase = SessionPhase.exercise;
      index++;
      left = current.timed ? current.seconds : 0;
    } else if (index >= steps.length - 1) {
      finish();
      return;
    } else {
      phase = SessionPhase.rest;
      left = workout.restSec;
    }
    notifyListeners();
  }

  void togglePause() {
    paused = !paused;
    notifyListeners();
  }

  /// Logs the minutes done so far and awards XP.
  Future<void> finish() async {
    if (phase == SessionPhase.done) return;
    _timer?.cancel();
    minutes = max(1, DateTime.now().difference(_started).inSeconds ~/ 60);
    await Store.addWorkout({'date': dayKey(), 'type': workout.logType, 'minutes': minutes, 'at': DateTime.now().toIso8601String(), 'plan': workout.id});
    xp = 20 + min<int>(minutes, 40);
    await Store.addXp(xp);
    phase = SessionPhase.done;
    onCue?.call(true);
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }
}
