import 'dart:convert';

import 'package:enough_mail/enough_mail.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/store.dart';
import 'ledger.dart';
import 'parse.dart';

/// The email account set in Settings: address in prefs, app password encrypted in the Android Keystore.
class MailAccount {
  static const _storage = FlutterSecureStorage();
  static String? _password;

  static String? get address => Store.raw.getString('mail_address');
  static bool get linked => address != null;
  static bool get scanBankEmails => Store.raw.getBool('mail_scan_bank') ?? true;
  static bool get isGmail => (address ?? '').toLowerCase().endsWith('@gmail.com') || (address ?? '').toLowerCase().endsWith('@googlemail.com');

  /// (imap host, smtp host) for common providers; custom domains default to Gmail (Google Workspace).
  static (String, String) get hosts {
    final d = (address ?? '').split('@').last.toLowerCase();
    if (d.contains('outlook') || d.contains('hotmail') || d.contains('live.')) return ('outlook.office365.com', 'smtp.office365.com');
    if (d.contains('yahoo')) return ('imap.mail.yahoo.com', 'smtp.mail.yahoo.com');
    if (d.contains('zoho')) return ('imap.zoho.in', 'smtp.zoho.in');
    return ('imap.gmail.com', 'smtp.gmail.com');
  }

  static Future<String?> password() async => _password ??= await _storage.read(key: 'mail_password');

  /// Verifies the login before saving anything.
  static Future<void> link(String addr, String appPassword) async {
    final pass = appPassword.replaceAll(' ', '');
    await Store.raw.setString('mail_address', addr.trim());
    _password = pass;
    try {
      final c = await MailService._imap();
      await c.logout();
    } catch (_) {
      await Store.raw.remove('mail_address');
      _password = null;
      rethrow;
    }
    await _storage.write(key: 'mail_password', value: pass);
  }

  static Future<void> unlink() async {
    await Store.raw.remove('mail_address');
    await _storage.delete(key: 'mail_password');
    _password = null;
  }
}

/// A row in the Mail tab (shown on the phone only; never sent to any AI).
class MailItem {
  final int uid;
  final String from, subject;
  final DateTime? at;
  final bool seen;
  const MailItem(this.uid, this.from, this.subject, this.at, this.seen);
}

class MailService {
  static Future<ImapClient> _imap() async {
    final c = ImapClient(isLogEnabled: false, defaultResponseTimeout: const Duration(seconds: 30));
    await c.connectToServer(MailAccount.hosts.$1, 993, isSecure: true);
    await c.login(MailAccount.address!, (await MailAccount.password())!);
    _inboxCount = (await c.selectInbox()).messagesExists;
    return c;
  }

  static int _inboxCount = 0;

  static Future<T> _with<T>(Future<T> Function(ImapClient) f) async {
    final c = await _imap();
    try {
      return await f(c);
    } finally {
      try {
        await c.logout();
      } catch (_) {}
    }
  }

  static List<MailItem> _items(FetchImapResult r) => [
        for (final m in r.messages.reversed)
          MailItem(
            m.uid ?? 0,
            m.from?.isNotEmpty == true ? (m.from!.first.personalName?.isNotEmpty == true ? m.from!.first.personalName! : m.from!.first.email) : '(unknown)',
            m.decodeSubject() ?? '(no subject)',
            m.decodeDate(),
            m.isSeen,
          ),
      ];

  /// Newest [count] inbox emails (headers only).
  static Future<List<MailItem>> inbox({int count = 40}) => _with((c) async {
        if (_inboxCount == 0) return <MailItem>[];
        return _items(await c.fetchRecentMessages(messageCount: count, criteria: '(UID FLAGS ENVELOPE)'));
      });

  /// Gmail search (e.g. "category:promotions older_than:30d"); plain subject/sender search elsewhere.
  static Future<List<MailItem>> search(String query, {int max = 100}) => _with((c) async {
        final criteria = MailAccount.isGmail ? 'X-GM-RAW "${query.replaceAll('"', '')}"' : 'OR SUBJECT "${query.replaceAll('"', '')}" FROM "${query.replaceAll('"', '')}"';
        final ids = (await c.uidSearchMessages(searchCriteria: criteria)).matchingSequence?.toList() ?? [];
        if (ids.isEmpty) return <MailItem>[];
        final newest = ids.length > max ? ids.sublist(ids.length - max) : ids;
        return _items(await c.uidFetchMessages(MessageSequence.fromIds(newest, isUid: true), '(UID FLAGS ENVELOPE)'))
          ..sort((a, b) => (b.at ?? DateTime(0)).compareTo(a.at ?? DateTime(0)));
      });

  /// Moves emails to Trash (recoverable ~30 days). Only ever called after the user confirms.
  static Future<void> trash(List<int> uids) => _with((c) async {
        final seq = MessageSequence.fromIds(uids, isUid: true);
        final boxes = await c.listMailboxes(recursive: true);
        final trashBox = boxes.where((b) => b.isTrash).firstOrNull;
        if (trashBox != null) {
          await c.uidMove(seq, targetMailbox: trashBox);
        } else {
          await c.uidMarkDeleted(seq);
          await c.uidExpunge(seq);
        }
      });

  /// Sends a plain-text email. Only ever called after the user confirms the preview.
  static Future<void> send({required String to, required String subject, required String body}) async {
    final s = SmtpClient('buddy.app', isLogEnabled: false);
    await s.connectToServer(MailAccount.hosts.$2, 465, isSecure: true);
    try {
      await s.ehlo();
      await s.authenticate(MailAccount.address!, (await MailAccount.password())!, AuthMechanism.plain);
      final b = MessageBuilder.prepareMultipartAlternativeMessage(plainText: body, htmlText: '<p>${const HtmlEscape().convert(body).replaceAll('\n', '<br>')}</p>')
        ..from = [MailAddress(Store.profile['name'] as String?, MailAccount.address!)]
        ..to = [for (final a in to.split(RegExp(r'[,; ]+')).where((a) => a.contains('@'))) MailAddress(null, a)]
        ..subject = subject;
      await s.sendMessage(b.buildMimeMessage());
    } finally {
      try {
        await s.quit();
      } catch (_) {}
    }
  }

  /// Bank alert emails since [since], reduced to amount + debit/credit + date + bank. Bodies are discarded.
  static Future<List<Txn>> bankAlerts(DateTime since) => _with((c) async {
        final days = DateTime.now().difference(since).inDays + 1;
        final criteria = MailAccount.isGmail
            ? 'X-GM-RAW "newer_than:${days}d (debited OR credited OR spent OR withdrawn OR \\"transaction alert\\")"'
            : 'SINCE ${_imapDate(since)} OR OR TEXT "debited" TEXT "credited" TEXT "spent"';
        final ids = (await c.uidSearchMessages(searchCriteria: criteria)).matchingSequence?.toList() ?? [];
        if (ids.isEmpty) return <Txn>[];
        final out = <Txn>[];
        final newest = ids.length > 150 ? ids.sublist(ids.length - 150) : ids;
        for (var i = 0; i < newest.length; i += 25) {
          final chunk = newest.sublist(i, (i + 25).clamp(0, newest.length));
          final r = await c.uidFetchMessages(MessageSequence.fromIds(chunk, isUid: true), 'BODY.PEEK[]');
          for (final m in r.messages) {
            final from = m.from?.firstOrNull?.email ?? '';
            if (!isBankSender(from)) continue; // a friend's "I sent Rs 500" is not a transaction
            final text = m.decodeTextPlainPart() ?? _stripHtml(m.decodeTextHtmlPart() ?? '');
            final p = parseTxn('${m.decodeSubject() ?? ''} . $text');
            if (p == null) continue;
            out.add(Txn(id: 'mail_${m.uid}', amount: p.amount, debit: p.debit, at: m.decodeDate() ?? DateTime.now(), bank: bankName(from), source: 'email'));
          }
        }
        return out;
      });

  static String _stripHtml(String h) => h.replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), ' ').replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll('&nbsp;', ' ').replaceAll('&#8377;', '₹');

  static String _imapDate(DateTime d) =>
      '${d.day}-${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]}-${d.year}';
}
