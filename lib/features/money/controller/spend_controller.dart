import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../../core/arch/load_state.dart';
import '../../../core/format.dart';
import '../../../core/arch/safe_notifier.dart';
import '../../../core/arch/repository.dart';
import '../../../core/store.dart';
import '../data/ai.dart';
import '../data/money_store.dart';
import '../data/txn_sources.dart';
import '../model/txn.dart';

/// Totals and groupings for one month, computed once per change.
class MonthSummary {
  final List<Txn> txns;
  final SplayTreeMap<DateTime, List<Txn>> byDay;
  final double spent, received;
  final List<MapEntry<String, double>> byCategory;

  MonthSummary(this.txns)
      : byDay = SplayTreeMap((a, b) => b.compareTo(a)),
        spent = _sum(txns, debit: true),
        received = _sum(txns, debit: false),
        byCategory = _categories(txns) {
    for (final t in txns) {
      byDay.putIfAbsent(t.day, () => []).add(t);
    }
  }

  static double _sum(Iterable<Txn> ts, {required bool debit}) => ts.where((t) => !t.hidden && t.debit == debit).fold(0.0, (a, t) => a + t.amount);

  static List<MapEntry<String, double>> _categories(Iterable<Txn> ts) {
    final m = <String, double>{};
    for (final t in ts.where((t) => t.debit && !t.hidden)) {
      m.update(t.category ?? 'Uncategorised', (v) => v + t.amount, ifAbsent: () => t.amount);
    }
    return m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  }

  static double daySpent(Iterable<Txn> ts) => _sum(ts, debit: true);
}

/// Spend tab logic: month navigation, syncing sources, budget pace, categories and AI insight.
class SpendController extends SafeNotifier {
  SpendController({MoneyStore? store, SmsTxnSource? sms, List<TxnSource>? sources, this._ask = askBuddy})
      : _store = store ?? MoneyStore.instance,
        sms = sms ?? SmsTxnSource() {
    _sources = sources ?? [this.sms, EmailTxnSource()];
    _txns.addListener(_onData);
  }

  final MoneyStore _store;
  final SmsTxnSource sms;
  late final List<TxnSource> _sources;
  final AiAsk _ask;
  Repository<String, Txn> get _txns => _store.txns;

  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  LoadState<int> sync = const Idle();
  LoadState<String> insight = const Idle();
  MonthSummary? _summary;

  bool get hasSources => _sources.any((s) => s.enabled);
  bool get isThisMonth => month.year == DateTime.now().year && month.month == DateTime.now().month;
  bool get hasAny => _txns.length > 0;
  double get budget => _store.budget;
  int get daysInMonth => DateTime(month.year, month.month + 1, 0).day;
  int get daysLeft => isThisMonth ? daysInMonth - DateTime.now().day + 1 : 0;

  MonthSummary get summary => _summary ??= MonthSummary(
        _txns.all.where((t) => t.at.year == month.year && t.at.month == month.month).toList()..sort((a, b) => b.at.compareTo(a.at)),
      );

  DateTime? get lastSync {
    final ms = Store.raw.getInt('money_synced');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  void _onData() {
    _summary = null;
    notifyListeners();
  }

  void shiftMonth(int by) {
    if (by > 0 && isThisMonth) return;
    month = DateTime(month.year, month.month + by);
    _onData();
  }

  /// Debits per day for the last 7 days, oldest first.
  List<(DateTime, double)> last7() {
    final now = DateTime.now();
    final days = [for (var i = 6; i >= 0; i--) DateTime(now.year, now.month, now.day - i)];
    final byDay = <DateTime, double>{for (final d in days) d: 0};
    for (final t in _txns.all) {
      if (t.debit && !t.hidden && byDay.containsKey(t.day)) byDay[t.day] = byDay[t.day]! + t.amount;
    }
    return [for (final d in days) (d, byDay[d]!)];
  }

  /// Pulls new transactions from every enabled source since the last sync (90 days the first time); null if a sync is already running.
  Future<int?> syncNow() async {
    if (sync.isLoading) return null;
    sync = const Loading();
    notifyListeners();
    try {
      final since = lastSync?.subtract(const Duration(days: 2)) ?? DateTime.now().subtract(const Duration(days: 90));
      final found = <Txn>[];
      for (final s in _sources.where((s) => s.enabled)) {
        try {
          found.addAll(await s.fetchSince(since));
        } catch (e) {
          debugPrint('[Spend] ${s.runtimeType} failed: $e');
        }
      }
      final added = await _merge(found);
      await Store.raw.setInt('money_synced', DateTime.now().millisecondsSinceEpoch);
      sync = Ready(added);
      return added;
    } catch (e) {
      sync = Failed('$e');
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  /// Adds unseen transactions, skipping removed ones and the same payment reported by both SMS and email.
  Future<int> _merge(List<Txn> found) async {
    final removed = _store.removedTxnIds;
    final index = HashMap<(double, bool), List<Txn>>();
    for (final t in _txns.all) {
      index.putIfAbsent((t.amount, t.debit), () => []).add(t);
    }
    final fresh = <Txn>[];
    for (final t in found..sort((a, b) => a.at.compareTo(b.at))) {
      if (removed.contains(t.id) || _txns.contains(t.id)) continue;
      final twins = index[(t.amount, t.debit)] ?? const <Txn>[];
      if (twins.any((o) => o.source != t.source && o.source != 'cash' && o.at.difference(t.at).inMinutes.abs() <= 20)) continue;
      fresh.add(t);
      index.putIfAbsent((t.amount, t.debit), () => []).add(t);
    }
    if (fresh.isNotEmpty) await _txns.putAll(fresh);
    return fresh.length;
  }

  /// True when SMS permission was denied with "don't ask again"; only Settings can grant it then.
  Future<bool> smsBlocked() => sms.blocked();

  Future<bool> enableSms() async {
    final ok = await sms.enable();
    if (ok) await syncNow();
    notifyListeners();
    return ok;
  }

  Future<void> setBudget(double v) async {
    await _store.setBudget(v);
    notifyListeners();
  }

  Future<void> addCash(double amount, {required bool debit, String? category}) =>
      _txns.put(Txn(id: 'cash_${DateTime.now().microsecondsSinceEpoch}', amount: amount, debit: debit, at: DateTime.now(), bank: 'Cash', source: 'cash', category: category));

  Future<void> setCategory(Txn t, String? c) => _txns.put(c == null ? t.copyWith(clearCategory: true) : t.copyWith(category: c));
  Future<void> setHidden(Txn t, bool hidden) => _txns.put(t.copyWith(hidden: hidden));

  /// Deletes [t] and remembers it so the next sync doesn't bring it back.
  Future<void> remove(Txn t) async {
    await _store.markRemoved(t.id);
    await _txns.remove(t.id);
  }

  String ruleInsight() {
    final w = last7();
    final week = w.fold(0.0, (a, e) => a + e.$2);
    if (week == 0) return 'No spending in the last 7 days. 🎉';
    final top = w.reduce((a, b) => a.$2 >= b.$2 ? a : b);
    return 'You spent ${inr(week)} in the last 7 days; the biggest day was ${const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][top.$1.weekday - 1]} (${inr(top.$2)}).';
  }

  /// Totals only (no banks, ids or messages) for the AI.
  String summaryForAi() {
    final now = DateTime.now();
    final m = MonthSummary(_txns.all.where((t) => t.at.year == now.year && t.at.month == now.month).toList());
    final last = MonthSummary(_txns.all.where((t) => t.at.year == (now.month == 1 ? now.year - 1 : now.year) && t.at.month == (now.month == 1 ? 12 : now.month - 1)).toList());
    return 'Day ${now.day} of the month. This month: spent ₹${m.spent.round()}, received ₹${m.received.round()}. '
        'Last month: spent ₹${last.spent.round()}. Monthly budget: ${budget > 0 ? '₹${budget.round()}' : 'not set'}. '
        'Last 7 days spend (oldest→today): ${last7().map((e) => e.$2.round()).join(', ')}. '
        'By category: ${m.byCategory.map((e) => '${e.key} ₹${e.value.round()}').join(', ')}.';
  }

  Future<void> askInsight() async {
    insight = const Loading();
    notifyListeners();
    final r = await _ask(
      'You are Buddy, a friendly, practical money coach for a young professional in India. Use only the numbers given. '
          'Reply in 3 short bullet points: one observation, one specific saving tip, one encouragement. Plain text, use ₹. No markdown headers.',
      summaryForAi(),
      maxTokens: 500,
    );
    insight = r == null ? Failed('Turn on the cloud brain (Talk → brain icon) for personalised insights. Meanwhile: ${ruleInsight()}') : Ready(r);
    notifyListeners();
  }

  @override
  void dispose() {
    _txns.removeListener(_onData);
    super.dispose();
  }
}
