import 'package:geolocator/geolocator.dart';

import '../../../core/arch/safe_notifier.dart';
import '../../../core/store.dart';
import '../data/activity.dart';
import '../data/food_ai.dart';
import '../data/food_engine.dart';
import '../data/nearby_food.dart';
import '../model/food_data.dart';

/// Food tab: today's targets vs eaten, meal log, saved places and meal suggestions.
class FoodController extends SafeNotifier {
  List<Suggestion>? suggestions;
  /// Extra ideas from the on-device AI; they arrive after [suggestions] (phone models are slow).
  List<Suggestion>? aiSuggestions;
  bool aiLoading = false;
  int _askId = 0;
  Ask? lastAsk;
  bool loading = false;

  int get burned => burnedToday();
  Targets get targets => Targets.from(Store.profile, burned: burned);
  Eaten get eaten => Eaten(Store.mealsOn(dayKey()));
  /// Today's meals in breakfast → lunch → snack → dinner order (older entries without a slot go last).
  List<Map<String, dynamic>> get meals {
    const order = ['b', 'l', 's', 'd'];
    int rank(Map<String, dynamic> m) => m['meal'] == null ? order.length : order.indexOf(m['meal'] as String);
    final all = Store.mealsOn(dayKey());
    final pos = {for (final (i, m) in all.indexed) m: i}; // Dart's sort isn't stable: keep log order within a meal
    return all..sort((a, b) => rank(a) != rank(b) ? rank(a).compareTo(rank(b)) : pos[a]!.compareTo(pos[b]!));
  }
  List<Map<String, dynamic>> get places => Store.places;

  Future<Position?> position() => roughPosition();

  /// Ranks dishes and nearby places for [ask] against what's left of today's targets right away, then
  /// adds the on-device AI's ideas when they're ready.
  Future<void> suggest(Ask ask) async {
    final id = ++_askId;
    loading = true;
    aiSuggestions = null;
    notifyListeners();
    final pos = await roughPosition();
    final today = dayKey();
    final nearby = pos == null || ask.where == 'home' ? <Map<String, dynamic>>[] : await NearbyFood.around(pos.latitude, pos.longitude);
    final t = targets, e = eaten;
    final shown = Map<String, dynamic>.from(Store.getJson('food_shown', {}) as Map)
      ..removeWhere((k, _) => DateTime.now().difference(DateTime.parse(k)).inDays > 2);
    final (slotKcal, slotProtein) = FoodEngine.budget(ask, t, e);
    final recent = [for (var i = 0; i < 3; i++) ...Store.mealsOn(dayKey(DateTime.now().subtract(Duration(days: i)))).map((m) => m['name'] as String)];
    suggestions = FoodEngine.suggest(
      ask: ask,
      t: t,
      e: e,
      workedOutToday: Store.workoutsOn(today).isNotEmpty || Store.stepsToday > 7000,
      lat: pos?.latitude,
      lng: pos?.longitude,
      nearby: nearby,
    );
    // Remember recent picks (last 3 days) so the next list is different
    shown[today] = {...List<String>.from(shown[today] ?? []), ...suggestions!.map((s) => s.dish.name)}.toList();
    await Store.setJson('food_shown', shown);
    lastAsk = ask;
    loading = false;
    aiLoading = true;
    notifyListeners();

    final ai = await FoodAi.suggest(
      ask: ask,
      slotKcal: slotKcal.round(),
      slotProtein: slotProtein.round(),
      kcalLeft: t.kcal - e.kcal,
      profile: Store.profile,
      eatenToday: meals.map((m) => m['name'] as String).toList(),
      avoid: {...recent, for (final v in shown.values) ...List<String>.from(v as List)}.toList(),
      nearby: nearby,
      lat: pos?.latitude,
      lng: pos?.longitude,
    );
    if (id != _askId) return; // asked again or cleared meanwhile
    aiSuggestions = ai;
    aiLoading = false;
    if (ai != null) {
      shown[today] = {...List<String>.from(shown[today] ?? []), ...ai.map((s) => s.dish.name)}.toList();
      await Store.setJson('food_shown', shown);
    }
    notifyListeners();
  }

  void clearSuggestions() {
    _askId++;
    suggestions = null;
    aiSuggestions = null;
    aiLoading = false;
    notifyListeners();
  }

  /// Logs [d] as eaten for [meal] (b/l/s/d, defaults to the time of day) at [place], which then counts a visit.
  /// A nearby restaurant you eat at is saved to your places.
  Future<void> logMeal(Dish d, [Map<String, dynamic>? place, String? meal]) async {
    await Store.setMeals([
      ...Store.meals,
      {'date': dayKey(), 'meal': meal ?? Ask.mealForNow(), 'at': DateTime.now().toIso8601String(), 'name': d.name, 'place': place?['name'], 'kcal': d.kcal, 'protein': d.protein, 'carbs': d.carbs, 'fat': d.fat, 'fiber': d.fiber},
    ]);
    if (place != null) {
      final all = Store.places;
      final saved = all.where((p) => p['name'] == place['name']).toList();
      for (final p in saved) {
        p['visits'] = (p['visits'] ?? 0) + 1;
        if (!(p['dishes'] as List).contains(d.name)) p['dishes'] = [...p['dishes'] as List, d.name];
      }
      if (saved.isEmpty && place['nearby'] == true) {
        all.add({'name': place['name'], 'lat': place['lat'], 'lng': place['lng'], 'visits': 1, 'dishes': [d.name]});
      }
      await Store.setPlaces(all);
    }
    clearSuggestions();
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
