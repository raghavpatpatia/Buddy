import 'dart:math';

import 'package:flutter/material.dart';

import 'store.dart';

/// Body metrics from the profile. Uses Asian/Indian BMI cut-offs (WHO Asia-Pacific / ICMR),
/// Mifflin–St Jeor BMR, and today's measured activity on top of a desk-job baseline.
class Body {
  final double weightKg, heightCm;
  final int age;
  final bool male;
  const Body({required this.weightKg, required this.heightCm, required this.age, required this.male});

  /// Null until height and sex are known (age comes from the birth chart or birth year).
  static Body? fromProfile() {
    final p = Store.profile;
    final h = (p['heightCm'] as num?)?.toDouble();
    final sex = p['sex'] as String?;
    final age = ageYears();
    if (h == null || sex == null || age == null) return null;
    return Body(weightKg: (p['weight'] as num).toDouble(), heightCm: h, age: age, male: sex == 'male');
  }

  /// From the Stars birth details if present, else the profile's birth year.
  static int? ageYears() {
    final b = Store.getJson('birth');
    final now = DateTime.now();
    if (b != null) {
      final dob = DateTime(b['y'], b['mo'], b['d']);
      var a = now.year - dob.year;
      if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) a--;
      return a;
    }
    final y = Store.profile['birthYear'] as int?;
    return y == null ? null : now.year - y;
  }

  double get bmi => weightKg / pow(heightCm / 100, 2);

  /// (label, colour, advice) with Asian cut-offs: <18.5, 18.5–22.9, 23–24.9, ≥25.
  (String, Color, String) get bmiCategory {
    final b = bmi;
    if (b < 18.5) return ('Underweight', Colors.blue, 'Building muscle with a small calorie surplus is recommended.');
    if (b < 23) return ('Healthy', Colors.green, 'You’re in the healthy range for Indians. Maintain or recompose.');
    if (b < 25) return ('Overweight', Colors.orange, 'A gentle calorie deficit and daily activity will bring you into range.');
    return ('Obese', Colors.red, 'A steady calorie deficit, daily walks and low-impact training are recommended.');
  }

  /// Healthy weight range for this height (BMI 18.5–22.9).
  (double, double) get healthyRange {
    final m2 = pow(heightCm / 100, 2).toDouble();
    return (18.5 * m2, 22.9 * m2);
  }

  String get suggestedGoal {
    final b = bmi;
    if (b < 18.5) return 'gain';
    if (b >= 23) return 'lose';
    return 'maintain';
  }

  /// Mifflin–St Jeor basal metabolic rate (kcal/day at complete rest).
  double get bmr => 10 * weightKg + 6.25 * heightCm - 5 * age + (male ? 5 : -161);

  /// Desk-job baseline (BMR × 1.2). Exercise and steps are added on top from what you actually do.
  double get baseline => bmr * 1.2;
}

class DailyTargets {
  final int kcal, baseline, burned, adjust;
  final double protein, carbs, fat, fiber;
  final Body? body;
  const DailyTargets(this.kcal, this.baseline, this.burned, this.adjust, this.protein, this.carbs, this.fat, this.fiber, this.body);

  /// Calories = BMR × 1.2 + today's burned − 500 (lose) / + 300 (gain), never below a safe floor.
  /// Falls back to weight × 30 until height/sex are filled in.
  factory DailyTargets.today({int burned = 0}) {
    final p = Store.profile;
    final goal = p['goal'] as String? ?? 'maintain';
    final body = Body.fromProfile();
    final w = (p['weight'] as num).toDouble();
    final base = body?.baseline.round() ?? (w * 30).round();
    final adjust = goal == 'lose' ? -500 : goal == 'gain' ? 300 : 0;
    final floor = body == null ? 1500 : (body.male ? 1500 : 1200);
    final kcal = max(floor, base + burned + adjust);
    // Protein: 1.6 g/kg when cutting or building, 1.2 g/kg to maintain (ICMR RDA is 0.83 g/kg minimum).
    final protein = w * (goal == 'maintain' ? 1.2 : 1.6);
    final fat = kcal * 0.25 / 9;
    final carbs = max(0.0, (kcal - protein * 4 - fat * 9) / 4);
    final fiber = body?.male == false ? 25.0 : 30.0;
    return DailyTargets(kcal, base, burned, adjust, protein, carbs, fat, fiber, body);
  }
}
