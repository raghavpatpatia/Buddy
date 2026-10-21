import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/store.dart';
import 'body_card.dart';
import 'fit/workout_plan.dart';
import 'fit/workout_session.dart';
import 'ui.dart';

const _mets = {'Walk': 3.5, 'Run': 9.8, 'Gym': 6.0, 'Dance': 6.0, 'Yoga': 2.8, 'Cycling': 7.5, 'Sports': 7.0, 'HIIT': 8.0, 'Other': 4.0};

/// kcal from logged workouts + steps today (MET formula; steps ≈ 0.04 kcal each).
int burnedToday() {
  final w = (Store.profile['weight'] as num).toDouble();
  var k = Store.stepsToday * 0.0005 * w; // ~0.035 kcal per step at 70 kg
  for (final x in Store.workoutsOn(dayKey())) {
    k += (_mets[x['type']] ?? 4) * w * (x['minutes'] as num) / 60;
  }
  return k.round();
}

class FitPage extends StatefulWidget {
  final bool embedded;
  const FitPage({super.key, this.embedded = false});
  @override
  State<FitPage> createState() => _FitPageState();
}

class _FitPageState extends State<FitPage> {
  StreamSubscription<StepCount>? _sub;
  int _steps = Store.stepsToday;
  String? _stepError;

  @override
  void initState() {
    super.initState();
    _sub = Pedometer.stepCountStream.listen(
      (s) async {
        final v = await Store.recordSteps(s.steps);
        if (mounted) setState(() => _steps = v);
      },
      onError: (_) async {
        final granted = await Permission.activityRecognition.isGranted;
        if (mounted) {
          setState(() => _stepError = granted ? 'No step sensor found on this phone. You can still log workouts.' : 'Allow Physical activity to count steps.');
        }
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _addWorkout() async {
    String type = 'Gym';
    double minutes = 30;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text('Log workout'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Wrap(spacing: 6, children: [
              for (final t in _mets.keys) ChoiceChip(label: Text(t), selected: t == type, onSelected: (_) => set(() => type = t)),
            ]),
            const SizedBox(height: 12),
            Text('${minutes.round()} min'),
            Slider(value: minutes, min: 5, max: 180, divisions: 35, onChanged: (v) => set(() => minutes = v)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok == true) {
      await Store.addWorkout({'date': dayKey(), 'type': type, 'minutes': minutes.round(), 'at': DateTime.now().toIso8601String()});
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final prof = Store.profile;
    final stepGoal = prof['stepGoal'] as int;
    final workoutGoal = prof['workoutGoal'] as int;
    final today = Store.workoutsOn(dayKey());
    final mins = today.fold<int>(0, (a, w) => a + (w['minutes'] as int));
    final hist = Map<String, dynamic>.from(Store.getJson('steps_hist', {}));
    final week = [
      for (var i = 6; i >= 0; i--)
        (() {
          final d = DateTime.now().subtract(Duration(days: i));
          final k = dayKey(d);
          final wm = Store.workoutsOn(k).fold<int>(0, (a, w) => a + (w['minutes'] as int));
          return (weekdayShort(d), i == 0 ? _steps : (hist[k] as int? ?? 0), wm);
        })(),
    ];
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: const Text('Fit')),
      body: ListView(padding: pagePadding.copyWith(top: 12), children: [
        _TodaysWorkout(onDone: () => setState(() {})),
        Row(children: [
          Expanded(child: _ring('Steps', _steps, stepGoal, Icons.directions_walk, Colors.teal)),
          const SizedBox(width: 12),
          Expanded(child: _ring('Active min', mins, workoutGoal, Icons.fitness_center, Colors.deepOrange)),
        ]),
        if (_stepError != null)
          InfoBanner(
            icon: Icons.directions_walk,
            text: _stepError!,
            action: _stepError!.startsWith('Allow') ? 'Allow' : 'OK',
            onTap: () async {
              if (_stepError!.startsWith('Allow')) await Permission.activityRecognition.request();
              setState(() => _stepError = null);
            },
          ),
        BodyCard(burned: burnedToday(), onChanged: () => setState(() {})),
        AppCard(
          child: Row(children: [
            const Icon(Icons.local_fire_department, color: Colors.orange, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${burnedToday()} kcal burned', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text('From steps + workouts. Your food targets adjust for this.', style: tt.bodySmall),
              ]),
            ),
          ]),
        ),
        const SectionTitle('Steps · last 7 days'),
        AppCard(
          child: WeekBars(
            data: [for (final (day, steps, _) in week) (day, steps)],
            goal: stepGoal,
            color: Colors.teal,
            emptyText: 'Walk around with your phone and your steps will show up here.',
          ),
        ),
        SectionTitle("Today's workouts",
            trailing: TextButton.icon(onPressed: _addWorkout, icon: const Icon(Icons.add, size: 18), label: Text('Log other · $mins/$workoutGoal min'))),
        if (today.isEmpty)
          const AppCard(child: EmptyState(emoji: '🏃', title: 'No workout yet', subtitle: 'Start today’s guided workout above, or log a walk, game or class with “Log other”.')),
        for (final w in today)
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: ListTile(
              leading: CircleAvatar(backgroundColor: Colors.green.withValues(alpha: 0.15), child: const Icon(Icons.check, color: Colors.green)),
              title: Text('${w['type']}', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${w['minutes']} min'),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  await Store.removeWorkout(Store.workouts.indexWhere((x) => x['at'] == w['at']));
                  setState(() {});
                },
              ),
            ),
          ),
        const SizedBox(height: 80),
      ]),
    );
  }

  Widget _ring(String label, int v, int goal, IconData icon, Color c) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
          child: Column(children: [
            SizedBox(
              width: 100,
              height: 100,
              child: Stack(alignment: Alignment.center, children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: (v / goal).clamp(0, 1),
                    strokeWidth: 10,
                    strokeCap: StrokeCap.round,
                    color: c,
                    backgroundColor: c.withValues(alpha: 0.15),
                  ),
                ),
                Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: c), Text('$v', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18))]),
              ]),
            ),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('goal $goal', style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      );
}

/// Today's planned workout (adapts to your goal & BMI) with one-tap guided start.
class _TodaysWorkout extends StatelessWidget {
  final VoidCallback onDone;
  const _TodaysWorkout({required this.onDone});

  Future<void> _start(BuildContext context, Workout w) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => WorkoutSession(workout: w, easy: useEasyVersions)));
    onDone();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final w = todaysWorkout();
    final easy = useEasyVersions;
    final mins = w.estMinutes(easy: easy);
    final weight = (Store.profile['weight'] as num).toDouble();
    final kcal = ((_mets[w.logType] ?? 5) * weight * mins / 60).round();
    final done = Store.workoutsOn(dayKey()).any((x) => x['plan'] == w.id);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
        color: done ? Colors.green.withValues(alpha: 0.12) : cs.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(done ? 'Today’s workout done ✓' : 'Today’s workout', style: tt.labelLarge),
            const SizedBox(height: 6),
            Row(children: [
              Text(w.emoji, style: const TextStyle(fontSize: 34)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(w.title, style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                  Text('~$mins min · ~$kcal kcal · ${w.rounds > 1 ? '${w.rounds} rounds' : '${w.items.length} moves'}', style: tt.bodySmall),
                ]),
              ),
            ]),
            const SizedBox(height: 8),
            Text(w.why, style: tt.bodyMedium),
            if (easy) ...[
              const SizedBox(height: 4),
              Text('Using knee-friendly, low-impact versions for your BMI.', style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _start(context, w),
              icon: Icon(done ? Icons.replay : Icons.play_arrow),
              label: Text(done ? 'Do it again' : 'Start guided workout'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
          ]),
        ),
      ),
      SizedBox(
        height: 48,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final o in workouts.values.where((o) => o.id != w.id))
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
              child: ActionChip(avatar: Text(o.emoji), label: Text(o.title), onPressed: () => _start(context, o)),
            ),
        ]),
      ),
    ]);
  }
}
