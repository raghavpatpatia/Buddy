/// A news source (RSS feed).
class Feed {
  final String id, name, emoji, url;
  const Feed(this.id, this.name, this.emoji, this.url);
}

const _gn = 'hl=en-IN&gl=IN&ceid=IN:en';
const feeds = <Feed>[
  Feed('india', 'India', '🇮🇳', 'https://news.google.com/rss?$_gn'),
  Feed('world', 'World', '🌍', 'https://news.google.com/rss/headlines/section/topic/WORLD?$_gn'),
  Feed('tech', 'Tech', '💻', 'https://news.google.com/rss/headlines/section/topic/TECHNOLOGY?$_gn'),
  Feed('gamedev', 'Game dev', '🎮', 'https://www.gamedeveloper.com/rss.xml'),
  Feed('80lv', '80.lv', '🎨', 'https://80.lv/feed'),
  Feed('hn', 'Hacker News', '🟧', 'https://hnrss.org/frontpage'),
  Feed('rgamedev', 'r/gamedev', '👾', 'https://www.reddit.com/r/gamedev/.rss'),
  Feed('science', 'Science', '🔬', 'https://news.google.com/rss/headlines/section/topic/SCIENCE?$_gn'),
  Feed('health', 'Health', '🩺', 'https://news.google.com/rss/headlines/section/topic/HEALTH?$_gn'),
];

/// One headline from a feed.
class NewsItem {
  final String title, link, source;
  final DateTime? at;
  NewsItem(this.title, this.link, this.source, this.at);
  Map<String, dynamic> toJson() => {'t': title, 'l': link, 's': source, 'a': at?.toIso8601String()};
  static NewsItem fromJson(Map m) => NewsItem(m['t'], m['l'], m['s'] ?? '', DateTime.tryParse(m['a'] ?? ''));
}
