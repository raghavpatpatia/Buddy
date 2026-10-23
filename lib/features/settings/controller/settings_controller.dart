import 'dart:async';

import 'package:permission_handler/permission_handler.dart';

import '../../../core/arch/safe_notifier.dart';
import '../../../core/background.dart';
import '../../../core/native.dart';
import '../../../core/store.dart';
import '../../grow/data/growth_service.dart';
import '../../home/data/brief_service.dart';

/// Native (accessibility, usage, files, battery) and runtime (notifications, activity, location) permissions.
class PermissionsController extends SafeNotifier {
  Map<String, dynamic> native = {};
  bool notifications = false, activity = false, location = false;

  /// Re-reads every permission; a plugin hiccup never breaks the screen.
  Future<void> check() async {
    try {
      native = await Native.permissions();
      final a = await Future.wait([Permission.notification.isGranted, Permission.activityRecognition.isGranted, Permission.locationWhenInUse.isGranted]);
      notifications = a[0];
      activity = a[1];
      location = a[2];
      notifyListeners();
    } catch (_) {}
  }

  bool nativeOk(String key) => native[key] == true;

  Future<void> openSystem(String what) => Native.open(what);

  /// Opened the phone maker's battery manager to allow Buddy (Android can't tell us if it was allowed).
  bool get killerOpened => Store.raw.getBool('killer_opened') == true;
  Future<void> openKiller() async {
    await Store.raw.setBool('killer_opened', true);
    await Native.open('killer');
    notifyListeners();
  }
}

/// Settings screen: profile and goals, daily growth check, morning brief, and permissions.
class SettingsController extends PermissionsController {
  final profile = Store.profile;

  Future<void> saveProfile(String key, dynamic value) async {
    profile[key] = value;
    notifyListeners();
    await Store.setProfile(profile);
  }

  /// Updates a profile value on screen only (e.g. while a slider moves); [saveProfile] persists it.
  void previewProfile(String key, dynamic value) {
    profile[key] = value;
    notifyListeners();
  }

  int get growthPenaltyXp => Store.growthPenaltyXp;
  bool get growthEnabled => Store.growthEnabled;
  int get growthHour => Store.growthHour;

  Future<void> setGrowthEnabled(bool v) async {
    await Store.raw.setBool('growth_enabled', v);
    await syncGrowth();
    notifyListeners();
  }

  Future<void> setGrowthHour(int h, {bool sync = false}) async {
    await Store.raw.setInt('growth_hour', h);
    if (sync) await syncGrowth();
    notifyListeners();
  }

  bool get briefOn => briefEnabled;
  int get briefAtHour => briefHour;
  int get briefAtMinute => briefMinute;

  Future<void> setBriefEnabled(bool v) async {
    await Store.raw.setBool('brief_enabled', v);
    await syncBrief();
    notifyListeners();
  }

  Future<void> setBriefTime(int hour, int minute) async {
    await Store.raw.setInt('brief_hour', hour);
    await Store.raw.setInt('brief_minute', minute);
    await syncBrief();
    unawaited(prepareBrief());
    notifyListeners();
  }
}

/// First-run setup: permissions, a few profile answers, then start the 24/7 companion.
class SetupController extends PermissionsController {
  final profile = Store.profile;

  void setProfile(String key, dynamic value) {
    profile[key] = value;
    notifyListeners();
  }

  Future<void> finish() async {
    await Store.setProfile(profile);
    await Native.startCompanion();
    await registerBackgroundJobs();
    await Store.raw.setBool('setup_done', true);
  }
}
