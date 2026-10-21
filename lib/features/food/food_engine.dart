import 'dart:math';

import '../../core/health.dart';
import '../../core/store.dart';
import 'food_data.dart';

class Targets {
  final int kcal;
  final double protein, carbs, fat, fiber;
  const Targets(this.kcal, this.protein, this.carbs, this.fat, this.fiber);

  /// Calorie & macro targets from BMI/BMR (see core/health.dart) plus what you burned today.
  factory Targets.from(Map<String, dynamic> profile, {int burned = 0}) {
    final d = DailyTargets.today(burned: burned);
    return Targets(d.kcal, d.protein, d.carbs, d.fat, d.fiber);
  }
}

class Eaten {
  int kcal = 0;
  double protein = 0, carbs = 0, fat = 0, fiber = 0;
  Eaten(List<Map<String, dynamic>> meals) {
    for (final m in meals) {
      kcal += (m['kcal'] as num).round();
      protein += (m['protein'] as num);
      carbs += (m['carbs'] as num);
      fat += (m['fat'] as num);
      fiber += (m['fiber'] as num? ?? 0);
    }
  }
}

class Ask {
  String meal; // b l s d
  String hunger; // light normal heavy
  String where; // any out home
  String cuisine;
  Ask({required this.meal, this.hunger = 'normal', this.where = 'any', this.cuisine = 'Any'});

  static String mealForNow() {
    final h = DateTime.now().hour;
    if (h < 11) return 'b';
    if (h < 16) return 'l';
    if (h < 19) return 's';
    return 'd';
  }
}

class Suggestion {
  final Dish dish;
  final Map<String, dynamic>? place;
  final double? km;
  final double score;
  final List<String> reasons;
  Suggestion(this.dish, this.place, this.km, this.score, this.reasons);
}

/// On-device recommender: nutrition gap + your habits + distance + variety.
class FoodEngine {
  static const _mealShare = {'b': 0.25, 'l': 0.35, 's': 0.12, 'd': 0.28};
  static const _hungerMul = {'light': 0.7, 'normal': 1.0, 'heavy': 1.3};

  static double distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    double rad(double d) => d * pi / 180;
    final dLat = rad(lat2 - lat1), dLon = rad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) + cos(rad(lat1)) * cos(rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    return 2 * r * asin(sqrt(a));
  }

  static List<Suggestion> suggest({
    required Ask ask,
    required Targets t,
    required Eaten e,
    required bool workedOutToday,
    double? lat,
    double? lng,
  }) {
    final profile = Store.profile;
    final diet = profile['diet'] as String;
    bool allowed(Dish d) => diet == 'nonveg' || d.diet == 'veg' || (diet == 'egg' && d.diet == 'egg');

    final remainingKcal = max(250, t.kcal - e.kcal);
    final proteinGap = max(0.0, t.protein - e.protein);
    final fiberGap = max(0.0, t.fiber - e.fiber);
    final slotKcal = min(remainingKcal.toDouble(), t.kcal * _mealShare[ask.meal]! * _hungerMul[ask.hunger]!);

    // What was eaten recently (variety)
    final recent = <String>{};
    for (var i = 0; i < 2; i++) {
      final day = dayKey(DateTime.now().subtract(Duration(days: i)));
      recent.addAll(Store.mealsOn(day).map((m) => m['name'] as String));
    }

    final candidates = <(Dish, Map<String, dynamic>?)>[];
    if (ask.where != 'home') {
      for (final pl in Store.places) {
        for (final n in List<String>.from(pl['dishes'] ?? [])) {
          final d = Dish.byName(n);
          if (d != null) candidates.add((d, pl));
        }
      }
    }
    if (ask.where != 'out' || candidates.isEmpty) {
      for (final d in dishes) {
        candidates.add((d, null));
      }
    }

    final out = <Suggestion>[];
    for (final (d, pl) in candidates) {
      if (!allowed(d)) continue;
      final why = <String>[];
      var s = 0.0;

      // 1. Calorie fit for this meal
      final fit = 1 - ((d.kcal - slotKcal).abs() / slotKcal);
      s += fit.clamp(-1, 1) * 2.0;
      if (fit > 0.75) why.add('Fits your ~${slotKcal.round()} kcal budget for this meal');

      // 2. Protein gap
      final pShare = d.protein / max(1, proteinGap);
      if (proteinGap > 20) {
        s += min(pShare, 0.6) * 4;
        if (d.protein >= 25) why.add('High protein (${d.protein.round()} g) — you still need ${proteinGap.round()} g today');
      }
      if (workedOutToday && d.protein >= 20) {
        s += 0.6;
        why.add('Good recovery meal after today\'s workout');
      }

      // 3. Fibre & overall quality
      if (fiberGap > 10 && d.fiber >= 7) {
        s += 0.5;
        why.add('Fibre-rich (${d.fiber.round()} g)');
      }
      s += (d.healthScore - 5) * 0.35;
      if (profile['goal'] == 'lose' && d.kcal > 700) s -= 1;

      // 4. Meal slot / craving
      if (!d.meals.contains(ask.meal)) s -= 1.2;
      if (ask.cuisine != 'Any') {
        if (d.cuisine == ask.cuisine) {
          s += 1.2;
        } else {
          s -= 0.6;
        }
      }

      // 5. Variety
      if (recent.contains(d.name)) {
        s -= 1.0;
        why.add('(you had this recently)');
      }

      // 6. Your places: habit + distance
      double? km;
      if (pl != null) {
        final visits = (pl['visits'] as num? ?? 0).toDouble();
        s += log(1 + visits) * 0.4;
        if (visits >= 3) why.add('You go to ${pl['name']} often');
        if (lat != null && pl['lat'] != null) {
          km = distanceKm(lat, lng!, (pl['lat'] as num).toDouble(), (pl['lng'] as num).toDouble());
          if (km < 1.5) {
            s += 0.8;
            why.add('${pl['name']} is ${km.toStringAsFixed(1)} km away');
          } else if (km < 5) {
            s += 0.3;
          } else if (km > 15) {
            s -= 1.0;
          }
        }
      } else if (ask.where == 'out') {
        s -= 0.5;
      }
      out.add(Suggestion(d, pl, km, s, why));
    }

    out.sort((a, b) => b.score.compareTo(a.score));
    // De-duplicate dishes (keep best place for each)
    final seen = <String>{};
    return out.where((x) => seen.add(x.dish.name)).take(6).toList();
  }
}
