import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../../core/arch/safe_notifier.dart';
import '../../../core/store.dart';
import '../data/chat_memory.dart';
import '../data/cloud_brain.dart';
import '../data/model_files.dart';
import '../data/prompts.dart';
import '../data/reply_chain.dart';
import '../data/robot_voice.dart';
import '../data/talk_settings.dart';
import '../data/wisdom.dart';
import '../model/chat_message.dart';

/// What Buddy is doing right now; exactly one at a time.
enum TalkPhase { idle, waking, listening, thinking, speaking }

/// Talk screen logic: the conversation, sending, voice input, spoken replies and clearing.
class TalkController extends SafeNotifier {
  TalkController({ReplyChain? chain, ChatMemory? memory, SpeechToText? stt, FlutterTts? tts})
      : _chain = chain ?? ReplyChain.instance,
        _memory = memory ?? ChatMemory.instance,
        _stt = stt ?? SpeechToText(),
        _tts = tts ?? FlutterTts();

  final ReplyChain _chain;
  final ChatMemory _memory;
  final SpeechToText _stt;
  final FlutterTts _tts;
  late final _voice = RobotVoice(_tts)
    ..onStart = (() => _setPhase(TalkPhase.speaking))
    ..onDone = (() => _setPhase(TalkPhase.idle));

  List<ChatMessage> get messages => _memory.messages;
  TalkPhase phase = TalkPhase.idle;
  String? emotion;
  bool sttReady = false;
  int _session = 0;

  /// Called with live speech-to-text words while listening.
  void Function(String words)? onTranscript;

  bool get thinking => phase == TalkPhase.thinking;
  bool get listening => phase == TalkPhase.listening;
  bool get speaking => phase == TalkPhase.speaking;
  bool get busy => phase != TalkPhase.idle;
  bool get speakReplies => TalkSettings.speakReplies;

  String get status => switch (phase) {
        TalkPhase.waking => 'Waking up…',
        TalkPhase.listening => 'Listening…',
        TalkPhase.thinking => messages.isNotEmpty && messages.last.text.isNotEmpty ? '' : _thinkingLabel,
        _ => '',
      };
  String _thinkingLabel = 'Thinking…';

  void _setPhase(TalkPhase p) {
    phase = p;
    notifyListeners();
  }

  Future<void> init() async {
    _memory.load();
    if (messages.isEmpty) messages.add(ChatMessage(false, 'Hi ${TalkSettings.userName} 👋 I’m all ears. Ask me anything: life, money or code.'));
    notifyListeners();
    await _initVoice();
    await _warmUp();
  }

  Future<void> _warmUp() async {
    if (!await ModelFiles.has(TalkSettings.mainBrain)) return;
    if (phase == TalkPhase.idle) _setPhase(TalkPhase.waking);
    await _chain.warmUp();
    if (phase == TalkPhase.waking) _setPhase(TalkPhase.idle);
  }

  Future<void> _initVoice() async {
    try {
      sttReady = await _stt.initialize(onStatus: (s) {
        if ((s == 'done' || s == 'notListening') && listening) _setPhase(TalkPhase.idle);
      }, onError: (_) {
        if (listening) _setPhase(TalkPhase.idle);
      });
    } catch (_) {
      sttReady = false;
    }
    try {
      await _tts.setLanguage('en-IN');
      await _tts.setSpeechRate(0.5);
      await _tts.setPitch(1.05);
      _tts.setStartHandler(() => _setPhase(TalkPhase.speaking));
      _tts.setCompletionHandler(() => _setPhase(TalkPhase.idle));
      _tts.setCancelHandler(() => _setPhase(TalkPhase.idle));
    } catch (_) {}
    notifyListeners();
  }

  void save() => _memory.save();

  /// Folds turns that no longer fit the brain's window into the saved memory notes (in the background).
  Future<void> _remember() async {
    final budget = CloudBrain.enabled ? cloudHistoryChars : TalkSettings.mainBrain.historyChars;
    final ctx = _memory.context(budget);
    final pending = _memory.unnoted(ctx);
    if (pending.isEmpty) return;
    final session = _session;
    // Only Buddy's own lines (e.g. the greeting) left the window: nothing worth a generation.
    if (!pending.any((t) => t.$1)) return _memory.setNotes(_memory.notes, ctx.dropped);
    final notes = await _chain.updateNotes(_memory.notes, pending);
    if (notes != null && session == _session) await _memory.setNotes(notes, ctx.dropped);
  }

  /// Starts listening, or stops and returns the words heard so far; false when voice input isn't available.
  Future<bool> toggleMic(String currentText) async {
    if (listening) {
      await _stt.stop();
      _setPhase(TalkPhase.idle);
      if (currentText.trim().isNotEmpty) await send(currentText);
      return true;
    }
    if (!sttReady) return false;
    await _voice.stop();
    emotion = 'listening';
    _setPhase(TalkPhase.listening);
    await _stt.listen(
      listenOptions: SpeechListenOptions(
        localeId: TalkSettings.voiceLocale,
        listenFor: const Duration(seconds: 45),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        listenMode: ListenMode.dictation,
        cancelOnError: true,
      ),
      onResult: (r) {
        onTranscript?.call(r.recognizedWords);
        if (r.finalResult && r.recognizedWords.trim().isNotEmpty) {
          _setPhase(TalkPhase.idle);
          send(r.recognizedWords);
        }
      },
    );
    return true;
  }

  /// Sends [raw] and streams Buddy's reply into the conversation.
  Future<void> send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || thinking) return;
    final u = understand(text);
    final coding = isCodingQuestion(text);
    final recent = messages.expand((m) => m.refs).toSet();
    final found = wantsWisdom(text, u) ? retrieve(text, recent: recent, fallback: false) : <Teaching>[];
    final history = _memory.history;
    messages
      ..add(ChatMessage(true, text))
      ..add(ChatMessage(false, '', found.take(1).map((t) => t.id).toList()));
    emotion = 'thinking';
    _thinkingLabel = coding ? 'Reading your code…' : 'Thinking…';
    _setPhase(TalkPhase.thinking);
    if (Store.raw.getString('talk_day') != dayKey()) {
      await Store.raw.setString('talk_day', dayKey());
      await Store.addXp(10);
    }
    final session = _session;
    var first = true;
    await for (final tok in _chain.reply(text: text, history: history, found: found, notes: _memory.notes)) {
      if (disposed || session != _session) return;
      if (first) {
        emotion = null;
        first = false;
      }
      final reply = messages.last;
      messages[messages.length - 1] = reply.withText(tok == resetReply ? '' : reply.text + tok);
      notifyListeners();
    }
    if (disposed || session != _session) return;
    emotion = switch (u.mood) {
      Mood.sad || Mood.anxious || Mood.angry => 'concerned',
      Mood.happy || Mood.motivated => 'happy',
      Mood.curious || Mood.confused => 'curious',
      Mood.calm => 'calm',
    };
    _setPhase(TalkPhase.idle);
    save();
    if (speakReplies) speak(messages.last.text);
    unawaited(_remember());
  }

  /// Stops every reply, voice and mic, and starts a fresh conversation.
  Future<void> clear() async {
    _session++;
    _chain.cancelAll();
    await _voice.stop();
    if (listening) await _stt.cancel();
    await _memory.clear();
    messages.add(ChatMessage(false, 'Fresh start ✨ I’ve forgotten our last chat. What’s on your mind, ${TalkSettings.userName}?'));
    emotion = 'calm';
    _setPhase(TalkPhase.idle);
    save();
  }

  /// Reads [text] aloud, skipping code blocks.
  Future<void> speak(String text) async {
    final spoken = text.replaceAll(RegExp(r'```[\s\S]*?```'), ' (see the code on screen) ').replaceAll(RegExp(r'[*_`#>]'), '');
    try {
      _voice.robotic = TalkSettings.robotVoice;
      await _voice.speak(spoken.length > 600 ? '${spoken.substring(0, 600)}…' : spoken);
    } catch (_) {}
  }

  Future<void> toggleSpeakReplies() async {
    await TalkSettings.setSpeakReplies(!speakReplies);
    if (!speakReplies) await _voice.stop();
    notifyListeners();
  }

  @override
  void dispose() {
    _stt.cancel();
    _voice.stop();
    _voice.dispose();
    save();
    super.dispose();
  }
}
