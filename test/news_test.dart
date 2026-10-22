import 'package:buddy_app/core/arch/time_sort.dart';
import 'package:buddy_app/core/store.dart';
import 'package:buddy_app/features/grow/controller/news_controller.dart';
import 'package:buddy_app/features/grow/model/news.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
    // A fresh cache for the default feed, so loading needs no network.
    await Store.setJson('news_${feeds.first.id}', {
      'at': DateTime.now().toIso8601String(),
      'items': [
        NewsItem('Top story', 'https://n/1', 'A', DateTime(2026, 10, 21, 9)).toJson(),
        NewsItem('Undated', 'https://n/2', 'B', null).toJson(),
        NewsItem('Breaking', 'https://n/3', 'C', DateTime(2026, 10, 22, 6)).toJson(),
        NewsItem('Old news', 'https://n/4', 'D', DateTime(2026, 10, 19)).toJson(),
      ],
    });
  });

  test('news: feed order by default, then newest/oldest by time, remembered', () async {
    final c = NewsController();
    expect(c.items, isNull);
    await c.load();
    expect(c.items!.map((n) => n.title), ['Top story', 'Undated', 'Breaking', 'Old news']);
    c.setSort(TimeSort.newest);
    expect(c.items!.map((n) => n.title), ['Breaking', 'Top story', 'Old news', 'Undated']);
    c.setSort(TimeSort.oldest);
    expect(c.items!.first.title, 'Old news');
    expect(NewsController().sort, TimeSort.oldest);
    c.dispose();
  });
}
