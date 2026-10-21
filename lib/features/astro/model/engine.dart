import 'dart:math';

/// Offline Vedic (sidereal, Lahiri) positions.
/// Moon: Meeus ch.47 (ELP-2000/82 truncated). Sun: Meeus ch.25.
/// Planets: JPL Keplerian elements (Standish, valid 1800–2050). Ascendant: standard spherical formula.
/// Verified against Swiss Ephemeris in test/astro_engine_test.dart.

const _deg = pi / 180;
double _norm(double d) => (d % 360 + 360) % 360;
double _sin(double d) => sin(d * _deg);
double _cos(double d) => cos(d * _deg);

double julianDay(DateTime t) {
  final u = t.toUtc();
  return u.millisecondsSinceEpoch / 86400000.0 + 2440587.5;
}

double _centuries(double jd) => (jd - 2451545.0) / 36525;

/// Lahiri (Chitrapaksha) ayanamsa, fitted to Swiss Ephemeris 1900–2100 (< 0.01″).
double lahiriAyanamsa(double jd) {
  final t = _centuries(jd);
  return 23.85709235 + 1.39688796 * t + 0.00030709 * t * t;
}

// ---------- Sun ----------
double _sunTropical(double t) {
  final l0 = 280.46646 + 36000.76983 * t + 0.0003032 * t * t;
  final m = 357.52911 + 35999.05029 * t - 0.0001537 * t * t;
  final c = (1.914602 - 0.004817 * t - 0.000014 * t * t) * _sin(m) + (0.019993 - 0.000101 * t) * _sin(2 * m) + 0.000289 * _sin(3 * m);
  return _norm(l0 + c - 0.00569); // aberration; nutation cancels in sidereal
}

// ---------- Moon (Meeus 47.A, longitude terms: D, M, M', F, coefficient ×1e-6°) ----------
const _moonTerms = <List<int>>[
  [0, 0, 1, 0, 6288774], [2, 0, -1, 0, 1274027], [2, 0, 0, 0, 658314], [0, 0, 2, 0, 213618],
  [0, 1, 0, 0, -185116], [0, 0, 0, 2, -114332], [2, 0, -2, 0, 58793], [2, -1, -1, 0, 57066],
  [2, 0, 1, 0, 53322], [2, -1, 0, 0, 45758], [0, 1, -1, 0, -40923], [1, 0, 0, 0, -34720],
  [0, 1, 1, 0, -30383], [2, 0, 0, -2, 15327], [0, 0, 1, 2, -12528], [0, 0, 1, -2, 10980],
  [4, 0, -1, 0, 10675], [0, 0, 3, 0, 10034], [4, 0, -2, 0, 8548], [2, 1, -1, 0, -7888],
  [2, 1, 0, 0, -6766], [1, 0, -1, 0, -5163], [1, 1, 0, 0, 4987], [2, -1, 1, 0, 4036],
  [2, 0, 2, 0, 3994], [4, 0, 0, 0, 3861], [2, 0, -3, 0, 3665], [0, 1, -2, 0, -2689],
  [2, 0, -1, 2, -2602], [2, -1, -2, 0, 2390], [1, 0, 1, 0, -2348], [2, -2, 0, 0, 2236],
  [0, 1, 2, 0, -2120], [0, 2, 0, 0, -2069], [2, -2, -1, 0, 2048], [2, 0, 1, -2, -1773],
  [2, 0, 0, 2, -1595], [4, -1, -1, 0, 1215], [0, 0, 2, 2, -1110], [3, 0, -1, 0, -892],
  [2, 1, 1, 0, -810], [4, -1, -2, 0, 759], [0, 2, -1, 0, -713], [2, 2, -1, 0, -700],
  [2, 1, -2, 0, 691], [2, -1, 0, -2, 596], [4, 0, 1, 0, 549], [0, 0, 4, 0, 537],
  [4, -1, 0, 0, 520], [1, 0, -2, 0, -487], [2, 1, 0, -2, -399], [0, 0, 2, -2, -381],
  [1, 1, 1, 0, 351], [3, 0, -2, 0, -340], [4, 0, -3, 0, 330], [2, -1, 2, 0, 327],
  [0, 2, 1, 0, -323], [1, 1, -1, 0, 299], [2, 0, 3, 0, 294],
];

double _moonTropical(double t) {
  final t2 = t * t, t3 = t2 * t, t4 = t3 * t;
  final lp = 218.3164477 + 481267.88123421 * t - 0.0015786 * t2 + t3 / 538841 - t4 / 65194000;
  final d = 297.8501921 + 445267.1114034 * t - 0.0018819 * t2 + t3 / 545868 - t4 / 113065000;
  final m = 357.5291092 + 35999.0502909 * t - 0.0001536 * t2 + t3 / 24490000;
  final mp = 134.9633964 + 477198.8675055 * t + 0.0087414 * t2 + t3 / 69699 - t4 / 14712000;
  final f = 93.2720950 + 483202.0175233 * t - 0.0036539 * t2 - t3 / 3526000 + t4 / 863310000;
  final e = 1 - 0.002516 * t - 0.0000074 * t2;
  var sl = 0.0;
  for (final r in _moonTerms) {
    var c = r[4].toDouble();
    if (r[1].abs() == 1) c *= e;
    if (r[1].abs() == 2) c *= e * e;
    sl += c * _sin(r[0] * d + r[1] * m + r[2] * mp + r[3] * f);
  }
  final a1 = 119.75 + 131.849 * t, a2 = 53.09 + 479264.290 * t;
  sl += 3958 * _sin(a1) + 1962 * _sin(lp - f) + 318 * _sin(a2);
  return _norm(lp + sl / 1e6);
}

/// Mean lunar node (Rahu), as used by most Vedic software.
double _meanNode(double t) =>
    _norm(125.0445479 - 1934.1362891 * t + 0.0020754 * t * t + t * t * t / 467441 - t * t * t * t / 60616000);

// ---------- Planets (JPL approximate elements, J2000 ecliptic) ----------
// a, e, I, L, long.perihelion, node  + rates per century
const _el = <String, List<double>>{
  'mercury': [0.38709927, 0.20563593, 7.00497902, 252.25032350, 77.45779628, 48.33076593, 0.00000037, 0.00001906, -0.00594749, 149472.67411175, 0.16047689, -0.12534081],
  'venus': [0.72333566, 0.00677672, 3.39467605, 181.97909950, 131.60246718, 76.67984255, 0.00000390, -0.00004107, -0.00078890, 58517.81538729, 0.00268329, -0.27769418],
  'earth': [1.00000261, 0.01671123, -0.00001531, 100.46457166, 102.93768193, 0.0, 0.00000562, -0.00004392, -0.01294668, 35999.37244981, 0.32327364, 0.0],
  'mars': [1.52371034, 0.09339410, 1.84969142, -4.55343205, -23.94362959, 49.55953891, 0.00001847, 0.00007882, -0.00813131, 19140.30268499, 0.44441088, -0.29257343],
  'jupiter': [5.20288700, 0.04838624, 1.30439695, 34.39644051, 14.72847983, 100.47390909, -0.00011607, -0.00013253, -0.00183714, 3034.74612775, 0.21252668, 0.20469106],
  'saturn': [9.53667594, 0.05386179, 2.48599187, 49.95424423, 92.59887831, 113.66242448, -0.00125060, -0.00050991, 0.00193609, 1222.49362201, -0.41897216, -0.28867794],
};

List<double> _helio(String p, double t) {
  final k = _el[p]!;
  final a = k[0] + k[6] * t, e = k[1] + k[7] * t, i = k[2] + k[8] * t;
  final l = k[3] + k[9] * t, w = k[4] + k[10] * t, o = k[5] + k[11] * t;
  final argp = w - o;
  final mAnom = _norm(l - w);
  // Kepler's equation
  var ea = mAnom + (e * 180 / pi) * _sin(mAnom);
  for (var n = 0; n < 8; n++) {
    final dm = mAnom - (ea - (e * 180 / pi) * _sin(ea));
    ea += dm / (1 - e * _cos(ea));
  }
  final xp = a * (_cos(ea) - e), yp = a * sqrt(1 - e * e) * _sin(ea);
  final x = (_cos(argp) * _cos(o) - _sin(argp) * _sin(o) * _cos(i)) * xp + (-_sin(argp) * _cos(o) - _cos(argp) * _sin(o) * _cos(i)) * yp;
  final y = (_cos(argp) * _sin(o) + _sin(argp) * _cos(o) * _cos(i)) * xp + (-_sin(argp) * _sin(o) + _cos(argp) * _cos(o) * _cos(i)) * yp;
  return [x, y];
}

/// Jupiter & Saturn: Schlyter's of-date elements + their Jupiter–Saturn perturbation terms
/// (the JPL table above has no periodic terms, which costs Saturn up to ~10′).
double _outerTropical(String p, double jd) {
  final d = jd - 2451543.5;
  double kepler(double m, double e) {
    var ea = m + e * 180 / pi * _sin(m) * (1 + e * _cos(m));
    for (var n = 0; n < 6; n++) {
      ea -= (ea - e * 180 / pi * _sin(ea) - m) / (1 - e * _cos(ea));
    }
    return ea;
  }

  (double, double) orbit(double nn, double i, double w, double a, double e, double m) {
    final ea = kepler(_norm(m), e);
    final xv = a * (_cos(ea) - e), yv = a * sqrt(1 - e * e) * _sin(ea);
    final v = atan2(yv, xv) / _deg, r = sqrt(xv * xv + yv * yv);
    final x = r * (_cos(nn) * _cos(v + w) - _sin(nn) * _sin(v + w) * _cos(i));
    final y = r * (_sin(nn) * _cos(v + w) + _cos(nn) * _sin(v + w) * _cos(i));
    return (atan2(y, x) / _deg, sqrt(x * x + y * y));
  }

  final mj = _norm(19.8950 + 0.0830853001 * d), ms = _norm(316.9670 + 0.0334442282 * d);
  final (lon0, r) = p == 'jupiter'
      ? orbit(100.4542 + 2.76854e-5 * d, 1.3030 - 1.557e-7 * d, 273.8777 + 1.64505e-5 * d, 5.20256, 0.048498 + 4.469e-9 * d, mj)
      : orbit(113.6634 + 2.38980e-5 * d, 2.4886 - 1.081e-7 * d, 339.3939 + 2.97661e-5 * d, 9.55475, 0.055546 - 9.499e-9 * d, ms);
  final dl = p == 'jupiter'
      ? -0.332 * _sin(2 * mj - 5 * ms - 67.6) - 0.056 * _sin(2 * mj - 2 * ms + 21) + 0.042 * _sin(3 * mj - 5 * ms + 21) -
          0.036 * _sin(mj - 2 * ms) + 0.022 * _cos(mj - ms) + 0.023 * _sin(2 * mj - 3 * ms + 52) - 0.016 * _sin(mj - 5 * ms - 69)
      : 0.812 * _sin(2 * mj - 5 * ms - 67.6) - 0.229 * _cos(2 * mj - 4 * ms - 2) + 0.119 * _sin(mj - 2 * ms - 3) +
          0.046 * _sin(2 * mj - 6 * ms - 69) + 0.014 * _sin(mj - 3 * ms + 32);
  final lon = lon0 + dl;
  // Sun's geocentric position (Schlyter) to convert heliocentric → geocentric.
  final sw = 282.9404 + 4.70935e-5 * d, se = 0.016709 - 1.151e-9 * d, sm = _norm(356.0470 + 0.9856002585 * d);
  final sea = kepler(sm, se);
  final sxv = _cos(sea) - se, syv = sqrt(1 - se * se) * _sin(sea);
  final sv = atan2(syv, sxv) / _deg, sr = sqrt(sxv * sxv + syv * syv);
  final xg = r * _cos(lon) + sr * _cos(sv + sw), yg = r * _sin(lon) + sr * _sin(sv + sw);
  return _norm(atan2(yg, xg) / _deg);
}

/// Geocentric ecliptic longitude referred to the J2000 equinox.
double _planetJ2000(String p, double t) {
  final pl = _helio(p, t);
  final ea = _helio('earth', t);
  return _norm(atan2(pl[1] - ea[1], pl[0] - ea[0]) / _deg);
}

const planetIds = ['sun', 'moon', 'mars', 'mercury', 'jupiter', 'venus', 'saturn', 'rahu', 'ketu'];

/// Sidereal (Lahiri) longitudes in degrees for the given instant.
Map<String, double> siderealPositions(DateTime when) {
  final jd = julianDay(when);
  final t = _centuries(jd);
  final ay = lahiriAyanamsa(jd);
  // Precession from J2000 to date, so J2000-frame planets line up with the of-date ayanamsa.
  final prec = 1.396971 * t + 0.0003086 * t * t;
  final rahu = _norm(_meanNode(t) - ay);
  return {
    'sun': _norm(_sunTropical(t) - ay),
    'moon': _norm(_moonTropical(t) - ay),
    'mars': _norm(_planetJ2000('mars', t) + prec - ay),
    'mercury': _norm(_planetJ2000('mercury', t) + prec - ay),
    'jupiter': _norm(_outerTropical('jupiter', jd) - ay),
    'venus': _norm(_planetJ2000('venus', t) + prec - ay),
    'saturn': _norm(_outerTropical('saturn', jd) - ay),
    'rahu': rahu,
    'ketu': _norm(rahu + 180),
  };
}

/// Sidereal ascendant (Lagna). lat/lon in degrees, east positive.
double siderealAscendant(DateTime when, double lat, double lon) {
  final jd = julianDay(when);
  final t = _centuries(jd);
  final gmst = 280.46061837 + 360.98564736629 * (jd - 2451545.0) + 0.000387933 * t * t - t * t * t / 38710000;
  final ramc = _norm(gmst + lon);
  final eps = 23.439291 - 0.0130042 * t;
  final asc = atan2(_cos(ramc), -(_sin(ramc) * _cos(eps) + tan(lat * _deg) * _sin(eps))) / _deg;
  return _norm(asc - lahiriAyanamsa(jd));
}

/// Sunrise & sunset (local DateTime) using the NOAA algorithm; null in polar day/night.
(DateTime, DateTime)? sunTimes(DateTime day, double lat, double lon, Duration utcOffset) {
  final noonUtc = DateTime.utc(day.year, day.month, day.day, 12).subtract(utcOffset);
  final t = _centuries(julianDay(noonUtc));
  final l0 = _norm(280.46646 + 36000.76983 * t);
  final m = 357.52911 + 35999.05029 * t;
  final ecc = 0.016708634 - 0.000042037 * t;
  final c = (1.914602 - 0.004817 * t) * _sin(m) + 0.019993 * _sin(2 * m) + 0.000289 * _sin(3 * m);
  final app = l0 + c - 0.00569 - 0.00478 * _sin(125.04 - 1934.136 * t);
  final eps = 23.439291 - 0.0130042 * t + 0.00256 * _cos(125.04 - 1934.136 * t);
  final decl = asin(_sin(eps) * _sin(app)) / _deg;
  final y = pow(tan(eps / 2 * _deg), 2).toDouble();
  final eqTime = 4 / _deg * (y * _sin(2 * l0) - 2 * ecc * _sin(m) + 4 * ecc * y * _sin(m) * _cos(2 * l0) - 0.5 * y * y * _sin(4 * l0) - 1.25 * ecc * ecc * _sin(2 * m));
  final cosH = (_cos(90.833) - _sin(lat) * _sin(decl)) / (_cos(lat) * _cos(decl));
  if (cosH.abs() > 1) return null;
  final h = acos(cosH) / _deg;
  final noonMin = 720 - 4 * lon - eqTime; // minutes from UTC midnight
  DateTime at(double mins) => DateTime.utc(day.year, day.month, day.day).add(Duration(seconds: (mins * 60).round())).add(utcOffset);
  final rise = at(noonMin - 4 * h), set = at(noonMin + 4 * h);
  // Return as "wall clock" local times (UTC fields hold local time).
  return (DateTime(rise.year, rise.month, rise.day, rise.hour, rise.minute, rise.second), DateTime(set.year, set.month, set.day, set.hour, set.minute, set.second));
}
