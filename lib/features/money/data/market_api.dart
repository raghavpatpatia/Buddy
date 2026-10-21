import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/arch/lru_cache.dart';
import '../model/market.dart';

const _ua = {'User-Agent': 'Mozilla/5.0 (Linux; Android 15) BuddyApp/1.0'};

/// Yahoo Finance prices and search (~15 min delayed for NSE/BSE), cached for 5 minutes.
class MarketApi {
  MarketApi._();
  static final instance = MarketApi._();
  final _cache = LruCache<String, Quote>(capacity: 120, ttl: const Duration(minutes: 5));

  /// Daily closes for [range] (1mo, 6mo, 1y, 5y) plus headline stats.
  Future<Quote> chart(String symbol, {String range = '1y'}) async {
    final key = '$symbol|$range';
    final hit = _cache.get(key);
    if (hit != null) return hit;
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
    _cache.put(key, q);
    return q;
  }

  /// Many symbols, 6 at a time; failed symbols are skipped.
  Future<List<Quote>> charts(List<String> symbols, {String range = '1y'}) async {
    final out = <Quote>[];
    for (var i = 0; i < symbols.length; i += 6) {
      final batch = await Future.wait(symbols.skip(i).take(6).map((s) => chart(s, range: range).then<Quote?>((q) => q).catchError((_) => null)));
      out.addAll(batch.whereType<Quote>());
    }
    return out;
  }

  /// (symbol, name, exchange) of stocks, ETFs and indices matching [q]; tries a second Yahoo host on failure.
  Future<List<(String, String, String)>> search(String q) async {
    Object? lastError;
    for (final host in const ['query1', 'query2']) {
      try {
        final r = await http
            .get(Uri.parse('https://$host.finance.yahoo.com/v1/finance/search?q=${Uri.encodeQueryComponent(q)}&quotesCount=10&newsCount=0'), headers: _ua)
            .timeout(const Duration(seconds: 10));
        if (r.statusCode != 200) throw Exception('search HTTP ${r.statusCode}');
        final quotes = (jsonDecode(r.body)['quotes'] as List? ?? []).cast<Map>();
        return [
          for (final x in quotes)
            if (const ['EQUITY', 'ETF', 'INDEX', 'MUTUALFUND'].contains(x['quoteType']) && x['symbol'] is String)
              (x['symbol'] as String, '${x['longname'] ?? x['shortname'] ?? x['symbol']}', '${x['exchDisp'] ?? x['exchange'] ?? ''}'),
        ];
      } catch (e) {
        lastError = e;
        debugPrint('[Market] $host search "$q" failed: $e');
      }
    }
    throw lastError!;
  }

}
