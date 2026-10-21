import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/math_controller.dart';
import '../model/math.dart';

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
    final lvl = MathController.levelInfo;
    final done = MathController.doneToday;
    final atTop = MathController.atTop;
    return Card(
      color: cs.secondaryContainer.withValues(alpha: 0.6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('🧮 Daily maths', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const Spacer(),
            if (MathController.streak > 0) Text('🔥 ${MathController.streak}', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Text(lvl.emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Level ${MathController.level + 1} of ${mathLevels.length} · ${lvl.name}', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Row(children: [
                  for (var i = 0; i < 3; i++)
                    Container(
                      width: 22,
                      height: 8,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        color: i < MathController.progress ? cs.primary : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  const SizedBox(width: 6),
                  Text(atTop ? 'top level!' : '${3 - MathController.progress} to next level', style: tt.labelSmall),
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

/// One maths problem with hint, check, worked steps and level-up.
class MathSheet extends StatefulWidget {
  final bool daily;
  const MathSheet({super.key, required this.daily});
  @override
  State<MathSheet> createState() => _MathSheetState();
}

class _MathSheetState extends State<MathSheet> {
  late final mc = MathController(daily: widget.daily);
  final _input = TextEditingController();

  @override
  void dispose() {
    mc.dispose();
    _input.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final r = await mc.check(_input.text);
    if (!mounted) return;
    switch (r) {
      case MathCheck.notANumber:
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Type a number (fractions like 3/4 are fine)')));
      case MathCheck.correct:
        HapticFeedback.mediumImpact();
      case MathCheck.wrong:
        HapticFeedback.heavyImpact();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: mc, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final lvl = MathController.levelInfo;
    final p = mc.problem;
    final solved = mc.solved;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text('${lvl.emoji}  Level ${MathController.level + 1} · ${lvl.name}', style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
            const Spacer(),
            Text(mc.daily ? "Today's problem" : 'Practice', style: tt.labelMedium),
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(20)),
            child: Text(p.question, textAlign: TextAlign.center, style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.4)),
          ),
          const SizedBox(height: 16),
          if (solved == null) ...[
            TextField(
              controller: _input,
              autofocus: true,
              textAlign: TextAlign.center,
              style: tt.headlineSmall,
              keyboardType: p.fraction ? TextInputType.text : const TextInputType.numberWithOptions(signed: true, decimal: true),
              decoration: InputDecoration(hintText: p.fraction ? 'e.g. 5/6' : 'Your answer', border: const OutlineInputBorder()),
              onSubmitted: (_) => _check(),
            ),
            if (mc.wrong == 1) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
                child: Text('Not quite, one more try 💪\nHint: ${p.hint}', style: tt.bodyMedium),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _check,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: Text(mc.wrong == 0 ? 'Check' : 'Check again'),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: (solved ? Colors.green : Colors.orange).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  mc.levelUp
                      ? '🚀 Level up! Next: ${lvl.name}'
                      : solved
                          ? '🎉 Correct! +${mc.xp} XP'
                          : 'No worries, here\'s how it works 👇',
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Text('Step by step', style: tt.labelLarge),
                const SizedBox(height: 4),
                for (final (i, s) in p.steps.indexed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text('${i + 1}.  $s', style: tt.bodyLarge),
                  ),
                if (!solved) ...[
                  const SizedBox(height: 6),
                  Text('Answer: ${mc.answerText}', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Missed answers never lower your level. Try a practice one!', style: tt.bodySmall),
                ],
              ]),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () {
                _input.clear();
                mc.practiceAnother();
              },
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
}
