import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/ui.dart';
import '../controller/practice_controller.dart';
import '../data/pitch.dart';

/// Grow → Practice: sound-activated timer, tuner and long-tone trainer per activity.
class PracticePage extends StatefulWidget {
  final PracticeController? controller;
  const PracticePage({super.key, this.controller});
  @override
  State<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends State<PracticePage> {
  late final c = widget.controller ?? PracticeController();
  bool _hadPb = false;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    if (widget.controller == null) c.dispose();
    super.dispose();
  }

  void _onChange() {
    if (c.newPb && !_hadPb) HapticFeedback.heavyImpact();
    _hadPb = c.newPb;
  }

  Future<void> _start() async {
    if (!await c.start()) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Microphone permission is needed to detect sound.')));
      return;
    }
    HapticFeedback.mediumImpact();
  }

  Future<void> _stop() async {
    final r = await c.stop();
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r.saved ? 'Saved ${_fmt(r.seconds)} of ${c.activity} · +${r.xp} XP 🎉' : 'Too short to save (under 30 s)'),
    ));
  }

  static String _fmt(int s) => '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  Future<void> _addActivity() async {
    final t = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('New practice'),
        content: TextField(controller: t, autofocus: true, decoration: const InputDecoration(hintText: 'e.g. Guitar, Tabla, Coding kata')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, t.text.trim()), child: const Text('Add')),
        ],
      ),
    );
    t.dispose();
    if (name != null) await c.addActivity(name);
  }

  Future<void> _settings() => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => ListenableBuilder(
          listenable: c,
          builder: (context, _) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${c.activity} settings', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Start/stop on sound'),
                subtitle: const Text('Off = plain stopwatch (e.g. dance without music)'),
                value: c.auto,
                onChanged: c.setAuto,
              ),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Show notes & tuner'), value: c.showNotes, onChanged: c.setShowNotes),
              Text('Daily goal: ${c.goalMin} min'),
              Slider(value: c.goalMin.toDouble(), min: 5, max: 120, divisions: 23, onChanged: (v) => c.setGoal(v.round())),
              Text('Sensitivity: ${c.sensitivity.round()} dB above room noise (lower = picks up softer sound)'),
              Slider(value: c.sensitivity, min: 4, max: 30, divisions: 26, onChanged: c.setSensitivity),
              const Text('My Sa (tonic) is'),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final (i, k) in keyNames.indexed) ChoiceChip(label: Text(k), selected: c.saKey == i, onSelected: (_) => c.setSaKey(i)),
              ]),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: c, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final goal = c.goalMin;
    final doneMin = c.todayMin;
    final running = c.running, auto = c.auto, pb = c.personalBest;
    final status = switch (c.phase) {
      PracticePhase.idle => auto ? 'Starts counting when you play' : 'Stopwatch mode',
      PracticePhase.calibrating => 'Listening to the room… stay quiet',
      PracticePhase.playing => auto ? '🎶 Playing, counting' : '⏱ Running',
      PracticePhase.paused => '⏸ Paused, waiting for sound',
    };
    return ListView(padding: pagePadding, children: [
      SizedBox(
        height: 52,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final a in c.activities)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
              child: ChoiceChip(label: Text('${_emoji(a)} $a'), selected: a == c.activity, onSelected: running ? null : (_) => c.select(a)),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 6),
            child: ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('Add'), onPressed: running ? null : _addActivity),
          ),
        ]),
      ),
      Card(
        color: c.phase == PracticePhase.playing ? cs.primaryContainer : cs.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(children: [
            Row(children: [
              Text(status, style: tt.labelLarge),
              const Spacer(),
              IconButton(onPressed: running ? null : _settings, icon: const Icon(Icons.tune), tooltip: 'Practice settings'),
            ]),
            Text(_fmt(c.active.round()), style: tt.displayLarge?.copyWith(fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()])),
            if (running && auto) ...[
              const SizedBox(height: 8),
              _LevelMeter(level: c.level, threshold: c.threshold),
            ],
            if (running && c.showNotes && auto) ...[
              const SizedBox(height: 16),
              _NoteView(note: c.note, saKey: c.saKey),
              const SizedBox(height: 16),
              _HoldView(
                hold: c.hold,
                pb: pb,
                newPb: c.newPb,
                onReset: () {
                  HapticFeedback.selectionClick();
                  c.resetHold();
                },
              ),
            ],
            if (!running && c.showNotes && auto && pb > 0) ...[
              const SizedBox(height: 8),
              Text('🏆 Longest note held: ${pb.toStringAsFixed(1)} s', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton.icon(
                onPressed: running ? _stop : _start,
                style: FilledButton.styleFrom(backgroundColor: running ? cs.error : null),
                icon: Icon(running ? Icons.stop : (auto ? Icons.mic : Icons.play_arrow)),
                label: Text(running ? 'Stop & save' : 'Start ${c.activity}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),
      Row(children: [
        Expanded(
          child: AppCard(
            child: Column(children: [
              Text('$doneMin / $goal min', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              Text('today', style: tt.bodySmall),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: (doneMin / goal).clamp(0, 1), minHeight: 8, borderRadius: BorderRadius.circular(8)),
            ]),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: AppCard(
            child: Column(children: [
              Text('🔥 ${c.streak}', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              Text('day streak', style: tt.bodySmall),
              const SizedBox(height: 16),
            ]),
          ),
        ),
      ]),
      SectionTitle('${c.activity} · last 7 days'),
      AppCard(child: WeekBars(data: [for (final (d, m) in c.week()) (weekdayShort(d), m)], goal: goal, color: cs.primary, emptyText: 'Your practice minutes will show up here.')),
      if (c.showNotes && !running)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Tip: set your Sa in ⚙ (e.g. a C bansuri → Sa = C). Notes show as Sa Re Ga… with komal (re, ga, dha, ni) and tivra (Ma).',
            style: tt.bodySmall,
          ),
        ),
    ]);
  }

  static String _emoji(String a) {
    final l = a.toLowerCase();
    if (l.contains('flute') || l.contains('bansuri')) return '🪈';
    if (l.contains('dance')) return '💃';
    if (l.contains('sing') || l.contains('vocal')) return '🎤';
    if (l.contains('guitar')) return '🎸';
    if (l.contains('tabla') || l.contains('drum')) return '🥁';
    if (l.contains('piano') || l.contains('key')) return '🎹';
    return '⭐';
  }
}

class _LevelMeter extends StatelessWidget {
  final double level, threshold;
  const _LevelMeter({required this.level, required this.threshold});
  @override
  Widget build(BuildContext context) {
    double norm(double db) => ((db + 70) / 70).clamp(0, 1);
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 10,
      child: LayoutBuilder(
        builder: (_, c) => Stack(children: [
          Container(decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(6))),
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: c.maxWidth * norm(level),
            decoration: BoxDecoration(color: level > threshold ? Colors.green : cs.outline, borderRadius: BorderRadius.circular(6)),
          ),
          Positioned(left: c.maxWidth * norm(threshold) - 1, top: 0, bottom: 0, child: Container(width: 2, color: cs.error)),
        ]),
      ),
    );
  }
}

class _NoteView extends StatelessWidget {
  final Note? note;
  final int saKey;
  const _NoteView({required this.note, required this.saKey});
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final n = note;
    final inTune = n != null && n.cents.abs() <= 10;
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(n?.sargam ?? '–', style: tt.displayMedium?.copyWith(fontWeight: FontWeight.w800, color: inTune ? Colors.green : null)),
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(n == null ? '' : '${n.western} · ${n.hz.round()} Hz', style: tt.titleMedium?.copyWith(color: cs.onSurfaceVariant)),
        ),
      ]),
      const SizedBox(height: 8),
      // Tuner: centre = in tune, left = flat, right = sharp
      SizedBox(
        height: 28,
        child: LayoutBuilder(
          builder: (_, c) => Stack(alignment: Alignment.center, children: [
            Container(height: 6, decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(4))),
            Container(width: c.maxWidth * 0.2, height: 6, color: Colors.green.withValues(alpha: 0.4)),
            Container(width: 2, height: 24, color: cs.onSurfaceVariant),
            if (n != null)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 120),
                left: (c.maxWidth / 2) + (n.cents / 50) * (c.maxWidth / 2) - 7,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: inTune ? Colors.green : Colors.orange),
                ),
              ),
          ]),
        ),
      ),
      Row(children: [
        Text('flat', style: tt.labelSmall),
        const Spacer(),
        Text(n == null ? 'play a note' : '${n.cents > 0 ? '+' : ''}${n.cents} cents', style: tt.labelSmall),
        const Spacer(),
        Text('sharp', style: tt.labelSmall),
      ]),
      Text('Sa = ${keyNames[saKey]}', style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
    ]);
  }
}

/// Long-tone trainer: how long the current note has been held, session best and personal best.
class _HoldView extends StatelessWidget {
  final NoteHold hold;
  final double pb;
  final bool newPb;
  final VoidCallback onReset;
  const _HoldView({required this.hold, required this.pb, required this.newPb, required this.onReset});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final cur = hold.current();
    final showing = hold.active ? cur : hold.last;
    // Beating your PB live turns the number gold.
    final beating = hold.active && pb > 0 && cur > pb;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(color: cs.surface.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(hold.active ? 'Holding ${hold.note}' : (hold.last > 0 ? 'Last note held' : 'Hold a note…'), style: tt.labelLarge),
            Text(
              '${showing.toStringAsFixed(1)} s',
              style: tt.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: beating ? Colors.amber.shade700 : null,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              [
                if (hold.best > 0) 'Best now ${hold.best.toStringAsFixed(1)} s',
                if (pb > 0) '🏆 PB ${pb.toStringAsFixed(1)} s',
              ].join('  ·  '),
              style: tt.bodySmall,
            ),
            if (newPb) Text('🎉 New personal best!', style: tt.labelLarge?.copyWith(color: Colors.amber.shade800, fontWeight: FontWeight.w800)),
          ]),
        ),
        Column(children: [
          IconButton.filledTonal(onPressed: onReset, icon: const Icon(Icons.restart_alt), tooltip: 'Reset hold timer'),
          Text('Reset', style: tt.labelSmall),
        ]),
      ]),
    );
  }
}
