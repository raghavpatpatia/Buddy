import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:pedometer/pedometer.dart';
import 'package:workmanager/workmanager.dart';

import '../features/brief.dart';
import 'cleaner.dart';
import 'store.dart';

const _tickTask = 'buddyTick';

/// Runs every 1-2 h even when the app is closed (WorkManager, survives reboots).
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    await Store.init();
    try {
      await prepareBrief();
    } catch (_) {}
    try {
      await _sampleSteps();
      final report = await Cleaner.scan();
      await Cleaner.save(report);
      await _maybeNotify(Cleaner.total(report));
    } catch (_) {}
    return true;
  });
}

Future<void> registerBackgroundJobs() async {
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    'buddy-tick',
    _tickTask,
    frequency: const Duration(hours: 1),
    flexInterval: const Duration(minutes: 50), // => runs once somewhere every 1-2 h
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    constraints: Constraints(requiresBatteryNotLow: true),
  );
}

Future<void> _sampleSteps() async {
  try {
    final s = await Pedometer.stepCountStream.first.timeout(const Duration(seconds: 5));
    await Store.recordSteps(s.steps);
  } catch (_) {}
}

/// Only ping when there's a lot to clean, at most once a day, silently.
Future<void> _maybeNotify(int bytes) async {
  if (bytes < 500 * 1024 * 1024) return;
  if (Store.raw.getString('clean_notified') == dayKey()) return;
  final n = FlutterLocalNotificationsPlugin();
  await n.initialize(
    settings: const InitializationSettings(android: AndroidInitializationSettings('@drawable/ic_stat_buddy')),
  );
  await n.show(
    id: 10,
    title: 'Buddy found ${fmtBytes(bytes)} to free',
    body: 'Duplicates, old APKs and caches. Tap to review & clean.',
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'buddy_clean',
        'Cleanup reports',
        channelDescription: 'Daily summary of space Buddy can free',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
      ),
    ),
  );
  await Store.raw.setString('clean_notified', dayKey());
}
