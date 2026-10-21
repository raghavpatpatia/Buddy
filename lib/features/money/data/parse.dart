/// Amount and direction of one bank transaction; nothing else from the message is kept.
class ParsedTxn {
  final double amount;
  final bool debit;
  const ParsedTxn(this.amount, this.debit);
}

final _amount = RegExp(r'(?:rs\.?|inr|₹)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)', caseSensitive: false);
final _debitWord = RegExp(r'\b(debited|debit(?:ed)? (?:by|for|with)|spent|withdrawn|withdrawal|paid|sent|purchase|deducted|dr\.?\b|txn of)', caseSensitive: false);
final _creditWord = RegExp(r'\b(credited|credit(?:ed)? (?:by|with)|received|deposited|refund(?:ed)?|cr\.?\b)', caseSensitive: false);
// Not a completed transaction: OTPs, reminders, offers, failures, future debits.
final _skip = RegExp(
  r'\b(otp|one[- ]time password|will be debited|to be debited|due (?:on|date|amount)|bill (?:of|is) generated|minimum (?:amount )?due|'
  r'pre-?approved|offer|loan of|eligible|cashback up to|win|failed|declined|unsuccessful|request(?:ed)? (?:money|for)|collect request|'
  r'emi of .* available|statement (?:for|of)|reward points?)\b',
  caseSensitive: false,
);
final _balance = RegExp(r'\b(avl\.?|avail(?:able)?|a/c|acct?\.?)?\s*bal(?:ance)?\b', caseSensitive: false);

ParsedTxn? parseTxn(String text) {
  final t = text.replaceAll(RegExp(r'\s+'), ' ');
  if (_skip.hasMatch(t)) return null;
  final d = _debitWord.firstMatch(t), c = _creditWord.firstMatch(t);
  if (d == null && c == null) return null;
  // Whichever word comes first decides: "debited … credited to beneficiary" is a debit.
  final debit = c == null || (d != null && d.start < c.start);
  // The transaction amount is the first one that isn't the balance ("Avl Bal Rs 10,000").
  final bal = _balance.firstMatch(t);
  for (final m in _amount.allMatches(t)) {
    if (bal != null && m.start > bal.start && m.start - bal.end < 12) continue;
    final v = double.tryParse(m.group(1)!.replaceAll(',', ''));
    if (v != null && v > 0 && v < 1e8) return ParsedTxn(v, debit);
  }
  return null;
}

const _banks = {
  'HDFC': 'HDFC', 'SBI': 'SBI', 'ICICI': 'ICICI', 'AXIS': 'Axis', 'KOTAK': 'Kotak', 'PNB': 'PNB', 'YES': 'Yes Bank',
  'IDFC': 'IDFC First', 'INDUS': 'IndusInd', 'BOB': 'Bank of Baroda', 'BARODA': 'Bank of Baroda', 'CANARA': 'Canara',
  'CANBNK': 'Canara', 'UNION': 'Union Bank', 'UBOI': 'Union Bank', 'PAYTM': 'Paytm', 'AIRTEL': 'Airtel Payments',
  'FEDERAL': 'Federal', 'FEDBNK': 'Federal', 'IDBI': 'IDBI', 'AUBANK': 'AU Bank', 'RBL': 'RBL', 'AMEX': 'Amex',
  'SCB': 'Standard Chartered', 'HSBC': 'HSBC', 'CITI': 'Citi', 'JUPITER': 'Jupiter', 'SLICE': 'slice', 'ONECARD': 'OneCard',
};

/// "VM-HDFCBK-S" / "alerts@hdfcbank.net" → "HDFC". Unknown senders keep their short code.
String bankName(String sender) {
  final s = sender.toUpperCase();
  for (final e in _banks.entries) {
    if (s.contains(e.key)) return e.value;
  }
  if (s.contains('@')) return s.split('@').last.split('.').first; // email: the domain, e.g. "SLICEIT"
  final parts = s.split(RegExp(r'[-@.]')).where((p) => p.length >= 3).toList();
  return parts.isEmpty ? 'Bank' : parts.length > 1 && s.contains('-') ? parts[1] : parts.first;
}

/// Bank / card / wallet alert senders only (by known bank or alert-style address).
bool isBankSender(String email) {
  final e = email.toLowerCase();
  if (_banks.keys.any((k) => e.contains(k.toLowerCase()))) return true;
  return RegExp(r'(bank|alert|card|upi|wallet|payments?|txn|transaction)').hasMatch(e);
}
