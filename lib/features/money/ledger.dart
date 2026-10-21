import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/native.dart';
import '../../core/store.dart';
import 'mail.dart';
import 'parse.dart';

/// One money movement. Holds only amount, direction, time, bank and your own category/note.
class Txn {
  final String id; // source + message id (e.g. sms_123); never the message itself
  final double amount;
  final bool debit;
  final DateTime at;
  final String bank, source; // source: sms | email | cash
  String? category;
  bool hidden; // e.g. transfers between your own accounts

  Txn({required this.id, required this.amount, required this.debit, required this.at, required this.bank, required this.source, this.category, this.hidden = false});

  Map<String, dynamic> toJson() => {'id': id, 'a': amount, 'd': debit, 't': at.millisecondsSinceEpoch, 'b': bank, 's': source, 'c': category, 'h': hidden};
  factory Txn.fromJson(Map j) => Txn(
        id: j['id'],
        amount: (j['a'] as num).toDouble(),
        debit: j['d'],
        at: DateTime.fromMillisecondsSinceEpoch(j['t']),
        bank: j['b'],
        source: j['s'],
        category: j['c'],
        hidden: j['h'] ?? false,
      );
}

const categories = [
  ('Food', '🍔'), ('Groceries', '🛒'), ('Shopping', '🛍️'), ('Bills', '💡'), ('Rent', '🏠'), ('Travel', '🚕'),
  ('Fuel', '⛽'), ('Health', '💊'), ('Fun', '🎬'), ('Invest', '📈'), ('Family', '👪'), ('Other', '💸'),
];
String categoryEmoji(String? c) => categories.firstWhere((e) => e.$1 == c, orElse: () => ('', '💸')).$2;

class Ledger {
  static final changed = ValueNotifier(0);
  static List<Txn>? _cache;

  static List<Txn> get all => _cache ??= ((jsonDecode(Store.raw.getString('money_txns') ?? '[]') as List).map((e) => Txn.fromJson(e)).toList()
    ..sort((a, b) => b.at.compareTo(a.at)));

  static Future<void> _save() async {
    all.sort((a, b) => b.at.compareTo(a.at));
    await Store.raw.setString('money_txns', jsonEncode([for (final t in all) t.toJson()]));
    changed.value++;
  }

  static double get monthlyBudget => Store.raw.getDouble('money_budget') ?? 0;
  static Future<void> setBudget(double v) async {
    await Store.raw.setDouble('money_budget', v);
    changed.value++;
  }

  static Iterable<Txn> inMonth(DateTime m) => all.where((t) => !t.hidden && t.at.year == m.year && t.at.month == m.month);
  static double spent(Iterable<Txn> ts) => ts.where((t) => t.debit).fold(0.0, (a, t) => a + t.amount);
  static double received(Iterable<Txn> ts) => ts.where((t) => !t.debit).fold(0.0, (a, t) => a + t.amount);

  /// Debits per day for the last 7 days (oldest first).
  static List<(DateTime, double)> last7() {
    final now = DateTime.now();
    return [
      for (var i = 6; i >= 0; i--)
        () {
          final d = DateTime(now.year, now.month, now.day - i);
          return (d, spent(all.where((t) => !t.hidden && t.at.year == d.year && t.at.month == d.month && t.at.day == d.day)));
        }(),
    ];
  }

  /// Adds new transactions, skipping ones already seen and the same payment reported by both SMS and email.
  static int _merge(List<Txn> found) {
    final ids = all.map((t) => t.id).toSet();
    var added = 0;
    for (final t in found) {
      if (ids.contains(t.id)) continue;
      final dup = all.any((o) => o.source != t.source && o.source != 'cash' && o.debit == t.debit && o.amount == t.amount && o.at.difference(t.at).inMinutes.abs() <= 20);
      if (dup) continue;
      all.add(t);
      ids.add(t.id);
      added++;
    }
    return added;
  }

  static Future<void> addCash(double amount, bool debit, String? category) async {
    all.add(Txn(id: 'cash_${DateTime.now().microsecondsSinceEpoch}', amount: amount, debit: debit, at: DateTime.now(), bank: 'Cash', source: 'cash', category: category));
    await _save();
  }

  static Future<void> update(Txn t) => _save();
  static Future<void> remove(Txn t) async {
    all.remove(t);
    // Remember removed ids so the next sync doesn't bring them back.
    final gone = Store.raw.getStringList('money_removed') ?? [];
    await Store.raw.setStringList('money_removed', [...gone, t.id]);
    await _save();
  }

  static bool get smsOn => Store.raw.getBool('money_sms') ?? false;
  static DateTime? lastSync() {
    final ms = Store.raw.getInt('money_synced');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static Future<bool> enableSms() async {
    final ok = (await Permission.sms.request()).isGranted;
    await Store.raw.setBool('money_sms', ok);
    return ok;
  }

  static bool _syncing = false;
  /// Reads new bank SMS (and alert emails, if an account is linked) since the last sync. Returns how many were added.
  static Future<int> sync({int firstDays = 90}) async {
    if (_syncing) return 0;
    _syncing = true;
    try {
      final since = lastSync()?.subtract(const Duration(days: 2)) ?? DateTime.now().subtract(Duration(days: firstDays));
      final removed = (Store.raw.getStringList('money_removed') ?? []).toSet();
      final found = <Txn>[];
      if (smsOn && await Permission.sms.isGranted) {
        for (final m in await Native.bankSms(since.millisecondsSinceEpoch)) {
          final p = parseTxn(m['body'] as String);
          if (p == null) continue;
          found.add(Txn(id: 'sms_${m['id']}', amount: p.amount, debit: p.debit, at: DateTime.fromMillisecondsSinceEpoch(m['date'] as int), bank: bankName(m['addr'] as String), source: 'sms'));
        }
      }
      if (MailAccount.linked && MailAccount.scanBankEmails) {
        try {
          found.addAll(await MailService.bankAlerts(since));
        } catch (e) {
          debugPrint('[BuddyMoney] email scan failed: $e');
        }
      }
      found.removeWhere((t) => removed.contains(t.id));
      found.sort((a, b) => a.at.compareTo(b.at));
      final added = _merge(found);
      await Store.raw.setInt('money_synced', DateTime.now().millisecondsSinceEpoch);
      await _save();
      return added;
    } finally {
      _syncing = false;
    }
  }

  /// Totals only (no banks, no ids) for Buddy's money insight.
  static String summaryForAi() {
    final now = DateTime.now();
    final m = inMonth(now).toList();
    final last = inMonth(DateTime(now.year, now.month - 1)).toList();
    final byCat = <String, double>{};
    for (final t in m.where((t) => t.debit)) {
      byCat[t.category ?? 'Uncategorised'] = (byCat[t.category ?? 'Uncategorised'] ?? 0) + t.amount;
    }
    final week = last7().map((e) => e.$2.round()).join(', ');
    return 'Day ${now.day} of the month. This month: spent ₹${spent(m).round()}, received ₹${received(m).round()}. '
        'Last month: spent ₹${spent(last).round()}. Monthly budget: ${monthlyBudget > 0 ? '₹${monthlyBudget.round()}' : 'not set'}. '
        'Last 7 days spend (oldest→today): $week. By category: ${byCat.entries.map((e) => '${e.key} ₹${e.value.round()}').join(', ')}.';
  }
}
