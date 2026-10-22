import 'package:buddy_app/core/arch/event_bus.dart';
import 'package:buddy_app/core/arch/load_state.dart';
import 'package:buddy_app/core/arch/lru_cache.dart';
import 'package:buddy_app/core/arch/repository.dart';
import 'package:buddy_app/core/arch/time_sort.dart';
import 'package:buddy_app/core/store.dart';
import 'package:buddy_app/features/money/controller/spend_controller.dart';
import 'package:buddy_app/features/money/data/money_store.dart';
import 'package:buddy_app/features/money/data/txn_sources.dart';
import 'package:buddy_app/features/money/model/market.dart';
import 'package:buddy_app/features/money/model/txn.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSource implements TxnSource {
  final List<Txn> txns;
  _FakeSource(this.txns);
  @override
  bool get enabled => true;
  @override
  Future<List<Txn>> fetchSince(DateTime since) async => txns;
}

class _SlowThenFast extends AsyncController<int> {
  Future<void> go(int v, Duration d) => run(() => Future.delayed(d, () => v), errorText: 'x');
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
  });

  test('PrefsRepository keeps order, looks up by id, persists and notifies', () async {
    final repo = PrefsRepository<String, Holding>(Store.raw, 'h', Holding.codec, (h) => h.symbol);
    var notified = 0;
    repo.addListener(() => notified++);
    await repo.putAll(const [Holding('A', 'a', 1, 10), Holding('B', 'b', 2, 20)]);
    await repo.put(const Holding('A', 'a', 5, 10));
    expect(repo.all.map((h) => h.symbol), ['A', 'B']);
    expect(repo['A']!.qty, 5);
    expect(notified, 2);
    final reloaded = PrefsRepository<String, Holding>(Store.raw, 'h', Holding.codec, (h) => h.symbol);
    expect(reloaded.length, 2);
  });

  test('watchlist stays readable in its old [symbol, name] format', () async {
    await Store.raw.setString('mkt_watch', '[["TCS.NS","TCS"]]');
    expect(MoneyStore(Store.raw).watchlist['TCS.NS']!.name, 'TCS');
  });

  test('LruCache evicts the least recently used entry', () {
    final c = LruCache<String, int>(capacity: 2, ttl: const Duration(minutes: 1))
      ..put('a', 1)
      ..put('b', 2);
    c.get('a');
    c.put('c', 3);
    expect(c.get('b'), isNull);
    expect(c.get('a'), 1);
  });

  test('AsyncController: a slow older load never overwrites a newer one', () async {
    final c = _SlowThenFast();
    final slow = c.go(1, const Duration(milliseconds: 60));
    await c.go(2, const Duration(milliseconds: 5));
    await slow;
    expect(c.state.data, 2);
  });

  test('EventBus delivers only the subscribed type', () async {
    final got = <AppEvent>[];
    final sub = EventBus.instance.on<MailOpened>().listen(got.add);
    EventBus.instance.emit('not a mail event');
    EventBus.instance.emit(const MailOpened('x'));
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(got, hasLength(1));
  });

  test('SpendController sync merges sources, drops SMS/email twins and removed entries', () async {
    final t0 = DateTime(2026, 10, 20, 10);
    final store = MoneyStore(Store.raw);
    await store.markRemoved('sms_gone');
    final c = SpendController(store: store, sources: [
      _FakeSource([
        Txn(id: 'sms_1', amount: 500, debit: true, at: t0, bank: 'HDFC', source: 'sms'),
        Txn(id: 'sms_gone', amount: 99, debit: true, at: t0, bank: 'HDFC', source: 'sms'),
      ]),
      _FakeSource([
        Txn(id: 'mail_1', amount: 500, debit: true, at: t0.add(const Duration(minutes: 3)), bank: 'HDFC', source: 'email'),
        Txn(id: 'mail_2', amount: 500, debit: true, at: t0.add(const Duration(hours: 5)), bank: 'HDFC', source: 'email'),
      ]),
    ]);
    expect(await c.syncNow(), 2);
    expect(store.txns.all.map((t) => t.id).toSet(), {'sms_1', 'mail_2'});
    expect(await c.syncNow(), 0);
  });

  test('reload() picks up writes made outside this repository (background isolate)', () async {
    final repo = PrefsRepository<String, Holding>(Store.raw, 'h2', Holding.codec, (h) => h.symbol);
    expect(repo.length, 0);
    await Store.raw.setString('h2', '[{"s":"X","n":"x","q":1,"a":1}]');
    expect(repo.length, 0);
    await repo.reload();
    expect(repo['X']?.qty, 1);
  });

  test('sortByTime: best keeps order, newest/oldest by date, undated last', () {
    final items = [('b', DateTime(2026, 1, 2)), ('none', null), ('a', DateTime(2026, 1, 1)), ('c', DateTime(2026, 1, 3))];
    String names(TimeSort s) => sortByTime(items, (e) => e.$2, s).map((e) => e.$1).join();
    expect(names(TimeSort.best), 'bnoneac');
    expect(names(TimeSort.newest), 'cbanone');
    expect(names(TimeSort.oldest), 'abcnone');
    expect(sortByTime(<(String, DateTime?)>[], (e) => e.$2, TimeSort.newest), isEmpty);
  });
}
