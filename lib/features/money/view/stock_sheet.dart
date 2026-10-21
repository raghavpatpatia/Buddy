import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/arch/load_state.dart';
import '../controller/stock_controller.dart';
import '../model/market.dart';
import 'widgets.dart';

const disclaimer = 'Educational analysis of public, ~15-min delayed data. Not SEBI-registered investment advice; decide with your own research.';

Future<void> showStock(BuildContext context, String symbol, String name) =>
    showModalBottomSheet(context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => StockSheet(symbol: symbol, name: name));

String fmtPrice(Quote q, double v) => q.currency == 'INR' ? inr(v, decimals: 2) : '${q.cur}${v.toStringAsFixed(2)}';

/// Stock detail: scrubbable chart, key stats, trend reading, news and Buddy's take.
class StockSheet extends StatefulWidget {
  final String symbol, name;
  final StockController? controller;
  const StockSheet({super.key, required this.symbol, required this.name, this.controller});
  @override
  State<StockSheet> createState() => _StockSheetState();
}

class _StockSheetState extends State<StockSheet> {
  late final c = widget.controller ?? StockController(widget.symbol, widget.name);
  int? _scrub;

  @override
  void initState() {
    super.initState();
    c.load();
    c.loadNews();
  }

  @override
  void dispose() {
    if (widget.controller == null) c.dispose();
    super.dispose();
  }

  static String _f(double? v) => v == null ? '—' : pct(v);
  static String _rangeLabel(String r) => switch (r) { '1mo' => 'month', '6mo' => '6 months', '5y' => '5 years', _ => 'year' };
  static String _date(DateTime d) => '${d.day} ${monthShort[d.month - 1]} ${d.year}';

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: c, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final q = c.chart.data;
    final y = c.year;
    final trend = c.trend;
    final hasChart = q != null && q.closes.length >= 2;
    final scrub = !hasChart || _scrub == null ? null : _scrub!.clamp(0, q.closes.length - 1);
    final shown = q == null ? null : (scrub == null ? q.price : q.closes[scrub]);
    final first = q == null || q.closes.isEmpty ? 0.0 : q.closes.first;
    final rangeChange = q == null || first == 0 ? 0.0 : (shown! / first - 1) * 100;
    final color = gainColor(context, rangeChange == 0 ? 1 : rangeChange);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      maxChildSize: 0.97,
      builder: (_, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.name, style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800), maxLines: 2, overflow: TextOverflow.ellipsis),
              Text(widget.symbol, style: tt.bodySmall),
            ]),
          ),
          IconButton.filledTonal(
            tooltip: c.watched ? 'Remove from watchlist' : 'Add to watchlist',
            onPressed: c.toggleWatch,
            icon: Icon(c.watched ? Icons.star : Icons.star_border),
          ),
        ]),
        const SizedBox(height: 12),
        if (c.chart case Failed(:final message)) Text(message, style: TextStyle(color: cs.error)),
        if (q == null && c.chart is! Failed) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
        if (q != null) ...[
          Text(fmtPrice(q, shown!), style: tt.headlineLarge?.copyWith(fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()])),
          Row(children: [
            ChangePill(rangeChange),
            const SizedBox(width: 8),
            Text(scrub == null ? 'past ${_rangeLabel(c.range)}' : _date(q.times[scrub]), style: tt.bodySmall),
            const Spacer(),
            if (scrub == null) Text('Today ', style: tt.bodySmall),
            if (scrub == null) ChangePill(q.changePct),
          ]),
          const SizedBox(height: 12),
          if (hasChart)
            PriceChart(values: q.closes, times: q.times, color: color, onScrub: (i) => setState(() => _scrub = i))
          else
            const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: Text('No price history for this range yet.'))),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [ButtonSegment(value: '1mo', label: Text('1M')), ButtonSegment(value: '6mo', label: Text('6M')), ButtonSegment(value: '1y', label: Text('1Y')), ButtonSegment(value: '5y', label: Text('5Y'))],
            selected: {c.range},
            onSelectionChanged: (v) {
              setState(() => _scrub = null);
              c.setRange(v.first);
            },
          ),
        ],
        if (y != null && trend != null) ...[
          const SizedBox(height: 16),
          _TrendCard(trend),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 2.6,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            children: [
              _Stat('52-week high', y.hi52 == null ? '—' : fmtPrice(y, y.hi52!)),
              _Stat('52-week low', y.lo52 == null ? '—' : fmtPrice(y, y.lo52!)),
              _Stat('From 52w high', _f(y.fromHigh)),
              _Stat('1-year return', _f(y.ret(250))),
              _Stat('50 / 200-day avg', '${y.sma(50)?.toStringAsFixed(0) ?? '—'} / ${y.sma(200)?.toStringAsFixed(0) ?? '—'}'),
              _Stat('RSI · Volatility', '${y.rsi?.round() ?? '—'} · ${y.volatility?.round() ?? '—'}%'),
            ],
          ),
          const SizedBox(height: 8),
          BuddyTakeCard(text: c.take.data, loading: c.take.isLoading, onAsk: c.analyse, askLabel: 'Analyse', footnote: disclaimer),
        ],
        if (c.news.isNotEmpty) ...[
          Padding(padding: const EdgeInsets.fromLTRB(4, 16, 4, 6), child: Text('News', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
          for (final n in c.news)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(n.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: tt.bodyMedium),
              subtitle: Text(n.source, style: tt.labelSmall),
              trailing: const Icon(Icons.open_in_new, size: 16),
              onTap: () => launchUrl(Uri.parse(n.link), mode: LaunchMode.externalApplication),
            ),
        ],
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  const _Stat(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(label, style: tt.labelSmall, maxLines: 1),
        FittedBox(child: Text(value, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()]))),
      ]),
    );
  }
}

class _TrendCard extends StatelessWidget {
  final Trend t;
  const _TrendCard(this.t);
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final c = t.score >= 65 ? gainColor(context, 1) : t.score >= 45 ? Colors.orange : gainColor(context, -1);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 56,
            height: 56,
            child: Stack(alignment: Alignment.center, children: [
              CircularProgressIndicator(value: t.score / 100, strokeWidth: 6, color: c, strokeCap: StrokeCap.round),
              Text('${t.score}', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ]),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.label, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: c)),
              for (final g in t.good.take(3)) Text('✓ $g', style: tt.bodySmall),
              for (final b in t.bad.take(3)) Text('✗ $b', style: tt.bodySmall),
            ]),
          ),
        ]),
      ),
    );
  }
}
