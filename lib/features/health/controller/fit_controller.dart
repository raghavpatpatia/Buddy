import 'dart:async';

import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/arch/safe_notifier.dart';
import '../../../core/store.dart';
import '../data/activity.dart';
import '../model/workout_plan.dart';

/// Fit tab: live steps, today's planned workout, logged workouts and the 7-day history.
class FitController extends SafeNotifier {
  StreamSubscription<StepCount>? _sub;
  int steps = Store.stepsToday;
  String? stepError;

  FitController() {
    _sub = Pedometer.stepCountStream.listen(
      (s) async {
        steps = await Store.recordSteps(s.steps);
        notifyListeners();
      },
      onError: (_) async {
        final granted = await Permission.activityRecognition.isGranted;
        stepError = granted ? 'No step sensor found on this phone. You can still log workouts.' : 'Allow Physical activity to count steps.';
        notifyListeners();
      },
    );
  }

  int get stepGoal => Store.profile['stepGoal'] as int;
  int get workoutGoal => Store.profile['workoutGoal'] as int;
  List<Map<String, dynamic>> get todays => Store.workoutsOn(dayKey());
  int get activeMinutes => todays.fold<int>(0, (a, w) => a + (w['minutes'] as int));
  int get burned => burnedToday();

  Workout get plan => todaysWorkout();
  bool get easy => useEasyVersions;
  int get planMinutes => plan.estMinutes(easy: easy);
  int get planKcal => ((mets[plan.logType] ?? 5) * bodyWeightKg * planMinutes / 60).round();
  bool get planDone => todays.any((x) => x['plan'] == plan.id);

  /// (weekday, steps, workout minutes) for the last 7 days, oldest first.
  List<(DateTime, int, int)> week() {
    final hist = Map<String, dynamic>.from(Store.getJson('steps_hist', {}));
    return [
      for (var i = 6; i >= 0; i--)
        () {
          final d = DateTime.now().subtract(Duration(days: i));
          final k = dayKey(d);
          final wm = Store.workoutsOn(k).fold<int>(0, (a, w) => a + (w['minutes'] as int));
          return (d, i == 0 ? steps : (hist[k] as int? ?? 0), wm);
        }(),
    ];
  }

  Future<void> addWorkout(String type, int minutes) async {
    await Store.addWorkout({'date': dayKey(), 'type': type, 'minutes': minutes, 'at': DateTime.now().toIso8601String()});
    notifyListeners();
  }

  Future<void> removeWorkout(Map<String, dynamic> w) async {
    await Store.removeWorkout(Store.workouts.indexWhere((x) => x['at'] == w['at']));
    notifyListeners();
  }

  /// Asks for the activity permission when that was the problem, then hides the banner.
  Future<void> resolveStepError() async {
    if (stepError?.startsWith('Allow') == true) await Permission.activityRecognition.request();
    stepError = null;
    notifyListeners();
  }

  void refresh() => notifyListeners();

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
