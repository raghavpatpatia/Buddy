import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/store.dart';

const _ua = {'User-Agent': 'Mozilla/5.0 (Linux; Android 15) BuddyApp/1.0'};

/// Price history + headline stats for one symbol (Yahoo Finance data, ~15 min delayed for NSE/BSE).
class Quote {
  final String symbol, name, currency;
  final double price, changePct;
  final double? hi52, lo52;
  final List<DateTime> times;
  final List<double> closes;
  const Quote(this.symbol, this.name, this.currency, this.price, this.changePct, this.hi52, this.lo52, this.times, this.closes);

  String get cur => currency == 'INR' ? '₹' : currency == 'USD' ? '\$' : '$currency ';
  bool get isIndian => symbol.endsWith('.NS') || symbol.endsWith('.BO') || symbol.startsWith('^NSE') || symbol.startsWith('^BSE');

  /// % return over the last [days] trading days (null if not enough history).
  double? ret(int days) => closes.length > days ? (price / closes[closes.length - 1 - days] - 1) * 100 : null;
  double? sma(int n) => closes.length >= n ? closes.sublist(closes.length - n).reduce((a, b) => a + b) / n : null;
  double? get fromHigh => hi52 == null || hi52 == 0 ? null : (price / hi52! - 1) * 100;

  /// Annualised volatility of daily returns, in %.
  double? get volatility {
    if (closes.length < 30) return null;
    final r = [for (var i = closes.length - 60 < 1 ? 1 : closes.length - 60; i < closes.length; i++) log(closes[i] / closes[i - 1])];
    final m = r.reduce((a, b) => a + b) / r.length;
    final v = r.fold(0.0, (a, x) => a + (x - m) * (x - m)) / (r.length - 1);
    return sqrt(v) * sqrt(252) * 100;
  }

  /// 14-day RSI (overbought > 70, oversold < 30).
  double? get rsi {
    if (closes.length < 15) return null;
    var up = 0.0, down = 0.0;
    for (var i = closes.length - 14; i < closes.length; i++) {
      final d = closes[i] - closes[i - 1];
      d > 0 ? up += d : down -= d;
    }
    return down == 0 ? 100 : 100 - 100 / (1 + up / down);
  }
}

/// A trend reading, not a prediction: 0–100 from momentum, moving averages, RSI and distance from the 52-week high.
class Trend {
  final int score;
  final List<String> good, bad;
  const Trend(this.score, this.good, this.bad);
  String get label => score >= 65 ? 'Strong trend' : score >= 45 ? 'Neutral' : 'Weak trend';
}

Trend trendOf(Quote q) {
  var s = 50.0;
  final good = <String>[], bad = <String>[];
  final s50 = q.sma(50), s200 = q.sma(200), r6 = q.ret(126), r12 = q.ret(250), rsi = q.rsi, fh = q.fromHigh, vol = q.volatility;
  if (s50 != null) {
    if (q.price > s50) {
      s += 8;
      good.add('Above its 50-day average');
    } else {
      s -= 8;
      bad.add('Below its 50-day average');
    }
  }
  if (s50 != null && s200 != null) {
    if (s50 > s200) {
      s += 10;
      good.add('Long-term uptrend (50 DMA > 200 DMA)');
    } else {
      s -= 10;
      bad.add('Long-term downtrend (50 DMA < 200 DMA)');
    }
  }
  if (r6 != null) s += (r6 / 2).clamp(-12, 12);
  if (r12 != null) {
    s += (r12 / 3).clamp(-10, 10);
    (r12 >= 0 ? good : bad).add('${r12 >= 0 ? '+' : ''}${r12.toStringAsFixed(0)}% in 1 year');
  }
  if (rsi != null) {
    if (rsi > 75) {
      s -= 8;
      bad.add('Overheated short-term (RSI ${rsi.round()})');
    } else if (rsi < 30) {
      s -= 4;
      bad.add('Selling pressure (RSI ${rsi.round()})');
    }
  }
  if (fh != null) {
    if (fh > -8) {
      s += 6;
      good.add('Near its 52-week high');
    } else if (fh < -30) {
      s -= 8;
      bad.add('${fh.abs().round()}% below its 52-week high');
    }
  }
  if (vol != null && vol > 45) {
    s -= 6;
    bad.add('Very volatile (${vol.round()}%/yr)');
  }
  return Trend(s.round().clamp(0, 100), good, bad);
}

const indices = [('^NSEI', 'NIFTY 50'), ('^BSESN', 'SENSEX'), ('^GSPC', 'S&P 500'), ('^IXIC', 'NASDAQ'), ('INR=X', 'USD/INR')];

/// Large, liquid names + index ETFs that "Ideas for you" ranks. Index ETFs are the sensible core for most people.
const ideaUniverse = [
  'NIFTYBEES.NS', 'JUNIORBEES.NS', 'GOLDBEES.NS', 'RELIANCE.NS', 'TCS.NS', 'HDFCBANK.NS', 'ICICIBANK.NS', 'INFY.NS', 'BHARTIARTL.NS',
  'ITC.NS', 'LT.NS', 'SBIN.NS', 'HINDUNILVR.NS', 'BAJFINANCE.NS', 'KOTAKBANK.NS', 'AXISBANK.NS', 'MARUTI.NS', 'SUNPHARMA.NS',
  'TITAN.NS', 'ASIANPAINT.NS', 'NTPC.NS', 'HCLTECH.NS', 'M&M.NS', 'ULTRACEMCO.NS', 'TATASTEEL.NS',
  'VOO', 'QQQ', 'AAPL', 'MSFT', 'NVDA', 'GOOGL', 'AMZN', 'META', 'AVGO', 'JPM', 'V', 'COST', 'LLY', 'BRK-B',
];

class Holding {
  final String symbol, name;
  final double qty, avg;
  const Holding(this.symbol, this.name, this.qty, this.avg);
  Map<String, dynamic> toJson() => {'s': symbol, 'n': name, 'q': qty, 'a': avg};
  factory Holding.fromJson(Map j) => Holding(j['s'], j['n'], (j['q'] as num).toDouble(), (j['a'] as num).toDouble());
}

class Market {
  static final changed = ValueNotifier(0);
  static final _mem = <String, (DateTime, Quote)>{};

  /// Daily closes for [range] (1mo, 6mo, 1y, 5y). Cached 5 minutes in memory.
  static Future<Quote> chart(String symbol, {String range = '1y'}) async {
    final key = '$symbol|$range';
    final hit = _mem[key];
    if (hit != null && DateTime.now().difference(hit.$1).inMinutes < 5) return hit.$2;
    final interval = range == '5y' ? '1wk' : '1d';
    final r = await http
        .get(Uri.parse('https://query1.finance.yahoo.com/v8/finance/chart/${Uri.encodeComponent(symbol)}?range=$range&interval=$interval'), headers: _ua)
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw Exception('Market data HTTP ${r.statusCode}');
    final res = ((jsonDecode(r.body)['chart']['result']) as List).first as Map;
    final meta = res['meta'] as Map;
    final ts = (res['timestamp'] as List? ?? []).cast<num>();
    final raw = ((res['indicators']['quote'] as List).first['close'] as List? ?? []);
    final times = <DateTime>[], closes = <double>[];
    for (var i = 0; i < ts.length && i < raw.length; i++) {
      if (raw[i] == null) continue;
      times.add(DateTime.fromMillisecondsSinceEpoch(ts[i].toInt() * 1000));
      closes.add((raw[i] as num).toDouble());
    }
    final price = ((meta['regularMarketPrice'] ?? (closes.isEmpty ? 0 : closes.last)) as num).toDouble();
    final prev = closes.length >= 2 ? closes[closes.length - 2] : ((meta['chartPreviousClose'] ?? price) as num).toDouble();
    final pct = (meta['regularMarketChangePercent'] as num?)?.toDouble() ?? (prev == 0 ? 0 : (price / prev - 1) * 100);
    final q = Quote(symbol, (meta['longName'] ?? meta['shortName'] ?? symbol) as String, (meta['currency'] ?? '') as String, price, pct,
        (meta['fiftyTwoWeekHigh'] as num?)?.toDouble(), (meta['fiftyTwoWeekLow'] as num?)?.toDouble(), times, closes);
    _mem[key] = (DateTime.now(), q);
    return q;
  }

  /// Many symbols at once, 6 in parallel; failures are skipped.
  static Future<List<Quote>> charts(List<String> symbols, {String range = '1y'}) async {
    final out = <Quote>[];
    for (var i = 0; i < symbols.length; i += 6) {
      final batch = await Future.wait(symbols.skip(i).take(6).map((s) => chart(s, range: range).then<Quote?>((q) => q).catchError((_) => null)));
      out.addAll(batch.whereType<Quote>());
    }
    return out;
  }

  /// Stocks / ETFs / indices matching [q] on NSE, BSE and US exchanges.
  static Future<List<(String, String, String)>> search(String q) async {
    final r = await http
        .get(Uri.parse('https://query2.finance.yahoo.com/v1/finance/search?q=${Uri.encodeQueryComponent(q)}&quotesCount=10&newsCount=0'), headers: _ua)
        .timeout(const Duration(seconds: 10));
    final quotes = (jsonDecode(r.body)['quotes'] as List? ?? []).cast<Map>();
    return [
      for (final x in quotes)
        if (const ['EQUITY', 'ETF', 'INDEX', 'MUTUALFUND'].contains(x['quoteType']))
          (x['symbol'] as String, (x['longname'] ?? x['shortname'] ?? x['symbol']) as String, (x['exchDisp'] ?? x['exchange'] ?? '') as String),
    ];
  }

  // ---- your lists (stored on the phone) ----
  static List<(String, String)> get watchlist =>
      [for (final e in (jsonDecode(Store.raw.getString('mkt_watch') ?? '[]') as List)) (e[0] as String, e[1] as String)];
  static Future<void> toggleWatch(String symbol, String name) async {
    final w = watchlist;
    w.any((e) => e.$1 == symbol) ? w.removeWhere((e) => e.$1 == symbol) : w.add((symbol, name));
    await Store.raw.setString('mkt_watch', jsonEncode([for (final e in w) [e.$1, e.$2]]));
    changed.value++;
  }

  static List<Holding> get holdings => [for (final e in (jsonDecode(Store.raw.getString('mkt_holdings') ?? '[]') as List)) Holding.fromJson(e)];
  static Future<void> saveHoldings(List<Holding> h) async {
    await Store.raw.setString('mkt_holdings', jsonEncode([for (final x in h) x.toJson()]));
    changed.value++;
  }

  static String get risk => Store.raw.getString('mkt_risk') ?? 'medium';
  static Future<void> setRisk(String r) async {
    await Store.raw.setString('mkt_risk', r);
    changed.value++;
  }
}
