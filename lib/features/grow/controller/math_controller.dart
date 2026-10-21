import 'dart:math';

import '../../../core/arch/safe_notifier.dart';
import '../../../core/store.dart';
import '../data/growth_service.dart';
import '../model/lessons.dart' show dayOfYear;
import '../model/math.dart';

/// Outcome of checking an answer.
enum MathCheck { notANumber, wrong, correct }

/// Daily maths: level progress plus one problem (today's fixed one, or random practice).
class MathController extends SafeNotifier {
  MathController({required this.daily}) {
    _newProblem();
  }

  bool daily;
  late MathProblem problem;
  int wrong = 0;
  bool? solved;
  bool levelUp = false;

  static int get level => Store.mathLevel;
  static MathLevel get levelInfo => mathLevels[Store.mathLevel];
  static int get streak => Store.mathStreak;
  static int get progress => Store.mathProgress;
  static bool get doneToday => Store.mathDoneToday;
  static bool get atTop => Store.mathLevel == mathLevels.length - 1;

  int get xp => daily ? 15 : 5;

  void _newProblem() {
    final now = DateTime.now();
    // The daily problem is fixed for the day; practice problems are random.
    final r = daily ? Random(now.year * 1000 + dayOfYear() + Store.mathLevel * 7919) : Random();
    problem = levelInfo.make(r);
    wrong = 0;
    solved = null;
    levelUp = false;
  }

  void practiceAnother() {
    daily = false;
    _newProblem();
    notifyListeners();
  }

  /// Checks [text]; two wrong answers reveal the solution (misses never lower the level).
  Future<MathCheck> check(String text) async {
    final v = parseAnswer(text);
    if (v == null) return MathCheck.notANumber;
    if (isCorrect(problem, v)) {
      if (daily) await Store.mathAttemptedToday();
      levelUp = await Store.mathSolved(maxLevel: mathLevels.length - 1);
      await Store.addXp(xp);
      await growthProgress();
      solved = true;
      notifyListeners();
      return MathCheck.correct;
    }
    wrong++;
    if (wrong >= 2) {
      if (daily) await Store.mathAttemptedToday();
      solved = false;
    }
    notifyListeners();
    return MathCheck.wrong;
  }

  String get answerText {
    final a = problem.answer;
    return a == a.roundToDouble() ? a.round().toString() : a.toStringAsFixed(2);
  }
}
