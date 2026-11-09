// test/support/chart_fuzz.dart is a copy of the core's layout fuzz generator,
// so the measurer fuzz draws the core gate's cases. It reads both files with
// `dart:io`, so the file is VM only. The tests run from the package root.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the copied fuzz generator equals the core\'s', () {
    final String core = File(
      '../jet_charts_core/test/layout/support/chart_fuzz.dart',
    ).readAsStringSync();
    final String copy = File('test/support/chart_fuzz.dart').readAsStringSync();
    // The copy is a provenance comment, a blank line and the core's file.
    final int start = copy.indexOf('\n\n') + 2;
    expect(copy.substring(start), core);
  });
}
