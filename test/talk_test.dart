import 'package:buddy_app/core/store.dart';
import 'package:buddy_app/features/talk/brain.dart';
import 'package:buddy_app/features/talk/wisdom.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
  });

  test('understands Hinglish feelings and topics', () {
    final a = understand('Mujhe bahut tension hai exam ki');
    expect(a.topics, containsAll(['anxiety', 'learning']));
    expect(a.mood, Mood.anxious);
    expect(understand('Aaj bahut gussa aa raha hai boss pe').mood, Mood.angry);
    expect(understand('Paise kaise bachaun?').topics, contains('saving'));
  });

  test('retrieves relevant, real teachings', () {
    expect(retrieve('paise kaise bachaun').first.tags, contains('saving'));
    expect(retrieve('gussa control kaise karun').first.tags, contains('anger'));
    expect(retrieve('reels dekhna band nahi hota, focus nahi hai').first.tags, anyOf(contains('scroll'), contains('focus')));
    expect(retrieve('dada ji ki death ho gayi').first.tags, anyOf(contains('death'), contains('grief')));
    // Avoids repeating what was just shown
    final first = retrieve('motivation chahiye').first;
    expect(retrieve('motivation chahiye', recent: {first.id}).first.id, isNot(first.id));
  });

  test('every teaching is complete', () {
    for (final t in teachings) {
      expect(t.src, isNotEmpty);
      expect(t.mean.length, greaterThan(20), reason: t.id);
      expect(t.act, isNotEmpty, reason: t.id);
      expect(t.tags, isNotEmpty, reason: t.id);
    }
  });

  test('routes coding questions to the coder', () {
    expect(isCodingQuestion('Flutter mein setState vs Provider?'), isTrue);
    expect(isCodingQuestion('Unity me null reference exception aa raha hai'), isTrue);
    expect(isCodingQuestion('void main() { print(1); }'), isTrue);
    expect(isCodingQuestion('Mann ashant hai'), isFalse);
    expect(isCodingQuestion('Paise kaise bachaun?'), isFalse);
  });

  test('offline reply quotes the real source and gives an action', () {
    final found = retrieve('bahut stress hai kaam ka');
    final r = offlineReply('bahut stress hai kaam ka', found);
    expect(r, contains(found.first.src));
    expect(r, contains('Try today'));
  });

  test('detects drift into Chinese/Japanese/Korean but not English, Hindi or emoji', () {
    for (final t in ['这是', '你好', 'こんにちは', '안녕하세요', '，']) {
      expect(cjkText.hasMatch(t), isTrue, reason: t);
    }
    for (final t in ['Take a deep breath 🙏', 'karmaṇy evādhikāras te', 'मन शांत करो', '“quotes” — dash']) {
      expect(cjkText.hasMatch(t), isFalse, reason: t);
    }
  });

  test('offline coding reply no longer blames a missing coding brain', () {
    final r = offlineReply('Flutter setState not updating', const [], coding: true);
    expect(r.toLowerCase(), isNot(contains('coding brain')));
  });
}
