import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/celebrate.dart' show Confetti;
import '../controller/workout_session_controller.dart';
import '../model/workout_plan.dart';

/// Guided workout: one exercise at a time, timers, rests, vibration cues; logs itself at the end.
class WorkoutSession extends StatefulWidget {
  final Workout workout;
  final bool easy;
  const WorkoutSession({super.key, required this.workout, required this.easy});
  @override
  State<WorkoutSession> createState() => _WorkoutSessionState();
}

class _WorkoutSessionState extends State<WorkoutSession> {
  late final c = WorkoutSessionController(widget.workout, easy: widget.easy)..onCue = (big) => big ? HapticFeedback.heavyImpact() : HapticFeedback.selectionClick();

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  Future<bool> _confirmQuit() async {
    if (c.phase == SessionPhase.done) return true;
    final quit = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('End workout?'),
        content: Text('You’ve done ${c.movesDone} of ${c.steps.length} moves. Save what you did so far?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep going')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save & end')),
        ],
      ),
    );
    if (quit == true && c.index > 0) await c.finish();
    return quit == true;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: c, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    if (c.phase == SessionPhase.done) return _finishScreen(tt);
    final e = c.current;
    final rest = c.phase == SessionPhase.rest;
    final left = c.left;
    final next = c.index + 1 < c.steps.length ? c.steps[c.index + 1] : null;
    final total = rest ? widget.workout.restSec : (e.timed ? e.seconds : 1);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && await _confirmQuit() && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.workout.title)),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(children: [
              LinearProgressIndicator(value: c.movesDone / c.steps.length, minHeight: 8, borderRadius: BorderRadius.circular(8)),
              const SizedBox(height: 6),
              Text('Move ${c.index + 1} of ${c.steps.length}', style: tt.labelLarge),
              const Spacer(),
              if (rest) ...[
                Text('Rest', style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w900, color: cs.primary)),
                const SizedBox(height: 4),
                Text('Next: ${next?.name ?? ''}', style: tt.titleMedium),
              ] else ...[
                Text(e.emoji, style: const TextStyle(fontSize: 64)),
                const SizedBox(height: 8),
                Text(e.name, textAlign: TextAlign.center, style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text(e.how, textAlign: TextAlign.center, style: tt.bodyLarge),
              ],
              const SizedBox(height: 24),
              SizedBox.square(
                dimension: 200,
                child: Stack(alignment: Alignment.center, children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: (rest || e.timed) ? left / total : 1,
                      strokeWidth: 12,
                      strokeCap: StrokeCap.round,
                      color: rest ? Colors.lightBlue : cs.primary,
                      backgroundColor: cs.surfaceContainerHighest,
                    ),
                  ),
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      (rest || e.timed) ? (left >= 60 ? '${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')}' : '$left') : '×${e.reps}',
                      style: tt.displayMedium?.copyWith(fontWeight: FontWeight.w900, fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                    Text((rest || e.timed) ? 'seconds' : 'reps', style: tt.labelLarge),
                  ]),
                ]),
              ),
              const Spacer(),
              Row(children: [
                IconButton.filledTonal(
                  iconSize: 28,
                  onPressed: c.togglePause,
                  icon: Icon(c.paused ? Icons.play_arrow : Icons.pause),
                  tooltip: c.paused ? 'Resume' : 'Pause',
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: c.next,
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                    child: Text(rest ? 'Skip rest' : (e.timed ? 'Next' : 'Done ✓'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _finishScreen(TextTheme tt) => Scaffold(
        body: Stack(children: [
          const Positioned.fill(child: IgnorePointer(child: Confetti())),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(widget.workout.emoji, textAlign: TextAlign.center, style: const TextStyle(fontSize: 72)),
                const SizedBox(height: 12),
                Text('Workout complete!', textAlign: TextAlign.center, style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text('${widget.workout.title} · ${c.minutes} min · +${c.xp} XP', textAlign: TextAlign.center, style: tt.titleMedium),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  child: const Text('Done'),
                ),
              ]),
            ),
          ),
        ]),
      );
}
