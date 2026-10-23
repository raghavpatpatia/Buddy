import 'package:permission_handler/permission_handler.dart';

import '../../../core/native.dart';
import '../../../core/store.dart';
import '../model/txn.dart';
import 'mail_service.dart';
import 'parse.dart';

/// Where transactions come from; each source turns its messages into amount-only [Txn]s.
abstract interface class TxnSource {
  bool get enabled;
  Future<List<Txn>> fetchSince(DateTime since);
}

/// Bank SMS (already filtered natively to business sender IDs).
class SmsTxnSource implements TxnSource {
  @override
  bool get enabled => Store.raw.getBool('money_sms') ?? false;

  /// Asks for SMS permission and remembers the answer.
  Future<bool> enable() async {
    final ok = (await Permission.sms.request()).isGranted;
    await Store.raw.setBool('money_sms', ok);
    return ok;
  }

  Future<bool> blocked() => Permission.sms.isPermanentlyDenied;

  @override
  Future<List<Txn>> fetchSince(DateTime since) async {
    if (!await Permission.sms.isGranted) return const [];
    return [
      for (final m in await Native.bankSms(since.millisecondsSinceEpoch))
        if (isBankSmsSender(m['addr'] as String))
          if (parseTxn(m['body'] as String) case final p?)
            Txn(
              id: 'sms_${m['id']}', amount: p.amount, debit: p.debit, at: DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
              bank: bankName(m['addr'] as String), source: 'sms',
              // Savings and investments aren't spending: tagged Invest and left out of the totals.
              category: p.invest ? 'Invest' : null, hidden: p.invest,
            ),
    ];
  }
}

/// Bank alert emails from the linked mailbox.
class EmailTxnSource implements TxnSource {
  @override
  bool get enabled => MailAccount.linked && MailAccount.scanBankEmails;

  @override
  Future<List<Txn>> fetchSince(DateTime since) => MailService.bankAlerts(since);
}
