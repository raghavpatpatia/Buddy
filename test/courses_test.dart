import 'package:buddy_app/core/store.dart';
import 'package:buddy_app/features/grow/model/course.dart';
import 'package:buddy_app/features/grow/view/courses_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('course card shows pace and +1 updates progress', (t) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('buddy/native'), (_) async => null);
    SharedPreferences.setMockInitialValues({});
    await Store.init();
    final deadline = DateTime.now().add(const Duration(days: 9)); // 10 days incl. today
    await Store.setCourses([
      {'id': '1', 'name': 'Web Development', 'platform': 'Tutedude', 'unit': 'videos', 'url': '', 'total': 40, 'done': 10, 'deadline': deadline.toIso8601String(), 'log': {}},
    ]);
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: MyCourses()))));

    expect(find.text('Web Development'), findsOneWidget);
    expect(find.text('Tutedude'), findsOneWidget);
    expect(find.text('10 of 40 videos'), findsOneWidget);
    expect(find.textContaining('3 videos/day to finish in 10 days · today 0/3'), findsOneWidget);

    await t.tap(find.text('+1 video'));
    await t.pumpAndSettle();
    expect(find.text('11 of 40 videos'), findsOneWidget);
    expect(Store.courses.first['done'], 11);
    expect(Store.courseLessonsToday(), 1);
    expect(Store.xp, 5);
  });

  test('generic course without deadline has no pace', () {
    expect(coursePace({'total': 10, 'done': 2}), isNull);
  });
}
