import 'dart:async';
import 'dart:math';

import '../../../core/arch/safe_notifier.dart';
import '../../../core/native.dart';
import '../../../core/store.dart';
import '../../grow/model/course.dart' show coursePace, unitOf;
import '../../talk/data/wisdom.dart';
import '../model/quest.dart';

const devTips = [
  'Tip: `git commit --fixup <sha>` + `git rebase -i --autosquash` keeps history clean.',
  'Tip: `git switch -` jumps back to your previous branch.',
  'Tip: rubber-duck it. Explaining the bug to me counts! 🦆',
  '20-20-20: every 20 min, look 20 ft away for 20 s. Your eyes will thank you.',
  'Tip: write the test that reproduces the bug before fixing it.',
  'Tip: `adb shell dumpsys gfxinfo <pkg>` shows jank stats for your app.',
  'Small PRs get reviewed faster. Ship in slices!',
  'Stuck for 30+ min? Take a 5 min walk. Brains debug in the background.',
  'Tip: in Flutter, `const` constructors skip rebuilds. Sprinkle them.',
  'Posture check! Shoulders down, screen at eye level. 🧍',
  'Why do programmers prefer dark mode? Because light attracts bugs. 🐛',
  'Tip: `Ctrl+R` in your shell searches command history. Life-changing.',
];

/// Home screen: water, reels vs limit, Buddy's speech bubble and mood, daily quests and trophy bookkeeping.
class HomeController extends SafeNotifier {
  Map<String, dynamic> water = {'count': 0, 'goal': 8, 'interval': 60, 'enabled': true, 'start': 8, 'end': 22};
  int reels = 0, reelLimit = 150;
  String say = '';
  bool talking = false, showAllQuests = false;
  Timer? _talkTimer;
  int _quoteSeed = Random().nextInt(1000);

  int get level => Store.level;
  int get xp => Store.xp;
  String get name => Store.profile['name'] as String? ?? '';
  int get growthStreak => Store.growthStreak;
  int get freezes => Store.freezes;
  int get learnedToday => Store.learnedToday.length;
  int get practiceMinToday => Store.practiceSeconds(dayKey()) ~/ 60;
  int get waterCount => water['count'] as int;
  int get waterGoal => water['goal'] as int;

  /// Reloads storage and native stats; records trophy progress (water goal days, a week under the reel limit).
  Future<void> refresh() async {
    await Store.init();
    final w = await Native.getWater();
    final s = await Native.scrollStats(7);
    final ss = await Native.getScrollSettings();
    water = w;
    reels = s.isEmpty ? 0 : Native.reelsOn(s.first);
    reelLimit = ss['reelLimit'];
    notifyListeners();
    if (say.isEmpty) speak(contextLine());
    if ((w['count'] as int) >= (w['goal'] as int)) {
      final days = Store.raw.getStringList('water_goal_days') ?? [];
      if (!days.contains(dayKey())) await Store.raw.setStringList('water_goal_days', [...days, dayKey()]);
    }
    final since = DateTime.tryParse(Store.raw.getString('growth_since') ?? '');
    if (s.length >= 7 && since != null && DateTime.now().difference(since).inDays >= 7 && s.every((d) => Native.reelsOn(d) <= reelLimit)) {
      await Store.raw.setBool('scroll_monk', true);
    }
  }

  /// Today's quests: claimable first, then in progress, claimed last.
  List<Quest> get quests {
    final p = Store.profile;
    final today = dayKey();
    final workoutMin = Store.workoutsOn(today).fold<int>(0, (a, w) => a + (w['minutes'] as int));
    final meals = Store.mealsOn(today).length;
    final learned = Store.learnedToday.length;
    final practiceMin = Store.practiceSeconds(today) ~/ 60;
    final list = [
      Quest('learn', '📚', 'Learn 2 lessons', learned / 2, 20, '$learned/2'),
      Quest('math', '🧮', "Solve today's maths problem", Store.mathDoneToday ? 1 : 0, 15, ''),
      if (Store.courses.any((c) => c['done'] < c['total']))
        Quest('course', '🎓', 'Progress a course', Store.courseLessonsToday().toDouble(), 25, '${Store.courseLessonsToday()} today'),
      Quest('practice', '🪈', 'Practice 20 min', practiceMin / 20, 30, '$practiceMin min'),
      Quest('water', '💧', 'Drink $waterGoal glasses', waterCount / waterGoal, 30, '$waterCount/$waterGoal'),
      Quest('steps', '🚶', 'Walk ${p['stepGoal']} steps', Store.stepsToday / (p['stepGoal'] as int), 30, '${Store.stepsToday}'),
      Quest('workout', '💪', 'Move ${p['workoutGoal']} min', workoutMin / (p['workoutGoal'] as int), 40, '$workoutMin min'),
      Quest('meal', '🥗', 'Log 2 meals', meals / 2, 15, '$meals/2'),
      Quest('clean', '🧹', 'Run a cleanup', Store.raw.getString('cleaned_on') == today ? 1 : 0, 10, ''),
      // Inverse quest: unlocks at 9 pm if you stayed under the limit.
      Quest('scroll', '🧘', 'Stay under $reelLimit reels', reels > reelLimit ? 0 : (DateTime.now().hour >= 21 ? 1 : 0.5), 50, reels > reelLimit ? 'failed' : 'unlocks 9 pm'),
    ];
    int rank(Quest q) => Store.questClaimed(q.id) ? 2 : (q.done ? 0 : 1);
    list.sort((a, b) => rank(a).compareTo(rank(b)));
    return list;
  }

  bool claimed(Quest q) => Store.questClaimed(q.id);

  /// Starts mildly happy; good habits lift it, bad ones (binge, dehydration) drop it.
  double get mood {
    final q = quests;
    var m = 0.3 + q.fold<double>(0, (a, x) => a + x.progress.clamp(0, 1)) / q.length * 0.7;
    if (reels > reelLimit) m -= 0.9;
    if (DateTime.now().hour >= 14 && waterCount < 3) m -= 0.4;
    return m.clamp(-1, 1).toDouble();
  }

  /// What Buddy says on opening: the most pressing nudge for this time of day.
  String contextLine() {
    final h = DateTime.now().hour;
    final name = Store.profile['name'];
    for (final c in Store.courses) {
      final p = coursePace(c);
      final today = (c['log'] as Map?)?[dayKey()] as int? ?? 0;
      if (p != null && c['done'] < c['total'] && p.daysLeft <= 7 && today < p.perDay && h >= 17) {
        return '"${c['name']}" is due in ${p.daysLeft} day${p.daysLeft == 1 ? '' : 's'}. ${p.perDay - today} more ${unitOf(c)} today keeps you on track 🎓';
      }
    }
    if (reels > reelLimit) return "You've swiped $reels reels today… I'm a little worried 😟 Let's do something else?";
    if (h >= 11 && waterCount < 2) {
      return waterCount == 0 ? 'No water yet today, $name! Tap + after your next glass 💧' : 'Just $waterCount glass so far. Let\'s top up 💧';
    }
    if (Store.stepsToday < 2000 && h >= 16) return "We've barely moved today. A 10-min walk = +XP for both of us!";
    if (Store.mealsOn(dayKey()).isEmpty && h >= 13) return 'Hungry? Ask me in the Food tab, I\'ll pick something nutritious.';
    if (h < 12) return 'Good morning $name! ☀️ Ready to crush some bugs today?';
    if (h < 17) return 'Hey $name! ${devTips[Random().nextInt(devTips.length)]}';
    return "Evening, $name. Wrap up, commit your work, and no doomscrolling before bed 🌙";
  }

  /// Tapping the speech bubble: a short teaching from the wisdom library (sometimes a dev tip).
  void nextQuote() {
    final short = teachings.where((t) => t.mean.length <= 150).toList();
    _quoteSeed++;
    final r = Random(_quoteSeed * 7919);
    if (r.nextInt(4) == 0) return speak(devTips[r.nextInt(devTips.length)]);
    final t = short[r.nextInt(short.length)];
    speak('“${t.mean}”\n— ${t.src.split(' (').first}');
  }

  /// Shows [s] in the bubble and animates Buddy's mouth for a time based on its length.
  void speak(String s) {
    say = s;
    talking = true;
    notifyListeners();
    _talkTimer?.cancel();
    _talkTimer = Timer(Duration(milliseconds: 600 + s.length * 25), () {
      talking = false;
      notifyListeners();
    });
  }

  /// Logs +1/−1 glass (never below 0) and cheers.
  Future<void> drink(int d) async {
    if (d < 0 && waterCount == 0) return;
    final c = await Native.logDrink(d);
    water['count'] = c;
    notifyListeners();
    if (d > 0) speak(c == waterGoal ? 'Hydration goal smashed! 🎉 Claim your XP below!' : 'Glug glug! $c/$waterGoal 💧');
  }

  Future<void> saveWater(Map<String, dynamic> w) async {
    await Native.setWater({'enabled': w['enabled'], 'interval': w['interval'], 'goal': w['goal'], 'start': w['start'], 'end': w['end']});
    await refresh();
  }

  Future<void> claim(Quest q) async {
    final before = Store.level;
    await Store.claimQuest(q.id, q.xp);
    speak(Store.level > before ? 'LEVEL UP! I\'m now level ${Store.level}! 🚀' : '+${q.xp} XP! Nice one 😄');
  }

  void toggleQuests() {
    showAllQuests = !showAllQuests;
    notifyListeners();
  }

  @override
  void dispose() {
    _talkTimer?.cancel();
    super.dispose();
  }
}
