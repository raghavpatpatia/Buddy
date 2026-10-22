import 'dart:math';

import 'package:flutter/material.dart';

import 'ui.dart';

/// App-wide backdrop behind every page: night-blue gradient, faint hex grid, mana glow and drifting motes.
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
    c.drawRect(r, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF070C1C), SystemColors.void_, Color(0xFF05040F)]).createShader(r));
    // Mana glow from the top, shadow glow from the bottom left.
    c.drawCircle(Offset(s.width * 0.7, -s.height * 0.05), s.width * 0.9,
        Paint()..shader = RadialGradient(colors: [SystemColors.mana.withValues(alpha: 0.16), Colors.transparent]).createShader(Rect.fromCircle(center: Offset(s.width * 0.7, -s.height * 0.05), radius: s.width * 0.9)));
    c.drawCircle(Offset(-s.width * 0.1, s.height * 0.95), s.width * 0.8,
        Paint()..shader = RadialGradient(colors: [SystemColors.shadow.withValues(alpha: 0.14), Colors.transparent]).createShader(Rect.fromCircle(center: Offset(-s.width * 0.1, s.height * 0.95), radius: s.width * 0.8)));
    // Hex grid, fading toward the bottom.
    const hex = 26.0;
    final w = sqrt(3) * hex, rowH = hex * 1.5;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    for (var row = 0; row * rowH < s.height + hex; row++) {
      final y = row * rowH;
      final fade = (1 - y / s.height).clamp(0.0, 1.0);
      line.color = SystemColors.mana.withValues(alpha: 0.05 * fade + 0.01);
      for (var col = -1; col * w < s.width + w; col++) {
        final x = col * w + (row.isOdd ? w / 2 : 0);
        final p = Path();
        for (var k = 0; k < 6; k++) {
          final a = pi / 6 + k * pi / 3;
          final pt = Offset(x + hex * cos(a), y + hex * sin(a));
          k == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
        }
        c.drawPath(p..close(), line);
      }
    }
    // Motes of light, fixed seed so they don't jump between paints.
    final rnd = Random(7);
    for (var i = 0; i < 55; i++) {
      final o = Offset(rnd.nextDouble() * s.width, rnd.nextDouble() * s.height);
      final violet = rnd.nextDouble() < 0.3;
      final rad = 0.6 + rnd.nextDouble() * 1.6;
      final col = (violet ? SystemColors.shadow : SystemColors.manaBright).withValues(alpha: 0.25 + rnd.nextDouble() * 0.4);
      c.drawCircle(o, rad * 3, Paint()..color = col.withValues(alpha: 0.12)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
      c.drawCircle(o, rad, Paint()..color = col);
    }
  }

  @override
  bool shouldRepaint(_SkyPainter old) => false;
}

/// Glowing corner brackets that turn any card into a "System window".
class SystemFrame extends StatelessWidget {
  final Widget child;
  final Color color;
  const SystemFrame({super.key, required this.child, this.color = SystemColors.manaBright});

  @override
  Widget build(BuildContext context) => CustomPaint(foregroundPainter: _CornerPainter(color), child: child);
}

class _CornerPainter extends CustomPainter {
  final Color color;
  const _CornerPainter(this.color);

  @override
  void paint(Canvas c, Size s) {
    const len = 14.0, inset = 3.0;
    final path = Path();
    for (final (x, y, dx, dy) in [(inset, inset, 1.0, 1.0), (s.width - inset, inset, -1.0, 1.0), (inset, s.height - inset, 1.0, -1.0), (s.width - inset, s.height - inset, -1.0, -1.0)]) {
      path
        ..moveTo(x, y + dy * len)
        ..lineTo(x, y)
        ..lineTo(x + dx * len, y);
    }
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    c.drawPath(path, p..color = color.withValues(alpha: 0.35)..strokeWidth = 5..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    c.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = color);
  }

  @override
  bool shouldRepaint(_CornerPainter old) => old.color != color;
}
