import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../../../core/store.dart';
import '../model/news.dart';

/// Free public feeds only: no accounts, no API keys. Only headlines are downloaded.
const _ua = {'User-Agent': 'BuddyApp/1.0 (personal Android app)'};

class Feeds {
  /// Cached for 30 min; falls back to the cache when offline.
  static Future<List<NewsItem>> load(Feed f, {bool force = false}) async {
    final key = 'news_${f.id}';
    final cached = Store.getJson(key);
    if (!force && cached != null && DateTime.now().difference(DateTime.parse(cached['at'])).inMinutes < 30) {
      return (cached['items'] as List).map((e) => NewsItem.fromJson(e)).toList();
    }
    try {
      final r = await http.get(Uri.parse(f.url), headers: _ua).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final items = _parse(utf8.decode(r.bodyBytes, allowMalformed: true), f.name);
      await Store.setJson(key, {'at': DateTime.now().toIso8601String(), 'items': items.map((e) => e.toJson()).toList()});
      return items;
    } catch (e) {
      if (cached != null) return (cached['items'] as List).map((e) => NewsItem.fromJson(e)).toList();
      rethrow;
    }
  }

  static List<NewsItem> _parse(String body, String fallbackSource) {
    final doc = XmlDocument.parse(body);
    String? txt(XmlElement e, String name) => e.findElements(name).firstOrNull?.innerText.trim();
    final out = <NewsItem>[];
    // RSS 2.0
    for (final it in doc.findAllElements('item')) {
      var title = txt(it, 'title') ?? '';
      var source = txt(it, 'source') ?? fallbackSource;
      // Google News appends " - Source" to titles.
      if (title.endsWith(' - $source')) title = title.substring(0, title.length - source.length - 3);
      out.add(NewsItem(title, txt(it, 'link') ?? '', source, _date(txt(it, 'pubDate'))));
    }
    // Atom (reddit)
    for (final it in doc.findAllElements('entry')) {
      final link = it.findElements('link').firstOrNull?.getAttribute('href') ?? '';
      out.add(NewsItem(txt(it, 'title') ?? '', link, fallbackSource, DateTime.tryParse(txt(it, 'updated') ?? '')));
    }
    return out.where((e) => e.title.isNotEmpty && e.link.isNotEmpty).take(40).toList();
  }

  static DateTime? _date(String? s) {
    if (s == null) return null;
    // RFC 822: "Tue, 20 Oct 2026 14:05:00 GMT"
    const months = {'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6, 'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12};
    final m = RegExp(r'(\d{1,2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) ?([+-]\d{4}|GMT|UTC|Z)?').firstMatch(s);
    if (m == null) return DateTime.tryParse(s);
    var d = DateTime.utc(int.parse(m[3]!), months[m[2]] ?? 1, int.parse(m[1]!), int.parse(m[4]!), int.parse(m[5]!), int.parse(m[6]!));
    final tz = m[7];
    if (tz != null && (tz.startsWith('+') || tz.startsWith('-'))) {
      final sign = tz.startsWith('-') ? -1 : 1;
      d = d.subtract(Duration(hours: sign * int.parse(tz.substring(1, 3)), minutes: sign * int.parse(tz.substring(3, 5))));
    }
    return d.toLocal();
  }

  /// Wikipedia daily feed: featured article, on-this-day, did-you-know. Cached per day.
  static Future<Map<String, dynamic>?> wikiToday() async {
    final key = 'wiki_${dayKey()}';
    final cached = Store.getJson(key);
    if (cached != null) return Map<String, dynamic>.from(cached);
    try {
      final n = DateTime.now();
      final url = 'https://api.wikimedia.org/feed/v1/wikipedia/en/featured/${n.year}/${n.month.toString().padLeft(2, '0')}/${n.day.toString().padLeft(2, '0')}';
      final r = await http.get(Uri.parse(url), headers: _ua).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return null;
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      String? page(Map? m) => m?['content_urls']?['mobile']?['page'];
      final tfa = d['tfa'] as Map?;
      final otd = (d['onthisday'] as List?)?.cast<Map>() ?? [];
      final dyk = (d['dyk'] as List?)?.cast<Map>() ?? [];
      final slim = {
        'tfa': tfa == null
            ? null
            : {'title': tfa['titles']?['normalized'], 'extract': tfa['extract'], 'url': page(tfa), 'thumb': tfa['thumbnail']?['source']},
        'onthisday': [
          for (final o in otd.take(6))
            {'year': o['year'], 'text': o['text'], 'url': page((o['pages'] as List?)?.firstOrNull as Map?)},
        ],
        'dyk': [for (final x in dyk.take(5)) x['text']],
      };
      await Store.setJson(key, slim);
      return slim;
    } catch (_) {
      return null;
    }
  }
}

String timeAgo(DateTime? t) {
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 60) return '${d.inMinutes.clamp(1, 59)}m';
  if (d.inHours < 24) return '${d.inHours}h';
  return '${d.inDays}d';
}
