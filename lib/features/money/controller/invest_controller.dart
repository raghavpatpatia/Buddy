
import '../../../core/arch/load_state.dart';
import '../../../core/arch/safe_notifier.dart';
import '../data/ai.dart';
import '../data/market_api.dart';
import '../data/money_store.dart';
import '../model/market.dart';

/// Portfolio value, cost and today's change in rupees.
typedef Portfolio = ({double value, double cost, double today});

/// Invest tab logic: market strip, holdings, watchlist, trend-ranked ideas and AI picks.
class InvestController extends SafeNotifier {
  InvestController({MarketApi? api, MoneyStore? store, this._ask = askBuddy})
      : _api = api ?? MarketApi.instance,
        _store = store ?? MoneyStore.instance {
    _store.holdings.addListener(_onLists);
    _store.watchlist.addListener(_onLists);
  }

  final MarketApi _api;
  final MoneyStore _store;
  final AiAsk _ask;

  LoadState<List<Quote>> indicesState = const Idle();
  LoadState<List<(Quote, Trend)>> ideas = const Idle();
  LoadState<String> picks = const Idle();
  final quotes = <String, Quote>{};
  int _ideasTicket = 0;

  List<Holding> get holdings => _store.holdings.all.toList();
  List<WatchItem> get watchlist => _store.watchlist.all.toList();
  String get risk => _store.risk;
  double get usdInr => indicesState.data?.where((q) => q.symbol == 'INR=X').firstOrNull?.price ?? 84;

  double inInr(Quote q, double v) => q.currency == 'USD' ? v * usdInr : v;

  Portfolio get portfolio {
    var value = 0.0, cost = 0.0, today = 0.0;
    for (final h in holdings) {
      final q = quotes[h.symbol];
      if (q == null) continue;
      value += inInr(q, q.price * h.qty);
      cost += inInr(q, h.avg * h.qty);
      today += inInr(q, q.price * h.qty * q.changePct / (100 + q.changePct));
    }
    return (value: value, cost: cost, today: today);
  }

  void _onLists() {
    notifyListeners();
    loadMine();
  }

  Future<void> load() async {
    indicesState = Loading(indicesState.data);
    notifyListeners();
    final idx = await _api.charts([for (final i in indices) i.$1], range: '1mo');
    indicesState = idx.isEmpty ? const Failed('Market data unavailable. Pull to retry.') : Ready(idx);
    notifyListeners();
    await loadMine();
    await loadIdeas();
  }

  Future<void> loadMine() async {
    final syms = {...holdings.map((h) => h.symbol), ...watchlist.map((w) => w.symbol)}.toList();
    for (final q in await _api.charts(syms)) {
      quotes[q.symbol] = q;
    }
    notifyListeners();
  }

  bool _fitsRisk(Quote q) {
    final etf = q.symbol.contains('BEES') || q.symbol == 'VOO' || q.symbol == 'QQQ';
    final vol = q.volatility ?? 30;
    return switch (risk) { 'low' => etf || vol < 22, 'medium' => vol < 38, _ => true };
  }

  /// Ranks [ideaUniverse] by trend score, filtered by the user's risk level.
  Future<void> loadIdeas() async {
    final ticket = ++_ideasTicket;
    ideas = Loading(ideas.data);
    notifyListeners();
    final qs = await _api.charts(ideaUniverse);
    if (ticket != _ideasTicket) return;
    final ranked = [for (final q in qs.where(_fitsRisk)) (q, trendOf(q))]..sort((a, b) => b.$2.score.compareTo(a.$2.score));
    ideas = Ready(ranked.take(6).toList());
    notifyListeners();
  }

  Future<void> setRisk(String r) async {
    await _store.setRisk(r);
    await loadIdeas();
  }

  Future<void> saveHolding(Holding h) => _store.holdings.put(h);

  Future<void> removeHolding(String symbol) => _store.holdings.remove(symbol);

  bool isWatched(String symbol) => _store.watchlist.contains(symbol);

  Future<void> toggleWatch(String symbol, String name) =>
      isWatched(symbol) ? _store.watchlist.remove(symbol) : _store.watchlist.put(WatchItem(symbol, name));

  Future<List<(String, String, String)>> search(String q) => _api.search(q);

  Future<void> askPicks() async {
    picks = const Loading();
    notifyListeners();
    final ideaLines = (ideas.data ?? []).map((e) => '${e.$1.name} (${e.$1.symbol}): score ${e.$2.score}, 1Y ${e.$1.ret(250)?.toStringAsFixed(0)}%, from high ${e.$1.fromHigh?.toStringAsFixed(0)}%, vol ${e.$1.volatility?.round()}%').join('\n');
    final mine = holdings.map((h) {
      final q = quotes[h.symbol];
      return '${h.name}: ${h.qty} @ ${h.avg}${q == null ? '' : ', now ${q.price.toStringAsFixed(2)} (${((q.price / h.avg - 1) * 100).toStringAsFixed(1)}%)'}';
    }).join('\n');
    final mkt = (indicesState.data ?? []).map((q) => '${indices.firstWhere((i) => i.$1 == q.symbol).$2} ${(q.ret(20) ?? 0).toStringAsFixed(1)}% 1M').join(', ');
    final r = await _ask(
      'You are Buddy, an honest, careful investing coach for an Indian retail investor. Use ONLY the data given; never invent numbers. '
          'Give: 1) one line on the market mood, 2) up to 3 ideas from the list worth researching and why (1 line each), 3) one line on their own portfolio (concentration/diversification), '
          '4) a reminder that a core of index funds + SIPs beats picking stocks for most people. Plain text, short, no markdown headers. Never promise returns.',
      'Risk appetite: $risk.\nMarkets (1 month): $mkt\nTrend-ranked ideas:\n$ideaLines\nTheir holdings:\n${mine.isEmpty ? 'none' : mine}',
      maxTokens: 900,
    );
    picks = r == null ? const Failed('Turn on the cloud brain (Talk → brain icon) for Buddy’s written picks. The trend ranking above is updated live.') : Ready(r);
    notifyListeners();
  }

  @override
  void dispose() {
    _store.holdings.removeListener(_onLists);
    _store.watchlist.removeListener(_onLists);
    super.dispose();
  }
}
