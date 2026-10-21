import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui.dart';
import 'market.dart';
import 'money_ui.dart';
import 'stock_sheet.dart';

/// Money → Invest: market pulse, your portfolio, ideas ranked by trend, watchlist.
class InvestPage extends StatefulWidget {
  const InvestPage({super.key});
  @override
  State<InvestPage> createState() => _InvestPageState();
}

class _InvestPageState extends State<InvestPage> {
  List<Quote> _indices = [];
  final _quotes = <String, Quote>{};
  List<(Quote, Trend)> _ideas = [];
  bool _loading = true, _ideasLoading = true;
  String? _error, _picks;
  bool _picksLoading = false;

  @override
  void initState() {
    super.initState();
    Market.changed.addListener(_onChanged);
    _load();
  }

  @override
  void dispose() {
    Market.changed.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
    _loadMine();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _indices = await Market.charts([for (final i in indices) i.$1], range: '1mo');
      if (_indices.isEmpty) _error = 'Market data unavailable. Pull to retry.';
    } catch (_) {
      _error = 'Market data unavailable. Pull to retry.';
    }
    await _loadMine();
    if (mounted) setState(() => _loading = false);
    _loadIdeas();
  }

  Future<void> _loadMine() async {
    final syms = {...Market.holdings.map((h) => h.symbol), ...Market.watchlist.map((w) => w.$1)}.toList();
    for (final q in await Market.charts(syms)) {
      _quotes[q.symbol] = q;
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadIdeas() async {
    setState(() => _ideasLoading = true);
    final qs = await Market.charts(ideaUniverse);
    final risk = Market.risk;
    bool fits(Quote q) {
      final etf = q.symbol.contains('BEES') || q.symbol == 'VOO' || q.symbol == 'QQQ';
      final vol = q.volatility ?? 30;
      return switch (risk) { 'low' => etf || vol < 22, 'medium' => vol < 38, _ => true };
    }

    final ranked = [for (final q in qs.where(fits)) (q, trendOf(q))]..sort((a, b) => b.$2.score.compareTo(a.$2.score));
    if (mounted) {
      setState(() {
        _ideas = ranked.take(6).toList();
        _ideasLoading = false;
      });
    }
  }

  double get _usdInr => _indices.where((q) => q.symbol == 'INR=X').firstOrNull?.price ?? 84;
  double _inInr(Quote q, double v) => q.currency == 'USD' ? v * _usdInr : v;

  Future<void> _askPicks() async {
    setState(() => _picksLoading = true);
    final ideas = _ideas.map((e) => '${e.$1.name} (${e.$1.symbol}): score ${e.$2.score}, 1Y ${e.$1.ret(250)?.toStringAsFixed(0)}%, from high ${e.$1.fromHigh?.toStringAsFixed(0)}%, vol ${e.$1.volatility?.round()}%').join('\n');
    final mine = Market.holdings.map((h) {
      final q = _quotes[h.symbol];
      return '${h.name}: ${h.qty} @ ${h.avg}${q == null ? '' : ', now ${q.price.toStringAsFixed(2)} (${pct((q.price / h.avg - 1) * 100)})'}';
    }).join('\n');
    final mkt = _indices.map((q) => '${indices.firstWhere((i) => i.$1 == q.symbol).$2} ${pct(q.ret(20) ?? 0)} 1M').join(', ');
    final r = await askBuddy(
      'You are Buddy, an honest, careful investing coach for an Indian retail investor. Use ONLY the data given; never invent numbers. '
          'Give: 1) one line on the market mood, 2) up to 3 ideas from the list worth researching and why (1 line each), 3) one line on their own portfolio (concentration/diversification), '
          '4) a reminder that a core of index funds + SIPs beats picking stocks for most people. Plain text, short, no markdown headers. Never promise returns.',
      'Risk appetite: ${Market.risk}.\nMarkets (1 month): $mkt\nTrend-ranked ideas:\n$ideas\nTheir holdings:\n${mine.isEmpty ? 'none' : mine}',
      maxTokens: 900,
    );
    if (mounted) {
      setState(() {
        _picksLoading = false;
        _picks = r ?? 'Turn on the cloud brain (Talk → brain icon) for Buddy’s written picks. The trend ranking above is updated live.';
      });
    }
  }

  Future<void> _search() async {
    final picked = await showSearch<(String, String)?>(context: context, delegate: _StockSearch());
    if (picked != null && mounted) showStock(context, picked.$1, picked.$2).then((_) => _onChanged());
  }

  Future<void> _editHolding([Holding? h]) async {
    (String, String)? sym = h == null ? null : (h.symbol, h.name);
    if (sym == null) {
      sym = await showSearch<(String, String)?>(context: context, delegate: _StockSearch());
      if (sym == null || !mounted) return;
    }
    final pick = sym;
    final qty = TextEditingController(text: h == null ? '' : _num(h.qty)), avg = TextEditingController(text: h == null ? '' : _num(h.avg));
    final res = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(c).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(pick.$2, style: Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          Text(pick.$1, style: Theme.of(c).textTheme.bodySmall),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: qty, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Quantity'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: avg, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Avg buy price'))),
          ]),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => Navigator.pop(c, 'save'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)), child: const Text('Save holding')),
          if (h != null) TextButton(onPressed: () => Navigator.pop(c, 'delete'), child: const Text('Remove holding')),
        ]),
      ),
    );
    final list = Market.holdings..removeWhere((x) => x.symbol == pick.$1);
    final q = double.tryParse(qty.text), a = double.tryParse(avg.text);
    qty.dispose();
    avg.dispose();
    if (res == 'delete') await Market.saveHoldings(list);
    if (res == 'save' && q != null && q > 0 && a != null && a > 0) {
      HapticFeedback.lightImpact();
      await Market.saveHoldings([...list, Holding(pick.$1, pick.$2, q, a)]);
    }
  }

  static String _num(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toString();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final holdings = Market.holdings;
    var value = 0.0, cost = 0.0, today = 0.0;
    for (final h in holdings) {
      final q = _quotes[h.symbol];
      if (q == null) continue;
      value += _inInr(q, q.price * h.qty);
      cost += _inInr(q, h.avg * h.qty);
      today += _inInr(q, q.price * h.qty * q.changePct / (100 + q.changePct));
    }
    final pnl = value - cost;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: pagePadding.copyWith(bottom: 32), children: [
          // Search bar look-alike: the main entry point
          Card(
            margin: const EdgeInsets.only(top: 8, bottom: 8),
            child: InkWell(
              onTap: _search,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(children: [
                  Icon(Icons.search, color: cs.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Search stocks & ETFs · NSE, BSE, US', maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant))),
                ]),
              ),
            ),
          ),
          // Market pulse
          SizedBox(
            height: 92,
            child: _loading && _indices.isEmpty
                ? const Center(child: LinearProgressIndicator())
                : ListView(scrollDirection: Axis.horizontal, children: [
                    for (final q in _indices)
                      Card(
                        margin: const EdgeInsets.only(right: 8),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Text(indices.firstWhere((i) => i.$1 == q.symbol).$2, style: tt.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                            Row(children: [
                              Text(q.price.toStringAsFixed(q.price < 1000 ? 2 : 0), style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()])),
                              const SizedBox(width: 8),
                              Sparkline(q.closes, color: gainColor(context, q.changePct == 0 ? 1 : q.changePct), width: 44, height: 20),
                            ]),
                            Text(pct(q.changePct), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: gainColor(context, q.changePct))),
                          ]),
                        ),
                      ),
                  ]),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error!, style: TextStyle(color: cs.error))),
          // Portfolio
          SectionTitle('My portfolio', trailing: TextButton.icon(onPressed: () => _editHolding(), icon: const Icon(Icons.add, size: 18), label: const Text('Add'))),
          if (holdings.isEmpty)
            AppCard(
              child: Column(children: [
                const EmptyState(emoji: '💼', title: 'Add what you own', subtitle: 'Add your stocks and ETFs with quantity and buy price. Buddy tracks value and P&L, and tailors ideas to you.'),
                Text('Groww link (₹499/mo Trade API) can be added later.', style: tt.labelSmall),
              ]),
            )
          else ...[
            Card(
              color: cs.primaryContainer.withValues(alpha: 0.55),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Current value', style: tt.labelLarge),
                  FittedBox(child: Text(inr(value), style: tt.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1, fontFeatures: const [FontFeature.tabularFigures()]))),
                  const SizedBox(height: 8),
                  Wrap(spacing: 12, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [Text('Total ', style: tt.bodySmall), ChangePill(pnl, text: '${inr(pnl, sign: true)} (${pct(cost == 0 ? 0 : pnl / cost * 100)})')]),
                    Row(mainAxisSize: MainAxisSize.min, children: [Text('Today ', style: tt.bodySmall), ChangePill(today, text: inr(today, sign: true))]),
                  ]),
                ]),
              ),
            ),
            Card(
              child: Column(children: [
                for (final h in holdings)
                  () {
                    final q = _quotes[h.symbol];
                    final p = q == null ? null : (q.price / h.avg - 1) * 100;
                    return ListTile(
                      onTap: () => showStock(context, h.symbol, h.name).then((_) => _onChanged()),
                      onLongPress: () => _editHolding(h),
                      title: Text(h.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${_num(h.qty)} × ${q == null ? '…' : fmtPrice(q, q.price)}'),
                      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(q == null ? '…' : inr(_inInr(q, q.price * h.qty)), style: const TextStyle(fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
                        if (p != null) Text(pct(p), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: gainColor(context, p))),
                      ]),
                    );
                  }(),
              ]),
            ),
            Padding(padding: const EdgeInsets.only(left: 8, top: 2), child: Text('Long-press a holding to edit.', style: tt.labelSmall)),
          ],
          // Ideas
          SectionTitle('Ideas for you', trailing: _ideasLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : null),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'low', label: Text('🛡️ Safe')),
              ButtonSegment(value: 'medium', label: Text('⚖️ Balanced')),
              ButtonSegment(value: 'high', label: Text('🚀 Bold')),
            ],
            selected: {Market.risk},
            onSelectionChanged: (v) async {
              await Market.setRisk(v.first);
              _loadIdeas();
            },
          ),
          const SizedBox(height: 8),
          for (final (q, t) in _ideas)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 3),
              child: ListTile(
                onTap: () => showStock(context, q.symbol, q.name).then((_) => _onChanged()),
                leading: _ScoreBadge(t.score),
                title: Text(q.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(t.good.isNotEmpty ? t.good.first : t.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(fmtPrice(q, q.price), style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
                  Text('1Y ${pct(q.ret(250) ?? 0)}', style: TextStyle(fontSize: 12, color: gainColor(context, q.ret(250) ?? 0))),
                ]),
              ),
            ),
          if (!_ideasLoading && _ideas.isNotEmpty) ...[
            const SizedBox(height: 4),
            BuddyTakeCard(text: _picks, loading: _picksLoading, onAsk: _askPicks, askLabel: 'Buddy’s picks', footnote: disclaimer),
          ],
          // Watchlist
          const SectionTitle('Watchlist'),
          if (Market.watchlist.isEmpty)
            const EmptyState(emoji: '⭐', title: 'Nothing watched yet', subtitle: 'Tap ☆ on any stock to follow it here.')
          else
            Card(
              child: Column(children: [
                for (final (s, n) in Market.watchlist)
                  () {
                    final q = _quotes[s];
                    return ListTile(
                      onTap: () => showStock(context, s, n).then((_) => _onChanged()),
                      title: Text(n, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(s),
                      trailing: q == null
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Row(mainAxisSize: MainAxisSize.min, children: [
                              Sparkline(q.closes.length > 22 ? q.closes.sublist(q.closes.length - 22) : q.closes, color: gainColor(context, q.ret(21) ?? 0)),
                              const SizedBox(width: 10),
                              Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                                Text(fmtPrice(q, q.price), style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
                                Text(pct(q.changePct), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: gainColor(context, q.changePct))),
                              ]),
                            ]),
                    );
                  }(),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text('Prices from Yahoo Finance, ~15 min delayed for NSE/BSE.', textAlign: TextAlign.center, style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
          ),
        ]),
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  final int score;
  const _ScoreBadge(this.score);
  @override
  Widget build(BuildContext context) {
    final c = score >= 65 ? gainColor(context, 1) : score >= 45 ? Colors.orange : gainColor(context, -1);
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
      child: Text('$score', style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 16)),
    );
  }
}

class _StockSearch extends SearchDelegate<(String, String)?> {
  @override
  String get searchFieldLabel => 'Reliance, NIFTY BEES, Apple…';

  @override
  List<Widget> buildActions(BuildContext context) => [if (query.isNotEmpty) IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear))];
  @override
  Widget buildLeading(BuildContext context) => IconButton(onPressed: () => close(context, null), icon: const Icon(Icons.arrow_back));
  @override
  Widget buildResults(BuildContext context) => _results(context);
  @override
  Widget buildSuggestions(BuildContext context) => _results(context);

  Widget _results(BuildContext context) {
    if (query.trim().length < 2) {
      return ListView(children: [
        for (final (s, n) in const [('NIFTYBEES.NS', 'Nippon India ETF Nifty 50 BeES'), ('RELIANCE.NS', 'Reliance Industries'), ('TCS.NS', 'Tata Consultancy Services'), ('HDFCBANK.NS', 'HDFC Bank'), ('VOO', 'Vanguard S&P 500 ETF'), ('AAPL', 'Apple')])
          ListTile(leading: const Icon(Icons.trending_up), title: Text(n), subtitle: Text(s), onTap: () => close(context, (s, n))),
      ]);
    }
    final q = query.trim();
    return FutureBuilder<List<(String, String, String)>>(
      future: Future.delayed(const Duration(milliseconds: 300), () => q == query.trim() ? Market.search(q) : <(String, String, String)>[]),
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator();
        final r = snap.data ?? [];
        if (r.isEmpty) return const EmptyState(emoji: '🔎', title: 'No matches', subtitle: 'Try the company name or NSE symbol.');
        return ListView(children: [
          for (final (s, n, ex) in r) ListTile(title: Text(n), subtitle: Text('$s · $ex'), onTap: () => close(context, (s, n))),
        ]);
      },
    );
  }

}
