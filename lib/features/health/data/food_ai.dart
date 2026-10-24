import 'dart:math';

import '../../money/data/ai.dart';
import '../model/food_data.dart';
import 'food_engine.dart';

const _mealNames = {'b': 'breakfast', 'l': 'lunch', 's': 'snack', 'd': 'dinner'};
const _dietNames = {'veg': 'vegetarian', 'egg': 'vegetarian + eggs', 'nonveg': 'eats everything (non-veg ok)'};

/// Fresh meal ideas from the on-device model (or any [AiAsk]) for every request, built around the restaurants near you right now
/// and what's left of today's targets. Returns null when the AI is off, over its limit, offline or answers
/// badly, so the caller can fall back to [FoodEngine].
class FoodAi {
  static Future<List<Suggestion>?> suggest({
    required Ask ask,
    required int slotKcal,
    required int slotProtein,
    required int kcalLeft,
    required Map<String, dynamic> profile,
    required List<String> eatenToday,
    required List<String> avoid,
    required List<Map<String, dynamic>> nearby,
    double? lat,
    double? lng,
    AiAsk ai = askFree,
    int maxPlaces = 10,
  }) async {
    // Closest places first; the model only needs a short list.
    double? kmTo(Map<String, dynamic> p) =>
        lat == null ? null : FoodEngine.distanceKm(lat, lng!, (p['lat'] as num).toDouble(), (p['lng'] as num).toDouble());
    final places = ask.where == 'home' ? <Map<String, dynamic>>[] : ([...nearby]..sort((a, b) => (kmTo(a) ?? 0).compareTo(kmTo(b) ?? 0)));
    final shortlist = places.take(maxPlaces).toList();

    final prompt = StringBuffer()
      ..writeln('Meal: ${_mealNames[ask.meal]} (local time ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')})')
      ..writeln('Hunger: ${ask.hunger}. Craving: ${ask.cuisine}. Where: ${{'any': 'home or out', 'out': 'eat out', 'home': 'home-cooked or order in'}[ask.where]}')
      ..writeln('Diet: ${_dietNames[profile['diet']] ?? profile['diet']}. Goal: ${profile['goal'] ?? 'maintain'}.')
      ..writeln('Budget for this meal: about $slotKcal kcal and $slotProtein g protein ($kcalLeft kcal left for the whole day).')
      ..writeln('Already eaten today: ${eatenToday.isEmpty ? 'nothing yet' : eatenToday.join(', ')}.')
      ..writeln('Do NOT suggest these (recently eaten or already shown): ${avoid.isEmpty ? 'none' : avoid.take(15).join(', ')}.')
      ..writeln('Variety seed: ${Random().nextInt(1 << 20)}');
    if (shortlist.isNotEmpty) {
      prompt.writeln('Restaurants near the user now (name | kind | km):');
      for (final p in shortlist) {
        final km = kmTo(p);
        prompt.writeln('- ${p['name']} | ${(p['cuisines'] as List).join('/')}${p['vegOnly'] == true ? ', pure veg' : ''} | ${km?.toStringAsFixed(1) ?? '?'}');
      }
    }

    // One short line per dish keeps the answer tiny, so a phone model finishes quickly.
    const system = 'You are a nutrition-savvy food buddy in India. Suggest 3 different, realistic dishes for the meal '
        'that fit the budget and diet and suit the time of day. When eating out is allowed, use the listed restaurants, '
        'choosing dishes that place really serves, with the name exactly as listed; write home for home-cooked. '
        'Estimate nutrition per serving. Reply with ONLY 3 lines, no other text, each exactly:\n'
        'dish | restaurant or home | kcal | protein g | carbs g | fat g | fibre g | veg or egg or nonveg';

    final sw = Stopwatch()..start();
    final raw = await ai(system, prompt.toString(), maxTokens: 220);
    // ignore: avoid_print
    print('[BuddyFood] AI answered in ${sw.elapsedMilliseconds} ms: ${raw == null ? 'unavailable' : '${raw.length} chars'}');
    if (raw == null) return null;
    final byName = {for (final p in shortlist) (p['name'] as String).toLowerCase(): p};
    double amount(String s) => double.tryParse(RegExp(r'[\d.]+').firstMatch(s)?.group(0) ?? '') ?? 0;
    final out = <Suggestion>[];
    // Complete lines only, so an answer cut off mid-line still gives the dishes before it.
    for (final line in raw.split('\n')) {
      final f = line.replaceFirst(RegExp(r'^[\s\-*\d.)]+'), '').split('|').map((s) => s.trim()).toList();
      if (f.length < 8 || f[0].isEmpty || amount(f[2]) <= 0) continue;
      final pl = byName[f[1].toLowerCase()];
      final dietTag = f[7].toLowerCase();
      final d = Dish(
        f[0],
        pl == null ? 'Home-style' : (pl['cuisines'] as List).first as String,
        dietTag.contains('non') ? 'nonveg' : dietTag.contains('egg') ? 'egg' : 'veg',
        {ask.meal},
        amount(f[2]).round(),
        amount(f[3]),
        amount(f[4]),
        amount(f[5]),
        amount(f[6]),
      );
      final diet = profile['diet'];
      if (diet != 'nonveg' && d.diet != 'veg' && !(diet == 'egg' && d.diet == 'egg')) continue;
      out.add(Suggestion(d, pl, pl == null ? null : kmTo(pl), 0, const ["Buddy's fresh idea"]));
    }
    if (out.isEmpty) {
      // ignore: avoid_print
      print('[BuddyFood] could not read AI picks from: $raw');
      return null;
    }
    return out;
  }
}
