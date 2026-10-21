import 'dart:async';

import '../../../core/arch/load_state.dart';
import '../../../core/arch/safe_notifier.dart';
import '../data/local_brain.dart';
import '../data/model_files.dart';
import '../data/prompts.dart';
import '../data/reply_chain.dart';
import '../data/talk_settings.dart';
import '../data/wisdom.dart';
import '../model/brain_model.dart';

/// Model downloads that keep running (and reporting) after the screen closes.
class ModelDownloads extends SafeNotifier {
  ModelDownloads._();
  static final instance = ModelDownloads._();

  final progress = <String, double>{};
  final errors = <String, String>{};
  final ready = <String, bool>{};

  bool downloading(BrainModel m) => progress.containsKey(m.id);

  Future<void> refresh() async {
    for (final m in allBrains) {
      ready[m.id] = await ModelFiles.has(m);
    }
    notifyListeners();
  }

  Future<void> start(BrainModel m) async {
    if (downloading(m)) return;
    progress[m.id] = 0;
    errors.remove(m.id);
    notifyListeners();
    try {
      await ModelFiles.download(m, (p) {
        progress[m.id] = p;
        notifyListeners();
      });
    } catch (e) {
      errors[m.id] = 'Download paused (${e is TimeoutException ? 'timeout' : 'network'}). Tap to resume.';
    } finally {
      progress.remove(m.id);
      await refresh();
    }
  }

  Future<void> delete(BrainModel m) async {
    await LocalBrain.instance.unload(m);
    await ModelFiles.delete(m);
    await refresh();
  }
}

/// Brain settings sheet logic: which brain, coder, language, voice and a speed test.
class BrainSettingsController extends SafeNotifier {
  final downloads = ModelDownloads.instance;
  LoadState<String> speedTest = const Idle();

  BrainSettingsController() {
    downloads.addListener(notifyListeners);
    downloads.refresh();
  }

  BrainModel get mainBrain => TalkSettings.mainBrain;
  bool get useCoder => TalkSettings.useCoder;
  String get language => TalkSettings.language;
  bool get robotVoice => TalkSettings.robotVoice;
  String get voiceLocale => TalkSettings.voiceLocale;

  Future<void> setMainBrain(String id) async {
    await TalkSettings.setMainBrain(allBrains.firstWhere((m) => m.id == id));
    notifyListeners();
  }

  Future<void> setUseCoder(bool v) async {
    await TalkSettings.setUseCoder(v);
    notifyListeners();
  }

  Future<void> setLanguage(String v) async {
    await TalkSettings.setLanguage(v);
    notifyListeners();
  }

  Future<void> setRobotVoice(bool v) async {
    await TalkSettings.setRobotVoice(v);
    notifyListeners();
  }

  Future<void> setVoiceLocale(String v) async {
    await TalkSettings.setVoiceLocale(v);
    notifyListeners();
  }

  /// Times one life and one code question through the reply chain (not saved to the chat).
  Future<void> runSpeedTest() async {
    speedTest = const Loading();
    notifyListeners();
    final lines = <String>[];
    for (final (label, q) in [('Life', 'I feel stressed about work'), ('Code', 'In Dart, how do I reverse a list?')]) {
      final sw = Stopwatch()..start();
      int? first;
      await for (final _ in ReplyChain.instance.reply(text: q, history: const [], found: isCodingQuestion(q) ? const [] : retrieve(q))) {
        first ??= sw.elapsedMilliseconds;
      }
      lines.add('$label: first words ${((first ?? sw.elapsedMilliseconds) / 1000).toStringAsFixed(1)} s · done ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} s');
    }
    speedTest = Ready(lines.join('\n'));
    notifyListeners();
  }

  @override
  void dispose() {
    downloads.removeListener(notifyListeners);
    super.dispose();
  }
}
