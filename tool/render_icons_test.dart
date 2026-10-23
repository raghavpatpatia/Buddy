// Renders Buddy's launcher icon layers from the in-app helm art, in a day (Morning) and a night (Midnight)
// version; Android shows the night one when the phone is in dark mode.
// Run: flutter test tool/render_icons_test.dart && tool/install_icons.sh
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:buddy_app/core/game.dart';
import 'package:buddy_app/core/store.dart';
import 'package:buddy_app/shared/bot_face.dart';
import 'package:buddy_app/shared/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _size = 432.0; // adaptive layer at xxxhdpi (108 dp × 4)
const _safe = 0.62; // keep the helm inside the 66/108 dp safe zone

/// Helm outline with horns and the eye slits cut out, for the monochrome (themed) icon.
Path silhouette(Size s) {
  Offset p(double x, double y) => Offset(s.width * x, s.height * y);
  const right = [(0.5, 0.07), (0.57, 0.2), (0.76, 0.27), (0.81, 0.5), (0.72, 0.76), (0.5, 0.9)];
  final pts = [...right, for (final (x, y) in right.reversed.skip(1).take(right.length - 2)) (1 - x, y)];
  var helm = Path()..addPolygon([for (final (x, y) in pts) p(x, y)], true);
  for (final dx in [-1.0, 1.0]) {
    double x(double v) => 0.5 + dx * (v - 0.5);
    final horn = Path()
      ..moveTo(s.width * x(0.72), s.height * 0.27)
      ..quadraticBezierTo(s.width * x(0.9), s.height * 0.2, s.width * x(0.97), s.height * 0.03)
      ..quadraticBezierTo(s.width * x(0.88), s.height * 0.24, s.width * x(0.79), s.height * 0.36)
      ..close();
    helm = Path.combine(PathOperation.union, helm, horn);
  }
  final eyes = Path();
  for (final dx in [-1.0, 1.0]) {
    eyes.addPolygon([p(0.5 + dx * 0.06, 0.47), p(0.5 + dx * 0.23, 0.44), p(0.5 + dx * 0.23, 0.49), p(0.5 + dx * 0.06, 0.53)], true);
  }
  return Path.combine(PathOperation.difference, helm, eyes);
}

class _Sky extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final r = Offset.zero & s;
    c.drawRect(r, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [SystemColors.tint(0.10), SystemColors.void_, SystemColors.tint(0.16)]).createShader(r));
    c.drawCircle(r.center, s.width * 0.55, Paint()..shader = RadialGradient(colors: [SystemColors.mana.withValues(alpha: 0.35), SystemColors.shadow.withValues(alpha: 0.12), Colors.transparent]).createShader(Rect.fromCircle(center: r.center, radius: s.width * 0.55)));
    const hex = 30.0;
    final w = sqrt(3) * hex;
    final line = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.2..color = SystemColors.mana.withValues(alpha: 0.12);
    for (var row = 0; row * hex * 1.5 < s.height + hex; row++) {
      for (var col = -1; col * w < s.width + w; col++) {
        final cx = col * w + (row.isOdd ? w / 2 : 0), cy = row * hex * 1.5;
        c.drawPath(Path()..addPolygon([for (var k = 0; k < 6; k++) Offset(cx + hex * cos(pi / 6 + k * pi / 3), cy + hex * sin(pi / 6 + k * pi / 3))], true), line);
      }
    }
  }

  @override
  bool shouldRepaint(_Sky old) => false;
}

class _Helm extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final box = s.width * _safe;
    c.translate((s.width - box) / 2, (s.height - box) / 2 + s.height * 0.01);
    HelmPainter(mood: 0, glow: 0.18).paint(c, Size.square(box));
  }

  @override
  bool shouldRepaint(_Helm old) => false;
}

class _Mono extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final box = s.width * _safe;
    c.translate((s.width - box) / 2, (s.height - box) / 2);
    c.drawPath(silhouette(Size.square(box)), Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_Mono old) => false;
}

/// Old launchers: rounded tile with sky and helm.
class _Legacy extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final rr = RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(s.width * 0.22));
    c.clipRRect(rr);
    _Sky().paint(c, s);
    final box = s.width * 0.86;
    c.translate((s.width - box) / 2, (s.height - box) / 2);
    HelmPainter(mood: 0, glow: 0.18).paint(c, Size.square(box));
  }

  @override
  bool shouldRepaint(_Legacy old) => false;
}

Future<void> _render(CustomPainter painter, double size, String name) async {
  final rec = ui.PictureRecorder();
  painter.paint(Canvas(rec), Size.square(size));
  final img = await rec.endRecording().toImage(size.toInt(), size.toInt());
  final png = await img.toByteData(format: ui.ImageByteFormat.png);
  File('build/icons/$name.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(png!.buffer.asUint8List());
}

void main() {
  testWidgets('render launcher icon layers', (t) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await Store.init();
    for (final (mode, id) in [('day', 'auto'), ('night', 'midnight')]) {
      final t0 = botColors.firstWhere((c) => c.id == id);
      SystemColors.apply(light: t0.light, background: t0.background, card: t0.card, accent: t0.accent, bright: t0.bright, flare: t0.flare);
      await t.runAsync(() async {
        await _render(_Sky(), _size, '$mode/background');
        await _render(_Helm(), _size, '$mode/foreground');
        await _render(_Mono(), _size, '$mode/monochrome');
        await _render(_Legacy(), 192, '$mode/legacy');
        await _render(_Legacy(), 512, '$mode/playstore');
      });
    }
  });
}
