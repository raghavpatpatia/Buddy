import 'dart:async';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/background.dart';
import 'core/native.dart';
import 'core/store.dart';
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.init();
  await Store.migrateDanceToFit();
  runApp(const BuddyApp());
  if (Store.raw.getBool('setup_done') == true) {
    // Idempotent: make sure the 24x7 companion and background jobs are alive.
    // Done after the first frame so app start isn't blocked.
    unawaited(Native.startCompanion());
    unawaited(registerBackgroundJobs());
  }
}
