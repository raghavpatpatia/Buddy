import 'dart:math';

import '../../../core/arch/repository.dart';

/// Price history and headline stats for one symbol.
class Quote {
  final String symbol, name, currency;
  final double price, changePct;
  final double? hi52, lo52;
  final List<DateTime> times;
  final List<double> closes;
  const Quote(this.symbol, this.name, this.currency, this.price, this.changePct, this.hi52, this.lo52, this.times, this.closes);

  String get cur => currency == 'INR' ? '₹' : currency == 'USD' ? '\$' : '$currency ';
  bool get isIndian => symbol.endsWith('.NS') || symbol.endsWith('.BO') || symbol.startsWith('^NSE') || symbol.startsWith('^BSE');

  /// % return over the last [days] trading days, or null without enough history.
  double? ret(int days) {
    if (closes.isEmpty) return null;
    // Markets close on holidays, so a "year" can be ~247 points; accept 90% of the window from the oldest close.
    final base = closes.length > days ? closes[closes.length - 1 - days] : (closes.length >= days * 0.9 ? closes.first : null);
    return base == null || base == 0 ? null : (price / base - 1) * 100;
  }
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

/// 0–100 trend reading (not a prediction) with the reasons behind it.
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

/// Large, liquid stocks and index ETFs ranked by "Ideas for you".
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

  static final codec = JsonCodec<Holding>(
    encode: (h) => {'s': h.symbol, 'n': h.name, 'q': h.qty, 'a': h.avg},
    decode: (j) => Holding(j['s'], j['n'], (j['q'] as num).toDouble(), (j['a'] as num).toDouble()),
  );
}

/// A followed stock, stored as a [symbol, name] pair.
class WatchItem {
  final String symbol, name;
  const WatchItem(this.symbol, this.name);
  static final codec = JsonCodec<WatchItem>(encode: (w) => [w.symbol, w.name], decode: (e) => WatchItem(e[0] as String, e[1] as String));
}
