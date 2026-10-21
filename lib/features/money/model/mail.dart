import 'dart:typed_data';

import '../../../core/arch/repository.dart';

/// One row of the mail list (headers only).
class MailItem {
  final int uid;
  final String from, subject;
  final DateTime? at;
  final bool seen;
  const MailItem(this.uid, this.from, this.subject, this.at, this.seen);
}

class MailAttachment {
  final String name, mime;
  final int size;
  final Uint8List? Function() bytes;
  const MailAttachment(this.name, this.size, this.mime, this.bytes);
}

/// A fully loaded email ready for the reader.
class MailMessage {
  final String from, fromEmail, subject, html, text;
  final DateTime? at;
  final int trackersBlocked;
  final List<MailAttachment> attachments;
  const MailMessage({required this.from, required this.fromEmail, required this.subject, required this.at, required this.html, required this.text, required this.trackersBlocked, required this.attachments});
}

/// One email sent with read tracking.
class TrackedMail {
  final String id, to, subject;
  final DateTime sentAt;
  final List<DateTime> opens;
  final bool viaGmail;
  const TrackedMail(this.id, this.to, this.subject, this.sentAt, this.opens, {this.viaGmail = false});

  static final codec = JsonCodec<TrackedMail>(
    encode: (t) => {'id': t.id, 'to': t.to, 's': t.subject, 't': t.sentAt.millisecondsSinceEpoch, 'o': [for (final o in t.opens) o.millisecondsSinceEpoch], 'g': t.viaGmail},
    decode: (j) => TrackedMail(j['id'], j['to'], j['s'], DateTime.fromMillisecondsSinceEpoch(j['t']), [for (final o in (j['o'] as List)) DateTime.fromMillisecondsSinceEpoch(o)], viaGmail: j['g'] ?? false),
  );
}
