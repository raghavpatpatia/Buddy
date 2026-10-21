import '../../../core/arch/load_state.dart';
import '../../../core/store.dart';
import '../data/feeds.dart';
import '../data/growth_service.dart';
import '../model/lessons.dart';
import '../model/news.dart';

/// Daily growth check: learn one thing + read one story, with headlines to pick from and the skip penalty.
class GrowthController extends AsyncController<List<NewsItem>> {
  bool get learnDone => Store.learnDoneToday;
  bool get newsDone => Store.newsDoneToday;
  bool get done => learnDone && newsDone;
  int get streak => Store.growthStreak;
  int get hour => Store.growthHour;
  bool get enabled => Store.growthEnabled;
  int get penaltyXp => Store.growthPenaltyXp;
  String? get lastTakeaway => Store.takeaways.isEmpty ? null : Store.takeaways.last['note'] as String?;
  Subject get suggested => suggestedSubject();

  /// Top story from India, World and Tech.
  Future<void> loadHeadlines() => run(() async {
        final out = <NewsItem>[];
        for (final id in ['india', 'world', 'tech']) {
          try {
            final items = await Feeds.load(feeds.firstWhere((f) => f.id == id));
            if (items.isNotEmpty) out.add(items.first);
          } catch (_) {}
        }
        return out;
      }, errorText: 'Offline');

  /// Gives up today's check: XP penalty and streak reset.
  Future<void> skip() async {
    await Store.penalize(dayKey());
    await syncGrowth();
  }

  /// Saves a one-line takeaway for an article; writing it is what counts as "read".
  static Future<void> saveTakeaway(NewsItem n, String note) async {
    await Store.addTakeaway({'title': n.title, 'link': n.link, 'source': n.source, 'note': note.trim()});
    await Store.addXp(10);
    await growthProgress();
  }

  void refresh() => notifyListeners();
}
