import '../../../core/store.dart';
import '../model/brain_model.dart';

/// Talk preferences, kept in one place (same storage keys as before).
class TalkSettings {
  static BrainModel get mainBrain => Store.raw.getString('brain_main') == smartBrain.id ? smartBrain : fastBrain;
  static Future<void> setMainBrain(BrainModel m) => Store.raw.setString('brain_main', m.id);

  /// The 1.5B coder is accurate but ~3 words/s on a Dimensity 6100+; opt-in only.
  static bool get useCoder => Store.raw.getBool('use_coder') ?? false;
  static Future<void> setUseCoder(bool v) => Store.raw.setBool('use_coder', v);

  static bool get hinglish => Store.raw.getString('talk_lang') == 'hinglish';
  static String get language => Store.raw.getString('talk_lang') ?? 'en';
  static Future<void> setLanguage(String v) => Store.raw.setString('talk_lang', v);

  static bool get speakReplies => Store.raw.getBool('talk_speak') ?? true;
  static Future<void> setSpeakReplies(bool v) => Store.raw.setBool('talk_speak', v);

  static bool get robotVoice => Store.raw.getBool('talk_robot') ?? true;
  static Future<void> setRobotVoice(bool v) => Store.raw.setBool('talk_robot', v);

  static String get voiceLocale => Store.raw.getString('talk_locale') ?? 'en_IN';
  static Future<void> setVoiceLocale(String v) => Store.raw.setString('talk_locale', v);

  static String get userName => Store.profile['name'] as String? ?? 'friend';
}
