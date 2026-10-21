import 'dart:math';

import 'package:flutter/material.dart';

import '../core/game.dart';

/// Animated robot face. mood: -1 (sad) .. 1 (happy). Blinks, looks around, talks.
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
              painter: _FacePainter(
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

/// Realistic robot head: gunmetal shell with panel seams, glass visor with glowing LED eyes,
/// side sensor modules and an LED mouth grille that animates while talking.
class _FacePainter extends CustomPainter {
  final double mood, blink, lookX, lookY, talk, glow;
  final String? emotion;
  _FacePainter({required this.mood, this.emotion, required this.blink, required this.lookX, required this.lookY, required this.talk, required this.glow});

  /// LED colour by mood: amber when worried, cyan when content, mint when happy.
  Color get _led {
    // Unlockable colours (Trophies screen) override the mood colour; mood still shows in eye/mouth shapes.
    final pick = selectedBotColor;
    if (pick.id == 'rainbow') return HSVColor.fromAHSV(1, (glow * 360 * 2) % 360, 0.65, 1).toColor();
    if (pick.color != null) return pick.color!;
    if (mood < -0.3) return const Color(0xFFFFB020);
    if (mood < 0.2) return const Color(0xFF4FC3F7);
    return Color.lerp(const Color(0xFF22D3EE), const Color(0xFF34F5C5), ((mood - 0.2) / 0.8).clamp(0, 1))!;
  }

  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    final led = _led;

    // Antenna sensor with status light
    final stem = Paint()..color = const Color(0xFF5B6675);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(w * 0.5, h * 0.11), width: w * 0.035, height: h * 0.09), Radius.circular(w * 0.02)), stem);
    final pulse = 0.55 + 0.45 * sin(glow * 2 * pi * 2);
    c.drawCircle(Offset(w * 0.5, h * 0.06), w * 0.045, Paint()..color = const Color(0xFF2A313B));
    c.drawCircle(Offset(w * 0.5, h * 0.06), w * 0.06, Paint()..color = led.withValues(alpha: 0.35 * pulse)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    c.drawCircle(Offset(w * 0.5, h * 0.06), w * 0.022, Paint()..color = led.withValues(alpha: 0.6 + 0.4 * pulse));

    // Side sensor modules ("ears")
    for (final dx in [-1.0, 1.0]) {
      final cx = w * 0.5 + dx * w * 0.445;
      final ear = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, h * 0.5), width: w * 0.09, height: h * 0.3), Radius.circular(w * 0.04));
      c.drawRRect(ear, Paint()..shader = const LinearGradient(colors: [Color(0xFF1F252E), Color(0xFF4A5462), Color(0xFF1F252E)]).createShader(ear.outerRect));
      c.drawCircle(Offset(cx, h * 0.5), w * 0.018, Paint()..color = led.withValues(alpha: 0.8));
    }

    // Head shell (gunmetal with soft shadow, rim light and top specular)
    final head = RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.1, h * 0.15, w * 0.8, h * 0.72), Radius.circular(w * 0.2));
    c.drawRRect(head.shift(Offset(0, h * 0.03)), Paint()..color = Colors.black.withValues(alpha: 0.3)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    c.drawRRect(
      head,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6B7684), Color(0xFF3A4350), Color(0xFF1E242C)],
          stops: [0, 0.45, 1],
        ).createShader(head.outerRect),
    );
    c.drawRRect(head.deflate(1.5), Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = Colors.white.withValues(alpha: 0.18));
    final spec = Rect.fromLTWH(w * 0.2, h * 0.17, w * 0.5, h * 0.12);
    c.drawOval(spec, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white.withValues(alpha: 0.32), Colors.white.withValues(alpha: 0)]).createShader(spec));
    // Panel seams + rivets
    final seam = Paint()..color = Colors.black.withValues(alpha: 0.35)..strokeWidth = 1.4;
    c.drawLine(Offset(w * 0.5, h * 0.16), Offset(w * 0.5, h * 0.3), seam);
    c.drawLine(Offset(w * 0.14, h * 0.72), Offset(w * 0.86, h * 0.72), seam);
    for (final x in [0.17, 0.83]) {
      for (final y in [0.25, 0.78]) {
        c.drawCircle(Offset(w * x, h * y), w * 0.012, Paint()..color = Colors.black.withValues(alpha: 0.35));
        c.drawCircle(Offset(w * x - 0.6, h * y - 0.6), w * 0.006, Paint()..color = Colors.white.withValues(alpha: 0.25));
      }
    }

    // Glass visor
    final visor = RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.17, h * 0.33, w * 0.66, h * 0.27), Radius.circular(w * 0.1));
    c.drawRRect(visor, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF05070A), Color(0xFF111821)]).createShader(visor.outerRect));
    c.drawRRect(visor, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = const Color(0xFF0B0E12));

    // LED eyes
    final eyeY = h * 0.465 + lookY * h * 0.02;
    // calm = relaxed half-open eyes; listening = wide open
    final open = (1 - blink * 0.92) * (emotion == 'calm' ? 0.55 : emotion == 'listening' ? 1.2 : 1.0);
    for (final dx in [-1.0, 1.0]) {
      final cx = w * 0.5 + dx * w * 0.15 + lookX * w * 0.025;
      final glowPaint = Paint()..color = led.withValues(alpha: 0.45)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      final core = Paint()..color = led;
      if (mood > 0.45 && blink < 0.5) {
        // Happy: upturned arc eyes
        final arc = Rect.fromCenter(center: Offset(cx, eyeY + h * 0.02), width: w * 0.13, height: h * 0.09);
        final stroke = Paint()..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeWidth = w * 0.03;
        c.drawArc(arc, pi * 1.1, pi * 0.8, false, stroke..color = led.withValues(alpha: 0.45)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
        c.drawArc(arc, pi * 1.1, pi * 0.8, false, Paint()..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeWidth = w * 0.026..color = led);
      } else {
        // curious: one eye a little bigger, like a raised eyebrow
        final scale = emotion == 'curious' && dx > 0 ? 1.25 : 1.0;
        final eye = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx, eyeY), width: w * 0.12 * scale, height: max(2, h * 0.1 * open * scale)),
          Radius.circular(w * 0.04),
        );
        c.drawRRect(eye.inflate(3), glowPaint);
        c.drawRRect(eye, core);
        // Worried/sad: dark lid slanting down toward the outside
        if (mood < -0.2 && blink < 0.5) {
          final lid = Path()
            ..moveTo(cx - w * 0.08, eyeY - h * 0.07)
            ..lineTo(cx + w * 0.08, eyeY - h * 0.07)
            ..lineTo(cx + dx * w * 0.08, eyeY - h * 0.01)
            ..close();
          c.drawPath(lid, Paint()..color = const Color(0xFF080B0F));
        }
        // Scan-line texture
        for (var y = eye.top + 2; y < eye.bottom; y += 3) {
          c.drawLine(Offset(eye.left, y), Offset(eye.right, y), Paint()..color = Colors.black.withValues(alpha: 0.18)..strokeWidth = 1);
        }
      }
    }
    // Visor reflection streak
    final refl = Path()
      ..moveTo(w * 0.22, h * 0.35)
      ..lineTo(w * 0.36, h * 0.35)
      ..lineTo(w * 0.27, h * 0.58)
      ..lineTo(w * 0.2, h * 0.58)
      ..close();
    c.drawPath(refl, Paint()..color = Colors.white.withValues(alpha: 0.06));

    // LED mouth grille: dots on a curve set by mood; equalizer bars while talking
    const n = 9;
    final mouthY = h * 0.67;
    for (var i = 0; i < n; i++) {
      final f = i / (n - 1) * 2 - 1; // -1..1
      final x = w * 0.5 + f * w * 0.2;
      final curve = -mood * (1 - f * f) * h * 0.035; // smile: centre lower
      final lit = talk > 0.05 || (f.abs() <= 0.8);
      final barH = talk > 0.05 ? h * (0.012 + 0.05 * talk * (0.5 + 0.5 * sin(glow * 2 * pi * 9 + i * 1.7)).abs()) : h * 0.012;
      final r = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x, mouthY - curve), width: w * 0.028, height: barH * 2), Radius.circular(w * 0.014));
      c.drawRRect(r.inflate(2), Paint()..color = led.withValues(alpha: lit ? 0.3 : 0.08)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
      c.drawRRect(r, Paint()..color = lit ? led.withValues(alpha: 0.9) : const Color(0xFF2A313B));
    }
  }

  @override
  bool shouldRepaint(_FacePainter o) => true;
}
