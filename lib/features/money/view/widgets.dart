import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/format.dart';

export '../../../core/format.dart';

Color gainColor(BuildContext c, double v) {
  final dark = Theme.of(c).brightness == Brightness.dark;
  if (v == 0) return Theme.of(c).colorScheme.onSurfaceVariant;
  return v > 0 ? (dark ? const Color(0xFF5BD68A) : const Color(0xFF1B8A4B)) : (dark ? const Color(0xFFFF7B72) : const Color(0xFFC62828));
}

/// Rounded % change pill.
class ChangePill extends StatelessWidget {
  final double value;
  final String? text;
  const ChangePill(this.value, {super.key, this.text});
  @override
  Widget build(BuildContext context) {
    final c = gainColor(context, value);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(8)),
      child: Text(text ?? pct(value), style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12, fontFeatures: const [FontFeature.tabularFigures()])),
    );
  }
}

/// Tiny line chart for list rows.
class Sparkline extends StatelessWidget {
  final List<double> values;
  final Color color;
  final double width, height;
  const Sparkline(this.values, {super.key, required this.color, this.width = 64, this.height = 28});
  @override
  Widget build(BuildContext context) => SizedBox(width: width, height: height, child: CustomPaint(painter: _LinePainter(values, color, fill: false)));
}

class _LinePainter extends CustomPainter {
  final List<double> v;
  final Color color;
  final bool fill;
  final int? scrub;
  _LinePainter(this.v, this.color, {this.fill = true, this.scrub});

  Offset _pt(int i, Size s, double lo, double hi) =>
      Offset(v.length == 1 ? 0 : i * s.width / (v.length - 1), hi == lo ? s.height / 2 : s.height - (v[i] - lo) / (hi - lo) * s.height);

  @override
  void paint(Canvas canvas, Size s) {
    if (v.length < 2) return;
    final lo = v.reduce(min), hi = v.reduce(max);
    final path = Path()..moveTo(_pt(0, s, lo, hi).dx, _pt(0, s, lo, hi).dy);
    for (var i = 1; i < v.length; i++) {
      final p = _pt(i, s, lo, hi);
      path.lineTo(p.dx, p.dy);
    }
    if (fill) {
      final area = Path.from(path)
        ..lineTo(s.width, s.height)
        ..lineTo(0, s.height)
        ..close();
      canvas.drawPath(area, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0)]).createShader(Offset.zero & s));
    }
    canvas.drawPath(path, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = fill ? 2.2 : 1.6
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round);
    if (scrub != null) {
      final p = _pt(scrub!.clamp(0, v.length - 1), s, lo, hi);
      canvas.drawLine(Offset(p.dx, 0), Offset(p.dx, s.height), Paint()
        ..color = color.withValues(alpha: 0.4)
        ..strokeWidth = 1);
      canvas.drawCircle(p, 5, Paint()..color = color);
      canvas.drawCircle(p, 2.5, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_LinePainter o) => o.v != v || o.color != color || o.scrub != scrub;
}

/// Price chart; drag or long-press to read any day's value.
class PriceChart extends StatefulWidget {
  final List<double> values;
  final List<DateTime> times;
  final Color color;
  final void Function(int? index) onScrub;
  const PriceChart({super.key, required this.values, required this.times, required this.color, required this.onScrub});
  @override
  State<PriceChart> createState() => _PriceChartState();
}

class _PriceChartState extends State<PriceChart> {
  int? _i;
  void _at(Offset p, double w) {
    if (widget.values.length < 2) return;
    final i = (p.dx / w * (widget.values.length - 1)).round().clamp(0, widget.values.length - 1);
    if (i != _i) {
      HapticFeedback.selectionClick();
      setState(() => _i = i);
      widget.onScrub(i);
    }
  }

  void _end() {
    setState(() => _i = null);
    widget.onScrub(null);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (_, c) => GestureDetector(
          onHorizontalDragStart: (d) => _at(d.localPosition, c.maxWidth),
          onHorizontalDragUpdate: (d) => _at(d.localPosition, c.maxWidth),
          onHorizontalDragEnd: (_) => _end(),
          onLongPressStart: (d) => _at(d.localPosition, c.maxWidth),
          onLongPressMoveUpdate: (d) => _at(d.localPosition, c.maxWidth),
          onLongPressEnd: (_) => _end(),
          child: SizedBox(height: 190, width: c.maxWidth, child: CustomPaint(painter: _LinePainter(widget.values, widget.color, scrub: _i))),
        ),
      );
}

/// "✨ Buddy’s take" card: shows an AI answer, a loader, or the ask button.
class BuddyTakeCard extends StatelessWidget {
  final String? text;
  final bool loading;
  final VoidCallback onAsk;
  final String askLabel, footnote;
  final bool? answered;
  const BuddyTakeCard({super.key, required this.text, required this.loading, required this.onAsk, this.askLabel = 'Ask Buddy', this.footnote = '', this.answered});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Card(
      color: cs.secondaryContainer.withValues(alpha: 0.6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('✨', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Expanded(child: Text('Buddy’s take', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
            if (!loading) TextButton(onPressed: onAsk, child: Text((answered ?? text != null) ? 'Refresh' : askLabel)),
          ]),
          if (loading)
            const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: LinearProgressIndicator())
          else if (text != null)
            Padding(padding: const EdgeInsets.only(top: 4), child: SelectableText(text!, style: tt.bodyMedium?.copyWith(height: 1.4))),
          if (footnote.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(footnote, style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant))),
        ]),
      ),
    );
  }
}
