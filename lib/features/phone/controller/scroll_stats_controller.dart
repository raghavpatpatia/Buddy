import '../../../core/arch/safe_notifier.dart';
import '../../../core/native.dart';

/// Scroll tab: reels counted per app (from the native tracker), screen time, permissions and nudge settings.
class ScrollStatsController extends SafeNotifier {
  List<Map> days = [];
  Map? usage;
  Map<String, dynamic> permissions = {};
  Map<String, dynamic> settings = {'nudgeEnabled': true, 'nudgeEvery': 30, 'reelLimit': 150};
  bool loaded = false;

  Map? get today => days.isNotEmpty ? days.first : null;
  int get reelsToday => today == null ? 0 : Native.reelsOn(today!);
  int get limit => settings['reelLimit'] as int;
  bool get trackerOff => permissions['accessibility'] == false;
  bool get usageOff => permissions['usage'] == false;

  Future<void> load() async {
    final r = await Future.wait([Native.scrollStats(7), Native.usageToday(), Native.permissions(), Native.getScrollSettings()]);
    days = r[0] as List<Map>;
    usage = r[1] as Map?;
    permissions = r[2] as Map<String, dynamic>;
    settings = r[3] as Map<String, dynamic>;
    loaded = true;
    notifyListeners();
  }

  /// Updates nudge settings locally right away and saves them natively.
  Future<void> updateSettings(Map<String, dynamic> s, {bool save = true}) async {
    settings.addAll(s);
    notifyListeners();
    if (save) await Native.setScrollSettings(s);
  }

  void openSystemSettings(String what) => Native.open(what);
}
