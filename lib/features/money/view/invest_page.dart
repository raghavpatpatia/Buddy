import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/arch/load_state.dart';
import '../../../shared/ui.dart';
import '../controller/invest_controller.dart';
import '../model/market.dart';
import 'stock_sheet.dart';
import 'widgets.dart';

/// Money → Invest: market pulse, portfolio, trend-ranked ideas and watchlist.
class InvestPage extends StatefulWidget {
  final InvestController? controller;
  const InvestPage({super.key, this.controller});
  @override
  State<InvestPage> createState() => _InvestPageState();
}

class _InvestPageState extends State<InvestPage> {
  late final c = widget.controller ?? InvestController();

  @override
  void initState() {
    super.initState();
    c.load();
  }

  @override
  void dispose() {
    if (widget.controller == null) c.dispose();
    super.dispose();
  }

  Future<void> _open(String symbol, String name) async {
    await showStock(context, symbol, name);
    c.loadMine();
  }

  Future<void> _search() async {
    final picked = await showSearch<(String, String)?>(context: context, delegate: _StockSearch(c.search));
    if (picked != null && mounted) _open(picked.$1, picked.$2);
  }

  Future<void> _editHolding([Holding? h]) async {
    var pick = h == null ? null : (h.symbol, h.name);
    pick ??= await showSearch<(String, String)?>(context: context, delegate: _StockSearch(c.search));
    if (pick == null || !mounted) return;
    final sym = pick;
    final qty = TextEditingController(text: h == null ? '' : _num(h.qty)), avg = TextEditingController(text: h == null ? '' : _num(h.avg));
    var tried = false;
    final res = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (s) => StatefulBuilder(
        builder: (s, set) {
          final qv = parseAmount(qty.text, max: 1e9), av = parseAmount(avg.text, max: 1e7);
          return Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(s).bottom),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(sym.$2, style: Theme.of(s).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              Text(sym.$1, style: Theme.of(s).textTheme.bodySmall),
              const SizedBox(height: 12),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: TextField(
                    controller: qty,
                    autofocus: true,
                    onChanged: (_) => set(() {}),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: 'Quantity', errorText: tried && qv == null ? 'Enter a number above 0' : null),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: avg,
                    onChanged: (_) => set(() {}),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: 'Avg buy price', errorText: tried && av == null ? 'Enter a price above 0' : null),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => qv != null && av != null ? Navigator.pop(s, 'save') : set(() => tried = true),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: const Text('Save holding'),
              ),
              if (h != null) TextButton(onPressed: () => Navigator.pop(s, 'delete'), child: const Text('Remove holding')),
            ]),
          );
        },
      ),
    );
    final q = parseAmount(qty.text, max: 1e9), a = parseAmount(avg.text, max: 1e7);
    qty.dispose();
    avg.dispose();
    if (res == 'delete') await c.removeHolding(sym.$1);
    if (res == 'save' && q != null && a != null) {
      HapticFeedback.lightImpact();
      await c.saveHolding(Holding(sym.$1, sym.$2, q, a));
    }
  }

  static String _num(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toString();

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: c, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final holdings = c.holdings;
    final p = c.portfolio;
    final pnl = p.value - p.cost;
    final idx = c.indicesState;
    final ideas = c.ideas.data ?? const [];

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: c.load,
        child: ListView(padding: pagePadding.copyWith(bottom: 32), children: [
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
          SizedBox(
            height: 92,
            child: idx.data == null && idx.isLoading
                ? const Center(child: LinearProgressIndicator())
                : ListView(scrollDirection: Axis.horizontal, children: [for (final q in idx.data ?? const <Quote>[]) _IndexCard(q)]),
          ),
          if (idx case Failed(:final message)) Padding(padding: const EdgeInsets.only(top: 6), child: Text(message, style: TextStyle(color: cs.error))),
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
                  FittedBox(child: Text(inr(p.value), style: tt.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1, fontFeatures: const [FontFeature.tabularFigures()]))),
                  const SizedBox(height: 8),
                  Wrap(spacing: 12, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [Text('Total ', style: tt.bodySmall), ChangePill(pnl, text: '${inr(pnl, sign: true)} (${pct(p.cost == 0 ? 0 : pnl / p.cost * 100)})')]),
                    Row(mainAxisSize: MainAxisSize.min, children: [Text('Today ', style: tt.bodySmall), ChangePill(p.today, text: inr(p.today, sign: true))]),
                  ]),
                ]),
              ),
            ),
            Card(
              child: Column(children: [
                for (final h in holdings)
                  _HoldingTile(h, quote: c.quotes[h.symbol], valueInr: (q) => c.inInr(q, q.price * h.qty), onTap: () => _open(h.symbol, h.name), onLongPress: () => _editHolding(h)),
              ]),
            ),
            Padding(padding: const EdgeInsets.only(left: 8, top: 2), child: Text('Long-press a holding to edit.', style: tt.labelSmall)),
          ],
          SectionTitle('Ideas for you', trailing: c.ideas.isLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : null),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [ButtonSegment(value: 'low', label: Text('🛡️ Safe')), ButtonSegment(value: 'medium', label: Text('⚖️ Balanced')), ButtonSegment(value: 'high', label: Text('🚀 Bold'))],
            selected: {c.risk},
            onSelectionChanged: (v) => c.setRisk(v.first),
          ),
          const SizedBox(height: 8),
          for (final (q, t) in ideas)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 3),
              child: ListTile(
                onTap: () => _open(q.symbol, q.name),
                leading: _ScoreBadge(t.score),
                title: Text(q.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(t.good.isNotEmpty ? t.good.first : t.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(fmtPrice(q, q.price), style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
                  Text('1Y ${pct(q.ret(250) ?? 0)}', style: TextStyle(fontSize: 12, color: gainColor(context, q.ret(250) ?? 0))),
                ]),
              ),
            ),
          if (!c.ideas.isLoading && ideas.isNotEmpty) ...[
            const SizedBox(height: 4),
            BuddyTakeCard(
              text: switch (c.picks) { Ready(:final value) => value, Failed(:final message) => message, _ => null },
              loading: c.picks.isLoading,
              onAsk: c.askPicks,
              askLabel: 'Buddy’s picks',
              footnote: disclaimer,
            ),
          ],
          const SectionTitle('Watchlist'),
          if (c.watchlist.isEmpty)
            const EmptyState(emoji: '⭐', title: 'Nothing watched yet', subtitle: 'Tap ☆ on any stock to follow it here.')
          else
            Card(child: Column(children: [for (final w in c.watchlist) _WatchTile(w, quote: c.quotes[w.symbol], onTap: () => _open(w.symbol, w.name))])),
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text('Prices from Yahoo Finance, ~15 min delayed for NSE/BSE.', textAlign: TextAlign.center, style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
          ),
        ]),
      ),
    );
  }
}

class _IndexCard extends StatelessWidget {
  final Quote q;
  const _IndexCard(this.q);
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Card(
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
    );
  }
}

class _HoldingTile extends StatelessWidget {
  final Holding h;
  final Quote? quote;
  final double Function(Quote) valueInr;
  final VoidCallback onTap, onLongPress;
  const _HoldingTile(this.h, {required this.quote, required this.valueInr, required this.onTap, required this.onLongPress});
  @override
  Widget build(BuildContext context) {
    final q = quote;
    final p = q == null ? null : (q.price / h.avg - 1) * 100;
    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      title: Text(h.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text('${_InvestPageState._num(h.qty)} × ${q == null ? '…' : fmtPrice(q, q.price)}'),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(q == null ? '…' : inr(valueInr(q)), style: const TextStyle(fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
        if (p != null) Text(pct(p), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: gainColor(context, p))),
      ]),
    );
  }
}

class _WatchTile extends StatelessWidget {
  final WatchItem w;
  final Quote? quote;
  final VoidCallback onTap;
  const _WatchTile(this.w, {required this.quote, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final q = quote;
    return ListTile(
      onTap: onTap,
      title: Text(w.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(w.symbol),
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

/// Stock search with popular picks before typing.
class _StockSearch extends SearchDelegate<(String, String)?> {
  final Future<List<(String, String, String)>> Function(String) find;
  final _cache = <String, Future<List<(String, String, String)>>>{};
  _StockSearch(this.find);

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
    final pending = _cache.putIfAbsent(q, () => Future.delayed(const Duration(milliseconds: 350), () {
          if (q == query.trim()) return find(q);
          _cache.remove(q);
          return const <(String, String, String)>[];
        }));
    return FutureBuilder<List<(String, String, String)>>(
      future: pending,
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator();
        if (q != query.trim()) return const LinearProgressIndicator();
        if (snap.hasError) {
          _cache.remove(q);
          return const EmptyState(emoji: '📡', title: 'Couldn’t search', subtitle: 'Check your internet connection and try again.');
        }
        final r = snap.data ?? const [];
        if (r.isEmpty) return const EmptyState(emoji: '🔎', title: 'No matches', subtitle: 'Try the company name or NSE symbol.');
        return ListView(children: [
          for (final (s, n, ex) in r) ListTile(title: Text(n), subtitle: Text('$s · $ex'), onTap: () => close(context, (s, n))),
        ]);
      },
    );
  }
}
