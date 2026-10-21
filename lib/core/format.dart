/// Formats rupees with Indian grouping, e.g. ₹1,23,456.
String inr(double v, {bool sign = false, int decimals = 0}) {
  final neg = v < 0;
  final s = v.abs().toStringAsFixed(decimals);
  final parts = s.split('.');
  var w = parts[0];
  if (w.length > 3) {
    final last3 = w.substring(w.length - 3);
    var rest = w.substring(0, w.length - 3);
    final groups = <String>[];
    while (rest.length > 2) {
      groups.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) groups.insert(0, rest);
    w = '${groups.join(',')},$last3';
  }
  final body = '₹$w${parts.length > 1 ? '.${parts[1]}' : ''}';
  return neg ? '−$body' : (sign ? '+$body' : body);
}

/// Compact rupees for tight spots, e.g. ₹1.2L or ₹3.4Cr.
String inrShort(double v) {
  final a = v.abs();
  final s = a >= 1e7 ? '${(a / 1e7).toStringAsFixed(1)}Cr' : a >= 1e5 ? '${(a / 1e5).toStringAsFixed(1)}L' : a >= 1e3 ? '${(a / 1e3).toStringAsFixed(1)}k' : a.toStringAsFixed(0);
  return '${v < 0 ? '−' : ''}₹$s';
}

String pct(double v) => '${v >= 0 ? '+' : '−'}${v.abs().toStringAsFixed(2)}%';

/// File size like "1.25 GB", "300 MB".
String fmtBytes(int b) {
  if (b >= 1 << 30) return '${(b / (1 << 30)).toStringAsFixed(2)} GB';
  if (b >= 1 << 20) return '${(b / (1 << 20)).toStringAsFixed(0)} MB';
  if (b >= 1 << 10) return '${(b / (1 << 10)).toStringAsFixed(0)} KB';
  return '$b B';
}

/// Parses a user-typed amount (commas allowed); null unless it's a plain number in (0, max].
double? parseAmount(String text, {double max = 1e8}) {
  final t = text.trim().replaceAll(',', '');
  if (!RegExp(r'^\d+(\.\d{1,4})?$').hasMatch(t)) return null;
  final v = double.parse(t);
  return v > 0 && v <= max ? v : null;
}

const monthShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const monthLong = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/// Clock time like "5:07 PM".
String hm(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// Date like "27 Jul 2001".
String dmy(DateTime t) => '${t.day} ${monthShort[t.month - 1]} ${t.year}';
