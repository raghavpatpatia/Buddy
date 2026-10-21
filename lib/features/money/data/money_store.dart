import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/arch/repository.dart';
import '../../../core/store.dart';
import '../model/mail.dart';
import '../model/market.dart';
import '../model/txn.dart';

/// Repositories for everything the Money section keeps on the phone (same keys as before, so data carries over).
class MoneyStore {
  final SharedPreferences prefs;
  MoneyStore(this.prefs);

  static MoneyStore? _instance;
  static MoneyStore get instance => _instance != null && identical(_instance!.prefs, Store.raw) ? _instance! : _instance = MoneyStore(Store.raw);

  late final Repository<String, Txn> txns = PrefsRepository(prefs, 'money_txns', Txn.codec, (t) => t.id);
  late final Repository<String, Holding> holdings = PrefsRepository(prefs, 'mkt_holdings', Holding.codec, (h) => h.symbol);
  late final Repository<String, WatchItem> watchlist = PrefsRepository(prefs, 'mkt_watch', WatchItem.codec, (w) => w.symbol);
  late final Repository<String, TrackedMail> tracked = PrefsRepository(prefs, 'track_sent', TrackedMail.codec, (t) => t.id);

  double get budget => prefs.getDouble('money_budget') ?? 0;
  Future<void> setBudget(double v) => prefs.setDouble('money_budget', v);

  Set<String> get removedTxnIds => (prefs.getStringList('money_removed') ?? const []).toSet();
  Future<void> markRemoved(String id) => prefs.setStringList('money_removed', [...removedTxnIds, id]);

  String get risk => prefs.getString('mkt_risk') ?? 'medium';
  Future<void> setRisk(String r) => prefs.setString('mkt_risk', r);
}
