
import 'package:flutter/material.dart';

import 'ui.dart';

/// App-wide backdrop behind every page: the theme's background with a faint wash of its accent at the top.
/// Painted once (static) so it costs nothing per frame.
class SystemBackground extends StatelessWidget {
  final Widget child;
  const SystemBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Stack(children: [
        const Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: _SkyPainter()))),
        child,
      ]);
}

class _SkyPainter extends CustomPainter {
  const _SkyPainter();

  @override
  void paint(Canvas c, Size s) {
    final r = Offset.zero & s;
    c.drawRect(
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [SystemColors.tint(SystemColors.light ? 0.06 : 0.08), SystemColors.void_, SystemColors.void_],
          stops: const [0, 0.45, 1],
        ).createShader(r),
    );
  }

  @override
  bool shouldRepaint(_SkyPainter old) => false;
}

/// Wraps a card's content. Kept as the one place to decorate cards; the calm themes use plain rounded cards.
class SystemFrame extends StatelessWidget {
  final Widget child;
  final Color? color;
  const SystemFrame({super.key, required this.child, this.color});

  @override
  Widget build(BuildContext context) => child;
}
