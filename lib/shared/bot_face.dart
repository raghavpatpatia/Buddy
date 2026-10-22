import 'dart:math';

import 'package:flutter/material.dart';

import '../core/game.dart';
import 'ui.dart';

/// Buddy's avatar: a shadow-knight helm with glowing eyes and a living aura. mood: -1 (sad) .. 1 (happy).
/// Blinks, looks around, talks.
class BotFace extends StatefulWidget {
  final double mood;

  /// Optional expression on top of mood: listening, thinking, curious, calm, concerned, happy.
  final String? emotion;
  final bool talking;
  final double size;
  final VoidCallback? onTap;
  const BotFace({super.key, required this.mood, this.emotion, this.talking = false, this.size = 200, this.onTap});

  @override
  State<BotFace> createState() => _BotFaceState();
}

class _BotFaceState extends State<BotFace> with TickerProviderStateMixin {
  late final AnimationController _life = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  late final AnimationController _bounce = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
  final _rnd = Random();
  double _lookX = 0, _lookY = 0;

  @override
  void initState() {
    super.initState();
    _life.addListener(() {
      // Occasionally glance somewhere new.
      if (_rnd.nextDouble() < 0.006) {
        _lookX = _rnd.nextDouble() * 2 - 1;
        _lookY = _rnd.nextDouble() * 1.2 - 0.6;
      }
    });
  }

  @override
  void dispose() {
    _life.dispose();
    _bounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        _bounce.forward(from: 0);
        widget.onTap?.call();
      },
      child: AnimatedBuilder(
        animation: Listenable.merge([_life, _bounce]),
        builder: (_, _) {
          final t = _life.value;
          // Blink twice per cycle, quickly.
          double blink = 0;
          for (final c in [0.3, 0.85]) {
            final d = (t - c).abs();
            if (d < 0.02) blink = 1 - d / 0.02;
          }
          final hop = sin(_bounce.value * pi) * 18;
          final float = sin(t * 2 * pi) * 4;
          final talk = widget.talking ? (sin(t * 2 * pi * 18).abs()) : 0.0;
          return Transform.translate(
            offset: Offset(0, -hop + float),
            child: CustomPaint(
              size: Size.square(widget.size),
              painter: HelmPainter(
                mood: switch (widget.emotion) {
                  'happy' => 0.9,
                  'concerned' => -0.5,
                  'calm' => 0.3,
                  _ => widget.mood,
                },
                emotion: widget.emotion,
                blink: blink,
                // Thinking: eyes drift up and to the side; listening: look straight at you.
                lookX: widget.emotion == 'thinking' ? 0.9 : widget.emotion == 'listening' ? 0 : _lookX,
                lookY: widget.emotion == 'thinking' ? -1.2 : widget.emotion == 'listening' ? 0 : _lookY,
                talk: talk,
                glow: t,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Shadow-knight helm: crested dark armour with swept horns, a V visor with glowing slit eyes,
/// a forehead gem, cheek runes, a vent grille that lights up while talking, and rising shadow flames.
/// Public so `tool/render_icons_test.dart` can draw the app icon from the same art.
class HelmPainter extends CustomPainter {
  final double mood, blink, lookX, lookY, talk, glow;
  final String? emotion;
  HelmPainter({required this.mood, this.emotion, this.blink = 0, this.lookX = 0, this.lookY = 0, this.talk = 0, this.glow = 0});

  /// Eye colour: mana blue by default, brighter when happy, shadow violet when worried; unlockable colours override.
  Color get _led {
    final pick = selectedBotColor;
    if (pick.id == 'rainbow') return HSVColor.fromAHSV(1, (glow * 360 * 2) % 360, 0.65, 1).toColor();
    if (pick.color != null) return pick.color!;
    if (mood < -0.3) return SystemColors.shadow;
    if (mood < 0.2) return SystemColors.mana;
    return Color.lerp(SystemColors.mana, SystemColors.manaBright, ((mood - 0.2) / 0.8).clamp(0, 1))!;
  }

  Offset _p(Size s, double x, double y) => Offset(s.width * x, s.height * y);

  /// The helm outline (crest, temples, cheek guards, jaw), symmetric around the centre.
  Path _helm(Size s) {
    const right = [(0.5, 0.07), (0.57, 0.2), (0.76, 0.27), (0.81, 0.5), (0.72, 0.76), (0.5, 0.9)];
    final pts = [...right, for (final (x, y) in right.reversed.skip(1).take(right.length - 2)) (1 - x, y)];
    final path = Path()..moveTo(s.width * pts.first.$1, s.height * pts.first.$2);
    for (final (x, y) in pts.skip(1)) {
      path.lineTo(s.width * x, s.height * y);
    }
    return path..close();
  }

  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    final led = _led;
    final t = glow * 2 * pi;

    // Shadow aura: thin flame tongues licking upward behind the helm, fading at the tips.
    for (var i = 0; i < 11; i++) {
      final f = i / 10 * 2 - 1;
      final sway = sin(t * 3 + i * 1.7) * w * 0.035;
      final height = 0.38 + 0.18 * (0.5 + 0.5 * sin(t * 2.3 + i * 2.1)) + (1 - f.abs()) * 0.3;
      final baseX = 0.5 + f * 0.4;
      final baseY = 0.74 - (1 - f.abs()) * 0.1;
      final half = 0.035 + 0.02 * (1 - f.abs());
      final tip = Offset(w * (baseX + f * 0.06) + sway, h * (baseY - height));
      final mid = h * (baseY - height * 0.55);
      final flame = Path()
        ..moveTo(w * (baseX - half), h * baseY)
        ..cubicTo(w * (baseX - half * 1.2), mid, tip.dx - sway * 0.6 - w * 0.01, tip.dy + h * 0.08, tip.dx, tip.dy)
        ..cubicTo(tip.dx + w * 0.012, tip.dy + h * 0.1, w * (baseX + half * 1.1) + sway * 0.4, mid, w * (baseX + half), h * baseY)
        ..close();
      final col = i.isEven ? SystemColors.shadow : led;
      final bounds = Rect.fromLTRB(0, tip.dy, w, h * baseY);
      c.drawPath(
        flame,
        Paint()
          ..shader = LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [col.withValues(alpha: 0.55), col.withValues(alpha: 0.18), col.withValues(alpha: 0)], stops: const [0, 0.6, 1]).createShader(bounds)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.012),
      );
    }
    c.drawCircle(_p(s, 0.5, 0.48), w * 0.42, Paint()..shader = RadialGradient(colors: [led.withValues(alpha: 0.22), Colors.transparent]).createShader(Rect.fromCircle(center: _p(s, 0.5, 0.48), radius: w * 0.42)));

    // Swept-back horns.
    for (final dx in [-1.0, 1.0]) {
      double x(double v) => 0.5 + dx * (v - 0.5);
      final horn = Path()
        ..moveTo(w * x(0.72), h * 0.27)
        ..quadraticBezierTo(w * x(0.9), h * 0.2, w * x(0.97), h * 0.03)
        ..quadraticBezierTo(w * x(0.88), h * 0.24, w * x(0.79), h * 0.36)
        ..close();
      c.drawPath(horn, Paint()..shader = LinearGradient(colors: const [Color(0xFF3D4A7A), Color(0xFF0B0E1C)], begin: Alignment(dx, -1), end: Alignment(-dx, 1)).createShader(Rect.fromLTWH(0, 0, w, h * 0.4)));
      c.drawPath(horn, Paint()..style = PaintingStyle.stroke..strokeWidth = w * 0.014..color = led.withValues(alpha: 0.3)..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.012));
      c.drawPath(horn, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.4..color = led.withValues(alpha: 0.85));
    }

    // Helm body: dark metal with a mana rim light.
    final helm = _helm(s);
    c.drawPath(helm.shift(Offset(0, h * 0.025)), Paint()..color = Colors.black.withValues(alpha: 0.55)..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.03));
    c.drawPath(helm, Paint()..shader = const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF323C63), Color(0xFF10142A), Color(0xFF040509)], stops: [0, 0.5, 1]).createShader(Offset.zero & s));
    c.drawPath(helm, Paint()..style = PaintingStyle.stroke..strokeWidth = w * 0.022..color = led.withValues(alpha: 0.35)..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.02));
    c.drawPath(helm, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.6..color = led.withValues(alpha: 0.85));

    // Centre ridge and plate seams.
    final seam = Paint()..strokeWidth = 1.2..color = Colors.white.withValues(alpha: 0.12);
    c.drawLine(_p(s, 0.5, 0.09), _p(s, 0.5, 0.4), seam);
    c.drawLine(_p(s, 0.28, 0.3), _p(s, 0.36, 0.42), seam);
    c.drawLine(_p(s, 0.72, 0.3), _p(s, 0.64, 0.42), seam);
    c.drawLine(_p(s, 0.31, 0.7), _p(s, 0.5, 0.8), seam);
    c.drawLine(_p(s, 0.69, 0.7), _p(s, 0.5, 0.8), seam);

    // Forehead gem, pulsing.
    final pulse = 0.55 + 0.45 * sin(t * 2);
    final gem = Path()
      ..moveTo(w * 0.5, h * 0.27)
      ..lineTo(w * 0.535, h * 0.32)
      ..lineTo(w * 0.5, h * 0.37)
      ..lineTo(w * 0.465, h * 0.32)
      ..close();
    c.drawPath(gem, Paint()..color = SystemColors.shadow.withValues(alpha: 0.5 * pulse)..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.03));
    c.drawPath(gem, Paint()..color = Color.lerp(SystemColors.shadow, Colors.white, 0.25 * pulse)!);

    // V-shaped visor.
    final visor = Path()
      ..moveTo(w * 0.22, h * 0.43)
      ..lineTo(w * 0.5, h * 0.47)
      ..lineTo(w * 0.78, h * 0.43)
      ..lineTo(w * 0.74, h * 0.53)
      ..lineTo(w * 0.5, h * 0.58)
      ..lineTo(w * 0.26, h * 0.53)
      ..close();
    c.drawPath(visor, Paint()..color = const Color(0xFF010205));
    c.drawPath(visor, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = led.withValues(alpha: 0.25));

    // Eyes: slanted glowing slits that follow the gaze; shape follows the emotion.
    final open = (1 - blink * 0.95) * (emotion == 'calm' ? 0.6 : emotion == 'listening' ? 1.35 : 1.0);
    final gx = lookX * w * 0.02, gy = lookY * h * 0.012;
    for (final dx in [-1.0, 1.0]) {
      final scale = emotion == 'curious' && dx > 0 ? 1.25 : 1.0;
      final inner = Offset(w * (0.5 + dx * 0.07) + gx, h * 0.5 + gy);
      final outer = Offset(w * (0.5 + dx * 0.21) + gx, h * (mood < -0.2 ? 0.515 : 0.475) + gy);
      final thick = h * 0.045 * open * scale;
      final eye = Path();
      if (mood > 0.45 && blink < 0.5) {
        // Happy: eyes curve up into crescents.
        eye
          ..moveTo(inner.dx, inner.dy)
          ..quadraticBezierTo((inner.dx + outer.dx) / 2, inner.dy - h * 0.05, outer.dx, outer.dy)
          ..quadraticBezierTo((inner.dx + outer.dx) / 2, inner.dy - h * 0.02, inner.dx, inner.dy)
          ..close();
      } else {
        eye
          ..moveTo(inner.dx, inner.dy - thick * 0.5)
          ..lineTo(outer.dx, outer.dy - thick * 0.25)
          ..lineTo(outer.dx, outer.dy + thick * 0.15)
          ..lineTo(inner.dx, inner.dy + thick * 0.5)
          ..close();
      }
      c.drawPath(eye, Paint()..color = led.withValues(alpha: 0.75)..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.035));
      c.drawPath(eye, Paint()..color = led);
      c.drawPath(eye, Paint()..style = PaintingStyle.stroke..strokeWidth = max(0.8, w * 0.004)..color = Colors.white.withValues(alpha: 0.75));
      // Lens flare streak from each eye.
      final flare = Paint()..color = led.withValues(alpha: 0.35 * (1 - blink))..strokeWidth = 1.2..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
      c.drawLine(outer.translate(-dx * w * 0.02, 0), outer.translate(dx * w * 0.09, -h * 0.01), flare);
    }

    // Cheek runes.
    for (final dx in [-1.0, 1.0]) {
      final rune = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.4..color = led.withValues(alpha: 0.35 + 0.3 * pulse);
      final a = _p(s, 0.5 + dx * 0.24, 0.58), b = _p(s, 0.5 + dx * 0.21, 0.65), d = _p(s, 0.5 + dx * 0.24, 0.7);
      c.drawPath(Path()..moveTo(a.dx, a.dy)..lineTo(b.dx, b.dy)..lineTo(d.dx, d.dy), rune);
    }

    // Vent grille: dim at rest, an equaliser while talking; curves slightly with mood.
    for (var i = 0; i < 5; i++) {
      final y = h * (0.64 + i * 0.03);
      final narrow = 1 - i * 0.16;
      final level = talk > 0.05 ? (0.35 + 0.65 * (0.5 + 0.5 * sin(t * 18 + i * 1.9)).abs() * talk) : 0.25;
      final half = w * 0.09 * narrow * (talk > 0.05 ? (0.6 + 0.4 * level) : 1);
      final bend = -mood * h * 0.008 * (1 - i / 5);
      final a = Offset(w * 0.5 - half, y + bend), b = Offset(w * 0.5 + half, y + bend);
      c.drawLine(a, b, Paint()..strokeWidth = h * 0.012..strokeCap = StrokeCap.round..color = led.withValues(alpha: level * 0.6)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
      c.drawLine(a, b, Paint()..strokeWidth = h * 0.007..strokeCap = StrokeCap.round..color = led.withValues(alpha: level));
    }

    // Mana motes drifting up around the helm.
    for (var i = 0; i < 10; i++) {
      final phase = (glow * (0.6 + i * 0.07) + i * 0.13) % 1;
      final x = 0.12 + (i * 0.37 % 0.76) + sin(t + i) * 0.02;
      final o = _p(s, x, 0.92 - phase * 0.8);
      final a = sin(phase * pi);
      c.drawCircle(o, w * 0.008, Paint()..color = (i.isEven ? led : SystemColors.shadow).withValues(alpha: 0.7 * a));
    }
  }

  @override
  bool shouldRepaint(HelmPainter o) => true;
}
