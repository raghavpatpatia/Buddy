import 'package:flutter/material.dart';

import '../../../core/game.dart';
import '../../../core/store.dart';
import '../../../shared/bot_face.dart';
import '../../../shared/theme_picker.dart';
import '../../../shared/ui.dart';

class TrophiesPage extends StatefulWidget {
  const TrophiesPage({super.key});
  @override
  State<TrophiesPage> createState() => _TrophiesPageState();
}

class _TrophiesPageState extends State<TrophiesPage> {
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final lvl = Store.level, xp = Store.xp;
    final earned = earnedTrophies.toSet();
    return Scaffold(
      appBar: AppBar(title: const Text('Trophies')),
      body: ListView(padding: pagePadding, children: [
        HeroCard(
          child: Column(children: [
            const BotFace(mood: 0.9, size: 110),
            const SizedBox(height: 6),
            Text(rankFor(lvl), style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
            Text('Level $lvl · $xp XP total', style: tt.bodyMedium),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: (xp % 100) / 100, minHeight: 10, borderRadius: BorderRadius.circular(8)),
            const SizedBox(height: 4),
            Text('${100 - xp % 100} XP to ${rankFor(lvl + 1) == rankFor(lvl) ? 'level ${lvl + 1}' : rankFor(lvl + 1)}', style: tt.bodySmall),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 6, alignment: WrapAlignment.center, children: [
              StatChip(icon: Icons.emoji_events_outlined, label: '${earned.length}/${trophies.length} trophies'),
              StatChip(icon: Icons.local_fire_department, label: 'Growth streak ${Store.growthStreak}'),
              StatChip(icon: Icons.ac_unit, label: '${Store.freezes} streak freeze${Store.freezes == 1 ? '' : 's'}'),
              StatChip(icon: Icons.shield_outlined, label: '$bossesDefeated bosses defeated'),
            ]),
          ]),
        ),
        const SectionTitle('Theme'),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text('Pick a colour family, then switch between its day and night look.', style: tt.bodySmall),
        ),
        const AppCard(padding: EdgeInsets.zero, child: ThemePicker()),
        const SectionTitle('Ranks'),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(children: [
            for (var l = 1; l <= 10; l++)
              ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: l <= lvl ? cs.primary : cs.surfaceContainerHighest,
                  child: Text('$l', style: TextStyle(fontSize: 12, color: l <= lvl ? cs.onPrimary : cs.onSurfaceVariant, fontWeight: FontWeight.w800)),
                ),
                title: Text(rankFor(l), style: TextStyle(fontWeight: l == lvl ? FontWeight.w900 : FontWeight.w500)),
                trailing: l == lvl ? const Text('YOU', style: TextStyle(fontWeight: FontWeight.w900)) : Text('${(l - 1) * 100} XP', style: tt.bodySmall),
              ),
          ]),
        ),
        SectionTitle('Trophy case', trailing: Text('${earned.length}/${trophies.length}', style: tt.bodySmall)),
        LayoutBuilder(builder: (_, box) {
          final cols = box.maxWidth > 420 ? 4 : 3;
          final w = (box.maxWidth - (cols - 1) * 8) / cols;
          return Wrap(spacing: 8, runSpacing: 8, children: [
            for (final t in [...trophies.where((t) => earned.contains(t.id)), ...trophies.where((t) => !earned.contains(t.id))])
              SizedBox(width: w, child: _TrophyTile(t: t, earned: earned.contains(t.id))),
          ]);
        }),
      ]),
    );
  }
}

class _TrophyTile extends StatelessWidget {
  final Trophy t;
  final bool earned;
  const _TrophyTile({required this.t, required this.earned});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
      decoration: BoxDecoration(
        color: earned ? Colors.amber.withValues(alpha: 0.16) : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: earned ? Colors.amber : Colors.transparent, width: 1.5),
      ),
      child: Column(children: [
        Opacity(opacity: earned ? 1 : 0.3, child: Text(t.emoji, style: const TextStyle(fontSize: 30))),
        const SizedBox(height: 4),
        Text(t.title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
        const SizedBox(height: 2),
        Text(earned ? 'Unlocked' : t.how, textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
      ]),
    );
  }
}
