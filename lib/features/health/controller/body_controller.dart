import '../../../core/arch/safe_notifier.dart';
import '../../../core/store.dart';

/// Body card: profile fields (height, sex, age, goal) and the daily weight log.
class BodyController extends SafeNotifier {
  Map<String, dynamic> get profile => Store.profile;
  String get goal => Store.profile['goal'] as String? ?? 'maintain';

  Future<void> saveProfile(Map<String, dynamic> changes) async {
    await Store.setProfile(Store.profile..addAll(changes));
    notifyListeners();
  }

  /// Logs today's weight (replacing an earlier entry today); ignores impossible values.
  Future<bool> logWeight(double kg) async {
    if (kg < 25 || kg > 300) return false;
    final log = List<Map<String, dynamic>>.from((Store.getJson('weight_log', []) as List).map((e) => Map<String, dynamic>.from(e)))
      ..removeWhere((e) => e['date'] == dayKey())
      ..add({'date': dayKey(), 'kg': kg});
    await Store.setJson('weight_log', log);
    await saveProfile({'weight': double.parse(kg.toStringAsFixed(1))});
    return true;
  }
}
