import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/store.dart';
import '../ui.dart';
import 'jyotish.dart';
import 'places.dart';

BirthData? loadBirth() {
  final j = Store.getJson('birth');
  return j == null ? null : BirthData.fromJson(j);
}

/// Where "today" is computed: last known location, else birth place.
Future<(double, double, Duration)> todayPlace(BirthData b) async {
  try {
    final p = await Geolocator.getLastKnownPosition().timeout(const Duration(seconds: 2));
    if (p != null) return (p.latitude, p.longitude, DateTime.now().timeZoneOffset);
  } catch (_) {}
  return (b.lat, b.lon, DateTime.now().timeZoneOffset);
}

String hm(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

String dmy(DateTime t) => '${t.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][t.month - 1]} ${t.year}';

class AstroPage extends StatefulWidget {
  const AstroPage({super.key});
  @override
  State<AstroPage> createState() => _AstroPageState();
}

class _AstroPageState extends State<AstroPage> {
  BirthData? _b = loadBirth();

  Future<void> _edit() async {
    final b = await Navigator.of(context).push<BirthData>(MaterialPageRoute(builder: (_) => BirthForm(initial: _b)));
    if (b != null) {
      await Store.setJson('birth', b.toJson());
      setState(() => _b = b);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_b == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Stars')),
        body: ListView(padding: pagePadding, children: [
          const SizedBox(height: 24),
          const Text('✨', textAlign: TextAlign.center, style: TextStyle(fontSize: 56)),
          Text('Your Vedic birth chart', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text(
            'Enter your date, exact time (to the second) and place of birth. Buddy calculates your Lagna, Rashi, Nakshatra, planets and dashas on your phone. Nothing is uploaded.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _edit,
            icon: const Icon(Icons.edit_calendar),
            label: const Text('Add birth details'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
        ]),
      );
    }
    final chart = Chart(_b!);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Stars'),
          actions: [IconButton(onPressed: _edit, icon: const Icon(Icons.edit_outlined), tooltip: 'Edit birth details')],
          bottom: const TabBar(tabs: [Tab(text: 'Today'), Tab(text: 'My chart'), Tab(text: 'Dasha')]),
        ),
        body: TabBarView(children: [_TodayTab(chart: chart), _ChartTab(chart: chart), _DashaTab(chart: chart)]),
      ),
    );
  }
}

// ---------------- Today ----------------
class _TodayTab extends StatefulWidget {
  final Chart chart;
  const _TodayTab({required this.chart});
  @override
  State<_TodayTab> createState() => _TodayTabState();
}

class _TodayTabState extends State<_TodayTab> {
  // Show today's panchang immediately for the birth place, then refine for where you are now.
  late Panchang? _p = Panchang.at(DateTime.now(), widget.chart.birth.lat, widget.chart.birth.lon, DateTime.now().timeZoneOffset);

  @override
  void initState() {
    super.initState();
    todayPlace(widget.chart.birth).then((loc) {
      if (mounted) setState(() => _p = Panchang.at(DateTime.now(), loc.$1, loc.$2, loc.$3));
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    if (p == null) return const Center(child: CircularProgressIndicator());
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final o = outlookFor(widget.chart, p);
    final now = DateTime.now();
    final rk = p.rahuKaal;
    final inRk = rk != null && now.isAfter(rk.$1) && now.isBefore(rk.$2);
    final d = widget.chart.currentDasha();
    return ListView(padding: pagePadding.copyWith(top: 12), children: [
      HeroCard(
        child: Column(children: [
          Text('★' * o.score + '☆' * (5 - o.score), style: TextStyle(fontSize: 34, color: Colors.amber.shade600, letterSpacing: 4)),
          const SizedBox(height: 6),
          Text(o.headline, style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('${p.vara} · ${p.paksha} ${p.tithiName} · Moon in ${nakshatras[p.nak].name}', textAlign: TextAlign.center, style: tt.bodyMedium),
        ]),
      ),
      AppCard(
        color: cs.tertiaryContainer,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Today’s focus · ${planetNames[p.dayLord]!.$1} (${planetNames[p.dayLord]!.$2}) day', style: tt.labelLarge),
          const SizedBox(height: 4),
          Text(o.focus.$1, style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(o.focus.$2, style: tt.bodyLarge),
          const SizedBox(height: 6),
          Text('🎨 Colour of the day: ${o.focus.$3}', style: tt.bodySmall),
        ]),
      ),
      if (rk != null)
        AppCard(
          color: inRk ? cs.errorContainer : null,
          child: Row(children: [
            Icon(Icons.do_not_disturb_on_outlined, color: inRk ? cs.error : null),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(inRk ? 'Rahu Kaal is ON now' : 'Rahu Kaal', style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('${hm(rk.$1)} – ${hm(rk.$2)} · traditionally avoided for new beginnings', style: tt.bodySmall),
              ]),
            ),
          ]),
        ),
      const SectionTitle('Why'),
      for (final (title, detail, good) in o.factors)
        AppCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(good > 0 ? '🟢' : good < 0 ? '🟠' : '⚪', style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(detail, style: tt.bodyMedium),
              ]),
            ),
          ]),
        ),
      const SectionTitle('Panchang'),
      AppCard(
        child: Column(children: [
          _kv('Vara', '${p.vara} (${planetNames[p.dayLord]!.$2})'),
          _kv('Tithi', '${p.paksha} ${p.tithiName}'),
          _kv('Nakshatra', nakshatras[p.nak].name),
          _kv('Yoga', yogaNames[p.yoga]),
          _kv('Karana', p.karana),
          _kv('Moon sign', '${rashis[p.moonSign].name} (${rashis[p.moonSign].english})'),
          if (p.sun != null) _kv('Sunrise / Sunset', '${hm(p.sun!.$1)} / ${hm(p.sun!.$2)}'),
        ]),
      ),
      if (d != null) ...[
        const SectionTitle('Running period'),
        AppCard(
          child: Text(
            '${planetNames[d.$1.lord]!.$1} Mahadasha → ${planetNames[d.$2.lord]!.$1} Antardasha\nuntil ${dmy(d.$2.end.toLocal())}',
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
      const _Disclaimer(),
    ]);
  }
}

Widget _kv(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(width: 130, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
        Expanded(child: Text(v)),
      ]),
    );

class _Disclaimer extends StatelessWidget {
  const _Disclaimer();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Text(
          'Positions are astronomically accurate (Lahiri ayanamsa, checked against Swiss Ephemeris). Interpretations are traditional Jyotish: use them for reflection, not for big decisions.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
}

// ---------------- My chart ----------------
class _ChartTab extends StatelessWidget {
  final Chart chart;
  const _ChartTab({required this.chart});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final c = chart;
    final n = nakshatras[c.nak];
    final moonR = rashis[c.moonSign], lagnaR = rashis[c.lagnaSign], sunR = rashis[c.sunSign];
    final b = c.birth;
    return ListView(padding: pagePadding.copyWith(top: 12), children: [
      Row(children: [
        _big(context, 'Lagna', lagnaR.symbol, lagnaR.name, lagnaR.english),
        _big(context, 'Moon (Rashi)', moonR.symbol, moonR.name, moonR.english),
        _big(context, 'Nakshatra', '✦', n.name, 'Pada ${c.pada}'),
      ]),
      const SizedBox(height: 4),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('🌙 ${n.name} nakshatra', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(n.traits, style: tt.bodyLarge),
          const SizedBox(height: 8),
          _kv('Lord', grahaLabel(n.lord)),
          _kv('Deity', n.deity),
          _kv('Symbol', n.symbol),
          _kv('Gana', n.gana),
          _kv('Pada', '${c.pada} of 4'),
        ]),
      ),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${lagnaR.symbol} Lagna: ${lagnaR.name} (${lagnaR.english})', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          Text('How you meet the world: ${lagnaR.traits}', style: tt.bodyMedium),
          const SizedBox(height: 10),
          Text('${moonR.symbol} Moon sign: ${moonR.name} (${moonR.english})', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          Text('Your mind & emotions: ${moonR.traits}', style: tt.bodyMedium),
          const SizedBox(height: 10),
          Text('${sunR.symbol} Sun sign (sidereal): ${sunR.name} (${sunR.english})', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          Text('Your core drive: ${sunR.traits}', style: tt.bodyMedium),
        ]),
      ),
      _ChartStyleSwitcher(chart: c),
      const SectionTitle('Planets'),
      AppCard(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(children: [
          _row(context, ['Graha', 'Sign', 'Degree', 'Nakshatra', 'H'], header: true),
          _row(context, ['Lagna', rashis[c.lagnaSign].name, dms(c.asc), '${nakshatras[nakOf(c.asc)].name} ${padaOf(c.asc)}', '1']),
          for (final p in ['sun', 'moon', 'mars', 'mercury', 'jupiter', 'venus', 'saturn', 'rahu', 'ketu'])
            _row(context, [
              planetNames[p]!.$1,
              rashis[signOf(c.pos[p]!)].name,
              dms(c.pos[p]!),
              '${nakshatras[nakOf(c.pos[p]!)].name} ${padaOf(c.pos[p]!)}',
              '${c.house(p)}',
            ]),
        ]),
      ),
      _MangalCard(chart: c),
      AppCard(
        child: Text(
          '${b.name.isEmpty ? 'Born' : b.name} · ${b.day}/${b.month}/${b.year} ${b.hour.toString().padLeft(2, '0')}:${b.minute.toString().padLeft(2, '0')}:${b.second.toString().padLeft(2, '0')} '
          '(UTC${b.tz >= 0 ? '+' : '−'}${b.tz.abs().floor()}:${((b.tz.abs() % 1) * 60).round().toString().padLeft(2, '0')}) · ${b.place} ${fmtLat(b.lat)}, ${fmtLon(b.lon)}',
          style: tt.bodySmall,
        ),
      ),
      const _Disclaimer(),
    ]);
  }

  Widget _big(BuildContext context, String label, String sym, String name, String sub) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
            child: Column(children: [
              Text(label, style: Theme.of(context).textTheme.labelSmall),
              Text(sym, style: const TextStyle(fontSize: 26)),
              Text(name, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(sub, style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ),
      );

  Widget _row(BuildContext context, List<String> cells, {bool header = false}) {
    const flex = [3, 3, 3, 4, 1];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        for (final (i, t) in cells.indexed)
          Expanded(
            flex: flex[i],
            child: Text(t, style: TextStyle(fontSize: 12, fontWeight: header || i == 0 ? FontWeight.w700 : null)),
          ),
      ]),
    );
  }
}

class _SouthChart extends StatelessWidget {
  final Chart chart;
  const _SouthChart({required this.chart});
  // Fixed sign positions in the 4×4 South Indian grid (row, col).
  static const _cell = {11: (0, 0), 0: (0, 1), 1: (0, 2), 2: (0, 3), 3: (1, 3), 4: (2, 3), 5: (3, 3), 6: (3, 2), 7: (3, 1), 8: (3, 0), 9: (2, 0), 10: (1, 0)};
  static const _abbr = {'sun': 'Su', 'moon': 'Mo', 'mars': 'Ma', 'mercury': 'Me', 'jupiter': 'Ju', 'venus': 'Ve', 'saturn': 'Sa', 'rahu': 'Ra', 'ketu': 'Ke'};

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bySign = <int, List<String>>{};
    for (final e in chart.pos.entries) {
      (bySign[signOf(e.value)] ??= []).add(_abbr[e.key]!);
    }
    return LayoutBuilder(builder: (_, box) {
      final s = box.maxWidth / 4;
      return Stack(children: [
        for (final e in _cell.entries)
          Positioned(
            top: e.value.$1 * s,
            left: e.value.$2 * s,
            width: s,
            height: s,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: cs.outlineVariant),
                color: e.key == chart.lagnaSign ? cs.primaryContainer : cs.surfaceContainerLow,
              ),
              padding: const EdgeInsets.all(4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${rashis[e.key].symbol} ${e.key == chart.lagnaSign ? 'Asc' : ''}',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text((bySign[e.key] ?? []).join(' '), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              ]),
            ),
          ),
        Positioned(
          top: s,
          left: s,
          width: 2 * s,
          height: 2 * s,
          child: Center(
            child: Text('Rasi\n${chart.birth.name}', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
        ),
      ]);
    });
  }
}

// ---------------- Dasha ----------------
class _DashaTab extends StatelessWidget {
  final Chart chart;
  const _DashaTab({required this.chart});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now().toUtc();
    final cur = chart.currentDasha();
    return ListView(padding: pagePadding.copyWith(top: 12), children: [
      if (cur != null)
        HeroCard(
          child: Column(children: [
            Text('Now running', style: tt.labelLarge),
            Text('${planetNames[cur.$1.lord]!.$1} – ${planetNames[cur.$2.lord]!.$1}', style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('${planetNames[cur.$2.lord]!.$2} sub-period until ${dmy(cur.$2.end.toLocal())}', style: tt.bodyMedium),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: now.difference(cur.$1.start).inMinutes / cur.$1.end.difference(cur.$1.start).inMinutes,
              minHeight: 8,
              borderRadius: BorderRadius.circular(8),
            ),
            const SizedBox(height: 4),
            Text('${planetNames[cur.$1.lord]!.$2} Mahadasha: ${dmy(cur.$1.start.toLocal())} → ${dmy(cur.$1.end.toLocal())}', style: tt.bodySmall),
          ]),
        ),
      const SectionTitle('Vimshottari Mahadashas'),
      for (final md in chart.mahadashas().take(9))
        Card(
          color: md.contains(now) ? cs.primaryContainer : null,
          child: ExpansionTile(
            shape: const RoundedRectangleBorder(),
            initiallyExpanded: md.contains(now),
            leading: Text(planetNames[md.lord]!.$3, style: const TextStyle(fontSize: 22)),
            title: Text(grahaLabel(md.lord), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${dmy(md.start.toLocal())} → ${dmy(md.end.toLocal())}'),
            children: [
              for (final ad in Chart.antardashas(md))
                ListTile(
                  dense: true,
                  leading: ad.contains(now) ? const Icon(Icons.play_arrow) : const SizedBox(width: 24),
                  title: Text('${planetNames[md.lord]!.$1} – ${planetNames[ad.lord]!.$1}',
                      style: TextStyle(fontWeight: ad.contains(now) ? FontWeight.w800 : null)),
                  subtitle: Text('${dmy(ad.start.toLocal())} → ${dmy(ad.end.toLocal())}', style: tt.bodySmall),
                ),
            ],
          ),
        ),
      const _Disclaimer(),
    ]);
  }
}

// ---------------- Birth form ----------------
class BirthForm extends StatefulWidget {
  final BirthData? initial;
  const BirthForm({super.key, this.initial});
  @override
  State<BirthForm> createState() => _BirthFormState();
}

class _BirthFormState extends State<BirthForm> {
  late final b = widget.initial;
  late final _name = TextEditingController(text: b?.name ?? Store.profile['name']);
  late DateTime? _date = b == null ? null : DateTime(b!.year, b!.month, b!.day);
  late final _h = TextEditingController(text: b == null ? '' : '${b!.hour}');
  late final _m = TextEditingController(text: b == null ? '' : '${b!.minute}');
  late final _s = TextEditingController(text: b == null ? '0' : '${b!.second}');
  late final _place = TextEditingController(text: b?.place ?? '');
  bool _pm = false;
  String? _error;

  // Coordinates: degrees/minutes/seconds + direction (default) or decimal.
  bool _dms = true;
  final _latD = TextEditingController(), _latM = TextEditingController(), _latS = TextEditingController();
  final _lonD = TextEditingController(), _lonM = TextEditingController(), _lonS = TextEditingController();
  bool _south = false, _west = false;
  final _latDec = TextEditingController(), _lonDec = TextEditingController();
  // UTC offset as ± hh:mm
  bool _tzNeg = false;
  final _tzH = TextEditingController(text: '5'), _tzM = TextEditingController(text: '30');

  @override
  void initState() {
    super.initState();
    if (b != null) {
      _pm = b!.hour >= 12;
      final h12 = b!.hour % 12 == 0 ? 12 : b!.hour % 12;
      _h.text = '$h12';
      _setCoords(b!.lat, b!.lon);
      _setTz(b!.tz);
    }
  }

  static (int, int, double) _toDms(double v) {
    final a = v.abs();
    var d = a.floor();
    var m = ((a - d) * 60).floor();
    var s = double.parse(((a - d - m / 60) * 3600).toStringAsFixed(1));
    if (s >= 60) {
      s -= 60;
      m++;
    }
    if (m >= 60) {
      m -= 60;
      d++;
    }
    return (d, m, s);
  }

  static String _fmtS(double s) => s == s.roundToDouble() ? '${s.round()}' : s.toStringAsFixed(1);

  void _setCoords(double lat, double lon) {
    final (ld, lm, ls) = _toDms(lat);
    final (gd, gm, gs) = _toDms(lon);
    _latD.text = '$ld';
    _latM.text = '$lm';
    _latS.text = _fmtS(ls);
    _south = lat < 0;
    _lonD.text = '$gd';
    _lonM.text = '$gm';
    _lonS.text = _fmtS(gs);
    _west = lon < 0;
    _latDec.text = lat.toStringAsFixed(6);
    _lonDec.text = lon.toStringAsFixed(6);
  }

  void _setTz(double tz) {
    _tzNeg = tz < 0;
    final mins = (tz.abs() * 60).round();
    _tzH.text = '${mins ~/ 60}';
    _tzM.text = (mins % 60).toString().padLeft(2, '0');
  }

  /// Current coordinates as decimals, or null if incomplete/invalid.
  (double, double)? _coords() {
    if (!_dms) {
      final lat = double.tryParse(_latDec.text), lon = double.tryParse(_lonDec.text);
      return lat == null || lon == null || lat.abs() > 90 || lon.abs() > 180 ? null : (lat, lon);
    }
    double? part(TextEditingController d, TextEditingController m, TextEditingController s, int maxDeg) {
      final dd = int.tryParse(d.text), mm = int.tryParse(m.text.isEmpty ? '0' : m.text), ss = double.tryParse(s.text.isEmpty ? '0' : s.text);
      if (dd == null || mm == null || ss == null || dd < 0 || dd > maxDeg || mm < 0 || mm > 59 || ss < 0 || ss >= 60) return null;
      return dd + mm / 60 + ss / 3600;
    }

    final lat = part(_latD, _latM, _latS, 90), lon = part(_lonD, _lonM, _lonS, 180);
    if (lat == null || lon == null) return null;
    return (_south ? -lat : lat, _west ? -lon : lon);
  }

  double? _tzValue() {
    final h = int.tryParse(_tzH.text), m = int.tryParse(_tzM.text.isEmpty ? '0' : _tzM.text);
    if (h == null || m == null || h > 14 || m > 59) return null;
    return (_tzNeg ? -1 : 1) * (h + m / 60);
  }

  void _pickPlace((String, double, double, double) p) => setState(() {
        _place.text = p.$1;
        _setCoords(p.$2, p.$3);
        _setTz(p.$4);
      });

  Future<void> _save() async {
    final h = int.tryParse(_h.text), m = int.tryParse(_m.text), s = int.tryParse(_s.text.isEmpty ? '0' : _s.text);
    final c = _coords(), tz = _tzValue();
    String? err;
    if (_date == null) err = 'Pick your date of birth';
    if (h == null || h < 1 || h > 12 || m == null || m < 0 || m > 59 || s == null || s < 0 || s > 59) err ??= 'Enter time as hh (1–12) : mm : ss';
    if (c == null) err ??= 'Choose a birth place, or enter latitude/longitude (degrees 0–90 / 0–180, minutes & seconds 0–59)';
    if (tz == null) err ??= 'Enter the UTC offset as hh:mm (India = +5:30)';
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() => _error = null);
    final data = BirthData(
      name: _name.text.trim(), place: _place.text.trim(), year: _date!.year, month: _date!.month, day: _date!.day,
      hour: (h! % 12) + (_pm ? 12 : 0), minute: m!, second: s!, tz: tz!, lat: c!.$1, lon: c.$2,
    );
    // Confirm in words, with a preview, so a wrong date/time can't slip through silently.
    final chart = Chart(data);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Is this right?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][_date!.weekday - 1]}, '
              '${_date!.day} ${const ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][_date!.month - 1]} ${_date!.year}',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          Text('${_h.text}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')} ${_pm ? 'PM' : 'AM'} (UTC${_tzNeg ? '−' : '+'}${_tzH.text}:${_tzM.text.padLeft(2, '0')})'),
          Text('${data.place.isEmpty ? 'Place' : data.place}: ${fmtLat(data.lat)}, ${fmtLon(data.lon)}'),
          const Divider(height: 24),
          Text('Moon: ${nakshatras[chart.nak].name} pada ${chart.pada} · ${nakshatras[chart.nak].gana} gana'),
          Text('Rashi: ${rashis[chart.moonSign].name} · Lagna: ${rashis[chart.lagnaSign].name}'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Edit')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Looks right')),
        ],
      ),
    );
    if (ok == true && mounted) Navigator.pop(context, data);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    InputDecoration dec(String l, {String? hint, String? suffix}) =>
        InputDecoration(labelText: l, hintText: hint, suffixText: suffix, border: const OutlineInputBorder(), counterText: '', isDense: true);
    Widget num(TextEditingController c, String l, {int len = 2, bool decimal = false}) => Expanded(
          child: TextField(
            controller: c,
            maxLength: len,
            textAlign: TextAlign.center,
            onChanged: (_) => setState(() {}),
            keyboardType: TextInputType.numberWithOptions(decimal: decimal),
            decoration: dec(l),
          ),
        );
    Widget dir(String a, String b2, bool second, ValueChanged<bool> set) => SegmentedButton<bool>(
          segments: [ButtonSegment(value: false, label: Text(a)), ButtonSegment(value: true, label: Text(b2))],
          selected: {second},
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          onSelectionChanged: (s) => setState(() => set(s.first)),
        );
    final c = _coords();
    return Scaffold(
      appBar: AppBar(title: const Text('Birth details')),
      body: ListView(padding: pagePadding.copyWith(top: 12), children: [
        TextField(controller: _name, decoration: dec('Name')),
        const SizedBox(height: 16),
        Text('Date of birth', style: tt.labelLarge),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: _date ?? DateTime(2000, 1, 1),
              firstDate: DateTime(1900),
              lastDate: DateTime.now(),
              initialEntryMode: DatePickerEntryMode.input,
              helpText: 'Date of birth (DD/MM/YYYY)',
              fieldHintText: 'DD/MM/YYYY',
            );
            if (d != null) setState(() => _date = d);
          },
          icon: const Icon(Icons.cake_outlined),
          label: Text(_date == null ? 'Pick date (DD/MM/YYYY)' : dmy(_date!)),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
        const SizedBox(height: 16),
        Text('Exact time of birth (seconds help with Lagna & pada)', style: tt.labelLarge),
        const SizedBox(height: 6),
        Row(children: [
          num(_h, 'hh'),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text(':', style: TextStyle(fontSize: 20))),
          num(_m, 'mm'),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text(':', style: TextStyle(fontSize: 20))),
          num(_s, 'ss'),
          const SizedBox(width: 8),
          SegmentedButton<bool>(
            segments: const [ButtonSegment(value: false, label: Text('AM')), ButtonSegment(value: true, label: Text('PM'))],
            selected: {_pm},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _pm = s.first),
          ),
        ]),
        const SizedBox(height: 16),
        Text('Place of birth', style: tt.labelLarge),
        const SizedBox(height: 6),
        Autocomplete<(String, double, double, double)>(
          initialValue: TextEditingValue(text: _place.text),
          displayStringForOption: (p) => p.$1,
          optionsBuilder: (v) => v.text.isEmpty ? const [] : places.where((p) => p.$1.toLowerCase().contains(v.text.toLowerCase())),
          onSelected: _pickPlace,
          fieldViewBuilder: (context, c, f, onSubmit) => TextField(
            controller: c,
            focusNode: f,
            decoration: dec('City (fills coordinates)', hint: 'Start typing, e.g. Delhi'),
            onChanged: (v) => _place.text = v,
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Text('Coordinates', style: tt.labelLarge),
          const Spacer(),
          SegmentedButton<bool>(
            segments: const [ButtonSegment(value: true, label: Text('° ′ ″')), ButtonSegment(value: false, label: Text('Decimal'))],
            selected: {_dms},
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onSelectionChanged: (v) => setState(() {
              final cur = _coords();
              _dms = v.first;
              if (cur != null) _setCoords(cur.$1, cur.$2);
            }),
          ),
        ]),
        const SizedBox(height: 8),
        if (_dms) ...[
          Row(children: [
            SizedBox(width: 44, child: Text('Lat', style: tt.bodySmall)),
            num(_latD, 'deg'),
            const SizedBox(width: 4),
            num(_latM, 'min'),
            const SizedBox(width: 4),
            num(_latS, 'sec', len: 4, decimal: true),
            const SizedBox(width: 6),
            dir('N', 'S', _south, (v) => _south = v),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            SizedBox(width: 44, child: Text('Long', style: tt.bodySmall)),
            num(_lonD, 'deg', len: 3),
            const SizedBox(width: 4),
            num(_lonM, 'min'),
            const SizedBox(width: 4),
            num(_lonS, 'sec', len: 4, decimal: true),
            const SizedBox(width: 6),
            dir('E', 'W', _west, (v) => _west = v),
          ]),
        ] else
          Row(children: [
            Expanded(
              child: TextField(
                controller: _latDec,
                onChanged: (_) => setState(() {}),
                keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                decoration: dec('Latitude', hint: '28.613900'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _lonDec,
                onChanged: (_) => setState(() {}),
                keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                decoration: dec('Longitude', hint: '77.209000'),
              ),
            ),
          ]),
        const SizedBox(height: 6),
        Text(
          c == null ? 'Enter both coordinates' : '= ${fmtLat(c.$1)}, ${fmtLon(c.$2)}  (${c.$1.toStringAsFixed(5)}, ${c.$2.toStringAsFixed(5)})',
          style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Text('UTC offset', style: tt.labelLarge),
          const SizedBox(width: 12),
          SegmentedButton<bool>(
            segments: const [ButtonSegment(value: false, label: Text('+')), ButtonSegment(value: true, label: Text('−'))],
            selected: {_tzNeg},
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onSelectionChanged: (v) => setState(() => _tzNeg = v.first),
          ),
          const SizedBox(width: 8),
          SizedBox(width: 56, child: TextField(controller: _tzH, maxLength: 2, textAlign: TextAlign.center, keyboardType: TextInputType.number, decoration: dec('hh'))),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text(':')),
          SizedBox(width: 56, child: TextField(controller: _tzM, maxLength: 2, textAlign: TextAlign.center, keyboardType: TextInputType.number, decoration: dec('mm'))),
        ]),
        const SizedBox(height: 4),
        Text('India = +05:30. Coordinates: Google Maps → long-press the spot, or any kundli site.', style: tt.bodySmall),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w700)),
        ],
        const SizedBox(height: 20),
        FilledButton(onPressed: _save, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)), child: const Text('Calculate my chart ✨')),
      ]),
    );
  }
}

String _dmsStr(double v) {
  final a = v.abs();
  final d = a.floor();
  final mf = (a - d) * 60;
  final m = mf.floor();
  final s = ((mf - m) * 60).round();
  return '$d°${m.toString().padLeft(2, '0')}′${s.toString().padLeft(2, '0')}″';
}

String fmtLat(double v) => '${_dmsStr(v)} ${v < 0 ? 'S' : 'N'}';
String fmtLon(double v) => '${_dmsStr(v)} ${v < 0 ? 'W' : 'E'}';

class _MangalCard extends StatelessWidget {
  final Chart chart;
  const _MangalCard({required this.chart});
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final m = chart.mangal;
    final (icon, verdict) = switch (m.level) {
      'none' => ('🟢', 'Not Manglik'),
      'cancelled' => ('🟢', 'Not Manglik: Mangal dosha is cancelled'),
      'low' => ('🟡', 'Low (Anshik) Mangal dosha: not from Lagna'),
      _ => ('🔴', 'Manglik'),
    };
    String h(int n) => '${ordinal(n)}${const {1, 2, 4, 7, 8, 12}.contains(n) ? ' ⚠' : ''}';
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(child: Text(verdict, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 8),
        Text('Mars is in the ${h(m.fromLagna)} house from Lagna, ${h(m.fromMoon)} from Moon, ${h(m.fromVenus)} from Venus.', style: tt.bodyMedium),
        if (m.cancellations.isNotEmpty && m.present) ...[
          const SizedBox(height: 6),
          Text('Cancelled by: ${m.cancellations.join('; ')}.', style: tt.bodyMedium),
        ],
        if (m.fromLagna == 2 && !m.cancelled) ...[
          const SizedBox(height: 6),
          Text('Note: many North Indian calculators don’t count the 2nd house, so they’d show “not Manglik”.', style: tt.bodySmall),
        ],
        const SizedBox(height: 6),
        Text('Rule: Mars in 1, 2, 4, 7, 8 or 12 (Lagna is primary; Moon/Venus are secondary), with classical cancellations.', style: tt.bodySmall),
      ]),
    );
  }
}

/// Rasi chart with a North / South Indian style switch (North is the default).
class _ChartStyleSwitcher extends StatefulWidget {
  final Chart chart;
  const _ChartStyleSwitcher({required this.chart});
  @override
  State<_ChartStyleSwitcher> createState() => _ChartStyleSwitcherState();
}

class _ChartStyleSwitcherState extends State<_ChartStyleSwitcher> {
  late bool _north = (Store.raw.getString('chart_style') ?? 'north') == 'north';

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle(
        'Birth chart (Lagna kundli)',
        trailing: SegmentedButton<bool>(
          segments: const [ButtonSegment(value: true, label: Text('North')), ButtonSegment(value: false, label: Text('South'))],
          selected: {_north},
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          onSelectionChanged: (v) {
            Store.raw.setString('chart_style', v.first ? 'north' : 'south');
            setState(() => _north = v.first);
          },
        ),
      ),
      AspectRatio(aspectRatio: 1, child: _north ? NorthChart(chart: widget.chart) : _SouthChart(chart: widget.chart)),
      const SizedBox(height: 4),
      Text(
        _north
            ? 'Top-centre diamond is the 1st house (Lagna); houses run anticlockwise. Numbers are rashis (1 = Mesha … 12 = Meena).'
            : 'Signs are fixed (Meena top-left, clockwise); the highlighted box is your Lagna.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ]);
  }
}

/// North Indian (diamond) chart: houses are fixed, signs rotate with the Lagna.
class NorthChart extends StatelessWidget {
  final Chart chart;
  const NorthChart({super.key, required this.chart});

  // Label centre for houses 1..12 (unit square), anticlockwise from the top diamond.
  static const _center = [
    Offset(0.5, 0.24), Offset(0.25, 0.09), Offset(0.09, 0.25), Offset(0.25, 0.5), Offset(0.09, 0.75), Offset(0.25, 0.91),
    Offset(0.5, 0.76), Offset(0.75, 0.91), Offset(0.91, 0.75), Offset(0.75, 0.5), Offset(0.91, 0.25), Offset(0.75, 0.09),
  ];
  // Rashi number position: tucked into each house's inner corner.
  static const _signAt = [
    Offset(0.5, 0.42), Offset(0.25, 0.2), Offset(0.2, 0.25), Offset(0.42, 0.5), Offset(0.2, 0.75), Offset(0.25, 0.8),
    Offset(0.5, 0.58), Offset(0.75, 0.8), Offset(0.8, 0.75), Offset(0.58, 0.5), Offset(0.8, 0.25), Offset(0.75, 0.2),
  ];
  static const _abbr = {'sun': 'Su', 'moon': 'Mo', 'mars': 'Ma', 'mercury': 'Me', 'jupiter': 'Ju', 'venus': 'Ve', 'saturn': 'Sa', 'rahu': 'Ra', 'ketu': 'Ke'};

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final byHouse = <int, List<String>>{};
    for (final e in chart.pos.entries) {
      (byHouse[chart.house(e.key)] ??= []).add(_abbr[e.key]!);
    }
    return LayoutBuilder(builder: (_, box) {
      final s = box.maxWidth;
      Widget at(Offset o, Widget child, {double w = 0.3}) => Positioned(
            left: (o.dx - w / 2) * s,
            top: o.dy * s - 14,
            width: w * s,
            child: Center(child: child),
          );
      return Stack(children: [
        Positioned.fill(child: CustomPaint(painter: _NorthPainter(cs.outline, cs.primaryContainer, cs.surfaceContainerLow))),
        for (var h = 1; h <= 12; h++) ...[
          at(
            _signAt[h - 1],
            Text('${(chart.lagnaSign + h - 1) % 12 + 1}', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
            w: 0.1,
          ),
          at(
            _center[h - 1].translate(0, h == 1 ? -0.03 : 0),
            Column(mainAxisSize: MainAxisSize.min, children: [
              if (h == 1) Text('Lagna', style: TextStyle(fontSize: 10, color: cs.primary, fontWeight: FontWeight.w800)),
              Text(
                (byHouse[h] ?? []).join(' '),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, height: 1.15),
              ),
            ]),
            w: const {2, 3, 5, 6, 8, 9, 11, 12}.contains(h) ? 0.2 : 0.3,
          ),
        ],
      ]);
    });
  }
}

class _NorthPainter extends CustomPainter {
  final Color line, lagnaFill, fill;
  _NorthPainter(this.line, this.lagnaFill, this.fill);

  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    c.drawRect(Offset.zero & s, Paint()..color = fill);
    // Lagna diamond highlighted
    c.drawPath(Path()..moveTo(w / 2, 0)..lineTo(w * 0.75, h * 0.25)..lineTo(w / 2, h / 2)..lineTo(w * 0.25, h * 0.25)..close(), Paint()..color = lagnaFill);
    final p = Paint()
      ..color = line
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    c.drawRect((Offset.zero & s).deflate(0.8), p);
    c.drawLine(Offset.zero, Offset(w, h), p);
    c.drawLine(Offset(w, 0), Offset(0, h), p);
    c.drawPath(Path()..moveTo(w / 2, 0)..lineTo(w, h / 2)..lineTo(w / 2, h)..lineTo(0, h / 2)..close(), p);
  }

  @override
  bool shouldRepaint(_NorthPainter o) => o.line != line || o.lagnaFill != lagnaFill;
}
