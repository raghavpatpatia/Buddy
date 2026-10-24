import 'package:buddy_app/core/store.dart';
import 'package:buddy_app/features/health/data/food_ai.dart';
import 'package:buddy_app/features/health/data/food_engine.dart';
import 'package:buddy_app/features/health/data/nearby_food.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
  });

  const t = Targets(2000, 100, 250, 60, 30);

  test('meal share grows when earlier meals were skipped', () {
    expect(FoodEngine.slotFraction('b', const {}), closeTo(0.25, 1e-9));
    expect(FoodEngine.slotFraction('l', const {'b'}), closeTo(0.35 / 0.75, 1e-9));
    expect(FoodEngine.slotFraction('d', const {'b', 'l', 's'}), 1.0);
    // Snack already eaten: dinner gets everything left, not just its 28%
    expect(FoodEngine.slotFraction('d', const {'s'}), 1.0);
  });

  test('nearby restaurants supply dishes matching their cuisine', () {
    final out = FoodEngine.suggest(
      ask: Ask(meal: 'l', where: 'out'),
      t: t,
      e: Eaten(const []),
      workedOutToday: false,
      lat: 12.97,
      lng: 77.59,
      nearby: [
        {'name': 'Dragon Wok', 'lat': 12.971, 'lng': 77.591, 'visits': 0, 'cuisines': ['Chinese'], 'vegOnly': false, 'nearby': true},
      ],
    );
    expect(out, isNotEmpty);
    expect(out.every((s) => s.place?['name'] == 'Dragon Wok' && s.dish.cuisine == 'Chinese'), isTrue);
  });

  test('OSM cuisine tags map to Buddy cuisines', () {
    expect(NearbyFood.cuisinesFor('restaurant', 'south_indian;chinese'), containsAll(['South Indian', 'Chinese']));
    expect(NearbyFood.cuisinesFor('fast_food', ''), ['Fast food']);
  });

  test('breakfast never suggests lunch-only dishes', () {
    final out = FoodEngine.suggest(ask: Ask(meal: 'b'), t: t, e: Eaten(const []), workedOutToday: false);
    expect(out, isNotEmpty);
    expect(out.every((s) => s.dish.meals.contains('b')), isTrue);
  });

  test('restaurant names fill in missing cuisine tags', () {
    expect(NearbyFood.cuisinesFor('restaurant', '', 'Donne Biriyani Palace'), ['North Indian']);
    expect(NearbyFood.cuisinesFor('restaurant', '', 'Mad Doh Sourdough Pizzeria'), containsAll(['Fast food', 'Continental']));
    expect(NearbyFood.cuisinesFor('cafe', '', 'House Of Desserts'), isEmpty);
  });

  test('AI picks are parsed, linked to nearby places and respect the diet', () async {
    String? prompt;
    Future<String?> fake(String system, String p, {int maxTokens = 0}) async {
      prompt = p;
      // A chatty preamble, a non-veg pick and a line cut off mid-way must all be handled.
      return 'Here you go:\n'
          '1. Veg hakka noodles | Dragon Wok | 500 kcal | 12 g | 70 g | 15 g | 5 g | veg\n'
          '2. Chicken momos | Dragon Wok | 400 | 25 | 40 | 12 | 2 | nonveg\n'
          '3. Moong dal chilla | home | 280 | 16 | 34 | 8 | 7 | veg\n'
          '4. Paneer tik';
    }

    final out = await FoodAi.suggest(
      ask: Ask(meal: 'l'),
      slotKcal: 600,
      slotProtein: 30,
      kcalLeft: 1500,
      profile: {'diet': 'veg', 'goal': 'maintain'},
      eatenToday: const ['Poha'],
      avoid: const ['Rajma chawal'],
      nearby: [
        {'name': 'Dragon Wok', 'lat': 12.971, 'lng': 77.591, 'visits': 0, 'cuisines': ['Chinese'], 'vegOnly': false, 'nearby': true},
      ],
      lat: 12.97,
      lng: 77.59,
      ai: fake,
    );
    expect(prompt, contains('Dragon Wok'));
    expect(prompt, contains('Rajma chawal'));
    expect(out!.map((s) => s.dish.name), ['Veg hakka noodles', 'Moong dal chilla']); // non-veg dropped for a vegetarian
    expect(out.first.place?['name'], 'Dragon Wok');
    expect(out.first.km, isNotNull);
    expect(out.first.dish.kcal, 500);
    expect(out.last.place, isNull);
  });

  test('AI unavailable falls back (returns null)', () async {
    final out = await FoodAi.suggest(
      ask: Ask(meal: 'l'), slotKcal: 600, slotProtein: 30, kcalLeft: 1500, profile: {'diet': 'veg'},
      eatenToday: const [], avoid: const [], nearby: const [], ai: (s, p, {int maxTokens = 0}) async => null,
    );
    expect(out, isNull);
  });
}
