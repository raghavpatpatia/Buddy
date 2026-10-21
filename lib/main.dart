import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/background.dart';
import 'core/native.dart';
import 'core/store.dart';
import 'features/buddy_page.dart';
import 'features/brief.dart';
import 'features/celebrate.dart';
import 'features/grow/growth.dart';
import 'features/money/tracking.dart';
import 'features/sections.dart';
import 'features/setup_page.dart';
import 'features/ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.init();
  await Store.migrateDanceToFit();
  runApp(const BuddyApp());
  if (Store.raw.getBool('setup_done') == true) {
    // Idempotent: make sure the 24x7 companion and background jobs are alive.
    // Done after the first frame so app start isn't blocked.
    unawaited(Native.startCompanion());
    unawaited(registerBackgroundJobs());
  }
}

class BuddyApp extends StatefulWidget {
  const BuddyApp({super.key});
  @override
  State<BuddyApp> createState() => _BuddyAppState();
}

class _BuddyAppState extends State<BuddyApp> {
  bool _setup = Store.raw.getBool('setup_done') == true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Buddy',
      debugShowCheckedModeBanner: false,
      // Indian English: dates are typed and shown as DD/MM/YYYY (the default en_US would read 05/08 as May 8).
      locale: const Locale('en', 'IN'),
      supportedLocales: const [Locale('en', 'IN'), Locale('en', 'US')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buddyTheme(Brightness.light),
      darkTheme: buddyTheme(Brightness.dark),
      home: _setup ? const HomeShell() : SetupPage(onDone: () => setState(() => _setup = true)),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;
  bool _gateOpen = false;

  @override
  void initState() {
    super.initState();
    navRequest.addListener(_onNav);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _dailyCheck());
  }

  @override
  void dispose() {
    navRequest.removeListener(_onNav);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _dailyCheck();
  }

  /// Penalties for missed days, native sync, morning-brief refresh and the forced growth check.
  Future<void> _dailyCheck() async {
    await Store.init();
    final missed = await Store.applyMissedGrowthPenalties();
    await syncGrowth();
    await syncBrief();
    // Read tracking: import the setup file once (if the deploy script left one) and check for new opens.
    unawaited(MailTracker.importSetupFile().then((_) => MailTracker.poll()).then((_) {}, onError: (_) {}));
    final last = DateTime.tryParse(Store.raw.getString('brief_prepared_at') ?? '');
    if (last == null || DateTime.now().difference(last).inMinutes > 60) {
      await Store.raw.setString('brief_prepared_at', DateTime.now().toIso8601String());
      unawaited(prepareBrief());
    }
    if (!mounted) return;
    if (missed > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('You skipped your growth tasks on $missed day${missed == 1 ? '' : 's'}: −${missed * Store.growthPenaltyXp} XP. Let’s do today’s! 🌱'),
      ));
    }
    if (growthDue() && !_gateOpen) {
      _gateOpen = true;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GrowthGatePage(forced: true), fullscreenDialog: true));
      _gateOpen = false;
      if (mounted) setState(() {});
    }
  }

  void _onNav() {
    final r = navRequest.value;
    if (r != null) setState(() => _tab = r.$1);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [const BuddyPage(), growSection(), healthSection(), moneySection(), phoneSection()];
    final growthPending = Store.growthEnabled && !Store.growthDoneToday && !Store.growthSkippedToday;
    return Scaffold(
      // Key includes the pending sub-tab so a quick action can open e.g. Grow → Practice directly.
      body: GameLayer(
        onChanged: () => mounted ? setState(() {}) : null,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: KeyedSubtree(key: ValueKey((_tab, navRequest.value)), child: pages[_tab]),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          HapticFeedback.selectionClick();
          setState(() => _tab = i);
        },
        destinations: [
          const NavigationDestination(icon: Icon(Icons.smart_toy_outlined), selectedIcon: Icon(Icons.smart_toy), label: 'Buddy'),
          NavigationDestination(
            icon: Badge(isLabelVisible: growthPending, child: const Icon(Icons.local_florist_outlined)),
            selectedIcon: Badge(isLabelVisible: growthPending, child: const Icon(Icons.local_florist)),
            label: 'Grow',
          ),
          const NavigationDestination(icon: Icon(Icons.favorite_outline), selectedIcon: Icon(Icons.favorite), label: 'Health'),
          const NavigationDestination(icon: Icon(Icons.currency_rupee), selectedIcon: Icon(Icons.currency_rupee), label: 'Money'),
          const NavigationDestination(icon: Icon(Icons.smartphone_outlined), selectedIcon: Icon(Icons.smartphone), label: 'Phone'),
        ],
      ),
    );
  }
}
