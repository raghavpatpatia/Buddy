import 'package:buddy_app/features/backup/data/backup_crypto.dart';
import 'package:buddy_app/features/backup/data/cloud_backup.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('phone-specific settings are never backed up', () {
    for (final k in ['setup_done', 'brain_ok_gemma', 'nav_maps', 'steps_base', 'steps_last_raw', 'backup_last', 'clean_report']) {
      expect(CloudBackup.backedUp(k), isFalse, reason: k);
    }
    for (final k in ['xp', 'chat', 'profile', 'streak', 'money_budget', 'nav_voice', 'steps_hist']) {
      expect(CloudBackup.backedUp(k), isTrue, reason: k);
    }
  });

  test('preferences survive a snapshot → JSON → restore round trip with their types', () async {
    SharedPreferences.setMockInitialValues({
      'xp': 420, 'streak': 7, 'talk_robot': false, 'water': 2.5, 'profile': '{"name":"Raghav"}',
      'places': <String>['home', 'office'], 'setup_done': true, 'brain_ok_x': true,
    });
    final p = await SharedPreferences.getInstance();
    final snap = CloudBackup.snapshot(p);
    expect(snap.keys, isNot(contains('setup_done')));
    expect(snap.keys, isNot(contains('brain_ok_x')));

    // As if it went through Firestore as JSON and landed on a fresh install.
    final wire = Map<String, dynamic>.from(snap.map((k, v) => MapEntry(k, List<dynamic>.from(v))));
    SharedPreferences.setMockInitialValues({});
    final fresh = await SharedPreferences.getInstance();
    await fresh.clear();
    await CloudBackup.applySnapshot(fresh, wire);
    expect(fresh.getInt('xp'), 420);
    expect(fresh.getBool('talk_robot'), false);
    expect(fresh.getDouble('water'), 2.5);
    expect(fresh.getString('profile'), '{"name":"Raghav"}');
    expect(fresh.getStringList('places'), ['home', 'office']);
    expect(fresh.getBool('setup_done'), isNull);
    expect(CloudBackup.fingerprint(CloudBackup.snapshot(fresh), 'h'), CloudBackup.fingerprint(snap, 'h'));
  });

  test('passwords encrypt with the passphrase and only decrypt with it', () async {
    const secrets = '{"mail_password":"hunter2","sa_key":"AKIA…"}';
    final blob = await BackupCrypto.encrypt(secrets, 'correct horse battery');
    expect(blob.values.join(), isNot(contains('hunter2')));
    expect(await BackupCrypto.decrypt(blob, 'correct horse battery'), secrets);
    await expectLater(BackupCrypto.decrypt(blob, 'wrong passphrase'), throwsA(isA<SecretBoxAuthenticationError>()));
    // Fresh salt and nonce every time.
    expect((await BackupCrypto.encrypt(secrets, 'correct horse battery'))['data'], isNot(blob['data']));
  });
}
