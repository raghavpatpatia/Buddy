import 'package:flutter/material.dart';

import '../../../core/arch/load_state.dart';
import '../../../shared/ui.dart';
import '../controller/brain_settings_controller.dart';
import '../data/cloud_brain.dart';
import '../model/brain_model.dart';
import 'cloud_card.dart';

/// Buddy's brain settings: cloud brain, on-device models, coder, speed test, voice and language.
class BrainSheet extends StatefulWidget {
  const BrainSheet({super.key});
  @override
  State<BrainSheet> createState() => _BrainSheetState();
}

class _BrainSheetState extends State<BrainSheet> {
  final c = BrainSettingsController();

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: c, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (_, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
        Text('Buddy’s brain', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        Text(CloudBrain.enabled ? 'Cloud first (AWS Bedrock), on-device when a limit is hit or offline.' : 'Runs fully on your phone. Your chats never leave it.', style: tt.bodySmall),
        const SizedBox(height: 12),
        CloudCard(onChanged: () => setState(() {})),
        const SizedBox(height: 12),
        Text('Main brain', style: tt.labelLarge),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [ButtonSegment(value: fastBrain.id, label: const Text('Fast')), ButtonSegment(value: smartBrain.id, label: const Text('Smart'))],
          selected: {c.mainBrain.id},
          onSelectionChanged: (v) => c.setMainBrain(v.first),
        ),
        const SizedBox(height: 8),
        for (final m in allBrains) _ModelCard(m: m, c: c),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: c.speedTest.isLoading ? null : c.runSpeedTest,
          icon: c.speedTest.isLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.speed),
          label: Text(c.speedTest.isLoading ? 'Testing… (first run loads the brain)' : 'Test speed'),
        ),
        if (c.speedTest case Ready(:final value)) Padding(padding: const EdgeInsets.only(top: 6), child: Text(value, style: tt.bodySmall)),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Robot voice 🤖'),
          subtitle: const Text('Metallic sci-fi effect on Buddy’s speech'),
          value: c.robotVoice,
          onChanged: c.setRobotVoice,
        ),
        Text('Buddy replies in', style: tt.labelLarge),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [ButtonSegment(value: 'en', label: Text('English')), ButtonSegment(value: 'hinglish', label: Text('Hinglish'))],
          selected: {c.language},
          onSelectionChanged: (v) => c.setLanguage(v.first),
        ),
        const SizedBox(height: 12),
        Text('Voice input language', style: tt.labelLarge),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [ButtonSegment(value: 'en_IN', label: Text('English / Hinglish')), ButtonSegment(value: 'hi_IN', label: Text('Hindi'))],
          selected: {c.voiceLocale},
          onSelectionChanged: (v) => c.setVoiceLocale(v.first),
        ),
      ]),
    );
  }
}

class _ModelCard extends StatelessWidget {
  final BrainModel m;
  final BrainSettingsController c;
  const _ModelCard({required this.m, required this.c});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final d = c.downloads;
    final v = d.progress[m.id];
    final ready = d.ready[m.id] == true;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(m == codeBrain ? Icons.code : Icons.self_improvement),
          const SizedBox(width: 8),
          Expanded(child: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w800))),
          Text('${m.sizeMb} MB', style: tt.bodySmall),
        ]),
        Text(m.purpose, style: tt.bodySmall),
        const SizedBox(height: 8),
        if (m == codeBrain && ready)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Use for coding questions'),
            subtitle: const Text('More accurate, but ~5× slower on this phone. Off = fast brain answers code.'),
            value: c.useCoder,
            onChanged: c.setUseCoder,
          ),
        if (v != null)
          LinearProgressIndicator(value: v, minHeight: 6, borderRadius: BorderRadius.circular(6))
        else if (ready)
          Row(children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 18),
            const SizedBox(width: 6),
            const Expanded(child: Text('Ready')),
            TextButton(onPressed: () => d.delete(m), child: const Text('Delete')),
          ])
        else
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(onPressed: () => d.start(m), icon: const Icon(Icons.download), label: Text(d.errors[m.id] ?? 'Download (Wi-Fi recommended)')),
          ),
      ]),
    );
  }
}
