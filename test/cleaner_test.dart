import 'dart:isolate';

import 'package:buddy_app/features/phone/data/cleaner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('scan with live progress completes even if the callback holds unsendable objects', () async {
    // In the app the callback references the Cleaner screen (with decoded thumbnails). Nothing from it
    // may be dragged into the background isolate, or the scan fails with "object is unsendable".
    final unsendable = ReceivePort();
    addTearDown(unsendable.close);
    var calls = 0;
    final r = await Cleaner.scan(onProgress: (_, _, _) => calls += unsendable.hashCode == 0 ? 0 : 1)
        .timeout(const Duration(seconds: 20));
    expect(r.keys, containsAll(cleanCategories.keys));
  });
}
