import '../core/native.dart';
import '../core/store.dart';
import 'astro/astro_page.dart' show loadBirth, hm;
import 'astro/jyotish.dart';
import 'grow/feeds.dart';
import 'grow/math.dart';
import 'talk/wisdom.dart';

int get briefHour => Store.raw.getInt('brief_hour') ?? 7;
int get briefMinute => Store.raw.getInt('brief_minute') ?? 30;
bool get briefEnabled => Store.raw.getBool('brief_enabled') ?? true;

Future<void> syncBrief() async {
  try {
    await Native.setBrief({'enabled': briefEnabled, 'hour': briefHour, 'minute': briefMinute});
  } catch (_) {}
}

/// Builds the next morning brief and stores it as `brief_<yyyy-mm-dd>`; the native 24/7 service
/// posts it at the chosen time (no server or Firebase needed). Safe to call often: refreshes headlines.
Future<void> prepareBrief() async {
  if (!briefEnabled) return;
  final now = DateTime.now();
  final briefAt = DateTime(now.year, now.month, now.day, briefHour, briefMinute);
  final day = now.isBefore(briefAt) ? now : now.add(const Duration(days: 1));
  final when = DateTime(day.year, day.month, day.day, briefHour, briefMinute);
  final name = Store.profile['name'];
  final lines = <String>[];
  var title = '☀️ Good morning, $name';

  final b = loadBirth();
  if (b != null) {
    try {
      final p = Panchang.at(when, b.lat, b.lon, Duration(minutes: (b.tz * 60).round()));
      final o = outlookFor(Chart(b), p);
      title = '☀️ Good morning, $name · ${'★' * o.score}${'☆' * (5 - o.score)}';
      lines.add('🪐 ${o.headline} · Moon in ${nakshatras[p.nak].name}${p.rahuKaal == null ? '' : ' · Rahu Kaal ${hm(p.rahuKaal!.$1)}–${hm(p.rahuKaal!.$2)}'}');
      lines.add('🎯 Focus: ${o.focus.$1}');
    } catch (_) {}
  }
  for (final (id, emoji) in [('india', '🇮🇳'), ('world', '🌍'), ('tech', '💻')]) {
    try {
      final items = await Feeds.load(feeds.firstWhere((f) => f.id == id), force: true);
      if (items.isNotEmpty) lines.add('$emoji ${items.first.title}');
    } catch (_) {}
  }
  if (Store.growthEnabled) {
    final h = Store.growthHour;
    lines.add('🌱 Today: learn 1 thing + read 1 story (by ${h > 12 ? h - 12 : h} ${h >= 12 ? 'PM' : 'AM'})');
  }
  final v = verseOfTheDay(day);
  lines.add('🪔 ${v.src}: ${v.mean}');
  lines.add('🧮 Maths level ${Store.mathLevel + 1}: ${mathLevels[Store.mathLevel].name} · 🔥 growth streak ${Store.growthStreak}');
  await Store.setJson('brief_${dayKey(day)}', {'title': title, 'lines': lines});
}
