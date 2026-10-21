
import '../../../core/arch/load_state.dart';
import '../../../core/arch/safe_notifier.dart';
import '../../grow/data/feeds.dart';
import '../../grow/model/news.dart';
import '../data/ai.dart';
import '../data/market_api.dart';
import '../data/money_store.dart';
import '../model/market.dart';

/// One stock's detail: chart range, 1-year stats, news, watch toggle and AI analysis.
class StockController extends SafeNotifier {
  StockController(this.symbol, this.name, {MarketApi? api, MoneyStore? store, this._ask = askBuddy})
      : _api = api ?? MarketApi.instance,
        _store = store ?? MoneyStore.instance;

  final String symbol, name;
  final MarketApi _api;
  final MoneyStore _store;
  final AiAsk _ask;

  String range = '1y';
  LoadState<Quote> chart = const Idle();
  Quote? year;
  List<NewsItem> news = const [];
  LoadState<String> take = const Idle();
  int _ticket = 0;

  Trend? get trend => year == null ? null : trendOf(year!);
  bool get watched => _store.watchlist.contains(symbol);

  /// Loads the chart for [range]; if the range changes mid-load, only the newest result is shown.
  Future<void> load() async {
    final ticket = ++_ticket;
    chart = Loading(chart.data);
    notifyListeners();
    try {
      final q = await _api.chart(symbol, range: range);
      final y = range == '1y' ? q : (year ?? await _api.chart(symbol));
      if (ticket != _ticket) return;
      year = y;
      chart = Ready(q);
    } catch (_) {
      if (ticket != _ticket) return;
      chart = Failed('Couldn’t load prices. Check your connection.', chart.data);
    }
    notifyListeners();
  }

  Future<void> loadNews() async {
    final clean = name.replaceAll(RegExp(r'\b(Limited|Ltd\.?|Inc\.?|Corporation|Corp\.?)\b', caseSensitive: false), '').trim();
    final feed = Feed('stock_$symbol', clean, '📈', 'https://news.google.com/rss/search?q=${Uri.encodeQueryComponent('"$clean" stock')}&hl=en-IN&gl=IN&ceid=IN:en');
    try {
      news = (await Feeds.load(feed)).take(5).toList();
      notifyListeners();
    } catch (_) {}
  }

  void setRange(String r) {
    if (r == range) return;
    range = r;
    load();
  }

  Future<void> toggleWatch() async {
    watched ? await _store.watchlist.remove(symbol) : await _store.watchlist.put(WatchItem(symbol, name));
    notifyListeners();
  }

  static String _pct(double? v) => v == null ? 'n/a' : '${v >= 0 ? '+' : '−'}${v.abs().toStringAsFixed(2)}%';

  /// Asks the AI for a verdict from the stats and headlines; falls back to the rule-based reading.
  Future<void> analyse() async {
    final q = year, t = trend;
    if (q == null || t == null) return;
    take = const Loading();
    notifyListeners();
    final held = _store.holdings[symbol];
    final facts = [
      '${q.name} (${q.symbol}), price ${q.cur}${q.price.toStringAsFixed(2)}, today ${_pct(q.changePct)}.',
      '1M ${_pct(q.ret(21))}, 6M ${_pct(q.ret(126))}, 1Y ${_pct(q.ret(250))}. 52w high ${q.hi52?.toStringAsFixed(2)}, low ${q.lo52?.toStringAsFixed(2)}, from high ${_pct(q.fromHigh)}.',
      '50DMA ${q.sma(50)?.toStringAsFixed(2)}, 200DMA ${q.sma(200)?.toStringAsFixed(2)}, RSI14 ${q.rsi?.round()}, volatility ${q.volatility?.round()}%/yr. Trend score ${t.score}/100.',
      if (held != null) 'User holds ${held.qty} at avg ${held.avg} (P&L ${_pct((q.price / held.avg - 1) * 100)}).',
      'User risk appetite: ${_store.risk}.',
      if (news.isNotEmpty) 'Recent headlines: ${news.map((n) => n.title).join(' | ')}',
    ].join('\n');
    final r = await _ask(
      'You are Buddy, a careful, honest equity research assistant for an Indian retail investor. Use ONLY the data given; never invent numbers or facts. '
          'Format (plain text, no markdown headers):\nVerdict: <Consider buying | Accumulate slowly (SIP) | Hold | Wait for a better price | Avoid for now>\n'
          'Why: 3 short bullets\nRisks: 2 short bullets\nFor you: one line tailored to their risk appetite and holding.\n'
          'Be balanced; prefer diversification and index funds for the core of a portfolio. Never promise returns.',
      facts,
      maxTokens: 900,
    );
    take = Ready(r ??
        'Trend reading: ${t.label} (${t.score}/100).\n${t.good.map((g) => '✓ $g').join('\n')}\n${t.bad.map((b) => '✗ $b').join('\n')}\n\nTurn on the cloud brain for a full written analysis.');
    notifyListeners();
  }
}
