import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/store.dart';
import '../celebrate.dart' show Confetti;
import 'workout_plan.dart';

/// Guided workout: one exercise at a time, timers, rests, vibration cues; logs itself at the end.
class WorkoutSession extends StatefulWidget {
  final Workout workout;
  final bool easy;
  const WorkoutSession({super.key, required this.workout, required this.easy});
  @override
  State<WorkoutSession> createState() => _WorkoutSessionState();
}

class _WorkoutSessionState extends State<WorkoutSession> {
  late final _steps = widget.workout.steps(easy: widget.easy);
  final _started = DateTime.now();
  int _i = 0;
  bool _rest = false, _paused = false, _done = false;
  late int _left = _steps.first.timed ? _steps.first.seconds : 0;
  Timer? _t;
  int _xp = 0, _minutes = 0;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _t?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  Exercise get _cur => _steps[_i];

  void _tick() {
    if (_paused || _done || !mounted) return;
    final counting = _rest || _cur.timed;
    if (!counting) return; // reps: waits for "Done"
    setState(() => _left--);
    if (_left > 0 && _left <= 3) HapticFeedback.selectionClick();
    if (_left <= 0) _advance();
  }

  void _advance() {
    HapticFeedback.heavyImpact();
    if (_rest) {
      setState(() {
        _rest = false;
        _i++;
        _left = _cur.timed ? _cur.seconds : 0;
      });
      return;
    }
    if (_i >= _steps.length - 1) {
      _finish();
      return;
    }
    setState(() {
      _rest = true;
      _left = widget.workout.restSec;
    });
  }

  Future<void> _finish() async {
    _t?.cancel();
    final mins = max(1, DateTime.now().difference(_started).inSeconds ~/ 60);
    await Store.addWorkout({'date': dayKey(), 'type': widget.workout.logType, 'minutes': mins, 'at': DateTime.now().toIso8601String(), 'plan': widget.workout.id});
    final int xp = 20 + min<int>(mins, 40);
    await Store.addXp(xp);
    HapticFeedback.heavyImpact();
    if (mounted) {
      setState(() {
        _done = true;
        _xp = xp;
        _minutes = mins;
      });
    }
  }

  Future<bool> _confirmQuit() async {
    if (_done) return true;
    final quit = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('End workout?'),
        content: Text('You’ve done ${_i + (_rest ? 1 : 0)} of ${_steps.length} moves. Save what you did so far?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep going')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save & end')),
        ],
      ),
    );
    if (quit == true && _i > 0) await _finish();
    return quit == true;
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    if (_done) return _finishScreen(tt);
    final e = _cur;
    final next = _i + 1 < _steps.length ? _steps[_i + 1] : null;
    final total = _rest ? widget.workout.restSec : (e.timed ? e.seconds : 1);
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
              LinearProgressIndicator(value: (_i + (_rest ? 1 : 0)) / _steps.length, minHeight: 8, borderRadius: BorderRadius.circular(8)),
              const SizedBox(height: 6),
              Text('Move ${_i + 1} of ${_steps.length}', style: tt.labelLarge),
              const Spacer(),
              if (_rest) ...[
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
                      value: (_rest || e.timed) ? _left / total : 1,
                      strokeWidth: 12,
                      strokeCap: StrokeCap.round,
                      color: _rest ? Colors.lightBlue : cs.primary,
                      backgroundColor: cs.surfaceContainerHighest,
                    ),
                  ),
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      (_rest || e.timed) ? (_left >= 60 ? '${_left ~/ 60}:${(_left % 60).toString().padLeft(2, '0')}' : '$_left') : '×${e.reps}',
                      style: tt.displayMedium?.copyWith(fontWeight: FontWeight.w900, fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                    Text((_rest || e.timed) ? 'seconds' : 'reps', style: tt.labelLarge),
                  ]),
                ]),
              ),
              const Spacer(),
              Row(children: [
                IconButton.filledTonal(
                  iconSize: 28,
                  onPressed: () => setState(() => _paused = !_paused),
                  icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                  tooltip: _paused ? 'Resume' : 'Pause',
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _advance,
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                    child: Text(_rest ? 'Skip rest' : (e.timed ? 'Next' : 'Done ✓'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
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
                Text('${widget.workout.title} · $_minutes min · +$_xp XP', textAlign: TextAlign.center, style: tt.titleMedium),
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
