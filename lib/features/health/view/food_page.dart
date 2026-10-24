import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../shared/ui.dart';
import '../controller/food_controller.dart';
import '../data/food_engine.dart';
import '../model/food_data.dart';
import 'body_card.dart';

/// Health → Food: targets vs eaten, "What should I eat?", meal log and saved places.
class FoodPage extends StatefulWidget {
  final bool embedded;
  const FoodPage({super.key, this.embedded = false});
  @override
  State<FoodPage> createState() => _FoodPageState();
}

class _FoodPageState extends State<FoodPage> {
  final c = FoodController();
  static const _mealNames = {'b': 'breakfast', 'l': 'lunch', 's': 'a snack', 'd': 'dinner'};
  static const _slotNames = {'b': 'Breakfast', 'l': 'Lunch', 's': 'Snack', 'd': 'Dinner'};

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  Future<void> _askAndSuggest() async {
    final ask = await showModalBottomSheet<Ask>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AskSheet(initial: Ask(meal: Ask.mealForNow())),
    );
    if (ask != null) await c.suggest(ask);
  }

  Future<void> _logMeal(Dish d, [Map<String, dynamic>? place, String? meal]) async {
    await c.logMeal(d, place, meal);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Logged ${d.name} 🍽️')));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: c, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final t = c.targets;
    final e = c.eaten;
    final meals = c.meals;
    final suggestions = c.suggestions;
    final tt = Theme.of(context).textTheme;
    final left = t.kcal - e.kcal;
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: const Text('Food')),
      body: ListView(
        padding: pagePadding.copyWith(top: 12),
        children: [
          BodyCard(burned: c.burned, onChanged: c.refresh),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('Today', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                Text(left >= 0 ? '$left kcal left' : '${-left} kcal over',
                    style: TextStyle(fontWeight: FontWeight.w700, color: left >= 0 ? Colors.green : Colors.red)),
              ]),
              const SizedBox(height: 8),
              _bar('Calories', e.kcal.toDouble(), t.kcal.toDouble(), 'kcal', Colors.orange),
              _bar('Protein', e.protein, t.protein, 'g', Colors.redAccent),
              _bar('Carbs', e.carbs, t.carbs, 'g', Colors.amber),
              _bar('Fat', e.fat, t.fat, 'g', Colors.purpleAccent),
              _bar('Fibre', e.fiber, t.fiber, 'g', Colors.green),
            ]),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: c.loading ? null : _askAndSuggest,
            icon: c.loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome),
            label: Text(c.loading ? 'Thinking…' : 'What should I eat?'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          if (suggestions != null) ...[
            SectionTitle('Top picks for ${_mealNames[c.lastAsk?.meal] ?? 'you'}',
                trailing: TextButton(onPressed: c.clearSuggestions, child: const Text('Clear'))),
            if (c.aiLoading)
              const AppCard(
                child: Row(children: [
                  SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 12),
                  Expanded(child: Text('✨ Buddy is thinking up fresh ideas… they\'ll appear here')),
                ]),
              ),
            for (final s in c.aiSuggestions ?? const <Suggestion>[])
              _SuggestionCard(s: s, rank: 0, onAte: () => _logMeal(s.dish, s.place, c.lastAsk?.meal)),
            if (suggestions.isEmpty)
              const AppCard(child: EmptyState(emoji: '🤔', title: 'No match', subtitle: 'Try "Anywhere" or a different craving.')),
            for (final (i, s) in suggestions.indexed) _SuggestionCard(s: s, rank: i + 1, onAte: () => _logMeal(s.dish, s.place, c.lastAsk?.meal)),
          ],
          SectionTitle('Meals today',
              trailing: TextButton.icon(
                onPressed: () async {
                  final d = await showDialog<Dish>(context: context, builder: (_) => const _DishPicker());
                  if (d != null) _logMeal(d);
                },
                icon: const Icon(Icons.add),
                label: const Text('Log meal'),
              )),
          if (meals.isEmpty)
            const AppCard(child: EmptyState(emoji: '🍽️', title: 'Nothing logged yet', subtitle: 'Log what you eat so suggestions fill your nutrition gaps.'))
          else
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(children: [
                for (final m in meals)
                  ListTile(
                    title: Text(m['name'], style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${_slotNames[m['meal']] != null ? '${_slotNames[m['meal']]} · ' : ''}${m['kcal']} kcal · P ${(m['protein'] as num).round()}g${m['place'] != null ? ' · ${m['place']}' : ''}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => c.removeMeal(m),
                    ),
                  ),
              ]),
            ),
          SectionTitle('My places',
              trailing: TextButton.icon(
                onPressed: () => showDialog(context: context, builder: (_) => _AddPlaceDialog(c: c)),
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('Add place'),
              )),
          if (c.places.isEmpty)
            const AppCard(
              child: EmptyState(
                emoji: '📍',
                title: 'Add places you eat at',
                subtitle: 'Restaurants, canteens, cafés + what you order there. Buddy ranks them by distance and how often you go.',
              ),
            )
          else
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(children: [
                for (final (i, p) in c.places.indexed)
                  ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.storefront)),
                    title: Text(p['name'], style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${p['visits'] ?? 0} visits${p['lat'] == null ? ' · no location' : ''} · ${(p['dishes'] as List).join(', ')}',
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => c.removePlace(i),
                    ),
                  ),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _bar(String label, double v, double max, String unit, Color c) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          SizedBox(width: 70, child: Text(label)),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: (v / max).clamp(0, 1), minHeight: 10, color: c),
            ),
          ),
          SizedBox(width: 92, child: Text(' ${v.round()}/${max.round()} $unit', textAlign: TextAlign.right)),
        ]),
      );
}

class _SuggestionCard extends StatelessWidget {
  final Suggestion s;
  final int rank;
  final VoidCallback onAte;
  const _SuggestionCard({required this.s, required this.rank, required this.onAte});

  @override
  Widget build(BuildContext context) {
    final d = s.dish;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(radius: 14, child: Text(rank == 0 ? '✨' : '$rank', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800))),
            const SizedBox(width: 10),
            Expanded(child: Text(d.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
            _pill('❤ ${d.healthScore.toStringAsFixed(1)}', d.healthScore >= 7 ? Colors.green : d.healthScore >= 5 ? Colors.amber : Colors.red),
          ]),
          const SizedBox(height: 4),
          Text(s.place != null
              ? '📍 ${s.place!['name']}${s.km != null ? ' · ${s.km!.toStringAsFixed(1)} km' : ''}'
              : '🏠 Home-cooked / order in · ${d.cuisine}'),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            _pill('${d.kcal} kcal', Colors.orange),
            _pill('P ${d.protein.round()}g', Colors.redAccent),
            _pill('C ${d.carbs.round()}g', Colors.amber),
            _pill('F ${d.fat.round()}g', Colors.purpleAccent),
            _pill('Fibre ${d.fiber.round()}g', Colors.green),
          ]),
          if (s.reasons.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final r in s.reasons) Text('• $r', style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(onPressed: onAte, icon: const Icon(Icons.check), label: const Text('I ate this')),
          ),
        ]),
      ),
    );
  }

  Widget _pill(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: const TextStyle(fontSize: 12)),
      );
}

class _AskSheet extends StatefulWidget {
  final Ask initial;
  const _AskSheet({required this.initial});
  @override
  State<_AskSheet> createState() => _AskSheetState();
}

class _AskSheetState extends State<_AskSheet> {
  late final Ask a = widget.initial;

  Widget _q(String title, Map<String, String> opts, String value, void Function(String) set) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            for (final e in opts.entries)
              ChoiceChip(label: Text(e.value), selected: value == e.key, onSelected: (_) => setState(() => set(e.key))),
          ]),
        ],
      );

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Quick questions 🍽️', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          _q('Which meal?', {'b': 'Breakfast', 'l': 'Lunch', 's': 'Snack', 'd': 'Dinner'}, a.meal, (v) => a.meal = v),
          _q('How hungry?', {'light': 'A bit', 'normal': 'Normal', 'heavy': 'Starving'}, a.hunger, (v) => a.hunger = v),
          _q('Where?', {'any': 'Anywhere', 'out': 'Eat out (nearby + my places)', 'home': 'Home / order'}, a.where,
              (v) => a.where = v),
          _q('Craving?', {for (final c in cuisines) c: c}, a.cuisine, (v) => a.cuisine = v),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.pop(context, a),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text('Suggest'),
          ),
        ]),
      );
}

class _DishPicker extends StatefulWidget {
  const _DishPicker();
  @override
  State<_DishPicker> createState() => _DishPickerState();
}

class _DishPickerState extends State<_DishPicker> {
  String q = '';
  @override
  Widget build(BuildContext context) {
    final list = dishes.where((d) => d.name.toLowerCase().contains(q.toLowerCase())).toList();
    return AlertDialog(
      title: TextField(decoration: const InputDecoration(hintText: 'Search dish'), onChanged: (v) => setState(() => q = v)),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: ListView(children: [
          for (final d in list)
            ListTile(title: Text(d.name), subtitle: Text('${d.kcal} kcal · P ${d.protein.round()}g'), onTap: () => Navigator.pop(context, d)),
        ]),
      ),
    );
  }
}

class _AddPlaceDialog extends StatefulWidget {
  final FoodController c;
  const _AddPlaceDialog({required this.c});
  @override
  State<_AddPlaceDialog> createState() => _AddPlaceDialogState();
}

class _AddPlaceDialogState extends State<_AddPlaceDialog> {
  final name = TextEditingController();
  final picked = <String>{};
  Position? pos;
  bool locating = false;
  String q = '';

  @override
  Widget build(BuildContext context) {
    final list = dishes.where((d) => d.name.toLowerCase().contains(q.toLowerCase())).toList();
    return AlertDialog(
      title: const Text('Add a place you eat at'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Name (e.g. office canteen)')),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: locating
                ? null
                : () async {
                    setState(() => locating = true);
                    pos = await widget.c.position();
                    setState(() => locating = false);
                  },
            icon: const Icon(Icons.my_location),
            label: Text(pos != null ? 'Location saved ✓' : locating ? 'Locating…' : "I'm here now (save location)"),
          ),
          TextField(decoration: const InputDecoration(hintText: 'What do you order there? (search)'), onChanged: (v) => setState(() => q = v)),
          SizedBox(
            height: 220,
            child: ListView(children: [
              for (final d in list)
                CheckboxListTile(
                  dense: true,
                  value: picked.contains(d.name),
                  title: Text(d.name),
                  onChanged: (v) => setState(() => v! ? picked.add(d.name) : picked.remove(d.name)),
                ),
            ]),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: name.text.trim().isEmpty || picked.isEmpty
              ? null
              : () async {
                  await widget.c.addPlace(name.text.trim(), pos, picked.toList());
                  if (context.mounted) Navigator.pop(context);
                },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
