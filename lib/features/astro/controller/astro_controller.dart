import '../../../core/arch/safe_notifier.dart';
import '../data/birth_store.dart';
import '../model/jyotish.dart';

/// Stars screen: birth details, the computed chart, and chart style.
class AstroController extends SafeNotifier {
  BirthData? birth = BirthStore.load();
  Chart? _chart;
  bool north = BirthStore.northChart;

  Chart? get chart => birth == null ? null : (_chart ??= Chart(birth!));

  Future<void> save(BirthData b) async {
    await BirthStore.save(b);
    birth = b;
    _chart = null;
    notifyListeners();
  }

  Future<void> setNorth(bool v) async {
    await BirthStore.setNorthChart(v);
    north = v;
    notifyListeners();
  }
}

/// Today's panchang: shown at once for the birth place, then refined for where you are now.
class TodayController extends SafeNotifier {
  TodayController(BirthData b) : panchang = Panchang.at(DateTime.now(), b.lat, b.lon, DateTime.now().timeZoneOffset) {
    BirthStore.todayPlace(b).then((loc) {
      panchang = Panchang.at(DateTime.now(), loc.$1, loc.$2, loc.$3);
      notifyListeners();
    });
  }

  Panchang panchang;
}
