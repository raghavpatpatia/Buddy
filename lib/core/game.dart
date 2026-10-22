import 'package:flutter/material.dart';

import 'store.dart';

// ---------------- Ranks ----------------
const _ranks = [
  'E-Rank Hunter', 'E-Rank Hunter', 'D-Rank Hunter', 'D-Rank Hunter', 'C-Rank Hunter',
  'C-Rank Hunter', 'B-Rank Hunter', 'B-Rank Hunter', 'A-Rank Hunter', 'S-Rank Hunter',
];

/// Hunter rank for a level: E to S over the first ten levels, then National Level and Monarch.
String rankFor(int level) => level <= _ranks.length ? _ranks[level - 1] : (level < 20 ? 'National Level Hunter' : 'Monarch');

// ---------------- Buddy eye colours (unlock by level) ----------------
class BotColor {
  final String id, name;
  final Color? color; // null = mood-based (auto); rainbow handled by the painter
  final int unlockLevel;
  const BotColor(this.id, this.name, this.color, this.unlockLevel);
  bool get unlocked => Store.level >= unlockLevel;
}

const botColors = [
  BotColor('auto', 'Mana (auto)', null, 1),
  BotColor('emerald', 'Emerald', Color(0xFF2EE59D), 2),
  BotColor('crimson', 'Crimson', Color(0xFFFF4D6D), 4),
  BotColor('violet', 'Violet', Color(0xFFB388FF), 6),
  BotColor('gold', 'Gold', Color(0xFFFFC94D), 8),
  BotColor('rainbow', 'Rainbow', null, 10),
];

BotColor get selectedBotColor {
  final id = Store.raw.getString('bot_color') ?? 'auto';
  final c = botColors.firstWhere((b) => b.id == id, orElse: () => botColors.first);
  return c.unlocked ? c : botColors.first;
}

// ---------------- Weekly boss ----------------
class Boss {
  final String name, emoji, taunt;
  const Boss(this.name, this.emoji, this.taunt);
}

const _bosses = [
  Boss('The Procrastinator', '🦥', '“Do it tomorrow…”'),
  Boss('Doomscroll Demon', '👹', '“Just one more reel.”'),
  Boss('Bug Hydra', '🐉', '“Fix one bug, two appear.”'),
  Boss('Couch Golem', '🗿', '“Steps are overrated.”'),
  Boss('Sleepy Slime', '🫠', '“Skip the water, nap instead.”'),
  Boss('Distraction Djinn', '🧞', '“Check your phone again.”'),
];

const bossMaxHp = 400;

/// Monday of the current week (local), used as the boss's id.
String weekKey([DateTime? d]) {
  final t = d ?? DateTime.now();
  return dayKey(DateTime(t.year, t.month, t.day).subtract(Duration(days: t.weekday - 1)));
}

int _weekIndex() => DateTime.parse(weekKey()).difference(DateTime(2026)).inDays ~/ 7;

Boss get currentBoss => _bosses[_weekIndex() % _bosses.length];

int get bossHp {
  if (Store.raw.getString('boss_week') != weekKey()) return bossMaxHp;
  return Store.raw.getInt('boss_hp') ?? bossMaxHp;
}

int get bossesDefeated => Store.raw.getInt('bosses_defeated') ?? 0;

/// Every XP earned hits the boss. Returns true if this hit defeated it.
Future<bool> damageBoss(int dmg) async {
  final p = Store.raw;
  if (p.getString('boss_week') != weekKey()) {
    await p.setString('boss_week', weekKey());
    await p.setInt('boss_hp', bossMaxHp);
  }
  final hp = p.getInt('boss_hp') ?? bossMaxHp;
  if (hp <= 0) return false;
  final left = (hp - dmg).clamp(0, bossMaxHp);
  await p.setInt('boss_hp', left);
  if (left == 0) {
    await p.setInt('bosses_defeated', bossesDefeated + 1);
    return true;
  }
  return false;
}

// ---------------- Trophies ----------------
class Trophy {
  final String id, emoji, title, how;
  final bool Function() earned;
  const Trophy(this.id, this.emoji, this.title, this.how, this.earned);
}

int _practiceMinutesTotal() => Store.practice.fold<int>(0, (a, p) => a + (p['seconds'] as int)) ~/ 60;
double _bestHold() {
  var best = 0.0;
  for (final k in Store.raw.getKeys().where((k) => k.startsWith('hold_pb_'))) {
    final v = Store.raw.getDouble(k) ?? 0;
    if (v > best) best = v;
  }
  return best;
}

final trophies = <Trophy>[
  Trophy('first_lesson', '📘', 'First Lesson', 'Pass your first lesson quiz', () => Store.lessonsTotal >= 1),
  Trophy('scholar', '🎓', 'Scholar', 'Pass 25 lesson quizzes', () => Store.lessonsTotal >= 25),
  Trophy('reader', '📰', 'Informed', 'Save your first news takeaway', () => Store.takeaways.isNotEmpty),
  Trophy('journalist', '🗞️', 'News Hound', 'Save 20 news takeaways', () => Store.takeaways.length >= 20),
  Trophy('growth_3', '🌱', 'Sprout', '3-day growth streak', () => Store.growthStreak >= 3),
  Trophy('growth_7', '🌿', 'Rooted', '7-day growth streak', () => Store.growthStreak >= 7),
  Trophy('growth_30', '🌳', 'Mighty Oak', '30-day growth streak', () => Store.growthStreak >= 30),
  Trophy('early_bird', '🐦', 'Early Bird', 'Finish your growth tasks before noon', () => Store.raw.getBool('early_bird') == true),
  Trophy('mathlete', '🧮', 'Mathlete', 'Reach maths level 5', () => Store.mathLevel >= 4),
  Trophy('math_master', '∫', 'Calculus Climber', 'Reach maths level 15', () => Store.mathLevel >= 14),
  Trophy('hydrated', '💧', 'Hydration Hero', 'Hit your water goal on 7 days', () => (Store.raw.getStringList('water_goal_days') ?? []).length >= 7),
  Trophy('practice_60', '🎵', 'Dedicated', 'Practise 60 minutes in total', () => _practiceMinutesTotal() >= 60),
  Trophy('long_tone', '🪈', 'Iron Lungs', 'Hold one note for 20 seconds', () => _bestHold() >= 20),
  Trophy('scroll_monk', '🧘', 'Scroll Monk', 'Stay under your reel limit 7 days in a row', () => Store.raw.getBool('scroll_monk') == true),
  Trophy('cleaner', '🧹', 'Declutterer', 'Free 1 GB of storage', () => (Store.raw.getInt('freed_total') ?? 0) >= 1 << 30),
  Trophy('course_done', '🏁', 'Finisher', 'Complete a course', () => Store.courses.any((c) => c['done'] >= c['total'])),
  Trophy('boss_1', '⚔️', 'Boss Slayer', 'Defeat a weekly boss', () => bossesDefeated >= 1),
  Trophy('boss_5', '🛡️', 'Champion', 'Defeat 5 weekly bosses', () => bossesDefeated >= 5),
  Trophy('stargazer', '🪐', 'Stargazer', 'Set up your birth chart', () => Store.raw.getString('birth') != null),
  Trophy('level_5', '⭐', 'Rising Star', 'Reach level 5', () => Store.level >= 5),
  Trophy('level_10', '🌟', 'Legend', 'Reach level 10', () => Store.level >= 10),
  Trophy('freeze', '🧊', 'Cool Head', 'Have a streak freeze save your streak', () => (Store.raw.getInt('freezes_used') ?? 0) >= 1),
];

List<String> get earnedTrophies => Store.raw.getStringList('trophies') ?? [];

/// Records newly earned trophies and returns them (to celebrate).
Future<List<Trophy>> checkTrophies() async {
  final have = earnedTrophies.toSet();
  final fresh = trophies.where((t) => !have.contains(t.id) && t.earned()).toList();
  if (fresh.isNotEmpty) await Store.raw.setStringList('trophies', [...have, ...fresh.map((t) => t.id)]);
  return fresh;
}
