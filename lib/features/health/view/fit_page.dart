import 'package:flutter/material.dart';

import '../../../shared/ui.dart';
import '../controller/fit_controller.dart';
import '../data/activity.dart';
import '../model/workout_plan.dart';
import 'body_card.dart';
import 'workout_session_page.dart';

/// Health → Fit: steps, today's guided workout, body card, calories burned and workout log.
class FitPage extends StatefulWidget {
  final bool embedded;
  const FitPage({super.key, this.embedded = false});
  @override
  State<FitPage> createState() => _FitPageState();
}

class _FitPageState extends State<FitPage> {
  final c = FitController();

  @override
  void dispose() {
    c.dispose();
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
              for (final t in mets.keys) ChoiceChip(label: Text(t), selected: t == type, onSelected: (_) => set(() => type = t)),
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
    if (ok == true) await c.addWorkout(type, minutes.round());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: c, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final stepGoal = c.stepGoal;
    final workoutGoal = c.workoutGoal;
    final today = c.todays;
    final mins = c.activeMinutes;
    final week = [for (final (d, steps, wm) in c.week()) (weekdayShort(d), steps, wm)];
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: const Text('Fit')),
      body: ListView(padding: pagePadding.copyWith(top: 12), children: [
        _TodaysWorkout(c: c),
        Row(children: [
          Expanded(child: _ring('Steps', c.steps, stepGoal, Icons.directions_walk, Colors.teal)),
          const SizedBox(width: 12),
          Expanded(child: _ring('Active min', mins, workoutGoal, Icons.fitness_center, Colors.deepOrange)),
        ]),
        if (c.stepError case final err?)
          InfoBanner(icon: Icons.directions_walk, text: err, action: err.startsWith('Allow') ? 'Allow' : 'OK', onTap: c.resolveStepError),
        BodyCard(burned: c.burned, onChanged: c.refresh),
        AppCard(
          child: Row(children: [
            const Icon(Icons.local_fire_department, color: Colors.orange, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${c.burned} kcal burned', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
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
                onPressed: () => c.removeWorkout(w),
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
  final FitController c;
  const _TodaysWorkout({required this.c});

  Future<void> _start(BuildContext context, Workout w) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => WorkoutSession(workout: w, easy: c.easy)));
    c.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final w = c.plan;
    final easy = c.easy;
    final mins = c.planMinutes;
    final kcal = c.planKcal;
    final done = c.planDone;
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
