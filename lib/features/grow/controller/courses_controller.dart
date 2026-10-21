import '../../../core/arch/safe_notifier.dart';
import '../../../core/store.dart';
import '../data/growth_service.dart';
import '../model/course.dart';

/// "My courses": progress per course, daily log, add/edit/delete and finishing rewards.
class CoursesController extends SafeNotifier {
  /// Active courses by nearest deadline first, finished ones last.
  List<Map<String, dynamic>> get courses => Store.courses..sort((a, b) => _urgency(a).compareTo(_urgency(b)));

  static int _urgency(Map c) {
    if (c['done'] >= c['total']) return 1 << 30;
    return coursePace(c)?.daysLeft ?? (1 << 20);
  }

  bool get anyActive => Store.courses.any((c) => c['done'] < c['total']);

  /// Moves progress by [delta] units; returns true when this finished the course.
  Future<bool> bump(Map<String, dynamic> c, int delta) async {
    final all = Store.courses;
    final x = all.firstWhere((e) => e['id'] == c['id']);
    final done = ((x['done'] as int) + delta).clamp(0, x['total'] as int);
    if (done == x['done']) return false;
    x['done'] = done;
    final log = Map<String, dynamic>.from(x['log'] ?? {});
    log[dayKey()] = ((log[dayKey()] as int? ?? 0) + delta).clamp(0, 999);
    x['log'] = log;
    await Store.setCourses(all);
    final finished = delta > 0 && done == x['total'];
    if (delta > 0) {
      await Store.addXp(finished ? 100 : 5);
      await growthProgress();
    }
    notifyListeners();
    return finished;
  }

  /// Saves a new or edited course, or deletes it when [result] has `_delete`.
  Future<void> save(Map<String, dynamic>? original, Map<String, dynamic> result) async {
    final all = Store.courses;
    if (result['_delete'] == true) {
      all.removeWhere((e) => e['id'] == original!['id']);
    } else if (original == null) {
      all.add(result);
    } else {
      all[all.indexWhere((e) => e['id'] == original['id'])] = result;
    }
    await Store.setCourses(all);
    notifyListeners();
  }
}
