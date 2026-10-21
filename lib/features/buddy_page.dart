import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/cleaner.dart';
import '../core/native.dart';
import '../core/store.dart';
import '../core/game.dart';
import 'astro/stars_card.dart';
import 'boss_card.dart';
import 'trophies_page.dart';
import 'bot_face.dart';
import 'grow/growth.dart';
import 'grow/courses.dart' show coursePace, unitOf;
import 'grow/lessons.dart' show subjects;
import 'sections.dart';
import 'talk/talk_page.dart';
import 'talk/wisdom.dart';
import 'settings_page.dart';
import 'ui.dart';

class Quest {
  final String id, title, emoji, progressText;
  final double progress; // 0..1
  final int xp;
  const Quest(this.id, this.emoji, this.title, this.progress, this.xp, this.progressText);
  bool get done => progress >= 1;
}

const _devTips = [
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

class BuddyPage extends StatefulWidget {
  const BuddyPage({super.key});
  @override
  State<BuddyPage> createState() => _BuddyPageState();
}

class _BuddyPageState extends State<BuddyPage> with WidgetsBindingObserver {
  Map<String, dynamic> _water = {'count': 0, 'goal': 8, 'interval': 60, 'enabled': true, 'start': 8, 'end': 22};
  int _reels = 0, _reelLimit = 150;
  String _say = '';
  bool _talking = false;
  bool _showAllQuests = false;
  Timer? _talkTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _talkTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    await Store.init();
    final w = await Native.getWater();
    final s = await Native.scrollStats(7);
    final ss = await Native.getScrollSettings();
    if (!mounted) return;
    setState(() {
      _water = w;
      _reels = s.isEmpty ? 0 : Native.reelsOn(s.first);
      _reelLimit = ss['reelLimit'];
    });
    if (_say.isEmpty) _speak(_contextLine());
    // Trophy bookkeeping
    if ((w['count'] as int) >= (w['goal'] as int)) {
      final days = Store.raw.getStringList('water_goal_days') ?? [];
      if (!days.contains(dayKey())) await Store.raw.setStringList('water_goal_days', [...days, dayKey()]);
    }
    final since = DateTime.tryParse(Store.raw.getString('growth_since') ?? '');
    if (s.length >= 7 && since != null && DateTime.now().difference(since).inDays >= 7 && s.every((d) => Native.reelsOn(d) <= _reelLimit)) {
      await Store.raw.setBool('scroll_monk', true);
    }
  }

  List<Quest> get _quests {
    final p = Store.profile;
    final today = dayKey();
    final workoutMin = Store.workoutsOn(today).fold<int>(0, (a, w) => a + (w['minutes'] as int));
    final water = _water['count'] as int, wGoal = _water['goal'] as int;
    final meals = Store.mealsOn(today).length;
    final learned = Store.learnedToday.length;
    final practiceMin = Store.practiceSeconds(today) ~/ 60;
    final list = [
      Quest('learn', '📚', 'Learn 2 lessons', learned / 2, 20, '$learned/2'),
      Quest('math', '🧮', "Solve today's maths problem", Store.mathDoneToday ? 1 : 0, 15, ''),
      if (Store.courses.any((c) => c['done'] < c['total']))
        Quest('course', '🎓', 'Progress a course', Store.courseLessonsToday().toDouble(), 25, '${Store.courseLessonsToday()} today'),
      Quest('practice', '🪈', 'Practice 20 min', practiceMin / 20, 30, '$practiceMin min'),
      Quest('water', '💧', 'Drink $wGoal glasses', water / wGoal, 30, '$water/$wGoal'),
      Quest('steps', '🚶', 'Walk ${p['stepGoal']} steps', Store.stepsToday / (p['stepGoal'] as int), 30, '${Store.stepsToday}'),
      Quest('workout', '💪', 'Move ${p['workoutGoal']} min', workoutMin / (p['workoutGoal'] as int), 40, '$workoutMin min'),
      Quest('meal', '🥗', 'Log 2 meals', meals / 2, 15, '$meals/2'),
      Quest('clean', '🧹', 'Run a cleanup', Store.raw.getString('cleaned_on') == today ? 1 : 0, 10, ''),
      // Inverse quest: unlocks at 9 pm if you stayed under the limit.
      Quest(
        'scroll',
        '🧘',
        'Stay under $_reelLimit reels',
        _reels > _reelLimit ? 0 : (DateTime.now().hour >= 21 ? 1 : 0.5),
        50,
        _reels > _reelLimit ? 'failed' : 'unlocks 9 pm',
      ),
    ];
    // Claimable first, then in progress, claimed last.
    int rank(Quest q) => Store.questClaimed(q.id)
        ? 2
        : q.done
        ? 0
        : 1;
    list.sort((a, b) => rank(a).compareTo(rank(b)));
    return list;
  }

  /// Starts mildly happy; good habits lift it, bad ones (binge, dehydration) drop it.
  double get _mood {
    final q = _quests;
    var m = 0.3 + q.fold<double>(0, (a, x) => a + x.progress.clamp(0, 1)) / q.length * 0.7;
    if (_reels > _reelLimit) m -= 0.9;
    if (DateTime.now().hour >= 14 && (_water['count'] as int) < 3) m -= 0.4;
    return m.clamp(-1, 1).toDouble();
  }

  String _contextLine() {
    final h = DateTime.now().hour;
    final name = Store.profile['name'];
    final water = _water['count'] as int;
    for (final c in Store.courses) {
      final p = coursePace(c);
      final today = (c['log'] as Map?)?[dayKey()] as int? ?? 0;
      if (p != null && c['done'] < c['total'] && p.daysLeft <= 7 && today < p.perDay && h >= 17) {
        return '"${c['name']}" is due in ${p.daysLeft} day${p.daysLeft == 1 ? '' : 's'}. ${p.perDay - today} more ${unitOf(c)} today keeps you on track 🎓';
      }
    }
    if (_reels > _reelLimit) return "You've swiped $_reels reels today… I'm a little worried 😟 Let's do something else?";
    if (h >= 11 && water < 2) {
      return water == 0 ? 'No water yet today, $name! Tap + after your next glass 💧' : 'Just $water glass so far. Let\'s top up 💧';
    }
    if (Store.stepsToday < 2000 && h >= 16) return "We've barely moved today. A 10-min walk = +XP for both of us!";
    if (Store.mealsOn(dayKey()).isEmpty && h >= 13) return 'Hungry? Ask me in the Food tab, I\'ll pick something nutritious.';
    if (h < 12) return 'Good morning $name! ☀️ Ready to crush some bugs today?';
    if (h < 17) return 'Hey $name! ${_devTips[Random().nextInt(_devTips.length)]}';
    return "Evening, $name. Wrap up, commit your work, and no doomscrolling before bed 🌙";
  }

  int _quoteSeed = Random().nextInt(1000);

  /// Tapping the speech bubble: a short teaching from the wisdom library (sometimes a dev tip).
  void _nextQuote() {
    HapticFeedback.selectionClick();
    final short = teachings.where((t) => t.mean.length <= 150).toList();
    _quoteSeed++;
    final r = Random(_quoteSeed * 7919);
    if (r.nextInt(4) == 0) {
      _speak(_devTips[r.nextInt(_devTips.length)]);
      return;
    }
    final t = short[r.nextInt(short.length)];
    _speak('“${t.mean}”\n— ${t.src.split(' (').first}');
  }

  void _speak(String s) {
    setState(() {
      _say = s;
      _talking = true;
    });
    _talkTimer?.cancel();
    _talkTimer = Timer(Duration(milliseconds: 600 + s.length * 25), () => mounted ? setState(() => _talking = false) : null);
  }

  Future<void> _drink(int d) async {
    if (d < 0 && (_water['count'] as int) == 0) return;
    HapticFeedback.lightImpact();
    final c = await Native.logDrink(d);
    setState(() => _water['count'] = c);
    if (d > 0) {
      _speak(c == (_water['goal'] as int) ? 'Hydration goal smashed! 🎉 Claim your XP below!' : 'Glug glug! $c/${_water['goal']} 💧');
    }
  }

  Future<void> _waterSettings() async {
    final w = Map<String, dynamic>.from(_water);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (context, set) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Water reminders', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const Text('Vibration only, never a sound'),
              const SizedBox(height: 8),
              SwitchListTile(title: const Text('Reminders'), value: w['enabled'], onChanged: (v) => set(() => w['enabled'] = v)),
              ListTile(
                title: Text('Every ${w['interval']} min'),
                subtitle: Slider(
                  value: (w['interval'] as int).toDouble(),
                  min: 30,
                  max: 180,
                  divisions: 10,
                  onChanged: w['enabled'] ? (v) => set(() => w['interval'] = v.round()) : null,
                ),
              ),
              ListTile(
                title: Text('Daily goal: ${w['goal']} glasses (${((w['goal'] as int) * 0.25).toStringAsFixed(1)} L)'),
                subtitle: Slider(
                  value: (w['goal'] as int).toDouble(),
                  min: 4,
                  max: 16,
                  divisions: 12,
                  onChanged: (v) => set(() => w['goal'] = v.round()),
                ),
              ),
              ListTile(
                title: Text('Only between ${w['start']}:00 and ${w['end']}:00'),
                subtitle: RangeSlider(
                  values: RangeValues((w['start'] as int).toDouble(), (w['end'] as int).toDouble()),
                  min: 5,
                  max: 24,
                  divisions: 19,
                  onChanged: w['enabled']
                      ? (r) => set(() {
                          w['start'] = r.start.round();
                          w['end'] = r.end.round();
                        })
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton.icon(onPressed: Native.testVibrate, icon: const Icon(Icons.vibration), label: const Text('Test')),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        await Native.setWater({
                          'enabled': w['enabled'],
                          'interval': w['interval'],
                          'goal': w['goal'],
                          'start': w['start'],
                          'end': w['end'],
                        });
                        if (context.mounted) Navigator.pop(context);
                      },
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final lvl = Store.level, xp = Store.xp;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final (at, cats) = Cleaner.load();
    final water = _water['count'] as int, goal = _water['goal'] as int;
    final quests = _quests;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: pagePadding,
            children: [
              // Header: level ring (→ Trophies), name + rank, trophies, settings
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
                child: Row(children: [
                  GestureDetector(onTap: _openTrophies, child: _LevelRing(level: lvl, progress: (xp % 100) / 100)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(Store.profile['name'], maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                      Text('${rankFor(lvl)} · ${100 - xp % 100} XP to Lv ${lvl + 1}', maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ]),
                  ),
                  Badge(
                    label: Text('${earnedTrophies.length}'),
                    backgroundColor: Colors.amber.shade700,
                    child: IconButton.filledTonal(tooltip: 'Trophies', onPressed: _openTrophies, icon: const Icon(Icons.emoji_events_outlined)),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filledTonal(
                    tooltip: 'Settings',
                    onPressed: () async {
                      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
                      _refresh();
                    },
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ]),
              ),
              Wrap(spacing: 6, runSpacing: 6, children: [
                StatChip(icon: Icons.local_fire_department, label: '${Store.growthStreak}-day growth streak'),
                if (Store.freezes > 0) StatChip(icon: Icons.ac_unit, label: '${Store.freezes} freeze${Store.freezes == 1 ? '' : 's'}'),
                if (at != null && Cleaner.total(cats) > 0) StatChip(icon: Icons.cleaning_services_outlined, label: '${fmtBytes(Cleaner.total(cats))} to clean'),
              ]),
              const SizedBox(height: 12),
              // Speech bubble + bot
              _SpeechBubble(text: _say, onTap: _nextQuote),
              Center(
                child: BotFace(
                  mood: _mood,
                  talking: _talking,
                  size: 170,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TalkPage()));
                  },
                ),
              ),
              Center(
                child: FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TalkPage())),
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: const Text('Talk to me'),
                ),
              ),
              const SizedBox(height: 10),
              GrowthCard(onChanged: _refresh),
              const SizedBox(height: 6),
              Row(children: [
                _action('📚', 'Learn', '${Store.learnedToday.length}/${subjects.length} today', (tabGrow, 0)),
                _action('🪈', 'Practice', '${Store.practiceSeconds(dayKey()) ~/ 60} min', (tabGrow, 2)),
                _action('📰', 'News', 'Tech · India', (tabGrow, 1)),
                _action('🍽️', 'Eat', 'Suggest', (tabHealth, 1)),
              ]),
              const SizedBox(height: 6),
              const BossCard(),
              // Water
              AppCard(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Water', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                              Text(_water['enabled'] ? 'Vibrates every ${_water['interval']} min' : 'Reminders off', style: tt.bodySmall),
                            ],
                          ),
                        ),
                        IconButton(onPressed: _waterSettings, icon: const Icon(Icons.tune), tooltip: 'Reminder settings'),
                        IconButton.outlined(onPressed: water > 0 ? () => _drink(-1) : null, icon: const Icon(Icons.remove)),
                        const SizedBox(width: 4),
                        IconButton.filled(onPressed: () => _drink(1), icon: const Icon(Icons.add)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        for (var i = 0; i < goal; i++)
                          Expanded(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              height: 36,
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(
                                color: i < water ? Colors.lightBlue : cs.surfaceContainerHighest,
                                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10), top: Radius.circular(4)),
                              ),
                              child: i < water ? const Icon(Icons.water_drop, size: 16, color: Colors.white) : null,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('$water of $goal glasses', style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
              const StarsCard(),
              SectionTitle(
                'Bonus quests',
                trailing: Text('${quests.where((q) => Store.questClaimed(q.id)).length}/${quests.length} done', style: tt.bodySmall),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                child: Text('Optional extra XP. Your must-do is just “Today’s growth” above.', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ),
              for (final q in _showAllQuests ? quests : quests.take(4)) _questTile(q),
              if (quests.length > 4)
                TextButton.icon(
                  onPressed: () => setState(() => _showAllQuests = !_showAllQuests),
                  icon: Icon(_showAllQuests ? Icons.expand_less : Icons.expand_more),
                  label: Text(_showAllQuests ? 'Show less' : 'Show all ${quests.length} quests'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _questTile(Quest q) {
    final claimed = Store.questClaimed(q.id);
    final cs = Theme.of(context).colorScheme;
    return Opacity(
      opacity: claimed ? 0.55 : 1,
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        color: q.done && !claimed ? cs.primaryContainer : null,
        child: Row(
          children: [
            Text(q.emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(q.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      if (q.progressText.isNotEmpty && !claimed) Text(q.progressText, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(value: q.progress.clamp(0, 1).toDouble(), minHeight: 6, borderRadius: BorderRadius.circular(6)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 72,
              child: claimed
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : q.done
                  ? FilledButton(
                      style: FilledButton.styleFrom(padding: EdgeInsets.zero),
                      onPressed: () async {
                        HapticFeedback.mediumImpact();
                        final before = Store.level;
                        await Store.claimQuest(q.id, q.xp);
                        setState(() {});
                        _speak(Store.level > before ? 'LEVEL UP! I\'m now level ${Store.level}! 🚀' : '+${q.xp} XP! Nice one 😄');
                      },
                      child: Text('+${q.xp}'),
                    )
                  : Text('+${q.xp} XP', textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelMedium),
            ),
          ],
        ),
      ),
    );
  }

  Widget _action(String emoji, String label, String sub, (int, int) target) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Material(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              HapticFeedback.selectionClick();
              navRequest.value = target;
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              child: Column(children: [
                Text(emoji, style: const TextStyle(fontSize: 24)),
                const SizedBox(height: 4),
                Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openTrophies() async {
    HapticFeedback.selectionClick();
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TrophiesPage()));
    if (mounted) setState(() {});
  }

}

class _SpeechBubble extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _SpeechBubble({required this.text, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.secondaryContainer;
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(a), child: child)),
            child: Container(
              key: ValueKey(text),
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(20)),
              child: Column(children: [
                Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, height: 1.3)),
                const SizedBox(height: 4),
                Text('Tap for another', style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSecondaryContainer.withValues(alpha: 0.6))),
              ]),
            ),
          ),
        ),
        CustomPaint(size: const Size(24, 12), painter: _TailPainter(c)),
      ],
    );
  }
}

class _TailPainter extends CustomPainter {
  final Color color;
  _TailPainter(this.color);
  @override
  void paint(Canvas c, Size s) => c.drawPath(
    Path()
      ..moveTo(0, 0)
      ..lineTo(s.width, 0)
      ..lineTo(s.width / 2, s.height)
      ..close(),
    Paint()..color = color,
  );
  @override
  bool shouldRepaint(_TailPainter o) => o.color != color;
}

/// Level number inside a circular XP-progress ring.
class _LevelRing extends StatelessWidget {
  final int level;
  final double progress;
  const _LevelRing({required this.level, required this.progress});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 52,
      child: Stack(alignment: Alignment.center, children: [
        SizedBox.expand(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => CircularProgressIndicator(
              value: v,
              strokeWidth: 5,
              strokeCap: StrokeCap.round,
              color: Colors.amber.shade600,
              backgroundColor: cs.surfaceContainerHighest,
            ),
          ),
        ),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text('LV', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: cs.onSurfaceVariant, height: 1)),
          Text('$level', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, height: 1.1)),
        ]),
      ]),
    );
  }
}
