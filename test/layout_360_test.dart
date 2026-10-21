// Renders screens at the owner's phone size (1080×2400 px @ 3.0 = 360×800 dp) with real Roboto
// metrics and fails on any "RenderFlex overflowed" error, scrolling through each page.
import 'dart:convert';
import 'dart:io';

import 'package:buddy_app/core/store.dart';
import 'package:buddy_app/features/astro/astro_page.dart';
import 'package:buddy_app/features/astro/jyotish.dart';
import 'package:buddy_app/features/buddy_page.dart';
import 'package:buddy_app/features/grow/learn_page.dart';
import 'package:buddy_app/features/grow/practice_page.dart';
import 'package:buddy_app/features/grow/toolbox_page.dart';
import 'package:buddy_app/features/money/invest_page.dart';
import 'package:buddy_app/features/money/mail_page.dart';
import 'package:buddy_app/features/money/market.dart';
import 'package:buddy_app/features/money/stock_sheet.dart';
import 'package:buddy_app/features/money/spend_page.dart';
import 'package:buddy_app/features/sections.dart';
import 'package:buddy_app/features/settings_page.dart';
import 'package:buddy_app/features/setup_page.dart';
import 'package:buddy_app/features/trophies_page.dart';
import 'package:buddy_app/features/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadRoboto() async {
  final loader = FontLoader('Roboto');
  for (final w in ['Regular', 'Medium', 'Bold']) {
    loader.addFont(Future.value(ByteData.sublistView(File('test/fixtures/fonts/Roboto-$w.ttf').readAsBytesSync())));
  }
  await loader.load();
}

void _mockNative() {
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  m.setMockStreamHandler(const EventChannel('step_count'), MockStreamHandler.inline(onListen: (_, _) {}));
  m.setMockMethodCallHandler(const MethodChannel('buddy/native'), (call) async {
    switch (call.method) {
      case 'permissions':
        return {'usage': true, 'accessibility': true, 'allFiles': true, 'battery': true, 'companion': true};
      case 'getWater':
        return {'count': 3, 'goal': 8, 'enabled': true, 'interval': 60, 'start': 8, 'end': 22, 'lastDrink': 0};
      case 'scrollStats':
        return [
          {'date': dayKey(), 'apps': <String, dynamic>{}}
        ];
      case 'getScrollSettings':
        return {'nudgeEnabled': true, 'nudgeEvery': 30, 'reelLimit': 150};
      default:
        return null;
    }
  });
}

Future<List<String>> _overflows(WidgetTester t, Widget page) async {
  final errors = <String>[];
  final old = FlutterError.onError;
  FlutterError.onError = (d) {
    final s = d.exceptionAsString();
    if (s.contains('overflowed')) errors.add('${s.split('\n').first}\n    ${d.informationCollector?.call().take(3).join(' | ') ?? ''}');
  };
  try {
    await t.pumpWidget(MaterialApp(theme: buddyTheme(Brightness.light), home: page));
    await t.pump(const Duration(milliseconds: 500));
    // Scroll every scrollable down a few screens so off-screen rows get laid out too.
    for (var i = 0; i < 8; i++) {
      final scrollables = find.byType(Scrollable);
      if (scrollables.evaluate().isEmpty) break;
      await t.drag(scrollables.first, const Offset(0, -500), warnIfMissed: false);
      await t.pump(const Duration(milliseconds: 300));
    }
  } finally {
    FlutterError.onError = old;
  }
  return errors;
}

void main() {
  setUpAll(_loadRoboto);
  setUp(() async {
    _mockNative();
    SharedPreferences.setMockInitialValues({'setup_done': true});
    await Store.init();
    await Store.setCourses([
      {'id': '1', 'name': 'Full Stack Web Development with React & Node', 'platform': 'Tutedude', 'unit': 'videos', 'url': 'https://x', 'total': 120, 'done': 37, 'deadline': DateTime.now().add(const Duration(days: 20)).toIso8601String(), 'log': {}},
    ]);
    final now = DateTime.now();
    await Store.raw.setString('money_txns', jsonEncode([
      for (var i = 0; i < 14; i++)
        {'id': 'sms_$i', 'a': [499.0, 1299.5, 45000.0, 86.0, 12500.0][i % 5], 'd': i % 5 != 2, 't': now.subtract(Duration(hours: i * 9)).millisecondsSinceEpoch, 'b': ['HDFC', 'SBI', 'IndusInd', 'Kotak'][i % 4], 's': i.isEven ? 'sms' : 'email', 'c': i % 3 == 0 ? 'Groceries' : null, 'h': false},
    ]));
    await Store.raw.setDouble('money_budget', 30000);
    await Store.raw.setBool('money_sms', true);
    await Store.setJson('birth', const BirthData(name: 'Raghav', place: 'Delhi', year: 1999, month: 8, day: 5, hour: 22, minute: 15, second: 30, tz: 5.5, lat: 28.6139, lon: 77.2090).toJson());
  });

  final pages = <String, Widget Function()>{
    'Grow (section)': () => growSection(),
    'Learn': () => const Scaffold(body: LearnPage()),
    'Practice': () => const Scaffold(body: PracticePage()),
    'Toolbox': () => const Scaffold(body: ToolboxPage()),
    'Buddy home': () => const BuddyPage(),
    'Settings': () => const SettingsPage(),
    'Setup': () => SetupPage(onDone: () {}),
    'Astro': () => const AstroPage(),
    'Birth form': () => const BirthForm(),
    'Trophies': () => const TrophiesPage(),
    'Health (Fit)': () => healthSection(),
    'Money (Spend)': () => moneySection(),
    'Spend': () => const Scaffold(body: SpendPage()),
    'Mail (not linked)': () => const Scaffold(body: MailPage()),
    'Compose': () => const ComposePage(),
    'Phone (Scroll)': () => phoneSection(),
  };

  for (final e in pages.entries) {
    testWidgets('no overflow at 360 dp: ${e.key}', (t) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.reset);
      final errs = await _overflows(t, e.value());
      expect(errs, isEmpty, reason: errs.join('\n'));
    });
  }

  for (final page in ['Settings', 'Setup']) {
    testWidgets('segmented labels stay on one line at 360 dp: $page', (t) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(theme: buddyTheme(Brightness.light), home: pages[page]!()));
      await t.pump(const Duration(milliseconds: 300));
      await t.scrollUntilVisible(find.text('Maintain'), 200, scrollable: find.byType(Scrollable).first);
      for (final label in ['Maintain', page == 'Settings' ? 'Non-veg' : 'Build muscle']) {
        final para = t.renderObject<RenderParagraph>(find.text(label));
        final lines = para.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: label.length)).map((b) => b.top.round()).toSet();
        expect(lines.length, 1, reason: '"$label" wrapped');
      }
    });
  }

  // Invest + stock sheet with fake market data (every symbol gets a 1-year random-walk chart).
  final fakeMarket = MockClient((req) async {
    if (req.url.path.contains('/search')) {
      return http.Response(jsonEncode({'quotes': [{'symbol': 'RELIANCE.NS', 'longname': 'Reliance Industries Limited', 'exchDisp': 'NSE', 'quoteType': 'EQUITY'}]}), 200);
    }
    if (req.url.host.contains('news.google')) return http.Response('<rss><channel></channel></rss>', 200);
    final sym = req.url.pathSegments.last;
    final n = 250, t0 = DateTime(2025, 10, 1).millisecondsSinceEpoch ~/ 1000;
    var p = sym.hashCode % 3000 + 100.0;
    final closes = [for (var i = 0; i < n; i++) p = p * (1 + ((i * 7919 + sym.hashCode) % 21 - 9) / 1000)];
    return http.Response(
        jsonEncode({
          'chart': {
            'result': [
              {
                'meta': {'currency': sym.endsWith('.NS') || sym.startsWith('^') ? 'INR' : 'USD', 'longName': 'Very Long Company Name Industries Limited $sym', 'regularMarketPrice': closes.last, 'regularMarketChangePercent': -1.23, 'fiftyTwoWeekHigh': closes.reduce((a, b) => a > b ? a : b), 'fiftyTwoWeekLow': closes.reduce((a, b) => a < b ? a : b)},
                'timestamp': [for (var i = 0; i < n; i++) t0 + i * 86400],
                'indicators': {'quote': [{'close': closes}]},
              }
            ]
          }
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'});
  });

  for (final (name, page) in [('Invest', () => const Scaffold(body: InvestPage())), ('Stock sheet', () => const Scaffold(body: StockSheet(symbol: 'RELIANCE.NS', name: 'Reliance Industries Limited')))]) {
    testWidgets('no overflow at 360 dp: $name (mock market)', (t) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.reset);
      await Market.saveHoldings(const [Holding('RELIANCE.NS', 'Reliance Industries Limited', 12, 1180.5), Holding('AAPL', 'Apple Inc.', 3, 190)]);
      await Market.toggleWatch('TCS.NS', 'Tata Consultancy Services Limited');
      final errs = await http.runWithClient(() async {
        final e = await t.runAsync(() async => <String>[]) ?? <String>[];
        e.addAll(await _overflows(t, page()));
        await t.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
        await t.pump(const Duration(milliseconds: 300));
        e.addAll(await _overflows(t, page()));
        return e;
      }, () => fakeMarket);
      expect(errs, isEmpty, reason: errs.join('\n'));
      if (name == 'Invest') {
        await t.fling(find.byType(Scrollable).first, const Offset(0, 4000), 3000, warnIfMissed: false);
        await t.pumpAndSettle();
        expect(find.text('My portfolio'), findsOneWidget);
        expect(find.textContaining('Market data unavailable'), findsNothing);
      }
    });
  }
}
