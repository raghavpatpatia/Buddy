import '../../../core/arch/repository.dart';

/// One money movement: only amount, direction, time, bank and the user's own category.
class Txn {
  final String id;
  final double amount;
  final bool debit;
  final DateTime at;
  final String bank, source;
  final String? category;
  final bool hidden;

  const Txn({required this.id, required this.amount, required this.debit, required this.at, required this.bank, required this.source, this.category, this.hidden = false});

  DateTime get day => DateTime(at.year, at.month, at.day);

  Txn copyWith({String? category, bool clearCategory = false, bool? hidden}) =>
      Txn(id: id, amount: amount, debit: debit, at: at, bank: bank, source: source, category: clearCategory ? null : (category ?? this.category), hidden: hidden ?? this.hidden);

  static final codec = JsonCodec<Txn>(
    encode: (t) => {'id': t.id, 'a': t.amount, 'd': t.debit, 't': t.at.millisecondsSinceEpoch, 'b': t.bank, 's': t.source, 'c': t.category, 'h': t.hidden},
    decode: (j) => Txn(
      id: j['id'],
      amount: (j['a'] as num).toDouble(),
      debit: j['d'],
      at: DateTime.fromMillisecondsSinceEpoch(j['t']),
      bank: j['b'],
      source: j['s'],
      category: j['c'],
      hidden: j['h'] ?? false,
    ),
  );
}

const categories = [
  ('Food', '🍔'), ('Groceries', '🛒'), ('Shopping', '🛍️'), ('Bills', '💡'), ('Rent', '🏠'), ('Travel', '🚕'),
  ('Fuel', '⛽'), ('Health', '💊'), ('Fun', '🎬'), ('Invest', '📈'), ('Family', '👪'), ('Other', '💸'),
];

String categoryEmoji(String? c) => categories.firstWhere((e) => e.$1 == c, orElse: () => ('', '💸')).$2;
