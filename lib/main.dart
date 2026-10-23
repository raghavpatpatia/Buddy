import 'dart:async';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/background.dart';
import 'core/game.dart';
import 'core/native.dart';
import 'core/store.dart';
import 'features/backup/controller/backup_controller.dart';
import 'features/backup/data/cloud_backup.dart';
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.init();
  await Store.migrateDanceToFit();
  applyBotTheme();
  await CloudBackup.init();
  runApp(const BuddyApp());
  unawaited(BackupController.instance.start());
  if (Store.raw.getBool('setup_done') == true) {
    // Idempotent: make sure the 24x7 companion and background jobs are alive.
    // Done after the first frame so app start isn't blocked.
    unawaited(Native.startCompanion());
    unawaited(registerBackgroundJobs());
  }
}
