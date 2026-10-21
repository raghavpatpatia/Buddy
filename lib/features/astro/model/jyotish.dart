import 'dart:math';

import 'engine.dart';

const nakSpan = 40 / 3; // 13°20′
const padaSpan = 10 / 3; // 3°20′

class Rashi {
  final String name, english, symbol, lord, traits;
  const Rashi(this.name, this.english, this.symbol, this.lord, this.traits);
}

const rashis = [
  Rashi('Mesha', 'Aries', '♈', 'mars', 'Bold starter, energetic, direct, competitive; learns by doing.'),
  Rashi('Vrishabha', 'Taurus', '♉', 'venus', 'Steady, patient, loves comfort and beauty; builds things that last.'),
  Rashi('Mithuna', 'Gemini', '♊', 'mercury', 'Curious, witty, communicative; thrives on ideas and variety.'),
  Rashi('Karka', 'Cancer', '♋', 'moon', 'Caring, intuitive, protective of family; strong emotional memory.'),
  Rashi('Simha', 'Leo', '♌', 'sun', 'Confident, generous, creative; natural leader who likes to shine.'),
  Rashi('Kanya', 'Virgo', '♍', 'mercury', 'Analytical, precise, helpful; spots the bug everyone else missed.'),
  Rashi('Tula', 'Libra', '♎', 'venus', 'Balanced, diplomatic, aesthetic; values fairness and partnership.'),
  Rashi('Vrischika', 'Scorpio', '♏', 'mars', 'Intense, private, determined; digs deep and transforms.'),
  Rashi('Dhanu', 'Sagittarius', '♐', 'jupiter', 'Optimistic, philosophical, adventurous; seeks meaning and truth.'),
  Rashi('Makara', 'Capricorn', '♑', 'saturn', 'Disciplined, practical, ambitious; climbs slowly and surely.'),
  Rashi('Kumbha', 'Aquarius', '♒', 'saturn', 'Inventive, independent, humanitarian; thinks in systems.'),
  Rashi('Meena', 'Pisces', '♓', 'jupiter', 'Imaginative, compassionate, artistic; deeply intuitive.'),
];

class Nakshatra {
  final String name, lord, deity, symbol, gana, traits;
  const Nakshatra(this.name, this.lord, this.deity, this.symbol, this.gana, this.traits);
}

const nakshatras = [
  Nakshatra('Ashwini', 'ketu', 'Ashwini Kumaras', 'Horse’s head', 'Deva', 'Quick, healing, pioneering; loves speed and fresh starts.'),
  Nakshatra('Bharani', 'venus', 'Yama', 'Yoni', 'Manushya', 'Intense, responsible, creative; carries heavy loads with grace.'),
  Nakshatra('Krittika', 'sun', 'Agni', 'Razor / flame', 'Rakshasa', 'Sharp, purifying, honest; cuts through confusion.'),
  Nakshatra('Rohini', 'moon', 'Brahma', 'Chariot', 'Manushya', 'Charming, artistic, fertile mind; grows ideas into reality.'),
  Nakshatra('Mrigashira', 'mars', 'Soma', 'Deer’s head', 'Deva', 'Curious searcher, gentle, restless; always exploring.'),
  Nakshatra('Ardra', 'rahu', 'Rudra', 'Teardrop', 'Manushya', 'Intellectual storms, research, transformation through effort.'),
  Nakshatra('Punarvasu', 'jupiter', 'Aditi', 'Quiver of arrows', 'Deva', 'Renewal, optimism, bouncing back; generous and wise.'),
  Nakshatra('Pushya', 'saturn', 'Brihaspati', 'Cow’s udder', 'Deva', 'Nourishing, dutiful, most auspicious; a natural mentor.'),
  Nakshatra('Ashlesha', 'mercury', 'Nagas', 'Coiled serpent', 'Rakshasa', 'Perceptive, strategic, hypnotic; reads people well.'),
  Nakshatra('Magha', 'ketu', 'Pitrs (ancestors)', 'Throne', 'Rakshasa', 'Regal, traditional, proud of roots; leads with authority.'),
  Nakshatra('Purva Phalguni', 'venus', 'Bhaga', 'Front legs of a bed', 'Manushya', 'Playful, romantic, creative; enjoys life and rest.'),
  Nakshatra('Uttara Phalguni', 'sun', 'Aryaman', 'Back legs of a bed', 'Manushya', 'Loyal, helpful, contract-keeper; great at partnerships.'),
  Nakshatra('Hasta', 'moon', 'Savitar', 'Hand', 'Deva', 'Skilful with hands, clever, crafty; a builder and maker.'),
  Nakshatra('Chitra', 'mars', 'Vishvakarma', 'Bright jewel', 'Rakshasa', 'Designer’s eye, architect, loves beautiful structures.'),
  Nakshatra('Swati', 'rahu', 'Vayu', 'Young sprout in wind', 'Deva', 'Independent, flexible, business-minded; moves freely.'),
  Nakshatra('Vishakha', 'jupiter', 'Indra–Agni', 'Triumphal arch', 'Rakshasa', 'Goal-driven, determined; reaches the target eventually.'),
  Nakshatra('Anuradha', 'saturn', 'Mitra', 'Lotus', 'Deva', 'Friendly, devoted, organised; succeeds through teamwork.'),
  Nakshatra('Jyeshtha', 'mercury', 'Indra', 'Earring / umbrella', 'Rakshasa', 'Protective elder, responsible, resourceful under pressure.'),
  Nakshatra('Mula', 'ketu', 'Nirriti', 'Bunch of roots', 'Rakshasa', 'Gets to the root of things; researcher, seeker of truth.'),
  Nakshatra('Purva Ashadha', 'venus', 'Apas (waters)', 'Fan', 'Manushya', 'Invincible spirit, persuasive, proud; refuses to give up.'),
  Nakshatra('Uttara Ashadha', 'sun', 'Vishvedevas', 'Elephant tusk', 'Manushya', 'Principled, patient, final victory through integrity.'),
  Nakshatra('Shravana', 'moon', 'Vishnu', 'Ear', 'Deva', 'Great listener and learner; gains wisdom by hearing.'),
  Nakshatra('Dhanishta', 'mars', 'Eight Vasus', 'Drum', 'Rakshasa', 'Rhythmic, musical, wealthy in talent; loves groups.'),
  Nakshatra('Shatabhisha', 'rahu', 'Varuna', 'Empty circle', 'Rakshasa', 'Healer, scientist, secretive; solves hidden problems.'),
  Nakshatra('Purva Bhadrapada', 'jupiter', 'Aja Ekapada', 'Swords / front of cot', 'Manushya', 'Passionate idealist, intense, transformative.'),
  Nakshatra('Uttara Bhadrapada', 'saturn', 'Ahirbudhnya', 'Back of a cot / twins', 'Manushya', 'Calm depth, wise, self-controlled; steady under pressure.'),
  Nakshatra('Revati', 'mercury', 'Pushan', 'Fish', 'Deva', 'Gentle guide, kind, imaginative; finishes journeys safely.'),
];

const planetNames = {
  'sun': ('Surya', 'Sun', '☉'), 'moon': ('Chandra', 'Moon', '☽'), 'mars': ('Mangal', 'Mars', '♂'),
  'mercury': ('Budh', 'Mercury', '☿'), 'jupiter': ('Guru', 'Jupiter', '♃'), 'venus': ('Shukra', 'Venus', '♀'),
  'saturn': ('Shani', 'Saturn', '♄'), 'rahu': ('Rahu', 'Rahu', '☊'), 'ketu': ('Ketu', 'Ketu', '☋'),
};

const _dashaOrder = ['ketu', 'venus', 'sun', 'moon', 'mars', 'rahu', 'jupiter', 'saturn', 'mercury'];
const _dashaYears = {'ketu': 7, 'venus': 20, 'sun': 6, 'moon': 10, 'mars': 7, 'rahu': 18, 'jupiter': 16, 'saturn': 19, 'mercury': 17};
const _yearDays = 365.2425;

const tithiNames = ['Pratipada', 'Dwitiya', 'Tritiya', 'Chaturthi', 'Panchami', 'Shashthi', 'Saptami', 'Ashtami', 'Navami', 'Dashami', 'Ekadashi', 'Dwadashi', 'Trayodashi', 'Chaturdashi'];
const yogaNames = ['Vishkambha', 'Priti', 'Ayushman', 'Saubhagya', 'Shobhana', 'Atiganda', 'Sukarma', 'Dhriti', 'Shula', 'Ganda', 'Vriddhi', 'Dhruva', 'Vyaghata', 'Harshana', 'Vajra', 'Siddhi', 'Vyatipata', 'Variyan', 'Parigha', 'Shiva', 'Siddha', 'Sadhya', 'Shubha', 'Shukla', 'Brahma', 'Indra', 'Vaidhriti'];
const _movableKaranas = ['Bava', 'Balava', 'Kaulava', 'Taitila', 'Gara', 'Vanija', 'Vishti (Bhadra)'];
const varaNames = ['Somavara', 'Mangalavara', 'Budhavara', 'Guruvara', 'Shukravara', 'Shanivara', 'Ravivara']; // Mon..Sun (DateTime.weekday 1..7)
const varaLords = ['moon', 'mars', 'mercury', 'jupiter', 'venus', 'saturn', 'sun'];

/// "Guru (Jupiter)", but just "Rahu" when both names are the same.
String grahaLabel(String p) {
  final (hi, en, _) = planetNames[p]!;
  return hi == en ? hi : '$hi ($en)';
}

int signOf(double lon) => (lon / 30).floor() % 12;
int nakOf(double lon) => (lon / nakSpan).floor() % 27;
int padaOf(double lon) => ((lon % nakSpan) / padaSpan).floor() + 1;
String dms(double lon) {
  final inSign = lon % 30;
  final d = inSign.floor(), m = ((inSign - d) * 60).floor(), s = (((inSign - d) * 60 - m) * 60).floor();
  return '$d°${m.toString().padLeft(2, '0')}′${s.toString().padLeft(2, '0')}″';
}

class BirthData {
  final String name, place;
  final int year, month, day, hour, minute, second; // local civil time
  final double tz, lat, lon; // tz in hours (India = 5.5)
  const BirthData({
    required this.name,
    required this.place,
    required this.year,
    required this.month,
    required this.day,
    required this.hour,
    required this.minute,
    required this.second,
    required this.tz,
    required this.lat,
    required this.lon,
  });

  DateTime get utc => DateTime.utc(year, month, day, hour, minute, second).subtract(Duration(minutes: (tz * 60).round()));

  Map<String, dynamic> toJson() => {
        'name': name, 'place': place, 'y': year, 'mo': month, 'd': day, 'h': hour, 'mi': minute, 's': second, 'tz': tz, 'lat': lat, 'lon': lon,
      };
  static BirthData fromJson(Map m) => BirthData(
        name: m['name'] ?? '', place: m['place'] ?? '', year: m['y'], month: m['mo'], day: m['d'], hour: m['h'], minute: m['mi'],
        second: m['s'] ?? 0, tz: (m['tz'] as num).toDouble(), lat: (m['lat'] as num).toDouble(), lon: (m['lon'] as num).toDouble(),
      );
}

class Dasha {
  final String lord;
  final DateTime start, end;
  const Dasha(this.lord, this.start, this.end);
  bool contains(DateTime t) => !t.isBefore(start) && t.isBefore(end);
}

class Chart {
  final BirthData birth;
  final Map<String, double> pos;
  final double asc;
  Chart(this.birth)
      : pos = siderealPositions(birth.utc),
        asc = siderealAscendant(birth.utc, birth.lat, birth.lon);

  int get lagnaSign => signOf(asc);
  int get moonSign => signOf(pos['moon']!);
  int get sunSign => signOf(pos['sun']!);
  int get nak => nakOf(pos['moon']!);
  int get pada => padaOf(pos['moon']!);

  /// Whole-sign house (1..12) counted from the Lagna.
  int house(String p) => (signOf(pos[p]!) - lagnaSign) % 12 + 1;

  MangalDosha get mangal => MangalDosha.of(this);

  /// Vimshottari Mahadashas from birth for 120 years.
  List<Dasha> mahadashas() {
    final moon = pos['moon']!;
    final lord = _dashaOrder[nak % 9];
    final fractionLeft = 1 - (moon % nakSpan) / nakSpan;
    final out = <Dasha>[];
    var start = birth.utc.subtract(Duration(minutes: ((1 - fractionLeft) * _dashaYears[lord]! * _yearDays * 1440).round()));
    var i = _dashaOrder.indexOf(lord);
    for (var n = 0; n < 10; n++) {
      final l = _dashaOrder[(i + n) % 9];
      final end = start.add(Duration(minutes: (_dashaYears[l]! * _yearDays * 1440).round()));
      out.add(Dasha(l, start, end));
      start = end;
    }
    return out;
  }

  static List<Dasha> antardashas(Dasha md) {
    final total = md.end.difference(md.start).inMinutes;
    final i = _dashaOrder.indexOf(md.lord);
    var s = md.start;
    return [
      for (var n = 0; n < 9; n++)
        (() {
          final l = _dashaOrder[(i + n) % 9];
          final e = s.add(Duration(minutes: (total * _dashaYears[l]! / 120).round()));
          final d = Dasha(l, s, e);
          s = e;
          return d;
        })(),
    ];
  }

  (Dasha, Dasha)? currentDasha([DateTime? at]) {
    final t = (at ?? DateTime.now()).toUtc();
    for (final md in mahadashas()) {
      if (md.contains(t)) {
        for (final ad in antardashas(md)) {
          if (ad.contains(t)) return (md, ad);
        }
      }
    }
    return null;
  }
}

class Panchang {
  final DateTime at;
  final Map<String, double> pos;
  final int tithi; // 1..30
  final int nak, yoga;
  final String karana;
  final int weekday; // DateTime.weekday of the Vedic day (changes at sunrise)
  final (DateTime, DateTime)? sun;
  final (DateTime, DateTime)? rahuKaal;

  factory Panchang.at(DateTime local, double lat, double lon, Duration tz) {
    final pos = siderealPositions(local);
    final s = pos['sun']!, m = pos['moon']!;
    final elong = (m - s) % 360;
    final tithi = (elong / 12).floor() + 1;
    final k = (elong / 6).floor();
    final karana = k == 0 ? 'Kimstughna' : k >= 57 ? ['Shakuni', 'Chatushpada', 'Naga'][k - 57] : _movableKaranas[(k - 1) % 7];
    final yoga = (((s + m) % 360) / nakSpan).floor() % 27;
    final st = sunTimes(local, lat, lon, tz);
    var wd = local.weekday;
    if (st != null && local.isBefore(st.$1)) wd = wd == 1 ? 7 : wd - 1;
    (DateTime, DateTime)? rk;
    if (st != null) {
      final part = st.$2.difference(st.$1) ~/ 8;
      const idx = {1: 1, 2: 6, 3: 4, 4: 5, 5: 3, 6: 2, 7: 7}; // Mon 2nd … Sun 8th segment
      final i = idx[local.weekday]!;
      rk = (st.$1.add(part * i), st.$1.add(part * (i + 1)));
    }
    return Panchang._(local, pos, tithi, nakOf(m), yoga, karana, wd, st, rk);
  }
  Panchang._(this.at, this.pos, this.tithi, this.nak, this.yoga, this.karana, this.weekday, this.sun, this.rahuKaal);

  String get paksha => tithi <= 15 ? 'Shukla' : 'Krishna';
  String get tithiName => tithi == 15 ? 'Purnima' : tithi == 30 ? 'Amavasya' : tithiNames[(tithi - 1) % 15];
  String get vara => varaNames[weekday - 1];
  String get dayLord => varaLords[weekday - 1];
  int get moonSign => signOf(pos['moon']!);
}

const taraNames = ['Janma', 'Sampat', 'Vipat', 'Kshema', 'Pratyari', 'Sadhaka', 'Vadha', 'Mitra', 'Param Mitra'];
const _taraGood = [0, 1, -1, 1, -1, 1, -1, 1, 2]; // −1 challenging … +2 very good

const _dayFocus = {
  'sun': ('Leadership & visibility', 'Present your work, take ownership, talk to seniors.', 'Orange / red'),
  'moon': ('Home, feelings & rest', 'Call family, hydrate, journal, do light tasks.', 'White'),
  'mars': ('Energy & courage', 'Hard workout, tackle the scariest bug first, decide fast.', 'Red'),
  'mercury': ('Learning & communication', 'Great for coding, writing docs, maths practice and courses.', 'Green'),
  'jupiter': ('Wisdom & growth', 'Study, mentor someone, plan long-term goals.', 'Yellow'),
  'venus': ('Art, music & relationships', 'Flute practice, design polish, time with loved ones.', 'White / pink'),
  'saturn': ('Discipline & clean-up', 'Clear backlog, refactor, clean your phone, be patient.', 'Blue / black'),
};

class DayOutlook {
  final int score; // 1..5
  final String headline;
  final List<(String, String, int)> factors; // title, detail, good(+)/bad(−)
  final (String, String, String) focus;
  const DayOutlook(this.score, this.headline, this.factors, this.focus);
}

DayOutlook outlookFor(Chart c, Panchang p) {
  final f = <(String, String, int)>[];
  var pts = 0.0;
  // Tara bala: today's Moon nakshatra counted from birth nakshatra.
  final count = (p.nak - c.nak) % 27;
  final tara = count % 9;
  final tg = _taraGood[tara];
  pts += tg * 1.2;
  f.add(('Tara Bala: ${taraNames[tara]}',
      'Moon in ${nakshatras[p.nak].name}, ${count + 1}th from your ${nakshatras[c.nak].name}. ${tg > 0 ? 'Supportive star.' : tg < 0 ? 'Go slow, double-check work.' : 'Your birth star returns: reflect.'}', tg));
  // Chandra bala: transit Moon's house from natal Moon.
  final h = (p.moonSign - c.moonSign) % 12 + 1;
  final cb = const {1, 3, 6, 7, 10, 11}.contains(h) ? 1 : const {4, 8, 12}.contains(h) ? -1 : 0;
  pts += cb;
  f.add(('Chandra Bala: Moon in your ${_ord(h)} house', '${rashis[p.moonSign].english} Moon. ${cb > 0 ? 'Mind is supported today.' : cb < 0 ? 'Emotions may run high; rest well.' : 'Neutral mood.'}', cb));
  // Tithi
  final rikta = const {4, 9, 14}.contains((p.tithi - 1) % 15 + 1);
  final tq = p.tithi == 15 ? 1 : p.tithi == 30 ? -1 : rikta ? -1 : const {2, 3, 5, 7, 10, 11, 13}.contains((p.tithi - 1) % 15 + 1) ? 1 : 0;
  pts += tq * 0.6;
  f.add(('${p.paksha} ${p.tithiName}', tq > 0 ? 'Good tithi to begin things.' : tq < 0 ? 'Better for finishing than starting.' : 'Ordinary tithi.', tq));
  // Saturn & Jupiter transits from natal Moon.
  final today = siderealPositions(p.at);
  final sat = (signOf(today['saturn']!) - c.moonSign) % 12 + 1;
  if (const {12, 1, 2}.contains(sat)) {
    pts -= 0.5;
    f.add(('Sade Sati (phase ${[12, 1, 2].indexOf(sat) + 1} of 3)', 'Saturn is teaching patience: steady effort pays off, avoid shortcuts.', -1));
  }
  final jup = (signOf(today['jupiter']!) - c.moonSign) % 12 + 1;
  final jg = const {2, 5, 7, 9, 11}.contains(jup);
  if (jg) pts += 0.5;
  f.add(('Jupiter in your ${_ord(jup)} house from Moon', jg ? 'A supportive year for growth and learning.' : 'Growth comes through effort, not luck.', jg ? 1 : 0));
  final score = (3 + pts).round().clamp(1, 5);
  const heads = ['Take it slow today', 'Mixed day: stay steady', 'Balanced day', 'Good day', 'Excellent day!'];
  return DayOutlook(score, heads[score - 1], f, _dayFocus[p.dayLord]!);
}

String _ord(int n) => '$n${n == 1 ? 'st' : n == 2 ? 'nd' : n == 3 ? 'rd' : 'th'}';
String ordinal(int n) => _ord(n);
double degIn(double lon) => lon % 30;
int clampSign(int s) => max(0, min(11, s));


/// Mangal (Kuja) dosha: Mars in houses 1, 2, 4, 7, 8 or 12 counted from Lagna (primary), Moon and Venus,
/// with the classical cancellations most kundli software applies.
class MangalDosha {
  static const _houses = {1, 2, 4, 7, 8, 12};
  final int fromLagna, fromMoon, fromVenus; // house of Mars from each reference
  final List<String> cancellations;
  const MangalDosha(this.fromLagna, this.fromMoon, this.fromVenus, this.cancellations);

  bool get lagna => _houses.contains(fromLagna);
  bool get moon => _houses.contains(fromMoon);
  bool get venus => _houses.contains(fromVenus);
  bool get present => lagna || moon || venus;
  bool get cancelled => present && cancellations.isNotEmpty;

  /// 'none' | 'cancelled' | 'low' | 'present'
  String get level => !present
      ? 'none'
      : cancelled
          ? 'cancelled'
          : lagna
              ? 'present'
              : 'low';

  factory MangalDosha.of(Chart c) {
    final mars = signOf(c.pos['mars']!);
    int from(int ref) => (mars - ref) % 12 + 1;
    final hL = from(c.lagnaSign), hM = from(c.moonSign), hV = from(signOf(c.pos['venus']!));
    final why = <String>[];
    const signNames = ['Aries', 'Taurus', 'Gemini', 'Cancer', 'Leo', 'Virgo', 'Libra', 'Scorpio', 'Sagittarius', 'Capricorn', 'Aquarius', 'Pisces'];
    if (mars == 0 || mars == 7) why.add('Mars in its own sign (${signNames[mars]})');
    if (mars == 9) why.add('Mars exalted in Capricorn');
    const exceptions = {2: {2, 5}, 4: {0, 7}, 7: {3, 9}, 8: {8, 11}, 12: {1, 6}};
    if (exceptions[hL]?.contains(mars) ?? false) why.add('Mars in ${signNames[mars]} in the ${ordinal(hL)} house (classical exception)');
    if (c.lagnaSign == 3 || c.lagnaSign == 4) why.add('${signNames[c.lagnaSign]} Lagna: Mars is a yogakaraka');
    final jup = signOf(c.pos['jupiter']!);
    if (jup == mars) why.add('Mars conjunct Jupiter');
    if (signOf(c.pos['moon']!) == mars) why.add('Mars conjunct Moon');
    if (const {4, 6, 8}.contains((mars - jup) % 12)) why.add('Jupiter aspects Mars');
    return MangalDosha(hL, hM, hV, why);
  }
}
