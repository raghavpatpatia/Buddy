import 'package:buddy_app/features/money/market.dart';
import 'package:buddy_app/features/money/money_ui.dart';
import 'package:buddy_app/features/money/parse.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('bank SMS parser keeps only amount + direction', () {
    final cases = <String, (double, bool)?>{
      'Rs.500.00 debited from A/c XX1234 on 20-10-26 to VPA swiggy@icici. Avl Bal Rs 10,234.50 -HDFC': (500, true),
      'Your A/c XX9876 is credited with INR 45,000.00 on 01-Oct by NEFT. Avl Bal: INR 52,100.20': (45000, false),
      'Spent Rs 1,299 on HDFC Bank Card x4321 at AMAZON on 2026-10-18.': (1299, true),
      'Avl Bal Rs 9,000.00. Rs 250 debited via UPI ref 123456': (250, true),
      '₹2,000 sent to Mom via UPI from SBI a/c': (2000, true),
      'INR 3,500 refund credited to your card': (3500, false),
      'Your OTP for txn of Rs 500 is 123456. Do not share.': null,
      'Rs 1,200 will be debited on 25-Oct for your SIP': null,
      'Congrats! Pre-approved loan of Rs 5,00,000 is waiting for you': null,
      'Your transaction of Rs 300 has failed': null,
      'Minimum amount due Rs 1,500 on your credit card. Total due Rs 12,000': null,
      'Hi, see you at 5?': null,
    };
    cases.forEach((sms, want) {
      test(sms, () {
        final p = parseTxn(sms);
        if (want == null) {
          expect(p, isNull);
        } else {
          expect(p, isNotNull);
          expect(p!.amount, want.$1);
          expect(p.debit, want.$2);
        }
      });
    });
  });

  test('bank names from SMS sender IDs and email addresses', () {
    expect(bankName('VM-HDFCBK'), 'HDFC');
    expect(bankName('AD-SBIINB-S'), 'SBI');
    expect(bankName('alerts@icicibank.com'), 'ICICI');
    expect(isBankSender('alerts@hdfcbank.net'), isTrue);
    expect(isBankSender('friend@gmail.com'), isFalse);
  });

  test('Indian rupee grouping', () {
    expect(inr(1234567), '₹12,34,567');
    expect(inr(950), '₹950');
    expect(inr(-1500, sign: true), '−₹1,500');
    expect(inr(100000, sign: true), '+₹1,00,000');
    expect(inrShort(250000), '₹2.5L');
  });

  test('trend score rewards a steady uptrend and flags a downtrend', () {
    Quote q(List<double> c) => Quote('X', 'X', 'INR', c.last, 0, c.reduce((a, b) => a > b ? a : b), c.reduce((a, b) => a < b ? a : b), List.generate(c.length, (i) => DateTime(2026, 1, 1).add(Duration(days: i))), c);
    final up = trendOf(q([for (var i = 0; i < 260; i++) 100 + i * 0.4 + (i.isEven ? 0.5 : -0.5)]));
    final down = trendOf(q([for (var i = 0; i < 260; i++) 200 - i * 0.4 + (i.isEven ? 0.5 : -0.5)]));
    expect(up.score, greaterThan(65));
    expect(down.score, lessThan(45));
    expect(down.bad, isNotEmpty);
  });
}
