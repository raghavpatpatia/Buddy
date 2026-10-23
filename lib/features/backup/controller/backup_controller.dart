import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' show SecretBoxAuthenticationError;
import 'package:flutter/widgets.dart';

import '../../../core/arch/safe_notifier.dart';
import '../../../core/store.dart';
import '../data/backup_crypto.dart';
import '../data/cloud_backup.dart';

/// App-wide cloud backup: signs in with Google, backs up automatically shortly after anything changes (and when
/// Buddy goes to the background), and restores onto a new install.
class BackupController extends SafeNotifier with WidgetsBindingObserver {
  static final instance = BackupController._();
  BackupController._();

  bool busy = false;
  String? error;
  BackupInfo? cloud;
  bool hasPassphrase = false;
  Timer? _timer;
  String? _secretsHash;
  Map<String, String>? _encrypted;

  String? get email => CloudBackup.user?.email;

  /// Automatic backups are allowed on this install. Off on a fresh install that finds an existing backup, until
  /// the user restores it or chooses to replace it, so an empty new install can never overwrite good data.
  bool get armed => Store.raw.getBool('backup_armed') == true;

  /// Signed in, a backup exists, and this install hasn't restored or replaced it yet.
  bool get needsChoice => signedIn && !armed && cloud != null;
  bool get signedIn => CloudBackup.user != null;
  DateTime? get lastBackup {
    final ms = Store.raw.getInt('backup_last');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Call once at app start, after [CloudBackup.init].
  Future<void> start() async {
    hasPassphrase = (await CloudBackup.secure.read(key: CloudBackup.passphraseKey)) != null;
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => backupIfChanged());
    notifyListeners();
    if (signedIn) unawaited(refreshInfo());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) unawaited(backupIfChanged());
  }

  Future<T?> _run<T>(Future<T> Function() job) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      return await job();
    } catch (e) {
      debugPrint('[Backup] $e');
      error = e is SecretBoxAuthenticationError ? 'Wrong passphrase.' : '$e';
      return null;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> signIn() async {
    final ok = await _run(() async {
          await CloudBackup.signIn();
          await refreshInfo();
          return true;
        }) ??
        false;
    // Nothing in the cloud yet: this phone's data is the backup.
    if (ok && cloud == null) {
      await Store.raw.setBool('backup_armed', true);
      unawaited(backupNow());
    }
    return ok;
  }

  Future<void> signOut() async {
    await CloudBackup.signOut();
    cloud = null;
    notifyListeners();
  }

  Future<void> refreshInfo() async {
    final u = CloudBackup.user;
    if (u == null) return;
    try {
      cloud = await CloudBackup.info(u.uid);
      notifyListeners();
    } catch (e) {
      debugPrint('[Backup] info: $e');
    }
  }

  /// The passphrase that protects saved passwords; kept on this phone so backups can run on their own.
  Future<void> setPassphrase(String p) async {
    await CloudBackup.secure.write(key: CloudBackup.passphraseKey, value: p);
    hasPassphrase = true;
    _secretsHash = null;
    notifyListeners();
    unawaited(backupNow());
  }

  /// Backs up when something changed since the last upload (or a day has passed).
  Future<void> backupIfChanged() async {
    if (!signedIn || busy || !armed) return;
    final last = lastBackup;
    if (last != null && DateTime.now().difference(last).inSeconds < 20) return;
    final (snap, secretsHash) = await _collect();
    final fp = CloudBackup.fingerprint(snap, secretsHash);
    final stale = last == null || DateTime.now().difference(last).inHours >= 24;
    if (fp != Store.raw.getString('backup_fp') || stale) await backupNow();
  }

  Future<(Map<String, List<Object>>, String)> _collect() async {
    final secrets = await CloudBackup.secrets();
    return (CloudBackup.snapshot(Store.raw), sha256.convert(utf8.encode(jsonEncode(secrets))).toString());
  }

  /// Uploads this phone's data now. Also how the user chooses to replace an existing backup.
  Future<void> backupNow() => _run(() async {
        final u = CloudBackup.user;
        if (u == null) return;
        await Store.raw.setBool('backup_armed', true);
        final snap = CloudBackup.snapshot(Store.raw);
        final secrets = await CloudBackup.secrets();
        final secretsHash = sha256.convert(utf8.encode(jsonEncode(secrets))).toString();
        final pass = await CloudBackup.secure.read(key: CloudBackup.passphraseKey);
        // Encrypting is slow on purpose, so only when passwords changed.
        if (pass != null && secrets.isNotEmpty && secretsHash != _secretsHash) {
          _encrypted = await BackupCrypto.encrypt(jsonEncode(secrets), pass);
          _secretsHash = secretsHash;
        }
        await CloudBackup.upload(u.uid, snap, pass == null || secrets.isEmpty ? null : _encrypted, 'Android phone');
        await Store.raw.setInt('backup_last', DateTime.now().millisecondsSinceEpoch);
        await Store.raw.setString('backup_fp', CloudBackup.fingerprint(snap, secretsHash));
        cloud = await CloudBackup.info(u.uid);
      });

  /// Restores everything from the cloud. Passwords need [passphrase] when the backup has them; it is then kept
  /// on this phone for future backups. Returns true on success.
  Future<bool> restore({String? passphrase}) async => await _run(() async {
        final u = CloudBackup.user;
        if (u == null) return false;
        final (snap, secrets) = await CloudBackup.download(u.uid);
        // Decrypt first, so a wrong passphrase changes nothing.
        Map<String, dynamic>? plain;
        if (secrets != null && passphrase != null && passphrase.isNotEmpty) {
          plain = jsonDecode(await BackupCrypto.decrypt(secrets, passphrase)) as Map<String, dynamic>;
        }
        await CloudBackup.applySnapshot(Store.raw, snap);
        if (plain != null) {
          await CloudBackup.restoreSecrets(plain);
          await CloudBackup.secure.write(key: CloudBackup.passphraseKey, value: passphrase!);
          hasPassphrase = true;
        }
        await Store.init();
        await Store.raw.setString('backup_fp', '');
        await Store.raw.setBool('backup_armed', true);
        return true;
      }) ??
      false;

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
