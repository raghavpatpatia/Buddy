import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/bot_face.dart';
import '../../../shared/ui.dart';
import '../controller/brain_settings_controller.dart';
import '../data/talk_settings.dart';
import '../data/wisdom.dart';
import '../model/chat_message.dart';

/// One chat bubble: text with copyable code blocks, the cited teaching and a read-aloud button.
class ChatBubble extends StatelessWidget {
  final ChatMessage msg;
  final VoidCallback? onSpeak;
  const ChatBubble({super.key, required this.msg, this.onSpeak});

  @override
  Widget build(BuildContext context) {
    final ref = msg.refs.map((id) => teachings.where((t) => t.id == id).firstOrNull).whereType<Teaching>().firstOrNull;
    final bubble = Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        gradient: msg.user ? LinearGradient(colors: [SystemColors.shadow.withValues(alpha: 0.85), SystemColors.mana.withValues(alpha: 0.85)]) : null,
        color: msg.user ? null : SystemColors.panel.withValues(alpha: 0.9),
        border: msg.user ? null : Border.all(color: SystemColors.mana.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(msg.user ? 20 : 6),
          bottomRight: Radius.circular(msg.user ? 6 : 20),
        ),
        boxShadow: [BoxShadow(color: (msg.user ? SystemColors.shadow : SystemColors.mana).withValues(alpha: 0.18), blurRadius: 12)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        if (msg.text.isEmpty && !msg.user)
          const TypingDots()
        else
          ..._rich(context, msg.text, msg.user ? Colors.white : SystemColors.text),
        if (!msg.user && msg.text.isNotEmpty && (ref != null || onSpeak != null))
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (ref != null)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => showModalBottomSheet(context: context, builder: (_) => VerseSheet(t: ref)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Text('📜 ${ref.src.split(',').first}', style: TextStyle(fontSize: 11, color: SystemColors.manaBright, fontWeight: FontWeight.w700)),
                ),
              ),
            if (onSpeak != null)
              IconButton(visualDensity: VisualDensity.compact, iconSize: 16, onPressed: onSpeak, icon: const Icon(Icons.volume_up_rounded), tooltip: 'Read aloud'),
          ]),
      ]),
    );
    return Align(
      alignment: msg.user ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.84), child: bubble),
    );
  }

  /// Plain text with ``` fenced code shown as copyable monospace blocks.
  List<Widget> _rich(BuildContext context, String text, Color color) {
    final parts = text.split('```');
    return [
      for (final (i, p) in parts.indexed)
        if (i.isOdd)
          CodeBlock(code: p.replaceFirst(RegExp(r'^[a-zA-Z#+]*\n'), '').trimRight())
        else if (p.trim().isNotEmpty)
          SelectableText.rich(TextSpan(children: markdownSpans(p.trim(), color)), style: TextStyle(color: color, fontSize: 15, height: 1.35)),
    ];
  }
}

final _inline = RegExp(r'\*\*(.+?)\*\*|`([^`]+)`');

/// Light markdown for chat replies: headings, bullet and numbered lists, **bold** and `code`.
List<InlineSpan> markdownSpans(String text, Color color) {
  final spans = <InlineSpan>[];
  final lines = text.split('\n');
  for (final (i, raw) in lines.indexed) {
    var line = raw.trimRight();
    var bold = false;
    final heading = RegExp(r'^#{1,6}\s+').firstMatch(line);
    if (heading != null) {
      line = line.substring(heading.end);
      bold = true;
    }
    final bullet = RegExp(r'^(\s*)[-*•]\s+').firstMatch(line);
    if (bullet != null) line = '${bullet.group(1)}•  ${line.substring(bullet.end)}';
    var last = 0;
    for (final m in _inline.allMatches(line)) {
      if (m.start > last) spans.add(TextSpan(text: line.substring(last, m.start), style: bold ? const TextStyle(fontWeight: FontWeight.w800) : null));
      spans.add(m.group(1) != null
          ? TextSpan(text: m.group(1), style: const TextStyle(fontWeight: FontWeight.w800))
          : TextSpan(text: m.group(2), style: TextStyle(fontFamily: 'monospace', backgroundColor: color.withValues(alpha: 0.12))));
      last = m.end;
    }
    if (last < line.length) spans.add(TextSpan(text: line.substring(last), style: bold ? const TextStyle(fontWeight: FontWeight.w800) : null));
    if (i < lines.length - 1) spans.add(const TextSpan(text: '\n'));
  }
  return spans;
}

/// Full verse, only when tapped.
class VerseSheet extends StatelessWidget {
  final Teaching t;
  const VerseSheet({super.key, required this.t});
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t.src, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        if (t.sa.isNotEmpty) ...[const SizedBox(height: 8), Text(t.sa, style: tt.bodyMedium?.copyWith(fontStyle: FontStyle.italic))],
        const SizedBox(height: 8),
        Text(t.mean, style: tt.bodyLarge),
      ]),
    );
  }
}

/// Buddy floating on a soft glowing ring that pulses while listening / thinking / talking.
class GlowBuddy extends StatefulWidget {
  final String? emotion;
  final bool talking, active;
  const GlowBuddy({super.key, required this.emotion, required this.talking, required this.active});
  @override
  State<GlowBuddy> createState() => GlowBuddyState();
}

class GlowBuddyState extends State<GlowBuddy> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 150,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, child) {
            final p = widget.active ? _c.value : 0.25;
            return Stack(alignment: Alignment.center, children: [
              Container(
                width: 120 + 24 * p,
                height: 120 + 24 * p,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [SystemColors.shadow.withValues(alpha: 0.3 + 0.25 * p), SystemColors.mana.withValues(alpha: 0.08), Colors.transparent]),
                ),
              ),
              child!,
            ]);
          },
          child: BotFace(mood: 0.5, emotion: widget.emotion, talking: widget.talking, size: 120),
        ),
      );
}

/// Slowly drifting colour blobs behind the chat.
class Aurora extends StatefulWidget {
  const Aurora({super.key});
  @override
  State<Aurora> createState() => AuroraState();
}

class AuroraState extends State<Aurora> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 14))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, _) {
          final t = _c.value * 2 * 3.14159;
          Alignment a(double ph, double r) => Alignment(r * cos(t + ph), r * sin(t * 0.8 + ph));
          final dark = Theme.of(context).brightness == Brightness.dark;
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [SystemColors.void_, SystemColors.panelHigh],
              ),
            ),
            child: Stack(children: [
              for (final (ph, col, r) in dark
                  ? [(0.0, SystemColors.mana, 0.7), (2.1, SystemColors.shadow, 0.8), (4.2, const Color(0xFF6D28D9), 0.6)]
                  : [(0.0, const Color(0xFF80DEEA), 0.7), (2.1, const Color(0xFFB39DDB), 0.8), (4.2, const Color(0xFFFFCC80), 0.6)])
                Align(
                  alignment: a(ph, r),
                  child: Container(
                    width: 260,
                    height: 260,
                    decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [col.withValues(alpha: dark ? 0.28 : 0.45), col.withValues(alpha: 0)])),
                  ),
                ),
            ]),
          );
        },
      );
}

/// Mic with expanding ripple rings while listening.
class MicButton extends StatefulWidget {
  final bool listening;
  final VoidCallback onTap;
  const MicButton({super.key, required this.listening, required this.onTap});
  @override
  State<MicButton> createState() => MicButtonState();
}

class MicButtonState extends State<MicButton> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = widget.listening ? SystemColors.shadow : cs.primary;
    return SizedBox.square(
      dimension: 50,
      child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
        if (widget.listening)
          AnimatedBuilder(
            animation: _c,
            builder: (_, _) => Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
              for (final d in [0.0, 0.5])
                Container(
                  width: 46 + 34 * ((_c.value + d) % 1),
                  height: 46 + 34 * ((_c.value + d) % 1),
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color.withValues(alpha: 1 - (_c.value + d) % 1), width: 2)),
                ),
            ]),
          ),
        IconButton.filled(
          onPressed: widget.onTap,
          style: IconButton.styleFrom(backgroundColor: color, minimumSize: const Size(46, 46)),
          icon: Icon(widget.listening ? Icons.stop_rounded : Icons.mic_rounded),
        ),
      ]),
    );
  }
}

/// Monospace code with a copy button.
class CodeBlock extends StatelessWidget {
  final String code;
  const CodeBlock({super.key, required this.code});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.fromLTRB(10, 4, 4, 10),
        decoration: BoxDecoration(color: SystemColors.panelHigh, borderRadius: BorderRadius.circular(8), border: Border.all(color: SystemColors.mana.withValues(alpha: 0.3))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              color: Colors.white70,
              tooltip: 'Copy',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copied')));
              },
              icon: const Icon(Icons.copy),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(code, style: TextStyle(fontFamily: 'monospace', color: SystemColors.text, fontSize: 12.5, height: 1.4)),
          ),
        ]),
      );
}

/// Three pulsing dots while Buddy is thinking.
class TypingDots extends StatefulWidget {
  const TypingDots({super.key});
  @override
  State<TypingDots> createState() => TypingDotsState();
}

class TypingDotsState extends State<TypingDots> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.all(3),
              child: Opacity(
                opacity: 0.3 + 0.7 * ((_c.value * 3 - i) % 3 < 1 ? 1 : 0),
                child: const CircleAvatar(radius: 4),
              ),
            ),
        ]),
      );
}

/// Shown until the main brain is downloaded, with a download button and progress.
class BrainBanner extends StatelessWidget {
  const BrainBanner({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: ModelDownloads.instance,
        builder: (context, _) {
          final d = ModelDownloads.instance;
          final m = TalkSettings.mainBrain;
          if (d.ready[m.id] != false) return const SizedBox();
          final v = d.progress[m.id];
          return Card(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(v == null ? 'Quick mode: answers from Buddy’s wisdom library' : 'Downloading Buddy’s brain… ${(v * 100).round()}%',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    if (v == null)
                      Text('Download his on-device AI (${m.sizeMb} MB, Wi-Fi) for real conversations. Private: nothing leaves your phone.',
                          style: Theme.of(context).textTheme.bodySmall)
                    else
                      LinearProgressIndicator(value: v, minHeight: 6, borderRadius: BorderRadius.circular(6)),
                  ]),
                ),
                if (v == null) TextButton(onPressed: () => d.start(m), child: const Text('Download')),
              ]),
            ),
          );
        },
      );
}
