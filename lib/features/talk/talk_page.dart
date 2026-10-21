import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/store.dart';
import '../bot_face.dart';
import '../ui.dart';
import 'brain.dart';
import 'cloud_brain.dart';
import 'robot_voice.dart';
import 'wisdom.dart';

/// Downloads survive leaving the Talk screen.
class BrainDownloads {
  static final progress = <String, ValueNotifier<double?>>{for (final m in [fastBrain, smartBrain, codeBrain]) m.id: ValueNotifier(null)};
  static final errors = <String, ValueNotifier<String?>>{for (final m in [fastBrain, smartBrain, codeBrain]) m.id: ValueNotifier(null)};

  static Future<void> start(BrainModel m) async {
    if (progress[m.id]!.value != null) return;
    progress[m.id]!.value = 0;
    errors[m.id]!.value = null;
    try {
      await Brain.instance.download(m, (p) => progress[m.id]!.value = p);
    } catch (e) {
      errors[m.id]!.value = 'Download paused (${e is TimeoutException ? 'timeout' : 'network'}). Tap to resume.';
    } finally {
      progress[m.id]!.value = null;
    }
  }
}

class _Msg {
  final bool user;
  String text;
  final List<String> refs; // teaching ids shown as verse cards
  _Msg(this.user, this.text, [this.refs = const []]);
  Map<String, dynamic> toJson() => {'u': user, 't': text, 'r': refs};
  static _Msg fromJson(Map m) => _Msg(m['u'] == true, m['t'] ?? '', List<String>.from(m['r'] ?? []));
}

class TalkPage extends StatefulWidget {
  const TalkPage({super.key});
  @override
  State<TalkPage> createState() => _TalkPageState();
}

class _TalkPageState extends State<TalkPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _stt = SpeechToText();
  final _tts = FlutterTts();
  late final _voice = RobotVoice(_tts)
    ..onStart = (() => mounted ? setState(() => _speaking = true) : null)
    ..onDone = (() => mounted ? setState(() => _speaking = false) : null);
  late final List<_Msg> _msgs = ((Store.getJson('chat', []) as List).map((e) => _Msg.fromJson(e))).toList();
  bool _listening = false, _thinking = false, _speaking = false, _sttReady = false;
  String? _emotion;
  String _status = '';
  bool get _speak => Store.raw.getBool('talk_speak') ?? true;
  int _session = 0; // bumped by Clear chat so in-flight replies stop updating the screen

  @override
  void initState() {
    super.initState();
    _initVoice();
    _warmUp();
    if (_msgs.isEmpty) {
      _msgs.add(_Msg(false, 'Hi ${Store.profile['name']} 👋 I’m all ears. Ask me anything: life, money or code.'));
    }
  }

  /// Load the AI into memory now so the first reply isn't a 20-second wait.
  Future<void> _warmUp() async {
    if (!await Brain.instance.has(mainBrain) && !await Brain.instance.has(fastBrain)) return;
    if (mounted) setState(() => _status = 'Waking up…');
    await Brain.instance.warmUp();
    if (mounted && _status == 'Waking up…') setState(() => _status = '');
  }

  Future<void> _initVoice() async {
    try {
      _sttReady = await _stt.initialize(onStatus: (s) {
        if ((s == 'done' || s == 'notListening') && mounted) setState(() => _listening = false);
      }, onError: (_) {
        if (mounted) setState(() => _listening = false);
      });
    } catch (_) {
      _sttReady = false;
    }
    try {
      await _tts.setLanguage('en-IN');
      await _tts.setSpeechRate(0.5);
      await _tts.setPitch(1.05);
      _tts.setStartHandler(() => mounted ? setState(() => _speaking = true) : null);
      _tts.setCompletionHandler(() => mounted ? setState(() => _speaking = false) : null);
      _tts.setCancelHandler(() => mounted ? setState(() => _speaking = false) : null);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _stt.cancel();
    _voice.stop();
    _voice.dispose();
    _save();
    super.dispose();
  }

  void _save() {
    final keep = _msgs.length > 60 ? _msgs.sublist(_msgs.length - 60) : _msgs;
    Store.setJson('chat', keep.map((m) => m.toJson()).toList());
  }

  Future<void> _toggleMic() async {
    HapticFeedback.selectionClick();
    if (_listening) {
      await _stt.stop();
      setState(() => _listening = false);
      if (_input.text.trim().isNotEmpty) _send();
      return;
    }
    if (!_sttReady) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Voice input isn’t available. Check that Google voice typing is installed.')));
      return;
    }
    await _voice.stop();
    setState(() {
      _listening = true;
      _emotion = 'listening';
      _status = 'Listening…';
    });
    await _stt.listen(
      listenOptions: SpeechListenOptions(
        localeId: Store.raw.getString('talk_locale') ?? 'en_IN',
        listenFor: const Duration(seconds: 45),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        listenMode: ListenMode.dictation,
        cancelOnError: true,
      ),
      onResult: (r) {
        setState(() => _input.text = r.recognizedWords);
        if (r.finalResult && r.recognizedWords.trim().isNotEmpty) {
          setState(() => _listening = false);
          _send();
        }
      },
    );
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _thinking) return;
    HapticFeedback.lightImpact();
    _input.clear();
    final u = understand(text);
    final coding = isCodingQuestion(text);
    final recent = _msgs.expand((m) => m.refs).toSet();
    final found = coding ? <Teaching>[] : retrieve(text, recent: recent);
    final history = [for (final m in _msgs.skip(1)) (m.user, m.text)];
    final reply = _Msg(false, '', found.take(1).map((t) => t.id).toList());
    setState(() {
      _msgs.add(_Msg(true, text));
      _msgs.add(reply);
      _thinking = true;
      _emotion = 'thinking';
      _status = coding ? 'Reading your code…' : 'Thinking…';
    });
    _scrollDown();
    // First chat of the day earns a little XP.
    if (Store.raw.getString('talk_day') != dayKey()) {
      await Store.raw.setString('talk_day', dayKey());
      await Store.addXp(10);
    }
    var first = true;
    final session = _session;
    await for (final tok in Brain.instance.reply(userText: text, history: history, found: found)) {
      if (!mounted || session != _session) return; // cleared: stop listening to this reply
      setState(() {
        if (first) {
          _emotion = null;
          _status = '';
          first = false;
        }
        if (tok == resetReply) {
          reply.text = ''; // model drifted into another language; it's retrying
        } else {
          reply.text += tok;
        }
      });
      _scrollDown();
    }
    if (!mounted) return;
    setState(() {
      _thinking = false;
      _emotion = switch (u.mood) {
        Mood.sad || Mood.anxious || Mood.angry => 'concerned',
        Mood.happy || Mood.motivated => 'happy',
        Mood.curious || Mood.confused => 'curious',
        Mood.calm => 'calm',
      };
    });
    _save();
    if (_speak) _say(reply.text);
  }

  /// Stops everything (reply generation, queued questions, voice, mic) and wipes the conversation.
  Future<void> _clearChat() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear the conversation?'),
        content: const Text('Buddy will stop answering and the whole chat will be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    HapticFeedback.mediumImpact();
    _session++;
    Brain.instance.cancelAll();
    await _voice.stop();
    if (_listening) await _stt.cancel();
    _input.clear();
    setState(() {
      _msgs
        ..clear()
        ..add(_Msg(false, 'Fresh start ✨ What’s on your mind, ${Store.profile['name']}?'));
      _thinking = false;
      _listening = false;
      _speaking = false;
      _emotion = 'calm';
      _status = '';
    });
    _save();
  }

  Future<void> _say(String text) async {
    // Read the explanation, not the code.
    final spoken = text.replaceAll(RegExp(r'```[\s\S]*?```'), ' (see the code on screen) ').replaceAll(RegExp(r'[*_`#>]'), '');
    try {
      _voice.robotic = Store.raw.getBool('talk_robot') ?? true;
      await _voice.speak(spoken.length > 600 ? '${spoken.substring(0, 600)}…' : spoken);
    } catch (_) {}
  }

  void _scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final busy = _listening || _speaking || _thinking;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Buddy'),
        actions: [
          IconButton(
            tooltip: _speak ? 'Voice replies on' : 'Voice replies off',
            onPressed: () async {
              await Store.raw.setBool('talk_speak', !_speak);
              if (!_speak) await _voice.stop();
              setState(() {});
            },
            icon: Icon(_speak ? Icons.volume_up_rounded : Icons.volume_off_rounded),
          ),
          IconButton(tooltip: 'Clear chat', onPressed: _clearChat, icon: const Icon(Icons.delete_sweep_outlined)),
          IconButton(
            tooltip: 'Buddy’s brain',
            onPressed: () => showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => const BrainSheet()).then((_) => setState(() {})),
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: Stack(children: [
        const Positioned.fill(child: _Aurora()),
        SafeArea(
          child: Column(children: [
            _GlowBuddy(emotion: _emotion, talking: _speaking || (_thinking && _status.isEmpty), active: busy),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _status.isEmpty
                  ? const SizedBox(height: 26)
                  : Container(
                      key: ValueKey(_status),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(color: cs.surfaceContainerHigh.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(20)),
                      child: Text(_status, style: tt.labelMedium?.copyWith(color: cs.primary, fontWeight: FontWeight.w800)),
                    ),
            ),
            const _BrainBanner(),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                itemCount: _msgs.length + 1,
                itemBuilder: (_, i) {
                  if (i == _msgs.length) return _suggestions();
                  final m = _msgs[i];
                  return _Bubble(msg: m, onSpeak: m.user ? null : () => _say(m.text));
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
                  _MicButton(listening: _listening, onTap: _toggleMic),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: _listening ? 'Listening…' : 'Message Buddy',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                      ),
                    ),
                  ),
                  IconButton.filled(
                    onPressed: _thinking ? null : _send,
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
    if (_thinking || _msgs.length > 1) return const SizedBox();
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

class _Bubble extends StatelessWidget {
  final _Msg msg;
  final VoidCallback? onSpeak;
  const _Bubble({required this.msg, this.onSpeak});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ref = msg.refs.map((id) => teachings.where((t) => t.id == id).firstOrNull).whereType<Teaching>().firstOrNull;
    final bubble = Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        gradient: msg.user ? const LinearGradient(colors: [Color(0xFF7C4DFF), Color(0xFF26C6DA)]) : null,
        color: msg.user ? null : (dark ? const Color(0xFF1C2333) : Colors.white).withValues(alpha: 0.92),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(msg.user ? 20 : 6),
          bottomRight: Radius.circular(msg.user ? 6 : 20),
        ),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        if (msg.text.isEmpty && !msg.user)
          const _TypingDots()
        else
          ..._rich(context, msg.text, msg.user ? Colors.white : (dark ? const Color(0xFFE8ECF6) : const Color(0xFF1B1F3B))),
        if (!msg.user && msg.text.isNotEmpty && (ref != null || onSpeak != null))
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (ref != null)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => showModalBottomSheet(context: context, builder: (_) => _VerseSheet(t: ref)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Text('📜 ${ref.src.split(',').first}', style: TextStyle(fontSize: 11, color: dark ? const Color(0xFF80DEEA) : cs.primary, fontWeight: FontWeight.w700)),
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
          _CodeBlock(code: p.replaceFirst(RegExp(r'^[a-zA-Z#+]*\n'), '').trimRight())
        else if (p.trim().isNotEmpty)
          SelectableText(p.trim(), style: TextStyle(color: color, fontSize: 15, height: 1.35)),
    ];
  }
}

/// Full verse, only when tapped.
class _VerseSheet extends StatelessWidget {
  final Teaching t;
  const _VerseSheet({required this.t});
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
class _GlowBuddy extends StatefulWidget {
  final String? emotion;
  final bool talking, active;
  const _GlowBuddy({required this.emotion, required this.talking, required this.active});
  @override
  State<_GlowBuddy> createState() => _GlowBuddyState();
}

class _GlowBuddyState extends State<_GlowBuddy> with SingleTickerProviderStateMixin {
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
                  gradient: RadialGradient(colors: [const Color(0xFF26C6DA).withValues(alpha: 0.35 + 0.25 * p), Colors.transparent]),
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
class _Aurora extends StatefulWidget {
  const _Aurora();
  @override
  State<_Aurora> createState() => _AuroraState();
}

class _AuroraState extends State<_Aurora> with SingleTickerProviderStateMixin {
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
                colors: dark ? const [Color(0xFF0A0F1F), Color(0xFF140C2A)] : const [Color(0xFFEFF7FF), Color(0xFFF7F0FF)],
              ),
            ),
            child: Stack(children: [
              for (final (ph, col, r) in dark
                  ? [(0.0, const Color(0xFF00B8D4), 0.7), (2.1, const Color(0xFF7C4DFF), 0.8), (4.2, const Color(0xFFFF6E9C), 0.6)]
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
class _MicButton extends StatefulWidget {
  final bool listening;
  final VoidCallback onTap;
  const _MicButton({required this.listening, required this.onTap});
  @override
  State<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<_MicButton> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = widget.listening ? const Color(0xFFFF5C8A) : cs.primary;
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

class _CodeBlock extends StatelessWidget {
  final String code;
  const _CodeBlock({required this.code});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.fromLTRB(10, 4, 4, 10),
        decoration: BoxDecoration(color: const Color(0xFF1E232B), borderRadius: BorderRadius.circular(10)),
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
            child: SelectableText(code, style: const TextStyle(fontFamily: 'monospace', color: Color(0xFFE6EDF3), fontSize: 12.5, height: 1.4)),
          ),
        ]),
      );
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
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

/// Shown until the main brain is downloaded.
class _BrainBanner extends StatefulWidget {
  const _BrainBanner();
  @override
  State<_BrainBanner> createState() => _BrainBannerState();
}

class _BrainBannerState extends State<_BrainBanner> {
  bool? _has;
  @override
  void initState() {
    super.initState();
    Brain.instance.has(mainBrain).then((v) => mounted ? setState(() => _has = v) : null);
    BrainDownloads.progress[mainBrain.id]!.addListener(_refresh);
  }

  void _refresh() => Brain.instance.has(mainBrain).then((v) => mounted ? setState(() => _has = v) : null);

  @override
  void dispose() {
    BrainDownloads.progress[mainBrain.id]!.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_has != false) return const SizedBox();
    final p = BrainDownloads.progress[mainBrain.id]!;
    return ValueListenableBuilder<double?>(
      valueListenable: p,
      builder: (_, v, _) => Card(
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
                  Text('Download his on-device AI (${mainBrain.sizeMb} MB, Wi-Fi) for real conversations. Private: nothing leaves your phone.',
                      style: Theme.of(context).textTheme.bodySmall)
                else
                  LinearProgressIndicator(value: v, minHeight: 6, borderRadius: BorderRadius.circular(6)),
              ]),
            ),
            if (v == null) TextButton(onPressed: () => BrainDownloads.start(mainBrain), child: const Text('Download')),
          ]),
        ),
      ),
    );
  }
}

/// Manage both models + voice language.
class BrainSheet extends StatefulWidget {
  const BrainSheet({super.key});
  @override
  State<BrainSheet> createState() => _BrainSheetState();
}

class _BrainSheetState extends State<BrainSheet> {
  final _has = <String, bool>{};
  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    for (final m in [fastBrain, smartBrain, codeBrain]) {
      _has[m.id] = await Brain.instance.has(m);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (_, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
        Text('Buddy’s brain', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        Text(CloudBrain.enabled ? 'Cloud first (AWS Bedrock), on-device when a limit is hit or offline.' : 'Runs fully on your phone. Your chats never leave it.', style: tt.bodySmall),
        const SizedBox(height: 12),
        _CloudCard(onChanged: () => setState(() {})),
        const SizedBox(height: 12),
        Text('Main brain', style: tt.labelLarge),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [ButtonSegment(value: 'qwen3-0.6b', label: Text('Fast')), ButtonSegment(value: 'gemma4-e2b', label: Text('Smart'))],
          selected: {mainBrain.id},
          onSelectionChanged: (v) => setState(() => Store.raw.setString('brain_main', v.first)),
        ),
        const SizedBox(height: 8),
        for (final m in [fastBrain, smartBrain, codeBrain])
          ValueListenableBuilder<double?>(
            valueListenable: BrainDownloads.progress[m.id]!,
            builder: (_, v, _) {
              if (v == null && _has[m.id] != null) Future.microtask(() => Brain.instance.has(m).then((h) => mounted && h != _has[m.id] ? setState(() => _has[m.id] = h) : null));
              final err = BrainDownloads.errors[m.id]!.value;
              return AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(m == codeBrain ? Icons.code : Icons.self_improvement),
                    const SizedBox(width: 8),
                    Expanded(child: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w800))),
                    Text('${m.sizeMb} MB', style: tt.bodySmall),
                  ]),
                  Text(m.purpose, style: tt.bodySmall),
                  const SizedBox(height: 8),
                  if (m == codeBrain && _has[m.id] == true)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('Use for coding questions'),
                      subtitle: const Text('More accurate, but ~5× slower on this phone. Off = fast brain answers code.'),
                      value: Store.raw.getBool('use_coder') ?? false,
                      onChanged: (val) => setState(() => Store.raw.setBool('use_coder', val)),
                    ),
                  if (v != null)
                    LinearProgressIndicator(value: v, minHeight: 6, borderRadius: BorderRadius.circular(6))
                  else if (_has[m.id] == true)
                    Row(children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 18),
                      const SizedBox(width: 6),
                      const Expanded(child: Text('Ready')),
                      TextButton(
                        onPressed: () async {
                          await Brain.instance.delete(m);
                          _check();
                        },
                        child: const Text('Delete'),
                      ),
                    ])
                  else
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.tonalIcon(
                        onPressed: () => BrainDownloads.start(m),
                        icon: const Icon(Icons.download),
                        label: Text(err ?? 'Download (Wi-Fi recommended)'),
                      ),
                    ),
                ]),
              );
            },
          ),
        const SizedBox(height: 4),
        _SpeedTest(),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Robot voice 🤖'),
          subtitle: const Text('Metallic sci-fi effect on Buddy’s speech'),
          value: Store.raw.getBool('talk_robot') ?? true,
          onChanged: (v) => setState(() => Store.raw.setBool('talk_robot', v)),
        ),
        Text('Buddy replies in', style: tt.labelLarge),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [ButtonSegment(value: 'en', label: Text('English')), ButtonSegment(value: 'hinglish', label: Text('Hinglish'))],
          selected: {Store.raw.getString('talk_lang') ?? 'en'},
          onSelectionChanged: (v) => setState(() => Store.raw.setString('talk_lang', v.first)),
        ),
        const SizedBox(height: 12),
        Text('Voice input language', style: tt.labelLarge),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [ButtonSegment(value: 'en_IN', label: Text('English / Hinglish')), ButtonSegment(value: 'hi_IN', label: Text('Hindi'))],
          selected: {Store.raw.getString('talk_locale') ?? 'en_IN'},
          onSelectionChanged: (v) => setState(() => Store.raw.setString('talk_locale', v.first)),
        ),
      ]),
    );
  }
}

/// Runs one sample question through the current brain (not saved to the chat) and reports speed.
class _SpeedTest extends StatefulWidget {
  @override
  State<_SpeedTest> createState() => _SpeedTestState();
}

class _SpeedTestState extends State<_SpeedTest> {
  String? _result;
  bool _running = false;

  Future<void> _run() async {
    setState(() {
      _running = true;
      _result = null;
    });
    final lines = <String>[];
    for (final (label, q) in [('Life', 'I feel stressed about work'), ('Code', 'In Dart, how do I reverse a list?')]) {
      final sw = Stopwatch()..start();
      int? first;
      final buf = StringBuffer();
      await for (final tok in Brain.instance.reply(userText: q, history: const [], found: isCodingQuestion(q) ? const [] : retrieve(q))) {
        first ??= sw.elapsedMilliseconds;
        if (tok == resetReply) {
          buf.clear();
        } else {
          buf.write(tok);
        }
      }
      // ignore: avoid_print
      print('[BuddyBrain] speed test $label: first ${first}ms, total ${sw.elapsedMilliseconds}ms: ${buf.toString().trim().replaceAll('\n', ' ⏎ ')}');
      lines.add('$label: first words ${(first! / 1000).toStringAsFixed(1)} s · done ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} s');
    }
    if (mounted) {
      setState(() {
        _running = false;
        _result = lines.join('\n');
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        OutlinedButton.icon(
          onPressed: _running ? null : _run,
          icon: _running ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.speed),
          label: Text(_running ? 'Testing… (first run loads the brain)' : 'Test speed'),
        ),
        if (_result != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_result!, style: Theme.of(context).textTheme.bodySmall)),
      ]);
}

/// Cloud brain (Claude on AWS Bedrock): on/off, API key, model, spend limits and today's/this month's usage.
class _CloudCard extends StatefulWidget {
  final VoidCallback onChanged;
  const _CloudCard({required this.onChanged});
  @override
  State<_CloudCard> createState() => _CloudCardState();
}

class _CloudCardState extends State<_CloudCard> {
  bool? _hasKey;
  final _keyCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    CloudBrain.instance.apiKey().then((k) => mounted ? setState(() => _hasKey = k != null) : null);
  }

  @override
  void dispose() {
    _keyCtl.dispose();
    super.dispose();
  }

  Future<void> _editLimit(String label, String pref, double current) async {
    final ctl = TextEditingController(text: current.toStringAsFixed(2));
    final v = await showDialog<double>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('$label limit (US\$)'),
        content: TextField(controller: ctl, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(prefixText: '\$ ')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, double.tryParse(ctl.text.trim())), child: const Text('Save')),
        ],
      ),
    );
    ctl.dispose();
    if (v != null && v >= 0) setState(() => Store.raw.setDouble(pref, v));
  }

  Widget _meter(String label, double spent, double limit, String pref) {
    final tt = Theme.of(context).textTheme;
    final f = limit <= 0 ? 1.0 : (spent / limit).clamp(0.0, 1.0);
    return InkWell(
      onTap: () => _editLimit(label, pref, limit),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(label, style: tt.bodyMedium)),
            Text('\$${spent.toStringAsFixed(3)} / \$${limit.toStringAsFixed(2)}', style: tt.bodySmall),
            const SizedBox(width: 4),
            const Icon(Icons.edit, size: 14),
          ]),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: f, minHeight: 6, borderRadius: BorderRadius.circular(6), color: f >= 1 ? Colors.red : (f > 0.8 ? Colors.orange : null)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final on = CloudBrain.enabled;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.cloud_outlined),
          title: const Text('Cloud brain · Claude on AWS', style: TextStyle(fontWeight: FontWeight.w800)),
          subtitle: const Text('Smarter & faster. Chats go to your AWS account. Stops at your limits.'),
          value: on,
          onChanged: (v) {
            Store.raw.setBool('cloud_on', v);
            setState(() {});
            widget.onChanged();
          },
        ),
        if (on) ...[
          if (_hasKey == true)
            Row(children: [
              const Icon(Icons.key, size: 18, color: Colors.green),
              const SizedBox(width: 6),
              const Expanded(child: Text('Bedrock API key saved (encrypted)')),
              TextButton(
                onPressed: () async {
                  await CloudBrain.instance.setApiKey(null);
                  setState(() => _hasKey = false);
                },
                child: const Text('Remove'),
              ),
            ])
          else
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _keyCtl,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(labelText: 'Bedrock API key', isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () async {
                  if (_keyCtl.text.trim().isEmpty) return;
                  await CloudBrain.instance.setApiKey(_keyCtl.text);
                  _keyCtl.clear();
                  setState(() => _hasKey = true);
                },
                child: const Text('Save'),
              ),
            ]),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [for (final m in cloudModels) ButtonSegment(value: m.id, label: Text(m.label))],
            selected: {CloudBrain.model.id},
            onSelectionChanged: (v) => setState(() => Store.raw.setString('cloud_model', v.first)),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('\$${CloudBrain.model.inPerM} in / \$${CloudBrain.model.outPerM} out per million tokens · region ${CloudBrain.region}', style: tt.bodySmall),
          ),
          const SizedBox(height: 8),
          _meter('Today', CloudBrain.spentToday, CloudBrain.dailyLimit, 'cloud_daily_usd'),
          _meter('This month', CloudBrain.spentMonth, CloudBrain.monthlyLimit, 'cloud_monthly_usd'),
          if (CloudBrain.instance.lastStatus != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(CloudBrain.instance.lastStatus!, style: tt.bodySmall)),
        ],
      ]),
    );
  }
}
