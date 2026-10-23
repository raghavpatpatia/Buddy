import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../shared/ui.dart';
import 'store.dart';

// ---------------- Ranks ----------------
const _ranks = [
  'E-Rank Hunter', 'E-Rank Hunter', 'D-Rank Hunter', 'D-Rank Hunter', 'C-Rank Hunter',
  'C-Rank Hunter', 'B-Rank Hunter', 'B-Rank Hunter', 'A-Rank Hunter', 'S-Rank Hunter',
];

/// Hunter rank for a level: E to S over the first ten levels, then National Level and Monarch.
String rankFor(int level) => level <= _ranks.length ? _ranks[level - 1] : (level < 20 ? 'National Level Hunter' : 'Monarch');

// ---------------- Themes (unlock by level) ----------------
/// A calm colour theme for the whole app (light or dark) and Buddy's eyes, which glow in the theme's colours by
/// mood. [accent] fills buttons; [bright] is the accent for text and icons (darker on light themes, lighter on
/// dark ones); [flare] is a warm second colour.
class BotColor {
  final String id, name;
  final Color? color; // fixed eye colour; null = mood-based in the theme's colours
  final int unlockLevel;
  final bool light;
  final Color background, card, accent, bright, flare;
  const BotColor(this.id, this.name, this.color, this.unlockLevel,
      {required this.light, required this.background, required this.card, required this.accent, required this.bright, required this.flare});

  bool get unlocked => Store.level >= unlockLevel;
}

/// Soft, high-contrast themes for every age: a day (light) and night (dark, deep grey-navy rather than pure black)
/// pair for each of the ten levels, so every level-up unlocks a new pair.
const botColors = [
  // Lv 1
  BotColor('auto', 'Morning', null, 1, light: true, background: Color(0xFFF5F7FA), card: Color(0xFFFFFFFF), accent: Color(0xFF2F80C8), bright: Color(0xFF1F5F99), flare: Color(0xFFE8A33D)),
  BotColor('midnight', 'Midnight', null, 1, light: false, background: Color(0xFF121A24), card: Color(0xFF1B2533), accent: Color(0xFF6FA3DF), bright: Color(0xFFA9CBF0), flare: Color(0xFFE5B567)),
  // Lv 2
  BotColor('mint', 'Mint', null, 2, light: true, background: Color(0xFFF3F8F6), card: Color(0xFFFFFFFF), accent: Color(0xFF1E9E8C), bright: Color(0xFF157567), flare: Color(0xFFE9A23B)),
  BotColor('forest', 'Forest', null, 2, light: false, background: Color(0xFF111A15), card: Color(0xFF1A271F), accent: Color(0xFF7FB894), bright: Color(0xFFB4DCC2), flare: Color(0xFFE0B872)),
  // Lv 3
  BotColor('sand', 'Sand', null, 3, light: true, background: Color(0xFFFAF6F0), card: Color(0xFFFFFFFF), accent: Color(0xFFC4683C), bright: Color(0xFF96461F), flare: Color(0xFF5E8B6A)),
  BotColor('plum', 'Plum', null, 3, light: false, background: Color(0xFF191320), card: Color(0xFF241B2D), accent: Color(0xFFB58FD6), bright: Color(0xFFD9C2EE), flare: Color(0xFFE79BA6)),
  // Lv 4
  BotColor('lavender', 'Lavender', null, 4, light: true, background: Color(0xFFF6F4FB), card: Color(0xFFFFFFFF), accent: Color(0xFF7C5CBF), bright: Color(0xFF5B3E99), flare: Color(0xFFE59AB4)),
  BotColor('dusk', 'Dusk', null, 4, light: false, background: Color(0xFF15152A), card: Color(0xFF1F1F38), accent: Color(0xFFA99BE6), bright: Color(0xFFCFC6F5), flare: Color(0xFFF2B6C6)),
  // Lv 5
  BotColor('peach', 'Peach', null, 5, light: true, background: Color(0xFFFDF5F0), card: Color(0xFFFFFFFF), accent: Color(0xFFE07A5F), bright: Color(0xFFB4513A), flare: Color(0xFF3D8C95)),
  BotColor('ember', 'Ember', null, 5, light: false, background: Color(0xFF1C1512), card: Color(0xFF28201B), accent: Color(0xFFE89B6C), bright: Color(0xFFF5C6A5), flare: Color(0xFF7FB8BF)),
  // Lv 6
  BotColor('ocean', 'Ocean', null, 6, light: true, background: Color(0xFFF1F8FA), card: Color(0xFFFFFFFF), accent: Color(0xFF1B8AA6), bright: Color(0xFF136478), flare: Color(0xFFF2A65A)),
  BotColor('deepsea', 'Deep Sea', null, 6, light: false, background: Color(0xFF0E1A20), card: Color(0xFF16262E), accent: Color(0xFF5DB7CF), bright: Color(0xFFA6DCEA), flare: Color(0xFFF2B880)),
  // Lv 7
  BotColor('rose', 'Rose', null, 7, light: true, background: Color(0xFFFBF4F5), card: Color(0xFFFFFFFF), accent: Color(0xFFC2546E), bright: Color(0xFF95374F), flare: Color(0xFF6B9E8A)),
  BotColor('wine', 'Wine', null, 7, light: false, background: Color(0xFF1C1216), card: Color(0xFF281A20), accent: Color(0xFFE08FA3), bright: Color(0xFFF3C3CF), flare: Color(0xFF9CC5B4)),
  // Lv 8
  BotColor('sunshine', 'Sunshine', null, 8, light: true, background: Color(0xFFFCF8EE), card: Color(0xFFFFFFFF), accent: Color(0xFFD99A1E), bright: Color(0xFF9A6B0C), flare: Color(0xFF4F7CAC)),
  BotColor('ambernight', 'Amber Night', null, 8, light: false, background: Color(0xFF1A1710), card: Color(0xFF262118), accent: Color(0xFFE6B84D), bright: Color(0xFFF3D892), flare: Color(0xFF8FB0D6)),
  // Lv 9
  BotColor('stone', 'Stone', null, 9, light: true, background: Color(0xFFF4F4F2), card: Color(0xFFFFFFFF), accent: Color(0xFF5E6B73), bright: Color(0xFF3E484F), flare: Color(0xFFC08457)),
  BotColor('graphite', 'Graphite', null, 9, light: false, background: Color(0xFF151719), card: Color(0xFF1F2225), accent: Color(0xFFA3AEB6), bright: Color(0xFFD3DADF), flare: Color(0xFFD9A47A)),
  // Lv 10
  BotColor('pearl', 'Pearl', null, 10, light: true, background: Color(0xFFF7F6F3), card: Color(0xFFFFFFFF), accent: Color(0xFF8A6D3B), bright: Color(0xFF6A5128), flare: Color(0xFF3E5A8A)),
  BotColor('royal', 'Royal', null, 10, light: false, background: Color(0xFF10142A), card: Color(0xFF1A1F3B), accent: Color(0xFFD4AF62), bright: Color(0xFFEBD39B), flare: Color(0xFF8FA4E0)),
];

/// Day ↔ night partners: each light theme has a dark twin.
const themePairs = {
  'auto': 'midnight', 'mint': 'forest', 'sand': 'plum', 'lavender': 'dusk', 'peach': 'ember',
  'ocean': 'deepsea', 'rose': 'wine', 'sunshine': 'ambernight', 'stone': 'graphite', 'pearl': 'royal',
};

BotColor _byId(String id) => botColors.firstWhere((b) => b.id == id, orElse: () => botColors.first);

/// The day (light) theme of the chosen colour family.
BotColor get themeFamily {
  final id = Store.raw.getString('bot_color') ?? 'auto';
  final day = themePairs.containsKey(id) ? id : themePairs.entries.firstWhere((e) => e.value == id, orElse: () => const MapEntry('auto', 'midnight')).key;
  final c = _byId(day);
  return c.unlocked ? c : botColors.first;
}

/// The family's night twin.
BotColor nightOf(BotColor day) => _byId(themePairs[day.id] ?? 'midnight');

/// Day / night (true = the dark twin). Follows the phone's dark-mode setting until the user picks one; their
/// choice is kept from then on.
bool get nightMode => Store.raw.getBool('theme_night') ?? ui.PlatformDispatcher.instance.platformBrightness == Brightness.dark;

/// The user has picked day or night themselves (otherwise it follows the phone).
bool get nightModeChosen => Store.raw.getBool('theme_night') != null;

/// The theme on screen: the family's day theme, or its night twin when night mode is on (if unlocked).
BotColor get selectedBotColor {
  final day = themeFamily;
  final night = nightOf(day);
  return nightMode && night.unlocked ? night : day;
}

/// Bumped whenever the theme changes; the app rebuilds everything in the new colours.
final themeChanges = ValueNotifier<int>(0);

/// Recolours the app for the selected theme (call at start, and after picking a theme).
void applyBotTheme() {
  final t = selectedBotColor;
  SystemColors.apply(light: t.light, background: t.background, card: t.card, accent: t.accent, bright: t.bright, flare: t.flare);
  themeChanges.value++;
}

/// Picks a colour family by its day theme's id.
Future<void> selectBotTheme(String id) async {
  await Store.raw.setString('bot_color', id);
  applyBotTheme();
}

/// Saves the user's day / night choice; null goes back to following the phone.
Future<void> setNightMode(bool? on) async {
  on == null ? await Store.raw.remove('theme_night') : await Store.raw.setBool('theme_night', on);
  applyBotTheme();
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
