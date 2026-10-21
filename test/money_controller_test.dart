import 'package:buddy_app/core/arch/load_state.dart';
import 'package:buddy_app/core/format.dart';
import 'package:buddy_app/core/store.dart';
import 'package:buddy_app/features/money/controller/invest_controller.dart';
import 'package:buddy_app/features/money/controller/mail_controller.dart';
import 'package:buddy_app/features/money/controller/stock_controller.dart';
import 'package:buddy_app/features/money/data/market_api.dart';
import 'package:buddy_app/features/money/data/money_store.dart';
import 'package:buddy_app/features/money/model/market.dart';
import 'package:buddy_app/features/money/view/stock_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Quote _q(String sym, String cur, double price, {double change = 0, List<double>? closes}) =>
    Quote(sym, sym, cur, price, change, null, null, [for (var i = 0; i < (closes ?? [price]).length; i++) DateTime(2026, 1, i + 1)], closes ?? [price]);

/// Market API stub: answers per range after a chosen delay.
class _FakeApi implements MarketApi {
  final Map<String, (Duration, Quote)> byRange;
  _FakeApi(this.byRange);
  @override
  Future<Quote> chart(String symbol, {String range = '1y'}) async {
    final (d, q) = byRange[range]!;
    await Future<void>.delayed(d);
    return q;
  }

  @override
  Future<List<Quote>> charts(List<String> symbols, {String range = '1y'}) async => const [];
  @override
  Future<List<(String, String, String)>> search(String q) async => const [];
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
  });

  test('portfolio converts US holdings to rupees and sums today’s change', () async {
    final store = MoneyStore(Store.raw);
    await store.holdings.putAll(const [Holding('TCS.NS', 'TCS', 10, 3000), Holding('AAPL', 'Apple', 2, 150)]);
    final c = InvestController(store: store, api: _FakeApi({}))
      ..indicesState = Ready([_q('INR=X', 'INR', 80)])
      ..quotes['TCS.NS'] = _q('TCS.NS', 'INR', 3300, change: 10)
      ..quotes['AAPL'] = _q('AAPL', 'USD', 200);
    final p = c.portfolio;
    expect(p.value, 10 * 3300 + 2 * 200 * 80);
    expect(p.cost, 10 * 3000 + 2 * 150 * 80);
    expect(p.today, closeTo(3000, 0.01)); // 33000 now, 30000 yesterday (+10%)
  });

  test('a slow older range never replaces the newer chart', () async {
    final c = StockController('X', 'X', store: MoneyStore(Store.raw), api: _FakeApi({
      '1y': (const Duration(milliseconds: 80), _q('X', 'INR', 1, closes: [1, 1])),
      '5y': (const Duration(milliseconds: 5), _q('X', 'INR', 5, closes: [5, 5])),
    }));
    final first = c.load();
    c.setRange('5y');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await first;
    expect(c.range, '5y');
    expect(c.chart.data?.price, 5);
  });

  testWidgets('stock with a single price point shows a message instead of crashing', (t) async {
    final c = StockController('NEW', 'New listing', store: MoneyStore(Store.raw), api: _FakeApi({'1y': (Duration.zero, _q('NEW', 'INR', 10))}));
    await t.pumpWidget(MaterialApp(home: Scaffold(body: StockSheet(symbol: 'NEW', name: 'New listing', controller: c))));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(find.text('No price history for this range yet.'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  test('typed amounts: plain positive numbers only, within the cap', () {
    expect(parseAmount('1,299.50'), 1299.5);
    expect(parseAmount('0'), isNull);
    expect(parseAmount('-5'), isNull);
    expect(parseAmount('1e9'), isNull);
    expect(parseAmount('abc'), isNull);
    expect(parseAmount('200000000'), isNull);
  });

  test('bad recipients are listed before sending', () {
    expect(ComposeController.badRecipients('a@b.com, priya@gmail.com'), isEmpty);
    expect(ComposeController.badRecipients('abc@, x@y.com; hello'), ['abc@', 'hello']);
  });
}
