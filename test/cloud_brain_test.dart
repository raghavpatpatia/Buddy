import 'package:buddy_app/core/store.dart';
import 'package:buddy_app/features/talk/data/cloud_brain.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> setUpCloud(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues({'flutter.cloud_on': true, ...prefs.map((k, v) => MapEntry('flutter.$k', v))});
    FlutterSecureStorage.setMockInitialValues({'bedrock_api_key': 'test-key'});
    await Store.init();
  }

  test('never sends a request that could cross the daily limit', () async {
    await setUpCloud({'cloud_daily_usd': 0.01, 'cloud_spent_${dayKey()}': 0.0});
    // Opus worst case for 1024 output tokens ≈ $0.0225 > $0.01 → refused before any network call.
    await expectLater(CloudBrain.instance.reply(system: 's', user: 'hi', maxTokens: 1024).toList(), throwsA(isA<CloudUnavailable>()));
    expect(CloudBrain.instance.lastStatus, contains('Daily limit'));
    expect(CloudBrain.spentToday, 0); // nothing reserved
  });

  test('monthly limit is checked too', () async {
    await setUpCloud({'cloud_monthly_usd': 1.0, 'cloud_spent_${dayKey().substring(0, 7)}': 0.99});
    await expectLater(CloudBrain.instance.reply(system: 's', user: 'hi', maxTokens: 1024).toList(), throwsA(isA<CloudUnavailable>()));
    expect(CloudBrain.instance.lastStatus, contains('Monthly limit'));
  });

  test('off means off', () async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
    await expectLater(CloudBrain.instance.reply(system: 's', user: 'hi', maxTokens: 1024).toList(), throwsA(isA<CloudUnavailable>()));
  });
}
