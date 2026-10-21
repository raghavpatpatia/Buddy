import '../../../core/arch/load_state.dart';
import '../../../core/store.dart';
import '../data/feeds.dart';
import '../model/news.dart';

/// News tab: the chosen feed (remembered) and its headlines.
class NewsController extends AsyncController<List<NewsItem>> {
  Feed feed = feeds.firstWhere((f) => f.id == Store.raw.getString('news_feed'), orElse: () => feeds.first);

  Future<void> load({bool force = false}) => run(() => Feeds.load(feed, force: force), errorText: 'Couldn\'t load ${feed.name}. Check your internet and pull to refresh.');

  void select(Feed f) {
    Store.raw.setString('news_feed', f.id);
    feed = f;
    state = const Idle();
    load();
  }
}
