import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../grow/feeds.dart';
import 'market.dart';
import 'money_ui.dart';

const disclaimer = 'Educational analysis of public, ~15-min delayed data. Not SEBI-registered investment advice; decide with your own research.';

Future<void> showStock(BuildContext context, String symbol, String name) =>
    showModalBottomSheet(context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => StockSheet(symbol: symbol, name: name));

String fmtPrice(Quote q, double v) => q.currency == 'INR' ? inr(v, decimals: 2) : '${q.cur}${v.toStringAsFixed(2)}';

/// Detail view: chart with scrub, key stats, trend reading, news and Buddy's take.
class StockSheet extends StatefulWidget {
  final String symbol, name;
  const StockSheet({super.key, required this.symbol, required this.name});
  @override
  State<StockSheet> createState() => _StockSheetState();
}

class _StockSheetState extends State<StockSheet> {
  var _range = '1y';
  Quote? _q, _year;
  int? _scrub;
  String? _error, _take;
  bool _taking = false;
  List<NewsItem> _news = [];

  @override
  void initState() {
    super.initState();
    _load();
    _loadNews();
  }

  Future<void> _load() async {
    try {
      final q = await Market.chart(widget.symbol, range: _range);
      final y = _range == '1y' ? q : await Market.chart(widget.symbol);
      if (mounted) {
        setState(() {
          _q = q;
          _year = y;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Couldn’t load prices. Check your connection.');
    }
  }

  Future<void> _loadNews() async {
    final clean = widget.name.replaceAll(RegExp(r'\b(Limited|Ltd\.?|Inc\.?|Corporation|Corp\.?)\b', caseSensitive: false), '').trim();
    final f = Feed('stock_${widget.symbol}', clean, '📈', 'https://news.google.com/rss/search?q=${Uri.encodeQueryComponent('"$clean" stock')}&hl=en-IN&gl=IN&ceid=IN:en');
    try {
      final n = await Feeds.load(f);
      if (mounted) setState(() => _news = n.take(5).toList());
    } catch (_) {}
  }

  Future<void> _ask() async {
    final q = _year;
    if (q == null) return;
    setState(() => _taking = true);
    final t = trendOf(q);
    final held = Market.holdings.where((h) => h.symbol == q.symbol).firstOrNull;
    final facts = [
      '${q.name} (${q.symbol}), price ${q.cur}${q.price.toStringAsFixed(2)}, today ${pct(q.changePct)}.',
      '1M ${_f(q.ret(21))}, 6M ${_f(q.ret(126))}, 1Y ${_f(q.ret(250))}. 52w high ${q.hi52?.toStringAsFixed(2)}, low ${q.lo52?.toStringAsFixed(2)}, from high ${_f(q.fromHigh)}.',
      '50DMA ${q.sma(50)?.toStringAsFixed(2)}, 200DMA ${q.sma(200)?.toStringAsFixed(2)}, RSI14 ${q.rsi?.round()}, volatility ${q.volatility?.round()}%/yr. Trend score ${t.score}/100.',
      if (held != null) 'User holds ${held.qty} at avg ${held.avg} (P&L ${_f((q.price / held.avg - 1) * 100)}).',
      'User risk appetite: ${Market.risk}.',
      if (_news.isNotEmpty) 'Recent headlines: ${_news.map((n) => n.title).join(' | ')}',
    ].join('\n');
    final r = await askBuddy(
      'You are Buddy, a careful, honest equity research assistant for an Indian retail investor. Use ONLY the data given; never invent numbers or facts. '
          'Format (plain text, no markdown headers):\nVerdict: <Consider buying | Accumulate slowly (SIP) | Hold | Wait for a better price | Avoid for now>\n'
          'Why: 3 short bullets\nRisks: 2 short bullets\nFor you: one line tailored to their risk appetite and holding.\n'
          'Be balanced; prefer diversification and index funds for the core of a portfolio. Never promise returns.',
      facts,
      maxTokens: 900,
    );
    if (mounted) {
      setState(() {
        _taking = false;
        _take = r ?? _ruleTake(t);
      });
    }
  }

  static String _f(double? v) => v == null ? 'n/a' : pct(v);

  String _ruleTake(Trend t) =>
      'Trend reading: ${t.label} (${t.score}/100).\n${t.good.map((g) => '✓ $g').join('\n')}\n${t.bad.map((b) => '✗ $b').join('\n')}\n\nTurn on the cloud brain for a full written analysis.';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final q = _q;
    final y = _year;
    final shown = q == null ? null : (_scrub == null ? q.price : q.closes[_scrub!]);
    final first = q == null || q.closes.isEmpty ? 0.0 : q.closes.first;
    final rangeChange = q == null || first == 0 ? 0.0 : ((shown ?? q.price) / first - 1) * 100;
    final color = gainColor(context, rangeChange == 0 ? 1 : rangeChange);
    final trend = y == null ? null : trendOf(y);
    final watched = Market.watchlist.any((w) => w.$1 == widget.symbol);

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
            tooltip: watched ? 'Remove from watchlist' : 'Add to watchlist',
            onPressed: () async {
              await Market.toggleWatch(widget.symbol, widget.name);
              setState(() {});
            },
            icon: Icon(watched ? Icons.star : Icons.star_border),
          ),
        ]),
        const SizedBox(height: 12),
        if (_error != null) Text(_error!, style: TextStyle(color: cs.error)),
        if (q == null && _error == null) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
        if (q != null) ...[
          Text(fmtPrice(q, shown!), style: tt.headlineLarge?.copyWith(fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()])),
          Row(children: [
            ChangePill(rangeChange),
            const SizedBox(width: 8),
            Text(_scrub == null ? 'past ${_rangeLabel(_range)}' : _date(q.times[_scrub!]), style: tt.bodySmall),
            const Spacer(),
            if (_scrub == null) Text('Today ', style: tt.bodySmall),
            if (_scrub == null) ChangePill(q.changePct),
          ]),
          const SizedBox(height: 12),
          PriceChart(values: q.closes, times: q.times, color: color, onScrub: (i) => setState(() => _scrub = i)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [ButtonSegment(value: '1mo', label: Text('1M')), ButtonSegment(value: '6mo', label: Text('6M')), ButtonSegment(value: '1y', label: Text('1Y')), ButtonSegment(value: '5y', label: Text('5Y'))],
            selected: {_range},
            onSelectionChanged: (v) {
              setState(() => _range = v.first);
              _load();
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
          BuddyTakeCard(text: _take, loading: _taking, onAsk: _ask, askLabel: 'Analyse', footnote: disclaimer),
        ],
        if (_news.isNotEmpty) ...[
          Padding(padding: const EdgeInsets.fromLTRB(4, 16, 4, 6), child: Text('News', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
          for (final n in _news)
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

  static String _rangeLabel(String r) => switch (r) { '1mo' => 'month', '6mo' => '6 months', '5y' => '5 years', _ => 'year' };
  static String _date(DateTime d) => '${d.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]} ${d.year}';
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
