import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// Encrypts saved passwords with a passphrase only the user knows (PBKDF2-SHA256 → AES-256-GCM), so the cloud
/// copy is unreadable without it. Runs in an isolate: key stretching takes a moment on purpose.
class BackupCrypto {
  static const _rounds = 100000;

  static Future<Map<String, String>> encrypt(String plain, String passphrase) => Isolate.run(() async {
        final rnd = Random.secure();
        final salt = List<int>.generate(16, (_) => rnd.nextInt(256));
        final key = await _key(passphrase, salt);
        final box = await AesGcm.with256bits().encrypt(utf8.encode(plain), secretKey: key);
        return {
          'v': '1',
          'salt': base64Encode(salt),
          'nonce': base64Encode(box.nonce),
          'data': base64Encode(box.cipherText),
          'mac': base64Encode(box.mac.bytes),
        };
      });

  /// Throws [SecretBoxAuthenticationError] when the passphrase is wrong.
  static Future<String> decrypt(Map<String, dynamic> blob, String passphrase) => Isolate.run(() async {
        final key = await _key(passphrase, base64Decode(blob['salt'] as String));
        final box = SecretBox(base64Decode(blob['data'] as String),
            nonce: base64Decode(blob['nonce'] as String), mac: Mac(base64Decode(blob['mac'] as String)));
        return utf8.decode(await AesGcm.with256bits().decrypt(box, secretKey: key));
      });

  static Future<SecretKey> _key(String passphrase, List<int> salt) =>
      Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: _rounds, bits: 256).deriveKeyFromPassword(password: passphrase, nonce: salt);
}
