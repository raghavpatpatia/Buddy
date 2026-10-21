/// Degrees, minutes and seconds of a coordinate (sign dropped).
(int, int, double) toDms(double v) {
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

/// Seconds without a needless ".0".
String fmtSeconds(double s) => s == s.roundToDouble() ? '${s.round()}' : s.toStringAsFixed(1);

/// Typed degrees/minutes/seconds as a decimal, or null when out of range (minutes and seconds may be empty).
double? parseDms(String d, String m, String s, int maxDeg) {
  final dd = int.tryParse(d), mm = int.tryParse(m.isEmpty ? '0' : m), ss = double.tryParse(s.isEmpty ? '0' : s);
  if (dd == null || mm == null || ss == null || dd < 0 || dd > maxDeg || mm < 0 || mm > 59 || ss < 0 || ss >= 60) return null;
  return dd + mm / 60 + ss / 3600;
}

/// Typed decimal latitude/longitude, or null when missing or out of range.
(double, double)? parseDecimalCoords(String lat, String lon) {
  final a = double.tryParse(lat), o = double.tryParse(lon);
  return a == null || o == null || a.abs() > 90 || o.abs() > 180 ? null : (a, o);
}

/// UTC offset typed as ±hh:mm, in hours (e.g. +5:30 → 5.5), or null when invalid.
double? parseTz({required bool negative, required String hours, required String minutes}) {
  final h = int.tryParse(hours), m = int.tryParse(minutes.isEmpty ? '0' : minutes);
  if (h == null || m == null || h > 14 || m > 59) return null;
  return (negative ? -1 : 1) * (h + m / 60);
}

/// First problem with the typed birth details, or null when everything is valid.
String? birthInputError({required DateTime? date, required int? hour12, required int? minute, required int? second, required (double, double)? coords, required double? tz}) {
  if (date == null) return 'Pick your date of birth';
  if (hour12 == null || hour12 < 1 || hour12 > 12 || minute == null || minute < 0 || minute > 59 || second == null || second < 0 || second > 59) {
    return 'Enter time as hh (1–12) : mm : ss';
  }
  if (coords == null) return 'Choose a birth place, or enter latitude/longitude (degrees 0–90 / 0–180, minutes & seconds 0–59)';
  if (tz == null) return 'Enter the UTC offset as hh:mm (India = +5:30)';
  return null;
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
