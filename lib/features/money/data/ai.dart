import '../../talk/data/cloud_brain.dart';

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
