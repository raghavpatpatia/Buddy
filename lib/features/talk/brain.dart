import 'dart:async';
import 'dart:io';

import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../core/store.dart';
import 'cloud_brain.dart';
import 'wisdom.dart';

/// An on-device model Buddy can use. Downloaded once into app storage, then activated from file.
class BrainModel {
  final String id, name, url, purpose;
  final int sizeMb;
  final ModelType type;
  const BrainModel(this.id, this.name, this.url, this.sizeMb, this.type, this.purpose);
}

// Gemma 3 1B would be ideal but is licence-gated on Hugging Face (needs an account), so the
// default is Qwen 3 0.6B (open, ~500 MB, fast). Gemma 4 E2B is the smarter, heavier option.
const fastBrain = BrainModel(
  'qwen3-0.6b',
  'Fast brain · Qwen 3 0.6B',
  'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/qwen3_0_6b_mixed_int4.litertlm',
  498,
  ModelType.qwen3,
  'Quick replies: talks, spiritual guidance, life & money',
);

const smartBrain = BrainModel(
  'gemma4-e2b',
  'Smart brain · Gemma 4 E2B',
  'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it-gpu.litertlm',
  2008,
  ModelType.gemma4,
  'Deeper, more natural Hinglish answers; slower',
);

/// The main brain the user picked (fast by default).
BrainModel get mainBrain => Store.raw.getString('brain_main') == smartBrain.id ? smartBrain : fastBrain;

const codeBrain = BrainModel(
  'qwen25-coder-1.5b-int4',
  'Qwen 2.5 Coder 1.5B',
  'https://huggingface.co/litert-community/Qwen2.5-Coder-1.5B-Instruct/resolve/main/Qwen2.5-Coder-1.5B-Instruct_int4.litertlm',
  1117,
  ModelType.qwen,
  'Coding help: Flutter, Cocos/TypeScript, Unity/C#',
);

/// Rough “is this a coding question?” check: code fences, symbols, or dev vocabulary.
/// Yielded by [Brain.reply] to tell the UI to discard the partial reply before a retry.
const resetReply = '\u0000reset';

/// Chinese, Japanese and Korean scripts: a sign a small multilingual model has drifted.
final cjkText = RegExp(r'[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uac00-\ud7af\uff00-\uffef]');

bool isCodingQuestion(String text) {
  final t = text.toLowerCase();
  if (t.contains('```') || RegExp(r'[{};]\s*$|=>|\w+\(\)|</?\w+>', multiLine: true).hasMatch(text)) return true;
  return RegExp(
    r'\b(code|coding|bug|debug|error|exception|stack ?trace|crash|compile|flutter|dart|widget|unity|c#|csharp|cocos|typescript|javascript|js|ts|python|java|kotlin|swift|sql|api|json|regex|git|function|method|class|variable|array|list|loop|recursion|algorithm|async|await|null|shader|prefab|gradle|npm|build fail|null pointer|refactor)\b',
  ).hasMatch(t);
}

class Brain {
  Brain._();
  static final instance = Brain._();

  bool _initialized = false;
  /// Every brain opened so far stays loaded: switching fast ↔ coder used to cost 10–26 s each time.
  final _open = <String, InferenceModel>{};
  Future<InferenceModel>? _loading;
  String? _loadingId;

  /// One generation at a time: two chats on the same model at once mixed up their answers.
  Future<void>? _busy;

  /// Bumped by [cancelAll]; running and queued replies stop when it changes.
  int _generation = 0;

  /// Stop every running and queued reply (used by “Clear chat”).
  void cancelAll() => _generation++;

  /// The 1.5B coder is accurate but ~3 words/s on a Dimensity 6100+; opt-in only.
  static bool get useCoder => Store.raw.getBool('use_coder') ?? false;

  Future<void> _init() async {
    if (_initialized) return;
    await FlutterEdgeAi.initialize(inferenceEngines: const [LiteRtLmEngine()]);
    _initialized = true;
  }

  /// Models can also be copied in by hand (e.g. from a PC over USB) to `Download/BuddyModels/{id}.litertlm`.
  static String sideloadPath(BrainModel m) => '/storage/emulated/0/Download/BuddyModels/${m.id}.litertlm';

  static Future<String> _pathFor(BrainModel m) async {
    if (File(sideloadPath(m)).existsSync()) return sideloadPath(m);
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/models');
    await dir.create(recursive: true);
    return '${dir.path}/${m.id}.litertlm';
  }

  /// Downloaded completely?
  Future<bool> has(BrainModel m) async {
    if (File(sideloadPath(m)).existsSync()) return true;
    final f = File(await _pathFor(m));
    return f.existsSync() && Store.raw.getBool('brain_ok_${m.id}') == true;
  }

  /// Resumable download with progress (0..1). Throws on network errors; call again to resume.
  Future<void> download(BrainModel m, void Function(double) onProgress, {Completer<void>? cancel}) async {
    final path = await _pathFor(m);
    final part = File('$path.part');
    final have = part.existsSync() ? part.lengthSync() : 0;
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(m.url));
      if (have > 0) req.headers['Range'] = 'bytes=$have-';
      final res = await client.send(req);
      if (res.statusCode != 200 && res.statusCode != 206) throw HttpException('HTTP ${res.statusCode}');
      final resumed = res.statusCode == 206;
      final total = (res.contentLength ?? 0) + (resumed ? have : 0);
      var got = resumed ? have : 0;
      final sink = part.openWrite(mode: resumed ? FileMode.append : FileMode.write);
      try {
        await for (final chunk in res.stream) {
          if (cancel?.isCompleted == true) throw const _Cancelled();
          sink.add(chunk);
          got += chunk.length;
          if (total > 0) onProgress(got / total);
        }
      } finally {
        await sink.close();
      }
      await part.rename(path);
      await Store.raw.setBool('brain_ok_${m.id}', true);
    } finally {
      client.close();
    }
  }

  Future<void> delete(BrainModel m) async {
    final p = await _pathFor(m);
    for (final f in [File(p), File('$p.part')]) {
      if (f.existsSync()) await f.delete();
    }
    await Store.raw.remove('brain_ok_${m.id}');
    await _open.remove(m.id)?.close();
  }

  /// Loads [m] (closing any other). Concurrent callers share one load: two parallel installs
  /// (warm-up + first message) broke the engine and made every reply fall back to offline.
  Future<InferenceModel> _load(BrainModel m) async {
    final cached = _open[m.id];
    if (cached != null && !cached.isClosed) return cached;
    while (_loading != null) {
      if (_loadingId == m.id) return _loading!;
      try {
        await _loading;
      } catch (_) {}
    }
    _loadingId = m.id;
    final f = _doLoad(m);
    _loading = f;
    try {
      return await f;
    } finally {
      _loading = null;
      _loadingId = null;
    }
  }

  Future<InferenceModel> _doLoad(BrainModel m) async {
    final sw = Stopwatch()..start();
    await _init();
    final path = await _pathFor(m);
    InferenceModel model;
    try {
      // Open as an independent model so several brains can stay loaded at once.
      final inst = await FlutterEdgeAi.installModel(modelType: m.type, fileType: ModelFileType.litertlm).fromFile(path).install(activate: false);
      model = await _withBackend((b) => FlutterEdgeAi.openModel(inst.spec, maxTokens: 1280, preferredBackend: b));
    } catch (e) {
      // ignore: avoid_print
      print('[BuddyBrain] multi-model open failed ($e); using single active model');
      for (final other in _open.values) {
        await other.close();
      }
      _open.clear();
      await FlutterEdgeAi.installModel(modelType: m.type, fileType: ModelFileType.litertlm).fromFile(path).install();
      model = await _withBackend((b) => FlutterEdgeAi.getActiveModel(maxTokens: 1280, preferredBackend: b));
    }
    _open[m.id] = model;
    // ignore: avoid_print
    print('[BuddyBrain] loaded ${m.id} in ${sw.elapsedMilliseconds}ms');
    return model;
  }

  /// GPU is much faster for prefill on Mali; fall back to CPU if the driver refuses.
  static Future<InferenceModel> _withBackend(Future<InferenceModel> Function(PreferredBackend) open) async {
    try {
      return await open(PreferredBackend.gpu);
    } catch (_) {
      return open(PreferredBackend.cpu);
    }
  }

  /// Streams a reply. Uses the coder for code questions (if downloaded), else the main brain;
  /// falls back to the offline composer if no model is available or it fails.
  Stream<String> reply({required String userText, required List<(bool, String)> history, required List<Teaching> found}) async* {
    final coding = isCodingQuestion(userText);
    // Cloud first (Claude on Bedrock) while within its spend limits; any failure falls through to on-device.
    if (CloudBrain.enabled) {
      final cloudGen = _generation;
      final name = Store.profile['name'] as String? ?? 'friend';
      var any = false;
      try {
        await for (final t in CloudBrain.instance.reply(system: _system(name, coding), user: _userTurn(name, userText, history, found, coding), maxTokens: coding ? 2048 : 1024)) {
          if (cloudGen != _generation) return; // chat was cleared
          any = true;
          yield t;
        }
        return;
      } catch (e) {
        // ignore: avoid_print
        print('[BuddyCloud] falling back to on-device: $e');
        if (any) yield resetReply;
      }
    }
    final main = await has(mainBrain) ? mainBrain : (await has(fastBrain) ? fastBrain : (await has(smartBrain) ? smartBrain : null));
    final model = coding && useCoder && await has(codeBrain) ? codeBrain : main;
    if (model == null) {
      yield offlineReply(userText, found, coding: coding);
      return;
    }
    final gen = _generation;
    while (_busy != null) {
      await _busy;
    }
    if (gen != _generation) return; // cleared while queued
    final done = Completer<void>();
    _busy = done.future;
    try {
      final m = await _load(model);
      final name = Store.profile['name'] as String? ?? 'friend';
      // The prompt follows the QUESTION, not the brain: with the coder switched off, the fast brain
      // got the spiritual prompt for code questions and answered "I can't help with coding".
      final codeMode = coding;
      // The LiteRT session fails to stream (code 13) when given a system instruction, so Buddy's
      // rules go at the top of the message in a short, clearly labelled block.
      final hinglish = Store.raw.getString('talk_lang') == 'hinglish';
      final lang = hinglish ? 'Hinglish (Roman script)' : 'English';
      final emitted = StringBuffer();
      // Small Qwen models sometimes drift into Chinese. Stop the moment CJK text appears; if almost
      // nothing useful came out, retry once with a stricter prompt, then fall back to offline wisdom.
      for (var attempt = 0; attempt < 2; attempt++) {
        final chat = await m.createChat(
          temperature: codeMode ? 0.2 : (attempt == 0 ? 0.45 : 0.25),
          topK: attempt == 0 ? 40 : 20,
          maxOutputTokens: codeMode ? (model == codeBrain ? 450 : 300) : 110,
          modelType: model.type,
          enableThinking: false, // straight answers: thinking makes small models much slower
        );
        final strict = attempt == 0 ? '' : 'IMPORTANT: Write ONLY in $lang. Never use Chinese characters. ';
        final prompt = '${strict}Instructions: ${_system(name, codeMode)} Always answer in $lang.\n\n'
            'Question: ${_userTurn(name, userText, history, found, codeMode)}\n\n(Answer in $lang only.)';
        await chat.addQueryChunk(Message.text(text: prompt, isUser: true));
        final sw = Stopwatch()..start();
        int? firstMs;
        var chunks = 0;
        var inThink = false, drifted = false;
        await for (final r in chat.generateChatResponseAsync()) {
          if (r is! TextResponse) continue;
          firstMs ??= sw.elapsedMilliseconds;
          chunks++;
          // Qwen 3 may wrap reasoning in <think>…</think>; never show it.
          var tok = r.token;
          if (tok.contains('<think>')) inThink = true;
          if (inThink) {
            if (tok.contains('</think>')) {
              inThink = false;
              tok = tok.split('</think>').last;
            } else {
              continue;
            }
          }
          if (gen != _generation) break; // chat was cleared
          if (cjkText.hasMatch(tok)) {
            drifted = true;
            break;
          }
          emitted.write(tok);
          yield tok;
        }
        // ignore: avoid_print
        print('[BuddyBrain] ${model.id}: first token ${firstMs}ms, $chunks chunks in ${sw.elapsedMilliseconds}ms${drifted ? ' (stopped: drifted into CJK, attempt ${attempt + 1})' : ''}');
        // Closing the session can hang on this engine; never make the reply wait for it.
        unawaited(chat.close().timeout(const Duration(seconds: 5)).catchError((_) {}));
        if (gen != _generation || !drifted || emitted.toString().trim().length >= 40) break;
        if (attempt == 0 && emitted.isNotEmpty) {
          emitted.clear();
          yield resetReply;
        }
        if (attempt == 1) {
          yield emitted.isEmpty ? offlineReply(userText, found, coding: coding) : '';
        }
      }
    } catch (e, st) {
      // ignore: avoid_print
      print('[BuddyBrain] error with ${model.id}: $e\n$st');
      yield offlineReply(userText, found, coding: coding);
    } finally {
      _busy = null;
      done.complete();
    }
  }

  /// Who Buddy is and how he answers (goes in the model's system slot; small models follow it far better there).
  static String _system(String name, bool code) {
    final hinglish = Store.raw.getString('talk_lang') == 'hinglish';
    if (code) {
      return 'You are Buddy, a senior Flutter, TypeScript and Unity developer. Give a short working code snippet, then 1–2 sentences. Only more if asked.';
    }
    return 'You are Buddy, $name\'s friendly robot with a calm, spiritual heart. Reply ${hinglish ? 'in Hinglish' : 'in simple English'}, '
        '1–3 short sentences, only what was asked. Use the reference idea if it fits and name its source. Never invent scripture. Money: save, avoid debt, index funds; no stock tips.';
  }

  /// The user's message, with a little context: last exchange and (optionally) one reference teaching.
  static String _userTurn(String name, String user, List<(bool, String)> history, List<Teaching> found, bool code) {
    final last = history.length > 2 ? history.sublist(history.length - 2) : history;
    final convo = last.map((h) => '${h.$1 ? name : 'Buddy'}: ${h.$2.length > 120 ? '${h.$2.substring(0, 120)}…' : h.$2}').join('\n');
    final ref = code || found.isEmpty ? '' : '\n\n(Reference idea, ${found.first.src}: ${found.first.mean} Small step: ${found.first.act})';
    return '${convo.isEmpty ? '' : '(Earlier:\n$convo)\n\n'}$user$ref';
  }

  /// Load the main brain in the background so the first reply isn't slow.
  Future<void> warmUp() async {
    final m = await has(mainBrain) ? mainBrain : (await has(fastBrain) ? fastBrain : null);
    if (m == null) return;
    try {
      await _load(m);
    } catch (_) {}
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}

/// Instant, offline reply built from the matched teaching (no model needed). Short and on-topic.
String offlineReply(String userText, List<Teaching> found, {bool coding = false}) {
  final name = Store.profile['name'] as String? ?? 'friend';
  final hinglish = Store.raw.getString('talk_lang') == 'hinglish';
  if (coding) {
    // Only reached when no brain is available or it failed; don't blame a missing coding brain.
    return hinglish
        ? 'Abhi mera AI brain ready nahi hai, ek baar phir try karo. Tip: error ka pehla line aur stack trace ka top frame padho, wahi bug batate hain.'
        : 'My AI brain isn’t ready right now, so please try again in a moment. Tip: read the first error line and the top stack frame; they usually point right at the bug.';
  }
  final u = understand(userText);
  final open = hinglish
      ? switch (u.mood) {
          Mood.sad => 'Main samajhta hoon, $name.',
          Mood.anxious => 'Ek gehri saans lo, $name.',
          Mood.angry => 'Gussa natural hai, bas usse drive mat karne do.',
          Mood.happy => 'Waah! 😄',
          _ => 'Hmm, $name.',
        }
      : switch (u.mood) {
          Mood.sad => 'I hear you, $name.',
          Mood.anxious => 'Take one slow breath, $name.',
          Mood.angry => 'Anger is natural; just don’t let it drive.',
          Mood.happy => 'Love that! 😄',
          _ => 'Hmm, $name.',
        };
  if (found.isEmpty) return hinglish ? '$open Thoda aur batao?' : '$open Tell me a little more?';
  final t = found.first;
  return hinglish ? '$open ${t.mean} (${t.src}) Aaj: ${t.act}' : '$open ${t.mean} (${t.src}) Try today: ${t.act}';
}
