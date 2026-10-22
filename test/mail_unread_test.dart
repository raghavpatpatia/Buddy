import 'package:buddy_app/core/arch/load_state.dart';
import 'package:buddy_app/core/store.dart';
import 'package:buddy_app/features/money/controller/mail_controller.dart';
import 'package:buddy_app/features/money/model/mail.dart';
import 'package:buddy_app/features/money/view/widgets.dart';
import 'package:buddy_app/shared/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
  });

  test('unread count drops when an email is opened', () {
    final c = MailController();
    c.items = Ready([
      MailItem(1, 'Asha', 'Hi', DateTime(2026, 10, 22), false),
      MailItem(2, 'Bank', 'Statement', DateTime(2026, 10, 21), true),
      MailItem(3, 'Ravi', 'Lunch?', DateTime(2026, 10, 20), false),
    ]);
    expect(c.unread, 2);
    c.markSeen(c.list.first);
    expect(c.unread, 1);
    expect(c.list.first.seen, isTrue);
    c.dispose();
  });

  testWidgets('unread mail shows a dot in front, read mail does not', (t) async {
    Color? dot(String label) {
      final box = t.widget<Container>(find.descendant(of: find.byWidgetPredicate((w) => w is Semantics && w.properties.label == label), matching: find.byType(Container)).first);
      return (box.decoration as BoxDecoration).color;
    }

    await t.pumpWidget(MaterialApp(
      theme: buddyTheme(Brightness.light),
      home: const Scaffold(body: Column(children: [MailAvatar(from: 'Asha', seen: false), MailAvatar(from: '', seen: true)])),
    ));
    expect(dot('Unread'), isNot(Colors.transparent));
    expect(dot('Read'), Colors.transparent);
    expect(find.text('?'), findsOneWidget);
  });
}
