import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

String dayKey([DateTime? d]) {
  final t = d ?? DateTime.now();
  return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}

/// Tiny JSON-in-SharedPreferences store. Works in the background isolate too.
class Store {
  static late SharedPreferences _p;

  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    await _p.reload();
  }

  static SharedPreferences get raw => _p;

  static dynamic getJson(String k, [dynamic fallback]) {
    final s = _p.getString(k);
    if (s == null) return fallback;
    try {
      return jsonDecode(s);
    } catch (_) {
      return fallback;
    }
  }

  static Future<void> setJson(String k, dynamic v) => _p.setString(k, jsonEncode(v));

  // ---------- Gamification ----------
  static int get xp => _p.getInt('xp') ?? 0;
  static int get level => 1 + xp ~/ 100;
  /// Every XP gain is broadcast so the UI can celebrate (toast, level-up, boss damage, trophies).
  static final xpEvents = ValueNotifier<XpEvent?>(null);

  static Future<void> addXp(int n) async {
    final before = level;
    await _p.setInt('xp', xp + n);
    if (n > 0) xpEvents.value = XpEvent(n, level > before ? level : null);
  }

  static bool questClaimed(String id) =>
      (_p.getStringList('claimed_${dayKey()}') ?? []).contains(id);
  static Future<void> claimQuest(String id, int reward) async {
    final k = 'claimed_${dayKey()}';
    await _p.setStringList(k, [...(_p.getStringList(k) ?? []), id]);
    await addXp(reward);
    // Streak: any claimed quest counts the day as active.
    final last = _p.getString('streak_last');
    if (last != dayKey()) {
      final yesterday = dayKey(DateTime.now().subtract(const Duration(days: 1)));
      await _p.setInt('streak', last == yesterday ? (_p.getInt('streak') ?? 0) + 1 : 1);
      await _p.setString('streak_last', dayKey());
    }
  }

  static int get streak {
    final last = _p.getString('streak_last');
    final yesterday = dayKey(DateTime.now().subtract(const Duration(days: 1)));
    return (last == dayKey() || last == yesterday) ? (_p.getInt('streak') ?? 0) : 0;
  }

  // ---------- Profile ----------
  static Map<String, dynamic> get profile => Map<String, dynamic>.from(getJson('profile', {
        'name': 'Raghav',
        'weight': 70,
        'diet': 'nonveg', // veg | egg | nonveg
        'goal': 'maintain', // lose | maintain | gain
        'stepGoal': 8000,
        'workoutGoal': 30,
      }));
  static Future<void> setProfile(Map<String, dynamic> p) => setJson('profile', p);

  // ---------- Steps (hardware counter counts since boot) ----------
  static Future<int> recordSteps(int raw) async {
    final today = dayKey();
    var base = _p.getInt('steps_base') ?? raw;
    final lastRaw = _p.getInt('steps_last_raw') ?? raw;
    if (_p.getString('steps_date') != today) {
      // New day: keep yesterday's total for history, start fresh.
      if (_p.getString('steps_date') != null) {
        final hist = Map<String, dynamic>.from(getJson('steps_hist', {}));
        hist[_p.getString('steps_date')!] = lastRaw - base;
        await setJson('steps_hist', hist);
      }
      base = raw;
      await _p.setString('steps_date', today);
    } else if (raw < lastRaw) {
      base = raw - (lastRaw - base); // phone rebooted
    }
    await _p.setInt('steps_base', base);
    await _p.setInt('steps_last_raw', raw);
    return raw - base;
  }

  static int get stepsToday => _p.getString('steps_date') == dayKey()
      ? (_p.getInt('steps_last_raw') ?? 0) - (_p.getInt('steps_base') ?? 0)
      : 0;

  // ---------- Workouts ----------
  static List<Map<String, dynamic>> get workouts =>
      List<Map<String, dynamic>>.from((getJson('workouts', []) as List).map((e) => Map<String, dynamic>.from(e)));
  static Future<void> addWorkout(Map<String, dynamic> w) => setJson('workouts', [...workouts, w]);
  static Future<void> removeWorkout(int i) => setJson('workouts', [...workouts]..removeAt(i));
  static List<Map<String, dynamic>> workoutsOn(String day) => workouts.where((w) => w['date'] == day).toList();

  // ---------- Food ----------
  static List<Map<String, dynamic>> get places =>
      List<Map<String, dynamic>>.from((getJson('places', []) as List).map((e) => Map<String, dynamic>.from(e)));
  static Future<void> setPlaces(List<Map<String, dynamic>> v) => setJson('places', v);
  static List<Map<String, dynamic>> get meals =>
      List<Map<String, dynamic>>.from((getJson('meals', []) as List).map((e) => Map<String, dynamic>.from(e)));
  static Future<void> setMeals(List<Map<String, dynamic>> v) => setJson('meals', v);
  static List<Map<String, dynamic>> mealsOn(String day) => meals.where((m) => m['date'] == day).toList();

  // ---------- Grow ----------
  static List<String> get learnedToday => _p.getStringList('learned_${dayKey()}') ?? [];
  static Future<void> markLearned(String subjectId) =>
      _p.setStringList('learned_${dayKey()}', {...learnedToday, subjectId}.toList());
  static int get lessonsTotal => _p.getInt('lessons_total') ?? 0;
  static Future<void> bumpLessons() => _p.setInt('lessons_total', lessonsTotal + 1);

  /// Practice sessions: {date, activity, seconds}
  static List<Map<String, dynamic>> get practice =>
      List<Map<String, dynamic>>.from((getJson('practice', []) as List).map((e) => Map<String, dynamic>.from(e)));
  static Future<void> addPractice(String activity, int seconds) =>
      setJson('practice', [...practice, {'date': dayKey(), 'activity': activity, 'seconds': seconds}]);
  static int practiceSeconds(String day, [String? activity]) => practice
      .where((p) => p['date'] == day && (activity == null || p['activity'] == activity))
      .fold(0, (a, p) => a + (p['seconds'] as int));
  static int practiceStreak(String activity) {
    var n = 0;
    var d = DateTime.now();
    // Today counts if done; otherwise start counting from yesterday.
    if (practiceSeconds(dayKey(d), activity) == 0) d = d.subtract(const Duration(days: 1));
    while (practiceSeconds(dayKey(d), activity) > 0) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  /// Courses: {id, name, platform, url, total, done, deadline?, log: {date: lessons}}
  static List<Map<String, dynamic>> get courses =>
      List<Map<String, dynamic>>.from((getJson('courses', []) as List).map((e) => Map<String, dynamic>.from(e)));
  static Future<void> setCourses(List<Map<String, dynamic>> v) => setJson('courses', v);
  static int courseLessonsToday() =>
      courses.fold(0, (a, c) => a + ((c['log'] as Map?)?[dayKey()] as int? ?? 0));

  // ---------- Daily growth commitment (learn 1 thing + read 1 news story) ----------
  static bool get growthEnabled => _p.getBool('growth_enabled') ?? true;
  static int get growthHour => _p.getInt('growth_hour') ?? 20;
  static bool get learnDoneToday => learnedToday.isNotEmpty || mathDoneToday || courseLessonsToday() > 0;

  /// {date, title, link, source, note}
  static List<Map<String, dynamic>> get takeaways =>
      List<Map<String, dynamic>>.from((getJson('takeaways', []) as List).map((e) => Map<String, dynamic>.from(e)));
  static Future<void> addTakeaway(Map<String, dynamic> t) => setJson('takeaways', [...takeaways, {...t, 'date': dayKey()}]);
  static bool get newsDoneToday => takeaways.any((t) => t['date'] == dayKey());

  static bool get growthDoneToday => learnDoneToday && newsDoneToday;
  static List<String> get growthDays => _p.getStringList('growth_days') ?? [];
  static List<String> get growthPenalized => _p.getStringList('growth_penalized') ?? [];
  static bool get growthSkippedToday => growthPenalized.contains(dayKey());

  /// Call after any learning/news action. Returns true the moment today's commitment is completed.
  static Future<bool> markGrowthIfDone() async {
    if (!growthDoneToday || growthDays.contains(dayKey())) return false;
    await _p.setStringList('growth_days', [...growthDays, dayKey()]);
    if (DateTime.now().hour < 12) await _p.setBool('early_bird', true);
    if (growthStreak > 0 && growthStreak % 7 == 0) await _p.setInt('freezes', min(2, freezes + 1));
    await addXp(40);
    return true;
  }

  static int get freezes => _p.getInt('freezes') ?? 0;
  static List<String> get frozenDays => _p.getStringList('growth_frozen') ?? [];

  static int get growthStreak {
    final days = {...growthDays, ...frozenDays};
    var d = DateTime.now();
    if (!days.contains(dayKey(d))) d = d.subtract(const Duration(days: 1));
    var n = 0;
    while (days.contains(dayKey(d))) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  static const growthPenaltyXp = 30;

  static Future<void> penalize(String day) async {
    if (growthPenalized.contains(day) || growthDays.contains(day)) return;
    await _p.setStringList('growth_penalized', [...growthPenalized, day]);
    await _p.setInt('xp', max(0, xp - growthPenaltyXp));
  }

  /// Applies penalties for past days that were neither completed nor already penalised (max 7 back).
  /// Returns how many days were penalised.
  static Future<int> applyMissedGrowthPenalties() async {
    if (!growthEnabled) return 0;
    final since = DateTime.tryParse(_p.getString('growth_since') ?? '');
    if (since == null) {
      await _p.setString('growth_since', DateTime.now().toIso8601String());
      return 0;
    }
    var n = 0;
    for (var i = 1; i <= 7; i++) {
      final d = DateTime.now().subtract(Duration(days: i));
      if (d.isBefore(DateTime(since.year, since.month, since.day + 1))) break;
      final k = dayKey(d);
      if (!growthDays.contains(k) && !growthPenalized.contains(k) && !frozenDays.contains(k)) {
        if (freezes > 0) {
          // A streak freeze protects the day: no penalty and the streak survives.
          await _p.setInt('freezes', freezes - 1);
          await _p.setStringList('growth_frozen', [...frozenDays, k]);
          await _p.setInt('freezes_used', (_p.getInt('freezes_used') ?? 0) + 1);
          continue;
        }
        await penalize(k);
        n++;
      }
    }
    return n;
  }

  // ---------- Daily maths ----------
  static int get mathLevel => _p.getInt('math_level') ?? 0;
  static int get mathProgress => _p.getInt('math_progress') ?? 0; // correct answers at current level
  static bool get mathDoneToday => _p.getString('math_day') == dayKey();
  static int get mathStreak {
    final last = _p.getString('math_day');
    final yesterday = dayKey(DateTime.now().subtract(const Duration(days: 1)));
    return (last == dayKey() || last == yesterday) ? (_p.getInt('math_streak') ?? 0) : 0;
  }

  /// Records a correct answer. Returns true if it unlocked the next level.
  static Future<bool> mathSolved({required int maxLevel}) async {
    final prog = mathProgress + 1;
    if (prog >= 3 && mathLevel < maxLevel) {
      await _p.setInt('math_level', mathLevel + 1);
      await _p.setInt('math_progress', 0);
      return true;
    }
    await _p.setInt('math_progress', prog.clamp(0, 3));
    return false;
  }

  /// Marks today's daily problem as attempted (even if missed), so the streak counts effort.
  static Future<void> mathAttemptedToday() async {
    if (mathDoneToday) return;
    final yesterday = dayKey(DateTime.now().subtract(const Duration(days: 1)));
    await _p.setInt('math_streak', _p.getString('math_day') == yesterday ? mathStreak + 1 : 1);
    await _p.setString('math_day', dayKey());
  }

  static List<String> get activities => _p.getStringList('activities') ?? ['Flute', 'Singing'];

  /// One-time move: dance is exercise (Fit), not music practice. Old dance sessions become workouts.
  static Future<void> migrateDanceToFit() async {
    if (_p.getBool('dance_migrated') == true) return;
    final acts = _p.getStringList('activities');
    if (acts != null) await _p.setStringList('activities', acts.where((a) => a.toLowerCase() != 'dance').toList());
    final dance = practice.where((p) => (p['activity'] as String).toLowerCase() == 'dance').toList();
    if (dance.isNotEmpty) {
      await setJson('practice', practice.where((p) => (p['activity'] as String).toLowerCase() != 'dance').toList());
      for (final d in dance) {
        await addWorkout({'date': d['date'], 'type': 'Dance', 'minutes': ((d['seconds'] as int) / 60).ceil(), 'at': '${d['date']}T12:00:00'});
      }
    }
    if (_p.getString('practice_activity')?.toLowerCase() == 'dance') await _p.remove('practice_activity');
    await _p.setBool('dance_migrated', true);
  }
  static Future<void> setActivities(List<String> v) => _p.setStringList('activities', v);
  static int practiceGoalMin(String activity) => _p.getInt('pgoal_$activity') ?? 20;
  static Future<void> setPracticeGoal(String activity, int min) => _p.setInt('pgoal_$activity', min);
}

class XpEvent {
  final int amount;
  final int? newLevel; // set when this gain crossed a level boundary
  const XpEvent(this.amount, this.newLevel);
}
