import 'package:flutter_tts/flutter_tts.dart';

import '../../../core/store.dart';
import '../../talk/data/robot_voice.dart';
import '../../talk/data/talk_settings.dart';

/// Spoken directions in Buddy's voice (the shadow voice when it's on in Talk settings).
class NavVoice {
  static bool get enabled => Store.raw.getBool('nav_voice') ?? true;
  static Future<void> setEnabled(bool v) => Store.raw.setBool('nav_voice', v);

  final _tts = FlutterTts();
  late final _voice = RobotVoice(_tts)..robotic = TalkSettings.robotVoice;
  bool _ready = false;

  Future<void> say(String text) async {
    if (!enabled) return;
    if (!_ready) {
      _ready = true;
      await _tts.setLanguage(TalkSettings.voiceLocale.replaceAll('_', '-'));
    }
    await _voice.speak(text);
  }

  Future<void> stop() => _voice.stop();

  void dispose() => _voice.dispose();
}
