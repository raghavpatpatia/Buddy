import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/store.dart';
import 'growth.dart';
import 'lessons.dart' show dayOfYear;
import 'math.dart';

/// Compact "Daily maths" card for the Learn tab.
class MathCard extends StatefulWidget {
  const MathCard({super.key});
  @override
  State<MathCard> createState() => _MathCardState();
}

class _MathCardState extends State<MathCard> {
  Future<void> _open({required bool daily}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => MathSheet(daily: daily),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final lvl = mathLevels[Store.mathLevel];
    final done = Store.mathDoneToday;
    final atTop = Store.mathLevel == mathLevels.length - 1;
    return Card(
      color: cs.secondaryContainer.withValues(alpha: 0.6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('🧮 Daily maths', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const Spacer(),
            if (Store.mathStreak > 0) Text('🔥 ${Store.mathStreak}', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Text(lvl.emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Level ${Store.mathLevel + 1} of ${mathLevels.length} · ${lvl.name}', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Row(children: [
                  for (var i = 0; i < 3; i++)
                    Container(
                      width: 22,
                      height: 8,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        color: i < Store.mathProgress ? cs.primary : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  const SizedBox(width: 6),
                  Text(atTop ? 'top level!' : '${3 - Store.mathProgress} to next level', style: tt.labelSmall),
                ]),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: done
                  ? OutlinedButton.icon(
                      onPressed: () => _open(daily: false),
                      icon: const Icon(Icons.replay),
                      label: const Text('✓ Done today · practise more'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                    )
                  : FilledButton.icon(
                      onPressed: () => _open(daily: true),
                      icon: const Icon(Icons.edit_note),
                      label: const Text("Solve today's problem"),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                    ),
            ),
          ]),
        ]),
      ),
    );
  }
}

class MathSheet extends StatefulWidget {
  final bool daily;
  const MathSheet({super.key, required this.daily});
  @override
  State<MathSheet> createState() => _MathSheetState();
}

class _MathSheetState extends State<MathSheet> {
  late bool _daily = widget.daily;
  late MathProblem _p;
  final _input = TextEditingController();
  int _wrong = 0;
  bool? _solved; // null = in progress
  bool _levelUp = false;

  @override
  void initState() {
    super.initState();
    _newProblem();
  }

  void _newProblem() {
    final now = DateTime.now();
    // Daily problem is fixed for the day; practice problems are random.
    final r = _daily ? Random(now.year * 1000 + dayOfYear() + Store.mathLevel * 7919) : Random();
    _p = mathLevels[Store.mathLevel].make(r);
    _input.clear();
    _wrong = 0;
    _solved = null;
    _levelUp = false;
  }

  Future<void> _check() async {
    final v = parseAnswer(_input.text);
    if (v == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Type a number (fractions like 3/4 are fine)')));
      return;
    }
    if (isCorrect(_p, v)) {
      HapticFeedback.mediumImpact();
      if (_daily) await Store.mathAttemptedToday();
      final up = await Store.mathSolved(maxLevel: mathLevels.length - 1);
      await Store.addXp(_daily ? 15 : 5);
      await growthProgress();
      setState(() {
        _solved = true;
        _levelUp = up;
      });
    } else {
      HapticFeedback.heavyImpact();
      setState(() => _wrong++);
      if (_wrong >= 2) {
        if (_daily) await Store.mathAttemptedToday();
        setState(() => _solved = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final lvl = mathLevels[Store.mathLevel];
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text('${lvl.emoji}  Level ${Store.mathLevel + 1} · ${lvl.name}', style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
            const Spacer(),
            Text(_daily ? "Today's problem" : 'Practice', style: tt.labelMedium),
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(20)),
            child: Text(_p.question, textAlign: TextAlign.center, style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.4)),
          ),
          const SizedBox(height: 16),
          if (_solved == null) ...[
            TextField(
              controller: _input,
              autofocus: true,
              textAlign: TextAlign.center,
              style: tt.headlineSmall,
              keyboardType: _p.fraction ? TextInputType.text : const TextInputType.numberWithOptions(signed: true, decimal: true),
              decoration: InputDecoration(hintText: _p.fraction ? 'e.g. 5/6' : 'Your answer', border: const OutlineInputBorder()),
              onSubmitted: (_) => _check(),
            ),
            if (_wrong == 1) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
                child: Text('Not quite, one more try 💪\nHint: ${_p.hint}', style: tt.bodyMedium),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _check,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: Text(_wrong == 0 ? 'Check' : 'Check again'),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: (_solved! ? Colors.green : Colors.orange).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  _levelUp
                      ? '🚀 Level up! Next: ${mathLevels[Store.mathLevel].name}'
                      : _solved!
                          ? '🎉 Correct! +${_daily ? 15 : 5} XP'
                          : 'No worries, here\'s how it works 👇',
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Text('Step by step', style: tt.labelLarge),
                const SizedBox(height: 4),
                for (final (i, s) in _p.steps.indexed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text('${i + 1}.  $s', style: tt.bodyLarge),
                  ),
                if (!_solved!) ...[
                  const SizedBox(height: 6),
                  Text('Answer: ${_fmtAnswer()}', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Missed answers never lower your level. Try a practice one!', style: tt.bodySmall),
                ],
              ]),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () => setState(() {
                _daily = false;
                _newProblem();
              }),
              icon: const Icon(Icons.refresh),
              label: const Text('Practice another (+5 XP)'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done for today')),
          ],
        ]),
      ),
    );
  }

  String _fmtAnswer() {
    final a = _p.answer;
    return a == a.roundToDouble() ? a.round().toString() : a.toStringAsFixed(2);
  }
}
