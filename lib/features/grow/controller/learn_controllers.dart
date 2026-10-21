import 'dart:math';

import '../../../core/arch/load_state.dart';
import '../../../core/arch/safe_notifier.dart';
import '../../../core/store.dart';
import '../data/feeds.dart';
import '../data/growth_service.dart';
import '../model/lessons.dart';

/// Learn tab: today's progress and Wikipedia's featured content.
class LearnController extends AsyncController<Map<String, dynamic>?> {
  List<String> get learnedToday => Store.learnedToday;
  int get lessonsTotal => Store.lessonsTotal;

  Future<void> loadWiki() => run(Feeds.wikiToday, errorText: 'Offline');

  /// Call after a lesson sheet closes so the grid shows the new tick.
  void refresh() => notifyListeners();
}

/// One subject's lesson and its quick quiz; "Another lesson" moves to a bonus lesson.
class LessonController extends SafeNotifier {
  LessonController(this.subject);
  final Subject subject;
  int skip = 0;
  int? picked;

  Lesson get lesson => subject.lessons[todaysIndex(subject, skip)];
  bool get answeredRight => picked == lesson.answer;

  /// Option order shuffled per lesson (stable seed from the title) so the answer isn't always in the same slot.
  List<int> get order {
    var seed = 0;
    for (final c in lesson.title.codeUnits) {
      seed = (seed * 31 + c) & 0x7fffffff;
    }
    return List.generate(lesson.options.length, (i) => i)..shuffle(Random(seed));
  }

  /// Records the answer; the first correct one of the day for this subject earns XP and counts for growth.
  Future<void> answer(int i) async {
    if (picked != null) return;
    picked = i;
    notifyListeners();
    if (answeredRight && !Store.learnedToday.contains(subject.id)) {
      await Store.markLearned(subject.id);
      await Store.bumpLessons();
      await Store.addXp(10);
      await growthProgress();
    }
  }

  void another() {
    skip++;
    picked = null;
    notifyListeners();
  }
}
