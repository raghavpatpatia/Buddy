import 'package:flutter/services.dart';

/// Bridge to the Kotlin side (companion service, scroll watcher, usage stats).
class Native {
  static const _ch = MethodChannel('buddy/native');

  static Future<Map<String, dynamic>> permissions() async =>
      Map<String, dynamic>.from(await _ch.invokeMethod('permissions'));

  static Future<void> open(String what, {String? pkg}) =>
      _ch.invokeMethod('open', {'what': what, 'pkg': pkg});

  static Future<void> startCompanion() => _ch.invokeMethod('startCompanion');

  static Future<Map<String, dynamic>> getWater() async =>
      Map<String, dynamic>.from(await _ch.invokeMethod('getWater'));
  static Future<int> logDrink([int delta = 1]) async =>
      await _ch.invokeMethod<int>('logDrink', {'delta': delta}) ?? 0;
  static Future<void> setWater(Map<String, dynamic> s) => _ch.invokeMethod('setWater', s);
  static Future<void> setBrief(Map<String, dynamic> s) => _ch.invokeMethod('setBrief', s);
  static Future<void> setGrowth(Map<String, dynamic> s) => _ch.invokeMethod('setGrowth', s);
  static Future<void> testVibrate() => _ch.invokeMethod('testVibrate');

  static Future<Map<String, dynamic>> getScrollSettings() async =>
      Map<String, dynamic>.from(await _ch.invokeMethod('getScrollSettings'));
  static Future<void> setScrollSettings(Map<String, dynamic> s) =>
      _ch.invokeMethod('setScrollSettings', s);

  /// Newest day first: [{date, apps: {Instagram: {reels, feed}}}]
  static Future<List<Map>> scrollStats([int days = 7]) async =>
      List<Map>.from(await _ch.invokeMethod('scrollStats', {'days': days}));

  /// null when usage access is missing.
  static Future<Map?> usageToday() => _ch.invokeMethod<Map>('usageToday');
  static Future<Map?> appInsights() => _ch.invokeMethod<Map>('appInsights');

  /// All indexed files as (path, size, modifiedMs); null without all-files access.
  static Future<List<(String, int, int)>?> mediaFiles() async {
    final m = await _ch.invokeMethod<Map>('mediaFiles');
    if (m == null) return null;
    final paths = (m['p'] as List).cast<String>();
    final sizes = m['s'] as List<int>, mods = m['m'] as List<int>;
    return [for (var i = 0; i < paths.length; i++) (paths[i], sizes[i], mods[i])];
  }

  /// JPEG bytes of a video frame (generated off the UI thread natively).
  static Future<Uint8List?> videoThumb(String path) => _ch.invokeMethod<Uint8List>('videoThumb', {'path': path});

  /// Bank debit/credit SMS since [sinceMs] (already filtered natively to business senders): [{id, addr, body, date}].
  static Future<List<Map>> bankSms(int sinceMs) async =>
      List<Map>.from(await _ch.invokeMethod('bankSms', {'since': sinceMs}) ?? const []);

  static int reelsOn(Map day) {
    var t = 0;
    (day['apps'] as Map).forEach((_, v) => t += (v['reels'] as int));
    return t;
  }
}
