@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

/// The `max…` fields that `this.maxX =` assigns in the constructor of the
/// limits class in [path].
Set<String> _limitFields(String path) => <String>{
  for (final RegExpMatch m in RegExp(
    r'this\.(max\w+)\s*=',
  ).allMatches(File(path).readAsStringSync()))
    m.group(1)!,
};

/// The `DocxReadLimits` fields no DOCX code enforces yet, each with the
/// task that will. The test fails once one of them is covered, so the entry
/// is removed with the code that enforces it.
const Map<String, String> _docxPending = <String, String>{
  'maxTextLength': 'enforced when document.xml is read (phase 4 D1, Task 8)',
};

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

  test('every DocxReadLimits field has a limits case', () {
    final Set<String> fields = _limitFields('lib/src/docx/read_limits.dart');
    final String tests = File(
      'test/docx/docx_package_test.dart',
    ).readAsStringSync();
    final int start = tests.indexOf("group('limits'");
    expect(start, greaterThanOrEqualTo(0), reason: 'no limits group');
    // The group ends where the next test at the top level starts.
    final int next = tests.indexOf('\n  test(', start);
    final String group = tests.substring(start, next < 0 ? tests.length : next);
    final Set<String> names = <String>{
      for (final RegExpMatch m in RegExp(
        r"test\(\s*'([^']*)'",
      ).allMatches(group))
        m.group(1)!,
    };
    Set<String> covered(String field) => <String>{
      for (final String name in names)
        if (RegExp('\\b$field\\b').hasMatch(name)) name,
    };
    expect(fields, isNotEmpty);
    expect(fields, containsAll(_docxPending.keys));
    for (final String field in fields) {
      if (_docxPending.containsKey(field)) {
        expect(
          covered(field),
          isEmpty,
          reason:
              '$field is covered now: remove it from _docxPending '
              '(${_docxPending[field]})',
        );
      } else {
        expect(
          covered(field),
          isNotEmpty,
          reason:
              'each DocxReadLimits field needs a test whose name contains it '
              'in the limits group of test/docx/docx_package_test.dart',
        );
      }
    }
  });
}
