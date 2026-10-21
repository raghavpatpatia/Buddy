import 'package:buddy_app/core/health.dart';
import 'package:buddy_app/core/store.dart';
import 'package:buddy_app/features/fit/workout_plan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
  });

  test('BMI uses Indian cut-offs and Mifflin–St Jeor BMR', () {
    const b = Body(weightKg: 72, heightCm: 172, age: 25, male: true);
    expect(b.bmi, closeTo(24.34, 0.01));
    expect(b.bmiCategory.$1, 'Overweight'); // 23–24.9 is overweight for Indians (normal for WHO global)
    expect(b.suggestedGoal, 'lose');
    expect(b.bmr, closeTo(10 * 72 + 6.25 * 172 - 5 * 25 + 5, 0.001)); // 1675
    final (lo, hi) = b.healthyRange;
    expect(lo, closeTo(54.7, 0.1));
    expect(hi, closeTo(67.7, 0.1));
  });

  test('targets: BMR × 1.2 + burned ± goal, with a safe floor', () async {
    await Store.setProfile({...Store.profile, 'weight': 72, 'heightCm': 172, 'sex': 'male', 'birthYear': DateTime.now().year - 25, 'goal': 'lose'});
    final t = DailyTargets.today(burned: 200);
    expect(t.baseline, (1675 * 1.2).round());
    expect(t.kcal, t.baseline + 200 - 500);
    expect(t.protein, closeTo(72 * 1.6, 0.01));
    await Store.setProfile({...Store.profile, 'weight': 45, 'heightCm': 150, 'sex': 'female', 'goal': 'lose'});
    expect(DailyTargets.today().kcal, greaterThanOrEqualTo(1200));
  });

  test('age comes from the birth chart when present', () async {
    await Store.setJson('birth', {'y': 2001, 'mo': 7, 'd': 27});
    final now = DateTime.now();
    final expected = now.year - 2001 - ((now.month < 7 || (now.month == 7 && now.day < 27)) ? 1 : 0);
    expect(Body.ageYears(), expected);
  });

  test('weekly plan: dance twice a week, rest-day walk, extra rounds when building muscle', () async {
    await Store.setProfile({...Store.profile, 'goal': 'maintain'});
    final week = [for (var d = 0; d < 7; d++) todaysWorkout(DateTime(2026, 10, 19 + d))]; // Mon..Sun
    expect(week.where((w) => w.logType == 'Dance').length, 2);
    expect(week.last.id, 'walk');
    await Store.setProfile({...Store.profile, 'goal': 'gain'});
    expect(todaysWorkout(DateTime(2026, 10, 19)).rounds, 3);
  });

  test('low-impact versions swap moves', () {
    final w = workouts['hiit']!;
    expect(w.steps(easy: true).map((e) => e.name), contains('Step jacks'));
    expect(w.steps().map((e) => e.name), contains('Jumping jacks'));
  });

  test('dance practice moves to Fit as workouts, once', () async {
    await Store.setActivities(['Flute', 'Dance', 'Singing']);
    await Store.addPractice('Dance', 600);
    await Store.addPractice('Flute', 300);
    await Store.migrateDanceToFit();
    expect(Store.activities, ['Flute', 'Singing']);
    expect(Store.practice.map((p) => p['activity']), ['Flute']);
    expect(Store.workouts.single['type'], 'Dance');
    expect(Store.workouts.single['minutes'], 10);
    await Store.migrateDanceToFit();
    expect(Store.workouts.length, 1);
  });
}
