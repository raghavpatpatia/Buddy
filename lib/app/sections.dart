import 'package:flutter/material.dart';

import '../features/phone/view/clean_page.dart';
import '../features/health/view/fit_page.dart';
import '../features/health/view/food_page.dart';
import '../features/jobs/view/jobs_page.dart';
import '../features/grow/view/learn_page.dart';
import '../features/grow/view/news_page.dart';
import '../features/grow/view/practice_page.dart';
import '../features/grow/view/toolbox_page.dart';
import '../features/money/view/invest_page.dart';
import '../features/money/view/mail_page.dart';
import '../features/money/view/spend_page.dart';
import '../features/nav/view/nav_page.dart';
import '../features/phone/view/scroll_page.dart';

/// App-wide navigation requests: (bottom tab, sub-tab). Used by Buddy's quick actions.
final navRequest = ValueNotifier<(int, int)?>(null);

const tabBuddy = 0, tabGrow = 1, tabHealth = 2, tabMoney = 3, tabPhone = 4;

/// A bottom-nav destination that groups related screens behind top tabs.
class SectionPage extends StatefulWidget {
  final String title;
  final List<(String, IconData, Widget)> tabs;
  final int tabIndex;
  const SectionPage({super.key, required this.title, required this.tabs, required this.tabIndex});
  @override
  State<SectionPage> createState() => _SectionPageState();
}

class _SectionPageState extends State<SectionPage> with SingleTickerProviderStateMixin {
  late final _tc = TabController(length: widget.tabs.length, vsync: this, initialIndex: _initial());

  int _initial() {
    final r = navRequest.value;
    if (r != null && r.$1 == widget.tabIndex) {
      navRequest.value = null;
      return r.$2.clamp(0, widget.tabs.length - 1);
    }
    return 0;
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          bottom: TabBar(
            controller: _tc,
            tabs: [for (final (label, icon, _) in widget.tabs) Tab(icon: Icon(icon, size: 20), text: label, iconMargin: const EdgeInsets.only(bottom: 2))],
          ),
        ),
        body: TabBarView(controller: _tc, children: [for (final (_, _, page) in widget.tabs) page]),
      );
}

SectionPage growSection() => const SectionPage(title: 'Grow', tabIndex: tabGrow, tabs: [
      ('Learn', Icons.auto_stories_outlined, LearnPage()),
      ('News', Icons.newspaper_outlined, NewsPage()),
      ('Practice', Icons.graphic_eq, PracticePage()),
      ('Toolbox', Icons.handyman_outlined, ToolboxPage()),
    ]);

SectionPage healthSection() => const SectionPage(title: 'Health', tabIndex: tabHealth, tabs: [
      ('Fit', Icons.directions_run, FitPage(embedded: true)),
      ('Food', Icons.restaurant_outlined, FoodPage(embedded: true)),
    ]);

SectionPage moneySection() => const SectionPage(title: 'Money', tabIndex: tabMoney, tabs: [
      ('Spend', Icons.receipt_long_outlined, SpendPage()),
      ('Invest', Icons.show_chart, InvestPage()),
      ('Mail', Icons.mail_outline, MailPage()),
      ('Jobs', Icons.work_outline, JobsPage()),
    ]);

SectionPage phoneSection() => const SectionPage(title: 'Phone', tabIndex: tabPhone, tabs: [
      ('Scroll', Icons.swipe_vertical_outlined, ScrollPage(embedded: true)),
      ('Clean', Icons.cleaning_services_outlined, CleanPage(embedded: true)),
      ('Map', Icons.map_outlined, NavPage()),
    ]);
