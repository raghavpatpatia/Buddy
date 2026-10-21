import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/native.dart';
import '../core/store.dart';
import 'brief.dart';
import 'grow/growth.dart';
import 'money/mail.dart';
import 'money/mail_page.dart' show showMailConnect;
import 'ui.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with WidgetsBindingObserver {
  final _p = Store.profile;
  Map<String, dynamic> _perm = {};
  bool _notif = false, _activity = false, _location = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    try {
      await _checkUnsafe();
    } catch (_) {
      // A permission plugin hiccup shouldn't break the Settings screen.
    }
  }

  Future<void> _checkUnsafe() async {
    final n = await Native.permissions();
    final a = await Future.wait([
      Permission.notification.isGranted,
      Permission.activityRecognition.isGranted,
      Permission.locationWhenInUse.isGranted,
    ]);
    if (!mounted) return;
    setState(() {
      _perm = n;
      _notif = a[0];
      _activity = a[1];
      _location = a[2];
    });
  }

  Future<void> _save(String k, dynamic v) async {
    setState(() => _p[k] = v);
    await Store.setProfile(_p);
  }

  Widget _permTile(String title, bool ok, VoidCallback fix) => ListTile(
    leading: Icon(ok ? Icons.check_circle : Icons.error_outline, color: ok ? Colors.green : Theme.of(context).colorScheme.error),
    title: Text(title),
    trailing: ok ? null : TextButton(onPressed: fix, child: const Text('Fix')),
  );

  Widget _slider(String label, String key, double min, double max, int divisions, String Function(int) fmt) => ListTile(
    title: Text('$label: ${fmt(_p[key] as int)}'),
    subtitle: Slider(
      value: (_p[key] as int).toDouble().clamp(min, max),
      min: min,
      max: max,
      divisions: divisions,
      onChanged: (v) => setState(() => _p[key] = v.round()),
      onChangeEnd: (v) => _save(key, v.round()),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final running = _perm['companion'] == true && _perm['battery'] == true;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: pagePadding,
        children: [
          AppCard(
            color: running ? Colors.green.withValues(alpha: 0.12) : Theme.of(context).colorScheme.errorContainer,
            child: Row(
              children: [
                Icon(running ? Icons.bolt : Icons.warning_amber, color: running ? Colors.green : null),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    running ? 'Buddy is running 24x7 in the background' : 'Background running is restricted. Buddy may get killed.',
                  ),
                ),
                if (!running) TextButton(onPressed: () => Native.open('battery'), child: const Text('Fix')),
              ],
            ),
          ),
          const SectionTitle('Profile'),
          AppCard(
            child: Column(
              children: [
                TextFormField(
                  initialValue: _p['name'],
                  decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
                  onChanged: (v) => _save('name', v.trim().isEmpty ? 'friend' : v.trim()),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: '${_p['weight']}',
                  decoration: const InputDecoration(labelText: 'Weight', suffixText: 'kg', border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    final w = double.tryParse(v);
                    if (w != null && w >= 30 && w <= 250) _save('weight', w);
                  },
                ),
                const SizedBox(height: 12),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: Store.profile['heightCm']?.toString() ?? '',
              decoration: const InputDecoration(labelText: 'Height', suffixText: 'cm', border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
              onChanged: (v) {
                final h = double.tryParse(v);
                if (h != null && h >= 120 && h <= 230) _save('heightCm', h);
              },
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                emptySelectionAllowed: true,
                segments: const [ButtonSegment(value: 'male', label: Text('Male')), ButtonSegment(value: 'female', label: Text('Female'))],
                selected: {?(_p['sex'] as String?)},
                onSelectionChanged: (s) => s.isEmpty ? null : _save('sex', s.first),
              ),
            ),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    showSelectedIcon: false, // the ✓ pushed labels like “Maintain” onto 2 lines
                    segments: const [
                      ButtonSegment(value: 'veg', label: Text('Veg')),
                      ButtonSegment(value: 'egg', label: Text('Egg')),
                      ButtonSegment(value: 'nonveg', label: Text('Non-veg')),
                    ],
                    selected: {_p['diet']},
                    onSelectionChanged: (s) => _save('diet', s.first),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    showSelectedIcon: false, // the ✓ pushed labels like “Maintain” onto 2 lines
                    segments: const [
                      ButtonSegment(value: 'lose', label: Text('Lose')),
                      ButtonSegment(value: 'maintain', label: Text('Maintain')),
                      ButtonSegment(value: 'gain', label: Text('Gain')),
                    ],
                    selected: {_p['goal']},
                    onSelectionChanged: (s) => _save('goal', s.first),
                  ),
                ),
              ],
            ),
          ),
          const SectionTitle('Daily growth'),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Growth check'),
                  subtitle: Text(
                    'Learn 1 thing + read 1 story daily. If not done by the deadline, Buddy opens itself '
                    '(max 3×, never during calls, lock screen or Do Not Disturb). Skipping costs ${Store.growthPenaltyXp} XP.',
                  ),
                  value: Store.growthEnabled,
                  onChanged: (v) async {
                    await Store.raw.setBool('growth_enabled', v);
                    await syncGrowth();
                    setState(() {});
                  },
                ),
                if (Store.growthEnabled)
                  ListTile(
                    title: Text(
                      'Deadline: ${Store.growthHour > 12 ? Store.growthHour - 12 : Store.growthHour} ${Store.growthHour >= 12 ? 'PM' : 'AM'}',
                    ),
                    subtitle: Slider(
                      value: Store.growthHour.toDouble(),
                      min: 12,
                      max: 22,
                      divisions: 10,
                      onChanged: (v) => setState(() => Store.raw.setInt('growth_hour', v.round())),
                      onChangeEnd: (_) => syncGrowth(),
                    ),
                  ),
                SwitchListTile(
                  title: const Text('Morning brief'),
                  subtitle: const Text(
                    'Stars, top India / World / Tech headlines and today’s tasks, as one quiet notification. Made on your phone, no server needed.',
                  ),
                  value: briefEnabled,
                  onChanged: (v) async {
                    await Store.raw.setBool('brief_enabled', v);
                    await syncBrief();
                    setState(() {});
                  },
                ),
                if (briefEnabled)
                  ListTile(
                    title: Text('Brief at ${TimeOfDay(hour: briefHour, minute: briefMinute).format(context)}'),
                    trailing: const Icon(Icons.schedule),
                    onTap: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay(hour: briefHour, minute: briefMinute),
                      );
                      if (t == null) return;
                      await Store.raw.setInt('brief_hour', t.hour);
                      await Store.raw.setInt('brief_minute', t.minute);
                      await syncBrief();
                      unawaited(prepareBrief());
                      setState(() {});
                    },
                  ),
              ],
            ),
          ),
          const SectionTitle('Daily goals'),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                _slider('Steps', 'stepGoal', 2000, 20000, 36, (v) => '$v'),
                _slider('Active minutes', 'workoutGoal', 10, 120, 22, (v) => '$v min'),
              ],
            ),
          ),
          const SectionTitle('Accounts'),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: const Icon(Icons.alternate_email),
              title: const Text('Email account'),
              subtitle: Text(MailAccount.address ?? 'Not linked · for bank alerts & Mail tab'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showMailConnect(context).then((_) => setState(() {})),
            ),
          ),
          const SectionTitle('Permissions'),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                _permTile('Notifications', _notif, () => Permission.notification.request().then((_) => _check())),
                _permTile('Unrestricted battery', _perm['battery'] == true, () => Native.open('battery')),
                _permTile('Scroll tracker (Accessibility)', _perm['accessibility'] == true, () => Native.open('accessibility')),
                _permTile('Usage access', _perm['usage'] == true, () => Native.open('usage')),
                _permTile('All files access', _perm['allFiles'] == true, () => Native.open('allFiles')),
                _permTile('Physical activity', _activity, () => Permission.activityRecognition.request().then((_) => _check())),
                _permTile('Location', _location, () => Permission.locationWhenInUse.request().then((_) => _check())),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Buddy keeps all your data on this phone. Nothing is uploaded.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
