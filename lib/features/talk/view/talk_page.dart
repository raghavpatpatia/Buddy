import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/talk_controller.dart';
import 'brain_sheet.dart';
import 'talk_widgets.dart';

/// Chat with Buddy by text or voice; replies stream in and can be read aloud.
class TalkPage extends StatefulWidget {
  final TalkController? controller;
  const TalkPage({super.key, this.controller});
  @override
  State<TalkPage> createState() => _TalkPageState();
}

class _TalkPageState extends State<TalkPage> {
  late final c = widget.controller ?? TalkController();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  int _shown = 0;

  @override
  void initState() {
    super.initState();
    c.onTranscript = (words) => _input.text = words;
    c.addListener(_onChange);
    c.init();
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    if (widget.controller == null) c.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChange() {
    final len = c.messages.fold(0, (a, m) => a + m.text.length + 1);
    if (len != _shown) {
      _shown = len;
      _scrollDown();
    }
  }

  void _scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      });

  Future<void> _send([String? preset]) async {
    final text = preset ?? _input.text;
    if (text.trim().isEmpty || c.thinking) return;
    HapticFeedback.lightImpact();
    _input.clear();
    await c.send(text);
  }

  Future<void> _toggleMic() async {
    HapticFeedback.selectionClick();
    final wasListening = c.listening;
    final ok = await c.toggleMic(_input.text);
    if (wasListening) _input.clear();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Voice input isn’t available. Check that Google voice typing is installed.')));
    }
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Clear the conversation?'),
        content: const Text('Buddy will stop answering and the whole chat will be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    HapticFeedback.mediumImpact();
    _input.clear();
    await c.clear();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: c, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final status = c.status;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Buddy'),
        actions: [
          IconButton(
            tooltip: c.speakReplies ? 'Voice replies on' : 'Voice replies off',
            onPressed: c.toggleSpeakReplies,
            icon: Icon(c.speakReplies ? Icons.volume_up_rounded : Icons.volume_off_rounded),
          ),
          IconButton(tooltip: 'Clear chat', onPressed: _clear, icon: const Icon(Icons.delete_sweep_outlined)),
          IconButton(
            tooltip: 'Buddy’s brain',
            onPressed: () => showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => const BrainSheet()).then((_) => setState(() {})),
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: Stack(children: [
        const Positioned.fill(child: Aurora()),
        SafeArea(
          child: Column(children: [
            GlowBuddy(emotion: c.emotion, talking: c.speaking || (c.thinking && status.isEmpty), active: c.busy),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: status.isEmpty
                  ? const SizedBox(height: 26)
                  : Container(
                      key: ValueKey(status),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(color: cs.surfaceContainerHigh.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(20)),
                      child: Text(status, style: tt.labelMedium?.copyWith(color: cs.primary, fontWeight: FontWeight.w800)),
                    ),
            ),
            const BrainBanner(),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                itemCount: c.messages.length + 1,
                itemBuilder: (_, i) {
                  if (i == c.messages.length) return _suggestions();
                  final m = c.messages[i];
                  return ChatBubble(msg: m, onSpeak: m.user ? null : () => c.speak(m.text));
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: cs.surface.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 4))],
                ),
                child: Row(children: [
                  MicButton(listening: c.listening, onTap: _toggleMic),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: c.listening ? 'Listening…' : 'Message Buddy',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                      ),
                    ),
                  ),
                  IconButton.filled(
                    onPressed: c.thinking ? null : _send,
                    icon: const Icon(Icons.arrow_upward_rounded),
                    style: IconButton.styleFrom(minimumSize: const Size(46, 46)),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _suggestions() {
    if (c.thinking || c.messages.length > 1) return const SizedBox();
    const s = ['😮‍💨 I feel stressed', '💰 How do I save money?', '🐞 Help me debug'];
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (final x in s)
          ActionChip(
            label: Text(x),
            shape: const StadiumBorder(),
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh.withValues(alpha: 0.9),
            onPressed: () => _send(x.substring(x.indexOf(' ') + 1)),
          ),
      ]),
    );
  }
}
