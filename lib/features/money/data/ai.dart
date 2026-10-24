import '../../talk/data/cloud_brain.dart';
import '../../talk/data/gemini_brain.dart';
import '../../talk/data/local_brain.dart';
import '../../talk/data/model_files.dart';
import '../../talk/data/openrouter_brain.dart';
import '../../talk/model/brain_model.dart';

/// Asks the AI a one-off question; returns null when unavailable.
typedef AiAsk = Future<String?> Function(String system, String prompt, {int maxTokens});

/// [AiAsk] backed by the cloud brain (within its spend limits); null when it's off, over a limit or offline.
Future<String?> askBuddy(String system, String prompt, {int maxTokens = 700}) async {
  try {
    final b = StringBuffer();
    await for (final t in CloudBrain.instance.reply(system: system, user: prompt, maxTokens: maxTokens)) {
      b.write(t);
    }
    return b.toString().trim();
  } catch (_) {
    return null;
  }
}

/// Free and fast first: Gemini with the user's key (~2 s), then OpenRouter's free models, else the on-device model.
Future<String?> askFree(String system, String prompt, {int maxTokens = 700}) async =>
    await GeminiBrain.instance.ask(system, prompt, maxTokens: maxTokens) ??
    await OpenRouterBrain.instance.ask(system, prompt, maxTokens: maxTokens) ??
    await askOnDevice(system, prompt, maxTokens: maxTokens);

/// [AiAsk] backed by a downloaded on-device model (the smart brain when present): free, private, works offline.
/// Null when no model is downloaded, it drifts, or it takes longer than [limit].
Future<String?> askOnDevice(String system, String prompt, {int maxTokens = 700, Duration limit = const Duration(seconds: 60)}) async {
  BrainModel? brain;
  for (final m in [smartBrain, fastBrain]) {
    if (await ModelFiles.has(m)) {
      brain = m;
      break;
    }
  }
  if (brain == null) return null;
  final release = await LocalBrain.instance.lock();
  try {
    final model = await LocalBrain.instance.load(brain);
    final sw = Stopwatch()..start();
    final b = StringBuffer();
    var stop = StopReason.none;
    await for (final t in LocalBrain.instance.generate(model, brain, prompt,
        system: system, temperature: 0.8, topK: 40, maxTokens: maxTokens, cancelled: () => sw.elapsed > limit, onStop: (s) => stop = s)) {
      b.write(t);
    }
    return stop == StopReason.drifted || b.isEmpty ? null : b.toString().trim();
  } catch (_) {
    return null;
  } finally {
    release();
  }
}
