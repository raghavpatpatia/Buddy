import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('en_IN parses typed dates as DD/MM/YYYY', (t) async {
    late MaterialLocalizations l;
    await t.pumpWidget(MaterialApp(
      locale: const Locale('en', 'IN'),
      supportedLocales: const [Locale('en', 'IN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Builder(builder: (c) {
        l = MaterialLocalizations.of(c);
        return const SizedBox();
      }),
    ));
    await t.pumpAndSettle();
    expect(l.parseCompactDate('05/08/1999'), DateTime(1999, 8, 5));
    expect(l.dateHelpText, contains('dd'));
  });
}
