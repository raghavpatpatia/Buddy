import 'dart:convert';
import 'dart:typed_data';

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

  /// Full email for the reader (marks it read, like opening it in Gmail). Attachments stay in memory until downloaded.
  static Future<MailMessage> read(int uid) => _with((c) async {
        final r = await c.uidFetchMessages(MessageSequence.fromIds([uid], isUid: true), 'BODY[]');
        final m = r.messages.first;
        final f = m.from?.firstOrNull;
        // Inline images referenced as cid:… become data: URIs so they show without a server.
        final cids = <String, String>{};
        for (final part in m.allPartsFlat) {
          final id = part.getHeaderValue('content-id')?.replaceAll(RegExp(r'[<>\s]'), '');
          final type = part.mediaType.text;
          if (id == null || id.isEmpty || !type.startsWith('image/')) continue;
          final bytes = part.decodeContentBinary();
          if (bytes != null) cids[id.toLowerCase()] = 'data:$type;base64,${base64Encode(bytes)}';
        }
        final atts = <MailAttachment>[
          for (final info in m.findContentInfo())
            MailAttachment(info.fileName ?? 'attachment', info.size ?? m.getPart(info.fetchId)?.decodeContentBinary()?.length ?? 0, info.mediaType?.text ?? 'application/octet-stream', () => m.getPart(info.fetchId)?.decodeContentBinary()),
        ];
        final prepared = prepareEmailHtml(m.decodeTextHtmlPart(), m.decodeTextPlainPart(), cids);
        return MailMessage(
          from: f?.personalName?.isNotEmpty == true ? f!.personalName! : (f?.email ?? '(unknown)'),
          fromEmail: f?.email ?? '',
          subject: m.decodeSubject() ?? '(no subject)',
          at: m.decodeDate(),
          html: prepared.$1,
          trackersBlocked: prepared.$2,
          text: htmlToText(m.decodeTextHtmlPart() ?? '').isNotEmpty ? htmlToText(m.decodeTextHtmlPart()!) : (m.decodeTextPlainPart() ?? '').trim(),
          attachments: atts,
        );
      });

  static final _trackerSrc = RegExp(
    r'(track|pixel|beacon|/open(\?|/|\.gif)|/o/[a-z0-9]{16,}|wf/open|mailtrack|mailsuite|list-manage\.com|hs-analytics|hubspot.*/e\d|mandrillapp\.com|sendgrid\.net|mailchimp|customeriomail|email\.mg\.|spacer\.gif|blank\.gif|1x1|lambda-url)',
    caseSensitive: false,
  );

  /// Builds a self-contained HTML page: inline images embedded, 1×1 tracking pixels removed, plain text linkified.
  /// Returns (html, number of trackers blocked).
  static (String, int) prepareEmailHtml(String? html, String? plain, Map<String, String> cids) {
    var blocked = 0;
    String body;
    if (html != null && html.trim().isNotEmpty) {
      body = html.replaceAllMapped(RegExp(r'<img\b[^>]*>', caseSensitive: false), (m) {
        final tag = m[0]!;
        final src = RegExp(r"""src\s*=\s*["']([^"']*)["']""", caseSensitive: false).firstMatch(tag)?[1] ?? '';
        int? dim(String a) => int.tryParse(RegExp('$a\\s*[=:]\\s*["\']?(\\d+)', caseSensitive: false).firstMatch(tag)?[1] ?? '');
        final w = dim('width'), h = dim('height');
        final tiny = (w != null && w <= 3) || (h != null && h <= 3);
        if (src.startsWith('http') && (tiny || _trackerSrc.hasMatch(src))) {
          blocked++;
          return '';
        }
        if (src.toLowerCase().startsWith('cid:')) {
          final data = cids[src.substring(4).toLowerCase()];
          return data == null ? '' : tag.replaceFirst(src, data);
        }
        return tag;
      });
      // Strip scripts and remote forms; JavaScript is off anyway.
      body = body
          .replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true, caseSensitive: false), '')
          .replaceAll(RegExp(r'''\son[a-z]+\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)''', caseSensitive: false), '')
          .replaceAll(RegExp(r'''href\s*=\s*["']\s*javascript:[^"']*["']''', caseSensitive: false), 'href="#"');
    } else {
      final esc = const HtmlEscape(HtmlEscapeMode.element).convert((plain ?? '').trim());
      body = '<div style="white-space:pre-wrap">${esc.replaceAllMapped(RegExp(r'(https?://[^\s<"]+)|([\w.+-]+@[\w-]+\.[\w.]+)'), (m) => m[1] != null ? '<a href="${m[1]}">${m[1]}</a>' : '<a href="mailto:${m[2]}">${m[2]}</a>')}</div>';
    }
    return (
      '<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">'
          '<style>html,body{margin:0;padding:0;background:#fff;color:#202124}body{padding:12px;font:15px/1.5 Roboto,Arial,sans-serif;word-wrap:break-word;overflow-wrap:anywhere}'
          'img{max-width:100%!important;height:auto!important}table{max-width:100%!important}a{color:#1a73e8}pre{white-space:pre-wrap}</style></head><body>$body</body></html>',
      blocked
    );
  }

  /// HTML → readable text: keeps paragraphs, list bullets and link targets; drops styles/scripts.
  static String htmlToText(String h) {
    var s = h
        .replaceAll(RegExp(r'<(style|script|head)[^>]*>.*?</\1>', dotAll: true, caseSensitive: false), ' ')
        .replaceAllMapped(RegExp(r'''<a\s[^>]*href=["']([^"']+)["'][^>]*>(.*?)</a>''', dotAll: true, caseSensitive: false), (m) {
          final text = m[2]!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
          final url = m[1]!;
          return text.isEmpty || !url.startsWith('http') || text == url ? (url.startsWith('http') ? ' $url ' : text) : '$text ($url)';
        })
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '\n• ')
        .replaceAll(RegExp(r'</(p|div|tr|h[1-6]|table|ul|ol)>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'<[^>]+>'), '');
    const ent = {'&nbsp;': ' ', '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&#39;': "'", '&#8377;': '₹', '&rsquo;': '’', '&lsquo;': '‘', '&ldquo;': '“', '&rdquo;': '”', '&hellip;': '…', '&zwnj;': '', '&#8203;': ''};
    ent.forEach((k, v) => s = s.replaceAll(k, v));
    s = s.replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m[1]!)));
    return s.split('\n').map((l) => l.replaceAll(RegExp(r'[ \t ]+'), ' ').trim()).join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

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

  /// Sends an email with optional attachments and read-tracking pixel. Only ever called after the user confirms the preview.
  static Future<void> send({required String to, required String subject, required String body, List<(String, Uint8List)> attachments = const [], String? pixelUrl}) async {
    final s = SmtpClient('buddy.app', isLogEnabled: false);
    await s.connectToServer(MailAccount.hosts.$2, 465, isSecure: true);
    try {
      await s.ehlo();
      await s.authenticate(MailAccount.address!, (await MailAccount.password())!, AuthMechanism.plain);
      final html = '<div>${const HtmlEscape().convert(body).replaceAll('\n', '<br>')}</div>${pixelUrl == null ? '' : '<img src="$pixelUrl" width="1" height="1" alt="" style="display:block;width:1px;height:1px;border:0">'}';
      final b = (attachments.isEmpty ? MessageBuilder.prepareMultipartAlternativeMessage(plainText: body, htmlText: html) : (MessageBuilder.prepareMultipartMixedMessage()..addMultipartAlternative(plainText: body, htmlText: html)))
        ..from = [MailAddress(Store.profile['name'] as String?, MailAccount.address!)]
        ..to = [for (final a in to.split(RegExp(r'[,; ]+')).where((a) => a.contains('@'))) MailAddress(null, a)]
        ..subject = subject;
      for (final (name, bytes) in attachments) {
        b.addBinary(bytes, MediaType.guessFromFileName(name), filename: name);
      }
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

class MailAttachment {
  final String name, mime;
  final int size;
  final Uint8List? Function() bytes;
  const MailAttachment(this.name, this.size, this.mime, this.bytes);
}

class MailMessage {
  final String from, fromEmail, subject, html, text;
  final DateTime? at;
  final int trackersBlocked;
  final List<MailAttachment> attachments;
  const MailMessage({required this.from, required this.fromEmail, required this.subject, required this.at, required this.html, required this.text, required this.trackersBlocked, required this.attachments});
}
