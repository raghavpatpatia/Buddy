import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' show Color;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../../core/arch/event_bus.dart';
import '../../../core/arch/repository.dart';
import '../../../core/store.dart';
import '../model/mail.dart';
import 'money_store.dart';

/// Mailsuite-style read receipts: an invisible image per sent email, served and logged by the user's AWS tracker.
class ReadTracker {
  ReadTracker(this._sent);
  static ReadTracker get instance => ReadTracker(MoneyStore.instance.tracked);

  final Repository<String, TrackedMail> _sent;
  static const _storage = FlutterSecureStorage();
  static const _prefetchWindow = Duration(seconds: 30);
  static const _keep = 200;

  static String? get endpoint => Store.raw.getString('track_url');
  static bool get ready => endpoint != null;
  static bool get onByDefault => Store.raw.getBool('track_default') ?? true;

  /// Imports `Download/buddy_tracker.txt` ("url|key" from the deploy script) once, then deletes it.
  static Future<void> importSetupFile() async {
    final f = File('/storage/emulated/0/Download/buddy_tracker.txt');
    try {
      if (!f.existsSync()) return;
      final parts = f.readAsStringSync().trim().split('|');
      if (parts.length == 2 && parts[0].startsWith('https://')) await configure(parts[0], parts[1]);
      f.deleteSync();
    } catch (_) {}
  }

  static Future<void> configure(String url, String key) async {
    await Store.raw.setString('track_url', url.replaceAll(RegExp(r'/+$'), ''));
    await _storage.write(key: 'track_key', value: key);
  }

  static String newId() {
    final r = Random.secure();
    return List.generate(24, (_) => '0123456789abcdefghijklmnopqrstuvwxyz'[r.nextInt(36)]).join();
  }

  static String pixelUrl(String id) => '$endpoint/o/$id.gif';

  /// Newest first.
  List<TrackedMail> get sent => _sent.all.toList()..sort((a, b) => b.sentAt.compareTo(a.sentAt));

  Future<void> recordSent(String id, String to, String subject) async {
    await _sent.reload();
    if (_sent.length >= _keep) await _sent.remove(sent.last.id);
    await _sent.put(TrackedMail(id, to, subject, DateTime.now(), const []));
  }

  /// Fetches opens for emails sent in the last 30 days; notifies and emits [MailOpened] for new ones.
  Future<int> poll({bool notify = true}) async {
    final url = endpoint;
    if (url == null) return 0;
    await _sent.reload();
    final all = _sent.all.toList();
    final recent = all.where((t) => DateTime.now().difference(t.sentAt).inDays <= 30).toList();
    if (recent.isEmpty) return 0;
    final key = await _storage.read(key: 'track_key');
    final r = await http.get(Uri.parse('$url/s?ids=${recent.map((t) => t.id).take(100).join(',')}'), headers: {'x-buddy-key': key ?? ''}).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw Exception('Tracker HTTP ${r.statusCode}');
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    var fresh = 0;
    final updated = <TrackedMail>[];
    for (final t in all) {
      final raw = (data[t.id] as List?)?.cast<Map>();
      if (raw == null) {
        updated.add(t);
        continue;
      }
      final opens = [
        for (final o in raw)
          if (DateTime.fromMillisecondsSinceEpoch(o['t'] as int).isAfter(t.sentAt.add(_prefetchWindow))) DateTime.fromMillisecondsSinceEpoch(o['t'] as int),
      ]..sort();
      final gmail = raw.isNotEmpty && (raw.last['ua'] as String? ?? '').contains('GoogleImageProxy');
      if (opens.length > t.opens.length) {
        fresh++;
        if (notify) await _notify(t, opens.last, first: t.opens.isEmpty);
        EventBus.instance.emit(MailOpened(t.id));
      }
      updated.add(TrackedMail(t.id, t.to, t.subject, t.sentAt, opens, viaGmail: gmail));
    }
    await _sent.putAll(updated);
    return fresh;
  }

  static Future<void> _notify(TrackedMail t, DateTime at, {required bool first}) async {
    final n = FlutterLocalNotificationsPlugin();
    await n.initialize(settings: const InitializationSettings(android: AndroidInitializationSettings('@drawable/ic_stat_buddy')));
    final h = at.hour % 12 == 0 ? 12 : at.hour % 12;
    await n.show(
      id: 2000 + t.id.hashCode % 1000,
      title: first ? '👀 ${t.to} opened your email' : '👀 ${t.to} opened it again',
      body: '“${t.subject}” · $h:${at.minute.toString().padLeft(2, '0')} ${at.hour < 12 ? 'AM' : 'PM'}',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails('buddy_mail_open', 'Email opened', channelDescription: 'When someone opens an email you sent with Buddy', importance: Importance.defaultImportance, color: Color(0xFF3FB8FF)),
      ),
    );
  }
}
