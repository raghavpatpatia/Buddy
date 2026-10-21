import 'dart:math';

/// One generated problem. [answer] is checked with a small tolerance.
class MathProblem {
  final String question, hint;
  final List<String> steps; // worked solution
  final double answer;
  final bool fraction; // answer may be typed as a/b
  const MathProblem(this.question, this.answer, this.hint, this.steps, {this.fraction = false});
}

class MathLevel {
  final String name, emoji;
  final MathProblem Function(Random r) make;
  const MathLevel(this.name, this.emoji, this.make);
}

int _gcd(int a, int b) => b == 0 ? a.abs() : _gcd(b, a % b);
String _frac(int n, int d) {
  final g = _gcd(n, d);
  final (a, b) = (n ~/ g, d ~/ g);
  return b == 1 ? '$a' : '$a/$b';
}

String _fmt(num v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
int _rng(Random r, int lo, int hi) => lo + r.nextInt(hi - lo + 1);

/// Easy → hard. 3 correct answers unlock the next level.
final mathLevels = <MathLevel>[
  MathLevel('Adding', '➕', (r) {
    final a = _rng(r, 12, 89), b = _rng(r, 11, 89);
    return MathProblem('$a + $b = ?', (a + b).toDouble(), 'Add the tens, then the ones: ${a ~/ 10 * 10} + ${b ~/ 10 * 10}, then ${a % 10} + ${b % 10}.',
        ['Tens: ${a ~/ 10 * 10} + ${b ~/ 10 * 10} = ${(a ~/ 10 + b ~/ 10) * 10}', 'Ones: ${a % 10} + ${b % 10} = ${a % 10 + b % 10}', 'Total: ${a + b}']);
  }),
  MathLevel('Subtracting', '➖', (r) {
    final a = _rng(r, 40, 99), b = _rng(r, 11, a - 5);
    final round = (b + 9) ~/ 10 * 10;
    return MathProblem('$a − $b = ?', (a - b).toDouble(), 'Subtract a round number first: $a − $round, then add back ${round - b}.',
        ['$a − $round = ${a - round}', 'You took away ${round - b} too many, so add it back: ${a - round} + ${round - b} = ${a - b}']);
  }),
  MathLevel('Times tables', '✖️', (r) {
    final a = _rng(r, 3, 12), b = _rng(r, 6, 12);
    return MathProblem('$a × $b = ?', (a * b).toDouble(), 'Break it up: $a × ${b - 5} + $a × 5.',
        ['$a × 5 = ${a * 5}', '$a × ${b - 5} = ${a * (b - 5)}', '${a * 5} + ${a * (b - 5)} = ${a * b}']);
  }),
  MathLevel('Dividing', '➗', (r) {
    final b = _rng(r, 3, 12), q = _rng(r, 4, 15);
    return MathProblem('${b * q} ÷ $b = ?', q.toDouble(), 'Which number times $b gives ${b * q}?', ['$b × $q = ${b * q}', 'So ${b * q} ÷ $b = $q']);
  }),
  MathLevel('Order of operations', '🧮', (r) {
    final a = _rng(r, 2, 9), b = _rng(r, 2, 9), c = _rng(r, 2, 6);
    return MathProblem('$a + $b × $c = ?', (a + b * c).toDouble(), 'BODMAS: multiply before you add.',
        ['Multiply first: $b × $c = ${b * c}', 'Then add: $a + ${b * c} = ${a + b * c}']);
  }),
  MathLevel('Negative numbers', '🌡️', (r) {
    final a = _rng(r, 3, 15), b = _rng(r, a + 2, a + 20);
    return MathProblem('It is $a°C. The temperature drops by $b°C. What is it now?', (a - b).toDouble(), 'Going below zero: you pass 0 after $a degrees.',
        ['$a − $a = 0', 'Still ${b - a} more to drop', '0 − ${b - a} = ${a - b}']);
  }),
  MathLevel('Fractions', '🍕', (r) {
    final d1 = [2, 3, 4, 5, 6][r.nextInt(5)], d2 = [2, 3, 4, 6, 8][r.nextInt(5)];
    final n1 = _rng(r, 1, d1 - 1), n2 = _rng(r, 1, d2 - 1);
    final l = d1 * d2 ~/ _gcd(d1, d2);
    final n = n1 * (l ~/ d1) + n2 * (l ~/ d2);
    return MathProblem('$n1/$d1 + $n2/$d2 = ?  (type like 5/6)', n / l, 'Make the bottoms the same: both become $l.',
        ['$n1/$d1 = ${n1 * (l ~/ d1)}/$l', '$n2/$d2 = ${n2 * (l ~/ d2)}/$l', 'Add the tops: ${n1 * (l ~/ d1)} + ${n2 * (l ~/ d2)} = $n → $n/$l', 'Simplify: ${_frac(n, l)}'],
        fraction: true);
  }),
  MathLevel('Percentages', '💯', (r) {
    final p = [10, 20, 25, 30, 40, 50, 75, 15][r.nextInt(8)], v = _rng(r, 2, 20) * 20;
    return MathProblem('A sword costs $v gold. It is $p% off. How much gold do you save?', v * p / 100, '10% of $v is ${v ~/ 10}. Build $p% from that.',
        ['1% of $v = ${_fmt(v / 100)}', '$p% = $p × ${_fmt(v / 100)} = ${_fmt(v * p / 100)}']);
  }),
  MathLevel('Decimals', '🔢', (r) {
    final a = _rng(r, 11, 49) / 10, b = _rng(r, 2, 9);
    return MathProblem('${_fmt(a)} × $b = ?', a * b, 'Ignore the decimal point, multiply, then put it back (1 decimal place).',
        ['${(a * 10).round()} × $b = ${(a * 10).round() * b}', 'One decimal place back: ${_fmt(a * b)}']);
  }),
  MathLevel('Simple equations', '🟰', (r) {
    final x = _rng(r, 2, 12), a = _rng(r, 2, 9), b = _rng(r, 1, 20);
    return MathProblem('Solve for x:  ${a}x + $b = ${a * x + b}', x.toDouble(), 'Undo the + $b first, then undo the × $a.',
        ['Subtract $b from both sides: ${a}x = ${a * x}', 'Divide both sides by $a: x = $x']);
  }),
  MathLevel('Ratios', '⚖️', (r) {
    final a = _rng(r, 1, 5), b = _rng(r, 2, 7), k = _rng(r, 3, 12);
    return MathProblem('Loot is split between Ana and Ben in the ratio $a : $b. Ana gets ${a * k} coins. How many does Ben get?', (b * k).toDouble(),
        'Find what one "part" is worth first.', ['Ana has $a parts = ${a * k} coins', '1 part = ${a * k} ÷ $a = $k', 'Ben has $b parts = $b × $k = ${b * k}']);
  }),
  MathLevel('Squares & roots', '🟦', (r) {
    final n = _rng(r, 4, 20);
    return r.nextBool()
        ? MathProblem('$n² = ?', (n * n).toDouble(), '$n² means $n × $n.', ['$n × $n = ${n * n}'])
        : MathProblem('√${n * n} = ?', n.toDouble(), 'Which number times itself is ${n * n}?', ['$n × $n = ${n * n}', 'So √${n * n} = $n']);
  }),
  MathLevel('Powers', '⚡', (r) {
    final b = _rng(r, 2, 3), m = _rng(r, 2, 4), n = _rng(r, 1, 3);
    return MathProblem('$b^$m × $b^$n = $b^? (give the power)', (m + n).toDouble(), 'Same base when multiplying → add the powers.',
        ['$b^$m × $b^$n = $b^($m+$n)', '= $b^${m + n}  (= ${pow(b, m + n)})']);
  }),
  MathLevel('Equations both sides', '🔁', (r) {
    final x = _rng(r, 1, 10), a = _rng(r, 4, 9), c = _rng(r, 1, a - 2), b = _rng(r, 1, 15);
    final d = a * x + b - c * x;
    return MathProblem('Solve:  ${a}x + $b = ${c}x + $d', x.toDouble(), 'Get all the x terms on one side first.',
        ['Subtract ${c}x: ${a - c}x + $b = $d', 'Subtract $b: ${a - c}x = ${d - b}', 'Divide by ${a - c}: x = $x']);
  }),
  MathLevel('Area & perimeter', '📐', (r) {
    final w = _rng(r, 3, 15), h = _rng(r, 3, 12);
    return r.nextBool()
        ? MathProblem('A tilemap room is $w × $h tiles. How many tiles cover the floor?', (w * h).toDouble(), 'Area of a rectangle = width × height.', ['$w × $h = ${w * h}'])
        : MathProblem('A $w × $h room needs a wall around the edge. How many tile-edges long is the wall?', (2 * (w + h)).toDouble(),
            'Perimeter = 2 × (width + height).', ['$w + $h = ${w + h}', '2 × ${w + h} = ${2 * (w + h)}']);
  }),
  MathLevel('Pythagoras', '📏', (r) {
    final t = [(3, 4, 5), (5, 12, 13), (8, 15, 17), (6, 8, 10), (9, 12, 15), (7, 24, 25)][r.nextInt(6)];
    return MathProblem('A sprite moves ${t.$1} px right and ${t.$2} px up. How far is it from where it started?', t.$3.toDouble(),
        'Distance² = dx² + dy² (Pythagoras).', ['${t.$1}² + ${t.$2}² = ${t.$1 * t.$1} + ${t.$2 * t.$2} = ${t.$3 * t.$3}', '√${t.$3 * t.$3} = ${t.$3}']);
  }),
  MathLevel('Two equations', '🔀', (r) {
    final x = _rng(r, 1, 9), y = _rng(r, 1, 9);
    return MathProblem('x + y = ${x + y}\nx − y = ${x - y}\nFind x.', x.toDouble(), 'Add the two equations: the y’s cancel.',
        ['(x + y) + (x − y) = ${x + y} + ${x - y}', '2x = ${2 * x}', 'x = $x  (and y = $y)']);
  }),
  MathLevel('Quadratics', '🎯', (r) {
    // Non-zero roots that don't cancel, so the equation always has both an x term and a constant.
    int nz() => [-6, -5, -4, -3, -2, -1, 1, 2, 3, 4, 5, 6][r.nextInt(12)];
    final p = nz();
    var q = nz();
    while (q == -p) {
      q = nz();
    }
    final b = -(p + q), c = p * q;
    String sgn(int v) => v < 0 ? '− ${-v}' : '+ $v';
    final lo = min(p, q);
    return MathProblem('x² ${sgn(b)}x ${sgn(c)} = 0\nWhat is the smaller solution for x?', lo.toDouble(),
        'Find two numbers that multiply to $c and add to $b.',
        ['Numbers: ${-p} and ${-q} (× = $c, + = $b)', '(x ${sgn(-p)})(x ${sgn(-q)}) = 0', 'x = $p or x = $q', 'Smaller: $lo']);
  }),
  MathLevel('Probability', '🎲', (r) {
    final red = _rng(r, 2, 8), blue = _rng(r, 2, 8);
    return MathProblem('A loot box has $red red gems and $blue blue gems. You pick one at random. Chance it is red?  (type like 3/7)',
        red / (red + blue), 'Probability = wanted outcomes ÷ all outcomes.', ['Red = $red, total = ${red + blue}', 'P(red) = $red/${red + blue} = ${_frac(red, red + blue)}'],
        fraction: true);
  }),
  MathLevel('Derivatives', '📈', (r) {
    final a = _rng(r, 2, 5), n = _rng(r, 2, 3), x = _rng(r, 1, 3);
    final d = a * n * pow(x, n - 1);
    return MathProblem('f(x) = ${a}x^$n.  What is f′($x)?  (the slope at x = $x)', d.toDouble(), 'Power rule: bring the power down, then lower it by 1.',
        ['f′(x) = $a·$n·x^${n - 1} = ${a * n}x${n - 1 == 1 ? '' : '^${n - 1}'}', 'f′($x) = ${a * n} × ${pow(x, n - 1)} = $d']);
  }),
  MathLevel('Integrals', '∫', (r) {
    final n = _rng(r, 1, 3), b = _rng(r, 1, 3), a = (n + 1) * _rng(r, 1, 3);
    final v = a / (n + 1) * pow(b, n + 1);
    return MathProblem('∫₀^$b ${a}x${n == 1 ? '' : '^$n'} dx = ?', v, 'Reverse power rule: raise the power by 1 and divide by the new power.',
        ['Antiderivative: ${a ~/ (n + 1)}x^${n + 1}', 'At x = $b: ${a ~/ (n + 1)} × ${pow(b, n + 1)} = ${_fmt(v)}', 'At x = 0: 0', 'Answer: ${_fmt(v)}']);
  }),
];

/// Parses "12", "-3.5", "5/6".
double? parseAnswer(String s) {
  s = s.trim().replaceAll(' ', '').replaceAll('−', '-');
  if (s.contains('/')) {
    final p = s.split('/');
    final a = double.tryParse(p[0]), b = double.tryParse(p.length > 1 ? p[1] : '');
    return (a == null || b == null || b == 0) ? null : a / b;
  }
  return double.tryParse(s);
}

bool isCorrect(MathProblem p, double v) => (v - p.answer).abs() < 0.011;
