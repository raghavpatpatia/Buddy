import 'dart:math';

import 'package:flutter/material.dart';

import '../core/game.dart';
import '../core/store.dart';

/// This week's boss: every XP you earn deals damage. Shakes when hit.
class BossCard extends StatefulWidget {
  const BossCard({super.key});
  @override
  State<BossCard> createState() => _BossCardState();
}

class _BossCardState extends State<BossCard> with SingleTickerProviderStateMixin {
  late final _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));

  @override
  void initState() {
    super.initState();
    Store.xpEvents.addListener(_hit);
  }

  @override
  void dispose() {
    Store.xpEvents.removeListener(_hit);
    _shake.dispose();
    super.dispose();
  }

  void _hit() {
    if (!mounted) return;
    // HP is updated by the game layer right after the event; repaint a moment later.
    Future.delayed(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      setState(() {});
      _shake.forward(from: 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final b = currentBoss;
    final hp = bossHp;
    final dead = hp <= 0;
    final frac = hp / bossMaxHp;
    final daysLeft = 7 - DateTime.now().weekday;
    return Card(
      color: dead ? Colors.green.withValues(alpha: 0.12) : const Color(0xFFB71C1C).withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          AnimatedBuilder(
            animation: _shake,
            builder: (_, child) => Transform.translate(offset: Offset(sin(_shake.value * pi * 6) * 6 * (1 - _shake.value), 0), child: child),
            child: Opacity(opacity: dead ? 0.35 : 1, child: Text(b.emoji, style: const TextStyle(fontSize: 40))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(dead ? '${b.name} defeated ⚔️' : 'Weekly boss: ${b.name}', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900))),
              ]),
              Text(dead ? 'New boss arrives Monday. +100 XP earned.' : '${b.taunt} · every XP you earn hits it', style: tt.bodySmall),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: frac),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, _) => LinearProgressIndicator(
                    value: v,
                    minHeight: 12,
                    color: v > 0.5 ? Colors.redAccent : v > 0.2 ? Colors.orange : Colors.amber,
                    backgroundColor: cs.surfaceContainerHighest,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(dead ? 'Bosses defeated: $bossesDefeated' : 'HP $hp / $bossMaxHp · ${daysLeft == 0 ? 'last day!' : '$daysLeft days left'}',
                  style: tt.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
      ),
    );
  }
}
