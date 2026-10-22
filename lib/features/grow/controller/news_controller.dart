import '../../../core/arch/load_state.dart';
import '../../../core/arch/time_sort.dart';
import '../../../core/store.dart';
import '../data/feeds.dart';
import '../model/news.dart';

/// News tab: the chosen feed and sort order (both remembered) and its headlines.
class NewsController extends AsyncController<List<NewsItem>> {
  Feed feed = feeds.firstWhere((f) => f.id == Store.raw.getString('news_feed'), orElse: () => feeds.first);
  TimeSort sort = TimeSort.values.asNameMap()[Store.raw.getString('news_sort')] ?? TimeSort.best;

  static const sortLabels = {TimeSort.best: 'Top', TimeSort.newest: 'Newest', TimeSort.oldest: 'Oldest'};

  /// Loaded headlines in the chosen order; null while nothing has loaded.
  List<NewsItem>? get items {
    final d = state.data;
    return d == null ? null : sortByTime(d, (n) => n.at, sort);
  }

  Future<void> load({bool force = false}) => run(() => Feeds.load(feed, force: force), errorText: 'Couldn\'t load ${feed.name}. Check your internet and pull to refresh.');

  void select(Feed f) {
    Store.raw.setString('news_feed', f.id);
    feed = f;
    state = const Idle();
    load();
  }

  void setSort(TimeSort s) {
    Store.raw.setString('news_sort', s.name);
    sort = s;
    notifyListeners();
  }
}
