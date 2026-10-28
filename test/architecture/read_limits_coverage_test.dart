@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('every XlsxReadLimits field has a hostile limits case', () {
    final String limits = File(
      'lib/src/xlsx/read/read_limits.dart',
    ).readAsStringSync();
    final Set<String> fields = <String>{
      for (final RegExpMatch m in RegExp(
        r'this\.(max\w+)\s*=',
      ).allMatches(limits))
        m.group(1)!,
    };
    final String hostile = File(
      'test/xlsx/read/hostile_files_test.dart',
    ).readAsStringSync();
    final int start = hostile.indexOf("group('limits'");
    final int end = hostile.indexOf("group('hostile'");
    expect(start, greaterThanOrEqualTo(0), reason: 'no limits group');
    expect(end, greaterThan(start), reason: 'no hostile group after limits');
    final Set<String> cases = <String>{
      for (final RegExpMatch m in RegExp(
        r"test\('(max\w+)'",
      ).allMatches(hostile.substring(start, end)))
        m.group(1)!,
    };
    expect(fields, isNotEmpty);
    expect(
      cases,
      fields,
      reason:
          'each XlsxReadLimits field needs one test named after it in the '
          'limits group of hostile_files_test.dart',
    );
  });
}
