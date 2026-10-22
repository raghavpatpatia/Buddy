import 'package:flutter/foundation.dart';

import '../model/chat_context.dart';

import '../model/brain_model.dart';
import 'cloud_brain.dart';
import 'local_brain.dart';
import 'model_files.dart';
import 'prompts.dart';
import 'talk_settings.dart';
import 'wisdom.dart';

/// Everything a reply source needs to answer one message.
class ReplyRequest {
  final String text;

  /// The whole session before [text], oldest first; each source takes what fits its window.
  final List<(bool, String)> history;

  /// Memory notes on turns older than any window.
  final String notes;
  final List<Teaching> found;
  final bool coding;
  final bool Function() cancelled;
  ReplyRequest(this.text, this.history, this.found, this.cancelled, {this.notes = ''}) : coding = isCodingQuestion(text);

  /// The notes plus the newest turns that fit in [budget] characters.
  ChatContext window(int budget) => buildContext(history, notes, budget: budget);
}

/// Cloud context budget in characters (~6k tokens): plenty of memory, still cheap.
const cloudHistoryChars = 24000;

/// Thrown by a [ReplySource] that can't answer, so the chain moves on to the next source.
class ReplyUnavailable implements Exception {
  final String reason;
  const ReplyUnavailable(this.reason);
  @override
  String toString() => reason;
}

/// One way of answering (cloud AI, on-device AI, offline wisdom).
abstract interface class ReplySource {
  Stream<String> reply(ReplyRequest r);
}

/// Claude on AWS Bedrock, within its spend limits; gets the session as real chat turns plus the notes.
class CloudReplySource implements ReplySource {
  @override
  Stream<String> reply(ReplyRequest r) async* {
    if (!CloudBrain.enabled) throw const ReplyUnavailable('cloud brain off');
    final name = TalkSettings.userName;
    final ctx = r.window(cloudHistoryChars);
    try {
      await for (final t in CloudBrain.instance.reply(
        system: systemPrompt(name, code: r.coding, notes: ctx.notes),
        user: userTurn(r.text, r.found, code: r.coding),
        history: ctx.turns,
        maxTokens: r.coding ? 2048 : 1024,
      )) {
        if (r.cancelled()) return;
        yield t;
      }
    } on CloudUnavailable catch (e) {
      throw ReplyUnavailable(e.reason);
    }
  }
}

/// The downloaded on-device model (coder for code questions when enabled), with drift and refusal guards.
class LocalReplySource implements ReplySource {
  final LocalBrain _brain;
  LocalReplySource([LocalBrain? brain]) : _brain = brain ?? LocalBrain.instance;

  Future<BrainModel?> _pick(bool coding) async {
    if (coding && TalkSettings.useCoder && await ModelFiles.has(codeBrain)) return codeBrain;
    for (final m in [TalkSettings.mainBrain, fastBrain, smartBrain]) {
      if (await ModelFiles.has(m)) return m;
    }
    return null;
  }

  @override
  Stream<String> reply(ReplyRequest r) async* {
    final brain = await _pick(r.coding);
    if (brain == null) throw const ReplyUnavailable('no model downloaded');
    final release = await _brain.lock();
    try {
      if (r.cancelled()) return;
      final model = await _brain.load(brain);
      final name = TalkSettings.userName;
      final lang = TalkSettings.hinglish ? 'Hinglish (Roman script)' : 'English';
      final ctx = r.window(brain.historyChars);
      final system = systemPrompt(name, code: r.coding, notes: ctx.notes);
      final prompt = localPrompt(name, ctx.turns, userTurn(r.text, r.found, code: r.coding));
      final emitted = StringBuffer();
      // Small Qwen models sometimes drift into Chinese: retry once with a stricter prompt.
      for (var attempt = 0; attempt < 2; attempt++) {
        var stop = StopReason.none;
        final strict = attempt == 0 ? '' : ' IMPORTANT: Write ONLY in $lang. Never use Chinese characters.';
        var lead = true;
        await for (var tok in _brain.generate(
          model,
          brain,
          prompt,
          system: '$system$strict',
          temperature: r.coding ? 0.2 : (attempt == 0 ? 0.6 : 0.3),
          topK: attempt == 0 ? 40 : 20,
          maxTokens: r.coding ? brain.replyTokens + 200 : brain.replyTokens,
          cancelled: r.cancelled,
          onStop: (s) => stop = s,
        )) {
          if (lead) {
            // Hold back the first tokens until any copied "Buddy:" label can be removed.
            emitted.write(tok);
            if (emitted.length < 12) continue;
            tok = stripSpeaker(emitted.toString());
            emitted
              ..clear()
              ..write(tok);
            lead = false;
            yield tok;
            continue;
          }
          emitted.write(tok);
          yield tok;
        }
        if (lead && emitted.isNotEmpty) {
          final rest = stripSpeaker(emitted.toString());
          emitted
            ..clear()
            ..write(rest);
          yield rest;
        }
        final text = emitted.toString().trim();
        if (stop == StopReason.cancelled) return;
        if (stop == StopReason.none) {
          // Tiny models sometimes refuse harmless questions or say nothing.
          if (text.isEmpty || isRefusal(text)) throw const ReplyUnavailable('empty or refused');
          return;
        }
        if (text.length >= 40) return; // drifted late: keep the useful part
        if (attempt == 1) {
          if (text.isEmpty) throw const ReplyUnavailable('drifted into another language');
          return;
        }
        if (emitted.isNotEmpty) yield resetReply;
        emitted.clear();
      }
    } finally {
      release();
    }
  }
}

/// Always answers, from the wisdom library; the last link of the chain.
class OfflineReplySource implements ReplySource {
  @override
  Stream<String> reply(ReplyRequest r) async* {
    yield offlineReply(r.text, r.found, coding: r.coding);
  }
}

/// Chain of responsibility: asks each source in turn until one answers.
class ReplyChain {
  ReplyChain([List<ReplySource>? sources]) : sources = sources ?? [CloudReplySource(), LocalReplySource(), OfflineReplySource()];
  static final instance = ReplyChain();

  final List<ReplySource> sources;
  int _generation = 0;

  /// Stops every running and queued reply (used by "Clear chat").
  void cancelAll() => _generation++;

  /// Streams the reply; [resetReply] in the stream means "discard what was shown so far".
  Stream<String> reply({required String text, required List<(bool, String)> history, required List<Teaching> found, String notes = ''}) async* {
    final gen = _generation;
    final req = ReplyRequest(text, history, found, () => gen != _generation, notes: notes);
    for (final source in sources) {
      var any = false;
      try {
        await for (final t in source.reply(req)) {
          if (req.cancelled()) return;
          any = true;
          yield t;
        }
        return;
      } catch (e) {
        debugPrint('[Buddy] ${source.runtimeType} unavailable: $e');
        if (req.cancelled()) return;
        if (any) yield resetReply;
      }
    }
  }

  /// Folds [turns] into the memory [notes] with the cloud brain, else the on-device one; null when neither can.
  Future<String?> updateNotes(String notes, List<(bool, String)> turns) async {
    if (turns.isEmpty) return notes;
    final prompt = notesPrompt(TalkSettings.userName, notes, turns);
    const system = 'You keep short, accurate memory notes for a chat assistant. Output only bullet lines.';
    if (CloudBrain.enabled) {
      try {
        final b = StringBuffer();
        await for (final t in CloudBrain.instance.reply(system: system, user: prompt, maxTokens: 400)) {
          b.write(t);
        }
        if (b.isNotEmpty) return cleanNotes(b.toString());
      } catch (_) {}
    }
    final brain = await LocalReplySource(LocalBrain.instance)._pick(false);
    if (brain == null) return null;
    final release = await LocalBrain.instance.lock();
    try {
      final model = await LocalBrain.instance.load(brain);
      final b = StringBuffer();
      var stop = StopReason.none;
      await for (final t in LocalBrain.instance.generate(model, brain, prompt,
          system: system, temperature: 0.2, topK: 20, maxTokens: 260, cancelled: () => false, onStop: (s) => stop = s)) {
        b.write(t);
      }
      final out = cleanNotes(b.toString());
      return stop == StopReason.none && out.isNotEmpty ? out : null;
    } catch (_) {
      return null;
    } finally {
      release();
    }
  }

  /// Loads the main on-device brain in the background so the first reply isn't slow.
  Future<void> warmUp() async {
    for (final m in [TalkSettings.mainBrain, fastBrain]) {
      if (await ModelFiles.has(m)) {
        try {
          await LocalBrain.instance.load(m);
        } catch (_) {}
        return;
      }
    }
  }
}
