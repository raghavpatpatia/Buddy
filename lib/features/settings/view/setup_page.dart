import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../shared/bot_face.dart';
import '../../backup/view/backup_card.dart';
import '../../../shared/ui.dart';
import '../controller/settings_controller.dart';

/// One-time setup. After "Start Buddy" everything runs on its own, 24x7.
class SetupPage extends StatefulWidget {
  final VoidCallback onDone;
  const SetupPage({super.key, required this.onDone});
  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> with WidgetsBindingObserver {
  final c = SetupController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) c.check(); // back from a settings screen
  }

  Widget _step(String title, String why, bool ok, Future<void> Function() grant, {bool required = false}) => Card(
    color: ok ? Colors.green.withValues(alpha: 0.08) : null,
    child: ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
      leading: Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked, color: ok ? Colors.green : null),
      title: Row(
        children: [
          Flexible(
            child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          if (required && !ok) ...[
            const SizedBox(width: 6),
            Text(
              'REQUIRED',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      subtitle: Text(why, style: const TextStyle(fontSize: 12)),
      trailing: ok
          ? null
          : FilledButton.tonal(
              onPressed: () async {
                await grant();
                await c.check();
              },
              child: const Text('Allow'),
            ),
    ),
  );

  Future<void> _finish() async {
    await c.finish();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: c, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final ready = c.notifications && c.native['battery'] == true;
    final done = [
      c.notifications,
      c.native['battery'],
      c.native['accessibility'],
      c.native['usage'],
      c.native['allFiles'],
      c.activity,
      c.location,
    ].where((v) => v == true).length;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: pagePadding,
          children: [
            const Center(child: BotFace(mood: 0.8, size: 140)),
            Text("Hi! I'm Buddy 👋", textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
            const Text('Set me up once and I\'ll run 24x7 in the background.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            const RestoreOnSetupCard(),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('Permissions', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('$done of 7 ready', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: done / 7, minHeight: 6, borderRadius: BorderRadius.circular(6)),
            const SizedBox(height: 8),
            _step(
              'Notifications',
              'For water & scroll nudges (vibration only, never sound).',
              c.notifications,
              () => Permission.notification.request(),
              required: true,
            ),
            _step(
              'Run unrestricted in background',
              'Lets Buddy stay alive 24x7 without Android killing it.',
              c.native['battery'] == true,
              () => c.openSystem('battery'),
              required: true,
            ),
            _step(
              'Scroll tracker (Accessibility)',
              'Counts Reels/Shorts swipes. Find "Buddy scroll tracker" → turn on.',
              c.native['accessibility'] == true,
              () => c.openSystem('accessibility'),
            ),
            if (c.native['killer'] != null)
              _step(
                'Allow Buddy in ${c.native['killer']}',
                'Your phone\'s own battery manager closes background apps, which switches the scroll tracker off. Allow Buddy there so it stays on.',
                c.killerOpened,
                () => c.openKiller(),
              ),
            _step('Usage access', 'Screen time per app + finds apps you never use.', c.native['usage'] == true, () => c.openSystem('usage')),
            _step(
              'All files access',
              'Lets the cleaner find duplicates, old APKs and caches.',
              c.native['allFiles'] == true,
              () => c.openSystem('allFiles'),
            ),
            _step('Physical activity', 'Counts your steps.', c.activity, () => Permission.activityRecognition.request()),
            _step('Location', 'Suggests food from places near you.', c.location, () => Permission.locationWhenInUse.request()),
            const SectionTitle('About you'),
            TextFormField(
              initialValue: c.profile['name'],
              decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
              onChanged: (v) => c.profile['name'] = v,
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: '${c.profile['weight']}',
              decoration: const InputDecoration(labelText: 'Weight', suffixText: 'kg', border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
              onChanged: (v) => c.profile['weight'] = double.tryParse(v) ?? 70,
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              showSelectedIcon: false, // the ✓ pushed labels like “Maintain” onto 2 lines
              segments: const [
                ButtonSegment(value: 'veg', label: Text('Veg')),
                ButtonSegment(value: 'egg', label: Text('Eggetarian')),
                ButtonSegment(value: 'nonveg', label: Text('Non-veg')),
              ],
              selected: {c.profile['diet']},
              onSelectionChanged: (s) => c.setProfile('diet', s.first),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              showSelectedIcon: false, // the ✓ pushed labels like “Maintain” onto 2 lines
              segments: const [
                ButtonSegment(value: 'lose', label: Text('Lose fat')),
                ButtonSegment(value: 'maintain', label: Text('Maintain')),
                ButtonSegment(value: 'gain', label: Text('Build muscle')),
              ],
              selected: {c.profile['goal']},
              onSelectionChanged: (s) => c.setProfile('goal', s.first),
            ),
            const SizedBox(height: 12),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Xiaomi / Redmi / Poco / Oppo / Vivo / Realme / OnePlus: also enable "Autostart" for Buddy in '
                  'Settings → Apps → Buddy, and lock Buddy in the recent-apps screen. These phones kill background '
                  'apps aggressively.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: ready ? _finish : null,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: Text(ready ? 'Start Buddy 🚀' : 'Allow the REQUIRED items to continue'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
