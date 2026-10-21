import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/store.dart';
import '../ui.dart';
import 'pitch.dart';

const _sr = 16000;
const _frame = 2048;
const _silenceGrace = Duration(milliseconds: 2500);

/// Sound-activated practice timer: counts only while you're actually playing.
class PracticePage extends StatefulWidget {
  const PracticePage({super.key});
  @override
  State<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends State<PracticePage> {
  final _rec = AudioRecorder();
  final _pitch = PitchDetector(sampleRate: _sr);
  StreamSubscription<Uint8List>? _sub;
  Timer? _ticker;

  late String _activity = Store.raw.getString('practice_activity') ?? Store.activities.first;
  bool _running = false;
  double _active = 0; // seconds of real playing this session
  double _level = -90, _floor = -60;
  DateTime _lastSound = DateTime(2000);
  DateTime? _calibrateUntil;
  Note? _note;
  late final _hold = NoteHold(onEnd: _onHoldEnd);
  bool _newPb = false;
  final _buf = Float32List(_frame);
  int _bufFill = 0;

  bool get _auto => Store.raw.getBool('pauto_$_activity') ?? true;
  bool get _showNotes => Store.raw.getBool('pnotes_$_activity') ?? !_activity.toLowerCase().contains('dance');
  double get _sensitivity => Store.raw.getDouble('psens') ?? 12;
  int get _saKey => Store.raw.getInt('sa_key') ?? 0;
  /// Sound threshold. The floor is clamped to a realistic mic noise level: a digitally silent
  /// input (noise-suppressed phones, emulators) would otherwise make any rounding noise count as playing.
  double get _threshold => max(_floor, -70) + _sensitivity;
  double get _pb => Store.raw.getDouble('hold_pb_$_activity') ?? 0;
  bool get _playing => !_auto || DateTime.now().difference(_lastSound) < _silenceGrace;

  @override
  void dispose() {
    if (_running) _stop();
    _rec.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_auto && !await _rec.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Microphone permission is needed to detect sound.')));
      }
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      _running = true;
      _active = 0;
      _note = null;
      _lastSound = DateTime(2000);
      _hold.reset();
      _newPb = false;
    });
    WakelockPlus.enable();
    if (_auto) {
      _calibrateUntil = DateTime.now().add(const Duration(milliseconds: 1200));
      _floor = -60;
      final stream = await _rec.startStream(const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: _sr, numChannels: 1));
      _sub = stream.listen(_onAudio);
    }
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() {
        if (_playing && (_calibrateUntil == null || DateTime.now().isAfter(_calibrateUntil!))) _active += 0.1;
        if (!_playing) _note = null;
      });
    });
  }

  void _onAudio(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      _buf[_bufFill++] = data.getInt16(i, Endian.little) / 32768.0;
      if (_bufFill == _frame) {
        _analyse();
        // 50% overlap
        _buf.setRange(0, _frame ~/ 2, _buf, _frame ~/ 2);
        _bufFill = _frame ~/ 2;
      }
    }
  }

  void _analyse() {
    var sum = 0.0;
    for (final v in _buf) {
      sum += v * v;
    }
    final db = 20 * log(sqrt(sum / _frame) + 1e-9) / ln10;
    _level = db;
    final now = DateTime.now();
    if (_calibrateUntil != null && now.isBefore(_calibrateUntil!)) {
      _floor = _floor == -60 ? db : _floor * 0.8 + db * 0.2; // learn room noise
      return;
    }
    final sound = db > _threshold;
    Note? heard;
    if (sound) {
      _lastSound = now;
      if (_showNotes) {
        final hz = _pitch.detect(_buf);
        if (hz != null && hz > 80 && hz < 2200) heard = _note = Note.fromHz(hz, _saKey);
      }
    } else {
      _floor = _floor * 0.995 + db * 0.005; // slowly follow changing room noise
    }
    // Western name includes the octave, so low Sa and high Sa count as different notes.
    if (_showNotes) _hold.update(sound: sound, heard: heard?.western, at: now);
  }

  void _onHoldEnd(String note, double secs) {
    if (secs > _pb && secs >= 1) {
      Store.raw.setDouble('hold_pb_$_activity', secs);
      _newPb = true;
      HapticFeedback.heavyImpact();
    }
  }

  Future<void> _stop() async {
    _hold.finish();
    _ticker?.cancel();
    await _sub?.cancel();
    _sub = null;
    if (await _rec.isRecording()) await _rec.stop();
    WakelockPlus.disable();
    final secs = _active.round();
    _running = false;
    if (secs >= 30) {
      await Store.addPractice(_activity, secs);
      await Store.addXp(min(secs ~/ 60, 60));
    }
    if (mounted) {
      HapticFeedback.mediumImpact();
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(secs >= 30 ? 'Saved ${_fmt(secs)} of $_activity · +${min(secs ~/ 60, 60)} XP 🎉' : 'Too short to save (under 30 s)'),
      ));
    }
  }

  String _fmt(int s) => '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  Future<void> _addActivity() async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New practice'),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(hintText: 'e.g. Guitar, Tabla, Coding kata')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Add')),
        ],
      ),
    );
    if (name == null || name.isEmpty || Store.activities.contains(name)) return;
    await Store.setActivities([...Store.activities, name]);
    _select(name);
  }

  void _select(String a) {
    if (_running) return;
    Store.raw.setString('practice_activity', a);
    setState(() => _activity = a);
  }

  Future<void> _settings() => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => StatefulBuilder(
          builder: (context, set) {
            final goal = Store.practiceGoalMin(_activity);
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$_activity settings', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Start/stop on sound'),
                  subtitle: const Text('Off = plain stopwatch (e.g. dance without music)'),
                  value: _auto,
                  onChanged: (v) => set(() => Store.raw.setBool('pauto_$_activity', v)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show notes & tuner'),
                  value: _showNotes,
                  onChanged: (v) => set(() => Store.raw.setBool('pnotes_$_activity', v)),
                ),
                Text('Daily goal: $goal min'),
                Slider(value: goal.toDouble(), min: 5, max: 120, divisions: 23, onChanged: (v) => set(() => Store.setPracticeGoal(_activity, v.round()))),
                Text('Sensitivity: ${_sensitivity.round()} dB above room noise (lower = picks up softer sound)'),
                Slider(value: _sensitivity, min: 4, max: 30, divisions: 26, onChanged: (v) => set(() => Store.raw.setDouble('psens', v))),
                const Text('My Sa (tonic) is'),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final (i, k) in keyNames.indexed)
                    ChoiceChip(label: Text(k), selected: _saKey == i, onSelected: (_) => set(() => Store.raw.setInt('sa_key', i))),
                ]),
              ]),
            );
          },
        ),
      ).then((_) => setState(() {}));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final today = dayKey();
    final goal = Store.practiceGoalMin(_activity);
    final doneMin = Store.practiceSeconds(today, _activity) ~/ 60;
    final calibrating = _calibrateUntil != null && DateTime.now().isBefore(_calibrateUntil!) && _running && _auto;
    final status = !_running
        ? (_auto ? 'Starts counting when you play' : 'Stopwatch mode')
        : calibrating
            ? 'Listening to the room… stay quiet'
            : _playing
                ? (_auto ? '🎶 Playing, counting' : '⏱ Running')
                : '⏸ Paused, waiting for sound';
    final week = [
      for (var i = 6; i >= 0; i--)
        (() {
          final d = DateTime.now().subtract(Duration(days: i));
          return (weekdayShort(d), Store.practiceSeconds(dayKey(d), _activity) ~/ 60);
        })(),
    ];
    return ListView(padding: pagePadding, children: [
      SizedBox(
        height: 52,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final a in Store.activities)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
              child: ChoiceChip(label: Text('${_emoji(a)} $a'), selected: a == _activity, onSelected: _running ? null : (_) => _select(a)),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 6),
            child: ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('Add'), onPressed: _running ? null : _addActivity),
          ),
        ]),
      ),
      Card(
        color: _running && _playing ? cs.primaryContainer : cs.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(children: [
            Row(children: [
              Text(status, style: tt.labelLarge),
              const Spacer(),
              IconButton(onPressed: _running ? null : _settings, icon: const Icon(Icons.tune), tooltip: 'Practice settings'),
            ]),
            Text(_fmt(_active.round()), style: tt.displayLarge?.copyWith(fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()])),
            if (_running && _auto) ...[
              const SizedBox(height: 8),
              _LevelMeter(level: _level, threshold: _threshold),
            ],
            if (_running && _showNotes && _auto) ...[
              const SizedBox(height: 16),
              _NoteView(note: _note, saKey: _saKey),
              const SizedBox(height: 16),
              _HoldView(
                hold: _hold,
                pb: _pb,
                newPb: _newPb,
                onReset: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _hold.reset();
                    _newPb = false;
                  });
                },
              ),
            ],
            if (!_running && _showNotes && _auto && _pb > 0) ...[
              const SizedBox(height: 8),
              Text('🏆 Longest note held: ${_pb.toStringAsFixed(1)} s', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton.icon(
                onPressed: _running ? _stop : _start,
                style: FilledButton.styleFrom(backgroundColor: _running ? cs.error : null),
                icon: Icon(_running ? Icons.stop : (_auto ? Icons.mic : Icons.play_arrow)),
                label: Text(_running ? 'Stop & save' : 'Start $_activity', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
              Text('🔥 ${Store.practiceStreak(_activity)}', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              Text('day streak', style: tt.bodySmall),
              const SizedBox(height: 16),
            ]),
          ),
        ),
      ]),
      SectionTitle('$_activity · last 7 days'),
      AppCard(child: WeekBars(data: week, goal: goal, color: cs.primary, emptyText: 'Your practice minutes will show up here.')),
      if (_showNotes && !_running)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Tip: set your Sa in ⚙ (e.g. a C bansuri → Sa = C). Notes show as Sa Re Ga… with komal (re, ga, dha, ni) and tivra (Ma).',
            style: tt.bodySmall,
          ),
        ),
    ]);
  }

  String _emoji(String a) {
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
