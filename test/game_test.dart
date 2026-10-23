import 'dart:ui' as ui;

import 'package:buddy_app/core/game.dart';
import 'package:buddy_app/core/store.dart';
import 'package:flutter/material.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
  });

  test('XP events fire and report level-ups', () async {
    await Store.addXp(60);
    expect(Store.xpEvents.value!.amount, 60);
    expect(Store.xpEvents.value!.newLevel, isNull);
    await Store.addXp(50); // 110 XP → level 2
    expect(Store.xpEvents.value!.newLevel, 2);
    expect(rankFor(2), 'E-Rank Hunter');
    expect(rankFor(10), 'S-Rank Hunter');
    expect(rankFor(12), 'National Level Hunter');
    expect(rankFor(25), 'Monarch');
  });

  test('boss takes damage, dies once, resets weekly', () async {
    expect(bossHp, bossMaxHp);
    expect(await damageBoss(150), isFalse);
    expect(bossHp, bossMaxHp - 150);
    expect(await damageBoss(1000), isTrue);
    expect(bossHp, 0);
    expect(await damageBoss(10), isFalse, reason: 'already defeated this week');
    expect(bossesDefeated, 1);
    await Store.raw.setString('boss_week', '2000-01-03'); // simulate last week
    expect(bossHp, bossMaxHp);
  });

  test('a streak freeze absorbs a missed day instead of the penalty', () async {
    final since = DateTime.now().subtract(const Duration(days: 3));
    await Store.raw.setString('growth_since', since.toIso8601String());
    await Store.raw.setInt('xp', 200);
    await Store.raw.setInt('freezes', 1);
    final missed = await Store.applyMissedGrowthPenalties();
    // 2 past days missed: one frozen, one penalised
    expect(missed, 1);
    expect(Store.freezes, 0);
    expect(Store.frozenDays.length, 1);
    expect(Store.xp, 200 - Store.growthPenaltyXp);
  });

  test('trophies unlock once', () async {
    await Store.raw.setInt('lessons_total', 1);
    final first = await checkTrophies();
    expect(first.map((t) => t.id), contains('first_lesson'));
    expect(await checkTrophies(), isEmpty);
  });

  test('bot colours unlock by level', () async {
    await Store.raw.setString('bot_color', 'sand'); // locked at level 1
    expect(selectedBotColor.id, 'auto');
    await Store.raw.setInt('xp', 800); // level 9
    expect(selectedBotColor.id, 'sand');
  });

  test('day / night switch flips a colour family to its twin', () async {
    await Store.raw.setInt('xp', 800); // level 9: everything unlocked
    await Store.raw.setString('bot_color', 'mint');
    await Store.raw.setBool('theme_night', false);
    expect(selectedBotColor.id, 'mint');
    await Store.raw.setBool('theme_night', true);
    expect(selectedBotColor.id, 'forest');
    expect(themeFamily.id, 'mint');
    // A night id saved by an older version still means its family.
    await Store.raw.setString('bot_color', 'plum');
    expect(themeFamily.id, 'sand');
    expect(selectedBotColor.id, 'plum');
    await Store.raw.setBool('theme_night', false);
    expect(selectedBotColor.id, 'sand');
  });

  test('follows the phone until the user picks day or night', () async {
    await Store.raw.setInt('xp', 800);
    await Store.raw.setString('bot_color', 'auto');
    await Store.raw.remove('theme_night');
    expect(nightModeChosen, isFalse);
    expect(nightMode, ui.PlatformDispatcher.instance.platformBrightness == Brightness.dark);
    await Store.raw.setBool('theme_night', true);
    expect(nightModeChosen, isTrue);
    expect(selectedBotColor.id, 'midnight');
  });

  test('each level unlocks a day + night pair', () async {
    final pairs = [for (final e in themePairs.entries) (botColors.firstWhere((c) => c.id == e.key), botColors.firstWhere((c) => c.id == e.value))];
    expect(pairs.map((p) => p.$1.unlockLevel), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    for (final (day, night) in pairs) {
      expect(day.light, isTrue);
      expect(night.light, isFalse);
      expect(night.unlockLevel, day.unlockLevel);
    }
    await Store.raw.setInt('xp', 150); // level 2
    await Store.raw.setString('bot_color', 'sand'); // level 3: not yet
    await Store.raw.setBool('theme_night', true);
    expect(selectedBotColor.id, 'midnight');
    await Store.raw.setString('bot_color', 'mint');
    expect(selectedBotColor.id, 'forest');
  });
}
