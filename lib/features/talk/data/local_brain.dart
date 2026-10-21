import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';

import '../model/brain_model.dart';
import 'model_files.dart';
import 'prompts.dart';

/// Why a local generation stopped early.
enum StopReason { none, drifted, cancelled }

/// Runs on-device models: loads them once (kept open), and generates one reply at a time.
class LocalBrain {
  LocalBrain._();
  static final instance = LocalBrain._();

  bool _initialized = false;
  final _open = <String, InferenceModel>{};
  Future<InferenceModel>? _loading;
  String? _loadingId;
  Future<void>? _busy;

  Future<void> _init() async {
    if (_initialized) return;
    await FlutterEdgeAi.initialize(inferenceEngines: const [LiteRtLmEngine()]);
    _initialized = true;
  }

  /// Loads [m] once; concurrent callers share one load (two parallel installs broke the engine).
  Future<InferenceModel> load(BrainModel m) async {
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
    final path = await ModelFiles.pathFor(m);
    InferenceModel model;
    try {
      // Opened independently so several brains can stay loaded at once.
      final inst = await FlutterEdgeAi.installModel(modelType: m.type, fileType: ModelFileType.litertlm).fromFile(path).install(activate: false);
      model = await _withBackend((b) => FlutterEdgeAi.openModel(inst.spec, maxTokens: 1280, preferredBackend: b));
    } catch (e) {
      debugPrint('[BuddyBrain] multi-model open failed ($e); using single active model');
      for (final other in _open.values) {
        await other.close();
      }
      _open.clear();
      await FlutterEdgeAi.installModel(modelType: m.type, fileType: ModelFileType.litertlm).fromFile(path).install();
      model = await _withBackend((b) => FlutterEdgeAi.getActiveModel(maxTokens: 1280, preferredBackend: b));
    }
    _open[m.id] = model;
    debugPrint('[BuddyBrain] loaded ${m.id} in ${sw.elapsedMilliseconds}ms');
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

  Future<void> unload(BrainModel m) async => _open.remove(m.id)?.close();

  /// Waits until no other generation runs (two at once mixed up their answers); call the result to release.
  Future<void Function()> lock() async {
    while (_busy != null) {
      await _busy;
    }
    final done = Completer<void>();
    _busy = done.future;
    return () {
      _busy = null;
      done.complete();
    };
  }

  /// Streams visible reply text for [prompt]; hides think blocks, stops on CJK drift or when [cancelled].
  /// [onStop] reports why it stopped.
  Stream<String> generate(
    InferenceModel m,
    BrainModel brain,
    String prompt, {
    required double temperature,
    required int topK,
    required int maxTokens,
    required bool Function() cancelled,
    required void Function(StopReason) onStop,
  }) async* {
    final chat = await m.createChat(temperature: temperature, topK: topK, maxOutputTokens: maxTokens, modelType: brain.type, enableThinking: false);
    await chat.addQueryChunk(Message.text(text: prompt, isUser: true));
    final sw = Stopwatch()..start();
    int? firstMs;
    var chunks = 0, inThink = false;
    var reason = StopReason.none;
    try {
      await for (final r in chat.generateChatResponseAsync()) {
        if (r is! TextResponse) continue;
        firstMs ??= sw.elapsedMilliseconds;
        chunks++;
        var tok = r.token;
        if (tok.contains('<think>')) inThink = true;
        if (inThink) {
          if (!tok.contains('</think>')) continue;
          inThink = false;
          tok = tok.split('</think>').last;
        }
        if (cancelled()) {
          reason = StopReason.cancelled;
          break;
        }
        if (cjkText.hasMatch(tok)) {
          reason = StopReason.drifted;
          break;
        }
        yield tok;
      }
    } finally {
      debugPrint('[BuddyBrain] ${brain.id}: first token ${firstMs}ms, $chunks chunks in ${sw.elapsedMilliseconds}ms${reason == StopReason.none ? '' : ' (${reason.name})'}');
      // Closing the session can hang on this engine; never make the reply wait for it.
      unawaited(chat.close().timeout(const Duration(seconds: 5)).catchError((_) {}));
      onStop(reason);
    }
  }
}
