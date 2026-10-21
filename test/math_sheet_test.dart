import 'package:buddy_app/core/store.dart';
import 'package:buddy_app/features/grow/model/math.dart';
import 'package:buddy_app/features/grow/view/math_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('wrong → hint → right answer advances progress & streak', (t) async {
    // Native bridge isn't available in tests.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('buddy/native'), (_) async => null);
    SharedPreferences.setMockInitialValues({});
    await Store.init();
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: MathSheet(daily: true))));

    final q = (t.widget(find.textContaining(' + ').first) as Text).data!; // "a + b = ?"
    final m = RegExp(r'(\d+) \+ (\d+)').firstMatch(q)!;
    final answer = int.parse(m[1]!) + int.parse(m[2]!);

    await t.enterText(find.byType(TextField), '${answer + 1}');
    await t.tap(find.text('Check'));
    await t.pumpAndSettle();
    expect(find.textContaining('Hint:'), findsOneWidget);

    await t.enterText(find.byType(TextField), '$answer');
    await t.tap(find.text('Check again'));
    await t.pumpAndSettle();
    expect(find.textContaining('Correct!'), findsOneWidget);
    expect(Store.mathProgress, 1);
    expect(Store.mathDoneToday, isTrue);
    expect(Store.mathStreak, 1);
    expect(Store.xp, 15);
  });

  test('3 correct answers unlock the next level, misses never demote', () async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
    final max = mathLevels.length - 1;
    expect(await Store.mathSolved(maxLevel: max), isFalse);
    expect(await Store.mathSolved(maxLevel: max), isFalse);
    expect(await Store.mathSolved(maxLevel: max), isTrue);
    expect(Store.mathLevel, 1);
    expect(Store.mathProgress, 0);
  });
}
