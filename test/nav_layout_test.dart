// Map + backup screens at the owner's phone size (360×800 dp) with long Indian place names, a full route with
// alternatives, and the keyboard open. Fails on any "overflowed" layout error.
import 'dart:io';

import 'package:buddy_app/core/arch/load_state.dart';
import 'package:buddy_app/core/store.dart';
import 'package:buddy_app/features/backup/view/backup_card.dart';
import 'package:buddy_app/features/nav/controller/nav_controller.dart';
import 'package:buddy_app/features/nav/data/map_store.dart';
import 'package:buddy_app/features/nav/data/tile_api.dart';
import 'package:buddy_app/features/nav/model/region.dart';
import 'package:buddy_app/features/nav/model/route_plan.dart';
import 'package:buddy_app/features/nav/view/area_picker.dart';
import 'package:buddy_app/features/nav/view/map_screen.dart';
import 'package:buddy_app/features/nav/view/maps_sheet.dart';
import 'package:buddy_app/features/nav/view/nav_page.dart';
import 'package:buddy_app/features/nav/view/nav_widgets.dart';
import 'package:buddy_app/shared/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _fonts() async {
  final r = FontLoader('Roboto');
  for (final w in ['Regular', 'Medium', 'Bold']) {
    r.addFont(Future.value(ByteData.sublistView(File('test/fixtures/fonts/Roboto-$w.ttf').readAsBytesSync())));
  }
  await r.load();
  final h = FontLoader('Rajdhani');
  for (final w in ['SemiBold', 'Bold']) {
    h.addFont(Future.value(ByteData.sublistView(File('assets/fonts/Rajdhani-$w.ttf').readAsBytesSync())));
  }
  await h.load();
}

const _long = 'Sir Mokshagundam Visvesvaraya Road Service Road';

RoutePlan _plan(double km, double min) {
  final pts = [for (var i = 0; i < 30; i++) (12.97 + i * 0.004, 77.59 + i * 0.003)];
  final cum = [for (var i = 0; i < 30; i++) i * km * 1000 / 29];
  return RoutePlan(
    points: pts,
    cumMetres: cum,
    metres: km * 1000,
    seconds: min * 60,
    flyovers: 3,
    tunnels: 1,
    streets: [_long, 'Bellary Road', 'Kempegowda International Airport Road', 'Hebbal Flyover', 'Outer Ring Road Service Lane'],
    maneuvers: [
      Maneuver(Turn.depart, 0, _long),
      Maneuver(Turn.roundabout, 600, _long, exit: 3, say: 'Enter Mekhri Circle Roundabout and take the 3rd exit onto $_long'),
      Maneuver(Turn.flyover, 4000, 'Hebbal Flyover'),
      Maneuver(Turn.arrive, km * 1000, ''),
    ],
  );
}

NavController _withRoute() => NavController()
  ..online = true
  ..me = (12.97, 77.59)
  ..heading = 45
  ..myStreet = _long
  ..to = const Place('Kempegowda International Airport Terminal 2 Departures Level Gate 4', 'Airport · Devanahalli, Bengaluru Rural', 13.19, 77.70)
  ..route = Ready(_plan(38.4, 64))
  ..alternatives = [_plan(41.2, 71), _plan(36.9, 79)]
  ..progress = const RouteProgress(3, 4, 34000, 4400);

final _region = Region(
  id: 'r1', name: 'Bengaluru Urban and Bengaluru Rural District Area', south: 12.8, west: 77.4, north: 13.3, east: 77.8,
  bytes: 48000000, nodes: 230000, roads: 300000, built: 'old', dataDate: '2026-10-21T00:00:00Z');

const _manifest = MapManifest(1, 1, 'India', 'new', '2026-10-21T00:00:00Z', '', {'12_77': (12755988, 1040316), '13_77': (5000000, 400000)});

Future<List<String>> _check(WidgetTester t, Future<void> Function(BuildContext) open, {double keyboard = 0, String? type}) async {
  final errors = <String>[];
  final old = FlutterError.onError;
  FlutterError.onError = (d) {
    final s = d.exceptionAsString();
    if (s.contains('overflowed')) errors.add('${s.split('\n').first}\n    ${d.informationCollector?.call().take(3).join(' | ') ?? ''}');
  };
  try {
    late BuildContext ctx;
    await t.pumpWidget(MaterialApp(theme: buddyTheme(), home: Scaffold(body: Builder(builder: (c) => SizedBox.expand(key: ValueKey(ctx = c))))));
    await open(ctx);
    // First frame builds the new route off-stage; the next ones finish the slide-in.
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    if (type != null) {
      await t.enterText(find.byType(TextField).first, type);
      await t.pump(const Duration(milliseconds: 800));
    }
    if (keyboard > 0) {
      t.view.viewInsets = FakeViewPadding(bottom: keyboard);
      await t.pump(const Duration(milliseconds: 400));
    }
    for (var i = 0; i < 6; i++) {
      final s = find.byType(Scrollable);
      if (s.evaluate().isEmpty) break;
      await t.drag(s.last, const Offset(0, -500), warnIfMissed: false);
      await t.pump(const Duration(milliseconds: 200));
    }
  } finally {
    FlutterError.onError = old;
  }
  return errors;
}

void main() {
  setUpAll(_fonts);
  setUp(() async {
    SharedPreferences.setMockInitialValues({'setup_done': true});
    await Store.init();
  });

  void phone(WidgetTester t) {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3.0;
    addTearDown(t.view.reset);
  }

  Future<void> push(BuildContext ctx, Widget w) async {
    Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => w));
  }

  final cases = <String, (Future<void> Function(BuildContext), double, String?)>{
    'Map tab, nothing set, offline': ((ctx) => push(ctx, Scaffold(body: NavPage(controller: NavController()..online = false))), 0, null),
    'Map tab with route, alternatives, error': (
      (ctx) => push(ctx, Scaffold(body: NavPage(controller: _withRoute()..from = const Place('Majestic Kempegowda Bus Station Platform 18', '', 12.97, 77.57)))),
      0,
      null
    ),
    'Live map while driving': ((ctx) => push(ctx, MapScreen(c: _withRoute())), 0, null),
    'Place search, keyboard open, no matches': ((ctx) async {
      pickPlace(ctx, _withRoute(), isStart: false);
    }, 900, 'felicity games office'),
    'Start search, keyboard open': ((ctx) async {
      pickPlace(ctx, _withRoute(), isStart: true);
    }, 900, 'majestic'),
    'Area picker': ((ctx) => push(ctx, AreaPicker(c: NavController()..manifest = _manifest)), 0, null),
    'Area picker, keyboard open': ((ctx) => push(ctx, AreaPicker(c: NavController()..manifest = _manifest)), 900, 'bengaluru'),
    'Maps sheet, long names, update': (
      (ctx) async {
        await MapStore.regions.put(_region);
        await MapStore.regions.put(Region(id: 'r2', name: 'Delhi National Capital Territory and Gurugram', south: 28.4, west: 76.8, north: 28.9, east: 77.4, bytes: 45000000));
        final c = NavController()
          ..manifest = _manifest
          ..region = _region;
        showMapsSheet(ctx, c);
      },
      0,
      null
    ),
    'Passphrase dialog, keyboard open': ((ctx) async {
      askPassphrase(ctx, confirm: true);
    }, 900, 'correct horse'),
    'Backup card (signed out)': ((ctx) => push(ctx, const Scaffold(body: SingleChildScrollView(child: Column(children: [BackupCard(), RestoreOnSetupCard()])))), 0, null),
  };

  for (final MapEntry(key: name, value: (open, keyboard, type)) in cases.entries) {
    testWidgets('no overflow at 360 dp: $name', (t) async {
      phone(t);
      final errs = await _check(t, open, keyboard: keyboard, type: type);
      expect(errs, isEmpty, reason: errs.join('\n'));
    });
  }

  test('download limit follows free memory', () async {
    final b = await junctionBudget();
    expect(b, inInclusiveRange(300000, 2500000));
  });
}
