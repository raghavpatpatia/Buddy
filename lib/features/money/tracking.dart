import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../core/store.dart';

/// One email sent with read tracking.
class TrackedMail {
  final String id, to, subject;
  final DateTime sentAt;
  final List<DateTime> opens;
  final bool viaGmail; // last open came through Gmail's image proxy
  const TrackedMail(this.id, this.to, this.subject, this.sentAt, this.opens, {this.viaGmail = false});

  Map<String, dynamic> toJson() => {'id': id, 'to': to, 's': subject, 't': sentAt.millisecondsSinceEpoch, 'o': [for (final o in opens) o.millisecondsSinceEpoch], 'g': viaGmail};
  factory TrackedMail.fromJson(Map j) => TrackedMail(j['id'], j['to'], j['s'], DateTime.fromMillisecondsSinceEpoch(j['t']), [for (final o in (j['o'] as List)) DateTime.fromMillisecondsSinceEpoch(o)], viaGmail: j['g'] ?? false);
}

/// Mailsuite-style open tracking on the user's own AWS (Lambda + DynamoDB): an invisible 1×1 image per email.
/// Self-opens are avoided because Buddy's reader blocks tracking images, and opens in the first
/// [_prefetchWindow] after sending (mail scanners / prefetchers) are ignored.
class MailTracker {
  static const _storage = FlutterSecureStorage();
  static const _prefetchWindow = Duration(seconds: 30);
  static final changed = ValueNotifier(0);

  static String? get endpoint => Store.raw.getString('track_url');
  static bool get ready => endpoint != null;
  static bool get onByDefault => Store.raw.getBool('track_default') ?? true;

  /// Picks up `Download/buddy_tracker.txt` ("url|key", written by the deploy script) once, then deletes it.
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
    changed.value++;
  }

  static String newId() {
    final r = Random.secure();
    return List.generate(24, (_) => '0123456789abcdefghijklmnopqrstuvwxyz'[r.nextInt(36)]).join();
  }

  static String pixelUrl(String id) => '$endpoint/o/$id.gif';

  static List<TrackedMail> get sent => [for (final e in (jsonDecode(Store.raw.getString('track_sent') ?? '[]') as List)) TrackedMail.fromJson(e)];
  static Future<void> _save(List<TrackedMail> l) async {
    await Store.raw.setString('track_sent', jsonEncode([for (final t in l) t.toJson()]));
    changed.value++;
  }

  static Future<void> recordSent(String id, String to, String subject) async => _save([TrackedMail(id, to, subject, DateTime.now(), const []), ...sent].take(200).toList());

  /// Fetches new opens for emails sent in the last 30 days; notifies for each newly opened email.
  static Future<int> poll({bool notify = true}) async {
    final url = endpoint;
    if (url == null) return 0;
    final all = sent;
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
      }
      updated.add(TrackedMail(t.id, t.to, t.subject, t.sentAt, opens, viaGmail: gmail));
    }
    await _save(updated);
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
        android: AndroidNotificationDetails('buddy_mail_open', 'Email opened', channelDescription: 'When someone opens an email you sent with Buddy', importance: Importance.defaultImportance),
      ),
    );
  }
}
