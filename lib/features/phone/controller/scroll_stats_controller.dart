import '../../../core/arch/safe_notifier.dart';
import '../../../core/store.dart';
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

  /// The phone maker's battery manager (e.g. "DuraSpeed") that switches the tracker off by closing Buddy, or null.
  String? get killer => permissions['killer'] as String?;

  /// It has switched the tracker off since the user last dismissed the tip.
  bool get killerStruck => killer != null && (permissions['trackerOffCount'] as int? ?? 0) > (Store.raw.getInt('killer_ack') ?? 0);
  int get killerTimes => permissions['trackerOffCount'] as int? ?? 0;

  Future<void> ackKiller() async {
    await Store.raw.setInt('killer_ack', killerTimes);
    notifyListeners();
  }

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
