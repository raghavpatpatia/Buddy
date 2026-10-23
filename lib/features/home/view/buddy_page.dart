import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/format.dart';
import '../../../core/game.dart';
import '../../../core/native.dart';
import '../../astro/view/stars_card.dart';
import '../../../shared/bot_face.dart';
import '../../grow/model/lessons.dart' show subjects;
import '../../grow/view/growth_page.dart';
import '../../phone/data/cleaner.dart';
import '../../../app/sections.dart';
import '../../settings/view/settings_page.dart';
import '../../talk/view/talk_page.dart';
import '../../../shared/system_background.dart';
import '../../../shared/ui.dart';
import '../controller/home_controller.dart';
import '../model/quest.dart';
import 'boss_card.dart';
import 'trophies_page.dart';

/// Buddy home: level, Buddy's face and speech, growth, quick actions, water, stars and daily quests.
class BuddyPage extends StatefulWidget {
  const BuddyPage({super.key});
  @override
  State<BuddyPage> createState() => _BuddyPageState();
}

class _BuddyPageState extends State<BuddyPage> with WidgetsBindingObserver {
  final c = HomeController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) c.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c.dispose();
    super.dispose();
  }

  void _nextQuote() {
    HapticFeedback.selectionClick();
    c.nextQuote();
  }

  Future<void> _drink(int d) async {
    if (d < 0 && c.waterCount == 0) return;
    HapticFeedback.lightImpact();
    await c.drink(d);
  }

  Future<void> _waterSettings() async {
    final w = Map<String, dynamic>.from(c.water);
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
                        await c.saveWater(w);
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
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: c, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final lvl = c.level, xp = c.xp;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final (at, cats) = Cleaner.load();
    final water = c.waterCount, goal = c.waterGoal;
    final quests = c.quests;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: c.refresh,
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
                      Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                      Text('${rankFor(lvl)} · ${100 - xp % 100} XP to Lv ${lvl + 1}', maxLines: 2, style: TextStyle(fontFamily: hudFont, fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: SystemColors.manaBright, height: 1.15)),
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
                      c.refresh();
                    },
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ]),
              ),
              Wrap(spacing: 6, runSpacing: 6, children: [
                StatChip(icon: Icons.local_fire_department, label: '${c.growthStreak}-day growth streak'),
                if (c.freezes > 0) StatChip(icon: Icons.ac_unit, label: '${c.freezes} freeze${c.freezes == 1 ? '' : 's'}'),
                if (at != null && Cleaner.total(cats) > 0) StatChip(icon: Icons.cleaning_services_outlined, label: '${fmtBytes(Cleaner.total(cats))} to clean'),
              ]),
              const SizedBox(height: 12),
              // Speech bubble + bot
              _SpeechBubble(text: c.say, onTap: _nextQuote),
              Center(
                child: BotFace(
                  mood: c.mood,
                  talking: c.talking,
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
              GrowthCard(onChanged: c.refresh),
              const SizedBox(height: 6),
              Row(children: [
                _action('📚', 'Learn', '${c.learnedToday}/${subjects.length} today', (tabGrow, 0)),
                _action('🪈', 'Practice', '${c.practiceMinToday} min', (tabGrow, 2)),
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
                              Text(c.water['enabled'] ? 'Vibrates every ${c.water['interval']} min' : 'Reminders off', style: tt.bodySmall),
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
                trailing: Text('${quests.where(c.claimed).length}/${quests.length} done', style: tt.bodySmall),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                child: Text('Optional extra XP. Your must-do is just “Today’s growth” above.', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ),
              for (final q in c.showAllQuests ? quests : quests.take(4)) _questTile(q),
              if (quests.length > 4)
                TextButton.icon(
                  onPressed: c.toggleQuests,
                  icon: Icon(c.showAllQuests ? Icons.expand_less : Icons.expand_more),
                  label: Text(c.showAllQuests ? 'Show less' : 'Show all ${quests.length} quests'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _questTile(Quest q) {
    final claimed = c.claimed(q);
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
                        await c.claim(q);
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
    final c = SystemColors.panel;
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
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: SystemColors.mana.withValues(alpha: 0.6)),
                boxShadow: [BoxShadow(color: SystemColors.mana.withValues(alpha: 0.2), blurRadius: 14)],
              ),
              child: SystemFrame(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(children: [
                    Text('[ SYSTEM ]', style: TextStyle(fontFamily: hudFont, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 3, color: SystemColors.mana)),
                    const SizedBox(height: 4),
                    Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, height: 1.3)),
                    const SizedBox(height: 4),
                    Text('Tap for another', style: TextStyle(fontSize: 10, color: SystemColors.muted.withValues(alpha: 0.8))),
                  ]),
                ),
              ),
            ),
          ),
        ),
        CustomPaint(size: const Size(24, 12), painter: _TailPainter(SystemColors.mana.withValues(alpha: 0.6))),
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
              color: SystemColors.mana,
              backgroundColor: cs.surfaceContainerHighest,
            ),
          ),
        ),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text('LV', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: cs.onSurfaceVariant, height: 1)),
          Text('$level', style: TextStyle(fontFamily: hudFont, fontSize: 22, fontWeight: FontWeight.w700, height: 1.0, color: SystemColors.manaBright)),
        ]),
      ]),
    );
  }
}
