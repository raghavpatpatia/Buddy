import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What a backup in the cloud looks like, before downloading it.
class BackupInfo {
  final DateTime? at;
  final String device;
  final bool hasSecrets;
  const BackupInfo(this.at, this.device, this.hasSecrets);
}

/// Buddy's data in the user's own Firebase project (Firestore, free Spark plan): every preference under
/// users/{uid}/backup, readable only by that signed-in user (see firestore.rules). Saved passwords are only ever
/// uploaded encrypted with the user's passphrase.
class CloudBackup {
  static bool _ready = false;
  static const secure = FlutterSecureStorage();

  /// Where the passphrase is kept on this phone, so automatic backups can encrypt passwords.
  static const passphraseKey = 'backup_passphrase';

  /// Settings tied to this phone (files, sensors, permissions, the backup itself) that must not move to another
  /// install: downloaded AI models and maps, raw step-counter readings, storage scan results, setup.
  static bool backedUp(String key) =>
      !key.startsWith('backup_') &&
      !key.startsWith('brain_ok_') &&
      !const {'setup_done', 'nav_maps', 'nav_last_region', 'steps_base', 'steps_last_raw', 'clean_report', 'clean_scan_ms', 'mail_cache_inbox'}.contains(key);

  static Future<void> init() async {
    try {
      await Firebase.initializeApp();
      _ready = true;
    } catch (e) {
      debugPrint('[Backup] Firebase unavailable: $e');
    }
  }

  static bool get ready => _ready;
  static User? get user => _ready ? FirebaseAuth.instance.currentUser : null;

  /// Google sign-in in a browser tab (no extra sign-in package).
  static Future<User?> signIn() async => (await FirebaseAuth.instance.signInWithProvider(GoogleAuthProvider())).user;
  static Future<void> signOut() => FirebaseAuth.instance.signOut();

  static DocumentReference<Map<String, dynamic>> _doc(String uid) => FirebaseFirestore.instance.doc('users/$uid/backup/latest');

  // ---------- Preferences ----------

  /// Every backed-up preference as {key: [type, value]}.
  static Map<String, List<Object>> snapshot(SharedPreferences p) {
    final out = <String, List<Object>>{};
    for (final k in p.getKeys().toList()..sort()) {
      if (!backedUp(k)) continue;
      final v = p.get(k);
      final t = switch (v) { bool() => 'b', int() => 'i', double() => 'd', String() => 's', List() => 'l', _ => null };
      if (t != null) out[k] = [t, v!];
    }
    return out;
  }

  /// Hash of a snapshot, to upload only when something changed.
  static String fingerprint(Map<String, List<Object>> snap, String secretsHash) =>
      sha256.convert(utf8.encode('${jsonEncode(snap)}|$secretsHash')).toString();

  static Future<void> applySnapshot(SharedPreferences p, Map<String, dynamic> snap) async {
    for (final MapEntry(key: k, value: e) in snap.entries) {
      if (!backedUp(k)) continue;
      final v = (e as List)[1];
      switch (e[0]) {
        case 'b':
          await p.setBool(k, v as bool);
        case 'i':
          await p.setInt(k, (v as num).toInt());
        case 'd':
          await p.setDouble(k, (v as num).toDouble());
        case 's':
          await p.setString(k, v as String);
        case 'l':
          await p.setStringList(k, (v as List).cast<String>());
      }
    }
  }

  // ---------- Saved passwords ----------

  /// All secure-storage secrets except the passphrase itself.
  static Future<Map<String, String>> secrets() async => Map.of(await secure.readAll())..remove(passphraseKey);

  static Future<void> restoreSecrets(Map<String, dynamic> s) async {
    for (final e in s.entries) {
      await secure.write(key: e.key, value: e.value as String);
    }
  }

  // ---------- Cloud ----------

  // Firestore documents are capped at 1 MB; the data is split into ~250k-character parts (≤ 750 KB in UTF-8).
  static const _part = 250000;

  static Future<void> upload(String uid, Map<String, List<Object>> snap, Map<String, String>? encryptedSecrets, String device) async {
    final text = jsonEncode(snap);
    final parts = [for (var i = 0; i < text.length; i += _part) text.substring(i, (i + _part).clamp(0, text.length))];
    final doc = _doc(uid);
    final old = (await doc.get()).data()?['parts'] as int? ?? 0;
    final batch = FirebaseFirestore.instance.batch();
    for (var i = 0; i < parts.length; i++) {
      batch.set(doc.collection('parts').doc('$i'), {'data': parts[i]});
    }
    for (var i = parts.length; i < old; i++) {
      batch.delete(doc.collection('parts').doc('$i'));
    }
    batch.set(doc, {
      'v': 1,
      'at': FieldValue.serverTimestamp(),
      'device': device,
      'parts': parts.length,
      'secrets': encryptedSecrets,
    });
    await batch.commit();
  }

  static Future<BackupInfo?> info(String uid) async {
    final d = (await _doc(uid).get()).data();
    if (d == null) return null;
    return BackupInfo((d['at'] as Timestamp?)?.toDate(), d['device'] as String? ?? '', d['secrets'] != null);
  }

  /// (preferences snapshot, encrypted passwords or null).
  static Future<(Map<String, dynamic>, Map<String, dynamic>?)> download(String uid) async {
    final doc = _doc(uid);
    final d = (await doc.get()).data();
    if (d == null) throw StateError('No backup found');
    final buf = StringBuffer();
    for (var i = 0; i < (d['parts'] as int); i++) {
      buf.write((await doc.collection('parts').doc('$i').get()).data()!['data'] as String);
    }
    return (jsonDecode(buf.toString()) as Map<String, dynamic>, (d['secrets'] as Map?)?.cast<String, dynamic>());
  }
}
