import 'dart:math';

import 'package:buddy_app/features/grow/model/math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every level generates sane problems with finite answers', () {
    for (final (i, lvl) in mathLevels.indexed) {
      for (var seed = 0; seed < 300; seed++) {
        final p = lvl.make(Random(seed * 31 + i));
        expect(p.answer.isFinite, isTrue, reason: '${lvl.name}: ${p.question}');
        expect(p.steps, isNotEmpty);
        expect(p.question.contains('null') || p.question.contains('NaN'), isFalse);
      }
    }
  });

  test('worked solutions end with the right answer (spot checks)', () {
    // Quadratic: smaller root actually solves the equation.
    for (var s = 0; s < 200; s++) {
      final p = mathLevels.firstWhere((l) => l.name == 'Quadratics').make(Random(s));
      final m = RegExp(r'x² ([+−]) (\d+)x ([+−]) (\d+)').firstMatch(p.question)!;
      final b = int.parse(m[2]!) * (m[1] == '−' ? -1 : 1), c = int.parse(m[4]!) * (m[3] == '−' ? -1 : 1);
      final x = p.answer;
      expect(x * x + b * x + c, closeTo(0, 1e-9), reason: p.question);
    }
    // Simple equations: substituting x back works.
    for (var s = 0; s < 200; s++) {
      final p = mathLevels.firstWhere((l) => l.name == 'Simple equations').make(Random(s));
      final m = RegExp(r'(\d+)x \+ (\d+) = (\d+)').firstMatch(p.question)!;
      expect(int.parse(m[1]!) * p.answer + int.parse(m[2]!), int.parse(m[3]!));
    }
  });

  test('levels go from arithmetic to calculus', () {
    expect(mathLevels.first.name, 'Adding');
    expect(mathLevels.last.name, 'Integrals');
    expect(mathLevels.length, greaterThanOrEqualTo(20));
  });

  test('answer parsing', () {
    expect(parseAnswer('5/6'), closeTo(0.8333, 1e-3));
    expect(parseAnswer(' −7 '), -7);
    expect(parseAnswer('3.50'), 3.5);
    expect(parseAnswer('abc'), isNull);
    expect(parseAnswer('1/0'), isNull);
  });
}
