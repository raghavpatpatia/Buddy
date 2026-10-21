import 'package:buddy_app/core/game.dart';
import 'package:buddy_app/core/store.dart';
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
    expect(rankFor(2), 'Rookie');
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
    await Store.raw.setString('bot_color', 'gold'); // locked at level 1
    expect(selectedBotColor.id, 'auto');
    await Store.raw.setInt('xp', 800); // level 9
    expect(selectedBotColor.id, 'gold');
  });
}
