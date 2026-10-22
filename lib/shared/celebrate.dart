import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/game.dart';
import '../core/store.dart';
import 'ui.dart';

/// Listens to every XP gain app-wide: floating "+XP" toast, boss damage, level-ups and trophies.
class GameLayer extends StatefulWidget {
  final Widget child;
  final VoidCallback? onChanged;
  const GameLayer({super.key, required this.child, this.onChanged});
  @override
  State<GameLayer> createState() => _GameLayerState();
}

class _GameLayerState extends State<GameLayer> {
  final _queue = <Widget Function()>[];
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    Store.xpEvents.addListener(_onXp);
    // Trophies earned while the app was closed (e.g. a 7-day streak) are celebrated on open.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkTrophies());
  }

  @override
  void dispose() {
    Store.xpEvents.removeListener(_onXp);
    super.dispose();
  }

  Future<void> _onXp() async {
    final e = Store.xpEvents.value;
    if (e == null || !mounted) return;
    _toast('+${e.amount} XP');
    if (e.newLevel != null) {
      final unlocked = botColors.where((c) => c.unlockLevel == e.newLevel).toList();
      _enqueue(() => _CelebrationDialog(
            emoji: '⚔️',
            title: '[SYSTEM] Level up! Lv ${e.newLevel}',
            subtitle: 'You are now a ${rankFor(e.newLevel!)}.'
                '${unlocked.isEmpty ? '' : '\nUnlocked: ${unlocked.map((c) => '${c.name} eyes for Buddy').join(', ')} 🎨'}',
          ));
    }
    if (await damageBoss(e.amount)) {
      final b = currentBoss;
      _enqueue(() => _CelebrationDialog(emoji: b.emoji, title: '${b.name} defeated!', subtitle: 'Weekly boss down ⚔️ +100 XP'));
      unawaited(Store.addXp(100));
    }
    await _checkTrophies();
    widget.onChanged?.call();
  }

  Future<void> _checkTrophies() async {
    for (final t in await checkTrophies()) {
      _enqueue(() => _CelebrationDialog(emoji: t.emoji, title: 'Trophy unlocked: ${t.title}', subtitle: t.how));
    }
  }

  void _enqueue(Widget Function() dialog) {
    _queue.add(dialog);
    _drain();
  }

  Future<void> _drain() async {
    if (_showing || _queue.isEmpty || !mounted) return;
    _showing = true;
    HapticFeedback.heavyImpact();
    final d = _queue.removeAt(0);
    await showDialog(context: context, useRootNavigator: true, builder: (_) => d());
    _showing = false;
    _drain();
  }

  void _toast(String text) {
    final overlay = Overlay.of(context, rootOverlay: true);
    late OverlayEntry entry;
    entry = OverlayEntry(builder: (_) => _XpToast(text: text, onDone: () => entry.remove()));
    overlay.insert(entry);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _XpToast extends StatefulWidget {
  final String text;
  final VoidCallback onDone;
  const _XpToast({required this.text, required this.onDone});
  @override
  State<_XpToast> createState() => _XpToastState();
}

class _XpToastState extends State<_XpToast> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
    ..forward().whenComplete(widget.onDone);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, child) {
            final t = _c.value;
            final opacity = t < 0.15 ? t / 0.15 : (t > 0.75 ? (1 - t) / 0.25 : 1.0);
            return Opacity(
              opacity: opacity.clamp(0, 1),
              child: Transform.translate(offset: Offset(0, -24 * t), child: Transform.scale(scale: 0.9 + 0.1 * Curves.elasticOut.transform(min(1, t * 2)), child: child)),
            );
          },
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: SystemColors.panel.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: SystemColors.mana),
                  boxShadow: [BoxShadow(color: SystemColors.mana.withValues(alpha: 0.45), blurRadius: 14)],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.bolt, color: SystemColors.manaBright, size: 18),
                  const SizedBox(width: 4),
                  Text(widget.text, style: const TextStyle(fontFamily: hudFont, color: SystemColors.manaBright, fontWeight: FontWeight.w700, fontSize: 18, letterSpacing: 1)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CelebrationDialog extends StatelessWidget {
  final String emoji, title, subtitle;
  const _CelebrationDialog({required this.emoji, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Stack(alignment: Alignment.center, children: [
      const Positioned.fill(child: IgnorePointer(child: Confetti())),
      AlertDialog(
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.3, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: Curves.elasticOut,
            builder: (_, v, child) => Transform.scale(scale: v, child: child),
            child: Text(emoji, style: const TextStyle(fontSize: 64)),
          ),
          const SizedBox(height: 8),
          Text(title, textAlign: TextAlign.center, style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(subtitle, textAlign: TextAlign.center, style: tt.bodyLarge),
        ]),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Awesome!'))],
        actionsAlignment: MainAxisAlignment.center,
      ),
    ]);
  }
}

/// Lightweight confetti burst (no package needed).
class Confetti extends StatefulWidget {
  const Confetti({super.key});
  @override
  State<Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<Confetti> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..forward();
  final _rnd = Random();
  late final _parts = List.generate(90, (_) => (
        x: _rnd.nextDouble(),
        vx: (_rnd.nextDouble() - 0.5) * 0.6,
        vy: 0.6 + _rnd.nextDouble() * 0.9,
        spin: _rnd.nextDouble() * 12,
        color: [Colors.amber, Colors.pinkAccent, Colors.cyanAccent, Colors.lightGreenAccent, Colors.deepPurpleAccent, Colors.orangeAccent][_rnd.nextInt(6)],
      ));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, _) => CustomPaint(painter: _ConfettiPainter(_c.value, _parts)),
      );
}

class _ConfettiPainter extends CustomPainter {
  final double t;
  final List<({double x, double vx, double vy, double spin, Color color})> parts;
  _ConfettiPainter(this.t, this.parts);

  @override
  void paint(Canvas c, Size s) {
    for (final p in parts) {
      final x = (p.x + p.vx * t) * s.width;
      final y = (-0.1 + p.vy * t + 0.5 * t * t) * s.height;
      c.save();
      c.translate(x, y);
      c.rotate(p.spin * t);
      c.drawRect(const Rect.fromLTWH(-4, -2, 8, 4), Paint()..color = p.color.withValues(alpha: (1 - t).clamp(0, 1)));
      c.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter o) => o.t != t;
}
