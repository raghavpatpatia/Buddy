const units = ['lessons', 'videos', 'chapters', 'modules', 'pages'];
String unitOf(Map c) => (c['unit'] as String?) ?? 'lessons';
String unitOne(Map c) => unitOf(c).substring(0, unitOf(c).length - 1);

/// Pace needed to finish on time: lessons/day, or null without a deadline.
({int perDay, int daysLeft})? coursePace(Map c) {
  final d = DateTime.tryParse(c['deadline'] ?? '');
  if (d == null) return null;
  final left = (c['total'] as int) - (c['done'] as int);
  final now = DateTime.now();
  // Whole calendar days, today included (comparing to "now" would drop a day every evening).
  final days = DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays + 1;
  return (perDay: days <= 0 ? left : (left / days).ceil(), daysLeft: days);
}
