import 'package:geolocator/geolocator.dart';

import '../../../core/arch/safe_notifier.dart';
import '../../../core/store.dart';
import '../data/activity.dart';
import '../data/food_engine.dart';
import '../model/food_data.dart';

/// Food tab: today's targets vs eaten, meal log, saved places and meal suggestions.
class FoodController extends SafeNotifier {
  List<Suggestion>? suggestions;
  Ask? lastAsk;
  bool loading = false;

  int get burned => burnedToday();
  Targets get targets => Targets.from(Store.profile, burned: burned);
  Eaten get eaten => Eaten(Store.mealsOn(dayKey()));
  List<Map<String, dynamic>> get meals => Store.mealsOn(dayKey());
  List<Map<String, dynamic>> get places => Store.places;

  Future<Position?> position() => roughPosition();

  /// Ranks dishes and nearby places for [ask] against what's left of today's targets.
  Future<void> suggest(Ask ask) async {
    loading = true;
    notifyListeners();
    final pos = await roughPosition();
    final today = dayKey();
    suggestions = FoodEngine.suggest(
      ask: ask,
      t: targets,
      e: eaten,
      workedOutToday: Store.workoutsOn(today).isNotEmpty || Store.stepsToday > 7000,
      lat: pos?.latitude,
      lng: pos?.longitude,
    );
    lastAsk = ask;
    loading = false;
    notifyListeners();
  }

  void clearSuggestions() {
    suggestions = null;
    notifyListeners();
  }

  /// Logs [d] as eaten (at [place], which then counts a visit).
  Future<void> logMeal(Dish d, [Map<String, dynamic>? place]) async {
    await Store.setMeals([
      ...Store.meals,
      {'date': dayKey(), 'name': d.name, 'place': place?['name'], 'kcal': d.kcal, 'protein': d.protein, 'carbs': d.carbs, 'fat': d.fat, 'fiber': d.fiber},
    ]);
    if (place != null) {
      final all = Store.places;
      for (final p in all) {
        if (p['name'] == place['name']) p['visits'] = (p['visits'] ?? 0) + 1;
      }
      await Store.setPlaces(all);
    }
    suggestions = null;
    notifyListeners();
  }

  Future<void> removeMeal(Map<String, dynamic> m) async {
    final all = Store.meals;
    final idx = all.indexWhere((x) => x['date'] == dayKey() && x['name'] == m['name']);
    if (idx >= 0) all.removeAt(idx);
    await Store.setMeals(all);
    notifyListeners();
  }

  Future<void> addPlace(String name, Position? pos, List<String> dishes) async {
    await Store.setPlaces([...Store.places, {'name': name, 'lat': pos?.latitude, 'lng': pos?.longitude, 'visits': 0, 'dishes': dishes}]);
    notifyListeners();
  }

  Future<void> removePlace(int i) async {
    await Store.setPlaces(Store.places..removeAt(i));
    notifyListeners();
  }

  void refresh() => notifyListeners();
}
