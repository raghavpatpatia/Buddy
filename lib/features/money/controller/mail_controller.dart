import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/arch/event_bus.dart';
import '../../../core/arch/load_state.dart';
import '../../../core/arch/safe_notifier.dart';
import '../../../core/store.dart';
import '../data/ai.dart';
import '../data/mail_service.dart';
import '../data/read_tracker.dart';
import '../model/mail.dart';

/// What the Mail tab is showing; each mode knows how to load its list.
sealed class MailMode {
  const MailMode();
  Future<List<MailItem>> load();
}

/// Inbox, optionally filtered with a Gmail query (e.g. old promotions).
class InboxMode extends MailMode {
  final int filter;
  const InboxMode(this.filter);
  static const filters = [
    ('Inbox', ''),
    ('Promotions 30d+', 'category:promotions older_than:30d'),
    ('Social 30d+', 'category:social older_than:30d'),
    ('Unread 90d+', 'is:unread older_than:90d'),
  ];
  @override
  Future<List<MailItem>> load() => filter == 0 ? MailService.inbox() : MailService.search(filters[filter].$2);
}

class SearchMode extends MailMode {
  final String query;
  const SearchMode(this.query);
  @override
  Future<List<MailItem>> load() => MailService.search(query);
}

/// Emails sent with read tracking (stored locally, not fetched from the mailbox).
class SentMode extends MailMode {
  const SentMode();
  @override
  Future<List<MailItem>> load() async => const [];
}

/// Mail tab logic: current mode, list loading, multi-select and trashing, read-receipt polling.
class MailController extends SafeNotifier {
  MailController({ReadTracker? tracker}) : tracker = tracker ?? ReadTracker.instance {
    _opens = EventBus.instance.on<MailOpened>().listen((_) => notifyListeners());
    // Last inbox, shown at once while the fresh one loads.
    final cached = Store.getJson(_cacheKey) as List?;
    if (cached != null) items = Ready([for (final j in cached) _decode(j as Map)]);
  }

  static const _cacheKey = 'mail_cache_inbox';
  static Map<String, Object?> _encode(MailItem m) => {'u': m.uid, 'f': m.from, 's': m.subject, 't': m.at?.millisecondsSinceEpoch, 'r': m.seen};
  static MailItem _decode(Map j) =>
      MailItem(j['u'] as int, j['f'] as String, j['s'] as String, j['t'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['t'] as int), j['r'] as bool);

  final ReadTracker tracker;
  late final StreamSubscription<MailOpened> _opens;

  MailMode mode = const InboxMode(0);
  LoadState<List<MailItem>> items = const Idle();
  final selected = <int>{};
  bool polling = false;

  bool get selecting => selected.isNotEmpty;
  List<MailItem> get list => items.data ?? const [];
  int get unread => list.where((m) => !m.seen).length;

  Future<void> show(MailMode m) async {
    mode = m;
    selected.clear();
    if (m is SentMode) return pollOpens();
    await refresh();
  }

  Future<void> refresh() async {
    if (mode is SentMode) return pollOpens();
    items = Loading(items.data);
    notifyListeners();
    try {
      final loaded = await mode.load();
      items = Ready(loaded);
      if (mode case InboxMode(filter: 0)) await Store.setJson(_cacheKey, [for (final m in loaded) _encode(m)]);
    } catch (_) {
      // Keep showing what we had; just say it's not fresh.
      items = Failed('Couldn’t reach your mailbox. Pull to retry.', items.data);
    }
    notifyListeners();
  }

  Future<void> pollOpens() async {
    polling = true;
    notifyListeners();
    try {
      await tracker.poll(notify: false);
    } catch (_) {}
    polling = false;
    notifyListeners();
  }

  void toggle(int uid) {
    selected.contains(uid) ? selected.remove(uid) : selected.add(uid);
    notifyListeners();
  }

  void selectAll() {
    selected.addAll(list.map((m) => m.uid));
    notifyListeners();
  }

  void clearSelection() {
    selected.clear();
    notifyListeners();
  }

  /// Moves the selected emails to Trash; the caller confirms with the user first.
  Future<void> trashSelected() async {
    final uids = selected.toList();
    await MailService.trash(uids);
    _replace(list.where((m) => !uids.contains(m.uid)).toList());
    selected.clear();
  }

  void removeItem(int uid) => _replace(list.where((m) => m.uid != uid).toList());

  void markSeen(MailItem m) => _replace([for (final x in list) x.uid == m.uid ? MailItem(m.uid, m.from, m.subject, m.at, true) : x]);

  void _replace(List<MailItem> l) {
    items = Ready(l);
    notifyListeners();
  }

  @override
  void dispose() {
    _opens.cancel();
    super.dispose();
  }
}

/// Loads one email for the reader and saves its attachments.
class ReaderController extends AsyncController<MailMessage> {
  ReaderController(this.item);
  final MailItem item;
  final downloading = <String>{};

  Future<void> load() => run(() => MailService.read(item.uid), errorText: 'Couldn’t open this email. Check your connection.');

  Future<void> trash() => MailService.trash([item.uid]);

  /// Writes [a] to Download/Buddy (or app storage without all-files access) and returns the file.
  Future<File> save(MailAttachment a) async {
    downloading.add(a.name);
    notifyListeners();
    try {
      final bytes = a.bytes() ?? (throw StateError('empty attachment'));
      final name = a.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      try {
        final dir = await Directory('/storage/emulated/0/Download/Buddy').create(recursive: true);
        return await File('${dir.path}/$name').writeAsBytes(bytes);
      } catch (_) {
        return await File('${(await getApplicationDocumentsDirectory()).path}/$name').writeAsBytes(bytes);
      }
    } finally {
      downloading.remove(a.name);
      notifyListeners();
    }
  }
}

/// Compose logic: attachments (25 MB cap), AI drafting, read tracking and sending.
class ComposeController extends SafeNotifier {
  ComposeController({this._ask = askBuddy});
  final AiAsk _ask;
  static const maxBytes = 24 * 1024 * 1024;

  final files = <(String, Uint8List)>[];
  bool track = ReadTracker.ready && ReadTracker.onByDefault;
  bool drafting = false, sending = false;

  int get totalBytes => files.fold(0, (a, f) => a + f.$2.length);

  /// Recipients in [to] that aren't valid email addresses (comma, semicolon or space separated).
  static List<String> badRecipients(String to) => [
        for (final a in to.split(RegExp(r'[,; ]+')).where((a) => a.isNotEmpty))
          if (!RegExp(r'^[^@\s]+@[^@\s]+\.[a-zA-Z]{2,}$').hasMatch(a)) a,
      ];

  /// Adds a file; returns false when it would exceed the size cap.
  bool attach(String name, Uint8List bytes) {
    if (totalBytes + bytes.length > maxBytes) return false;
    files.add((name, bytes));
    notifyListeners();
    return true;
  }

  void detach((String, Uint8List) f) {
    files.remove(f);
    notifyListeners();
  }

  void setTrack(bool v) {
    track = v;
    notifyListeners();
  }

  /// Returns (subject, body) drafted by the AI, or null when the cloud brain is unavailable.
  Future<(String?, String)?> draft(String request, String to) async {
    drafting = true;
    notifyListeners();
    final name = Store.profile['name'] as String? ?? '';
    final r = await _ask(
      'You write clear, warm, professional emails. Output exactly: first line "Subject: …", a blank line, then the body signed "$name". No markdown.',
      'Recipient: ${to.isEmpty ? 'unknown' : to}\nRequest: $request${files.isEmpty ? '' : '\nAttached: ${files.map((f) => f.$1).join(', ')}'}',
      maxTokens: 700,
    );
    drafting = false;
    notifyListeners();
    if (r == null) return null;
    final lines = r.split('\n');
    return lines.first.toLowerCase().startsWith('subject:') ? (lines.first.substring(8).trim(), lines.skip(1).join('\n').trim()) : (null, r);
  }

  /// Sends the email (with tracking pixel when on) and records it for read receipts.
  Future<void> send({required String to, required String subject, required String body}) async {
    sending = true;
    notifyListeners();
    try {
      final id = track ? ReadTracker.newId() : null;
      await MailService.send(to: to, subject: subject, body: body, attachments: files, pixelUrl: id == null ? null : ReadTracker.pixelUrl(id));
      if (id != null) await ReadTracker.instance.recordSent(id, to.trim(), subject.trim().isEmpty ? '(no subject)' : subject.trim());
    } finally {
      sending = false;
      notifyListeners();
    }
  }
}
