import 'package:url_launcher/url_launcher.dart';

import '../../../core/native.dart';
import '../../../core/store.dart';
import '../model/lessons.dart';

/// Opens a link in the in-app browser.
Future<void> openLink(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);

/// Pushes today's growth state to the native side so it stops nagging once done; never throws.
Future<void> syncGrowth() async {
  try {
    await Native.setGrowth({
      'enabled': Store.growthEnabled,
      'hour': Store.growthHour,
      'doneDate': Store.growthDays.contains(dayKey()) ? dayKey() : '',
      'skipDate': Store.growthSkippedToday ? dayKey() : '',
    });
  } catch (_) {}
}

/// Call after any learning or news action: marks the day done when both parts are finished.
Future<void> growthProgress() async {
  await Store.markGrowthIfDone();
  await syncGrowth();
}

/// True when the forced growth check should be shown right now.
bool growthDue() =>
    Store.growthEnabled && !Store.growthDoneToday && !Store.growthSkippedToday && DateTime.now().hour >= Store.growthHour && Store.raw.getBool('setup_done') == true;

/// Today's suggested lesson: alternates "Build it yourself" with your other unfinished subjects.
Subject suggestedSubject() {
  final notDone = subjects.where((s) => !Store.learnedToday.contains(s.id)).toList();
  final build = subjects.firstWhere((s) => s.id == 'build');
  if (dayOfYear().isEven && notDone.contains(build)) return build;
  return notDone.isEmpty ? build : notDone[dayOfYear() % notDone.length];
}

/// The Toolbox "challenge of the day": done flag and reward.
class DailyChallenge {
  static bool get doneToday => Store.raw.getString('challenge_done') == dayKey();

  static Future<void> complete() async {
    await Store.raw.setString('challenge_done', dayKey());
    await Store.addXp(25);
  }
}
