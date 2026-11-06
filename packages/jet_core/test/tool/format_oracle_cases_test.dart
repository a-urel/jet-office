// Checks the committed oracle case list, test/fixtures/owner/number_format/
// cases.json, against the owner checklist and the "Settled by Excel" list
// of docs/number-format.md and the `Owner Excel check` tests.
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import '../../tool/src/format_oracle.dart';

void main() {
  final OracleCases cases = parseOracleCases(
    File(oracleCasesPath).readAsStringSync(),
  );
  final String doc = File('docs/number-format.md').readAsStringSync();

  test('every item of the owner checklist has a case, and every check a '
      'case names is on the checklist', () {
    final String checklist = doc.substring(
      doc.indexOf('## Owner checklist'),
      doc.indexOf('\n## ', doc.indexOf('## Owner checklist') + 1),
    );
    final Set<String> listed = <String>{
      for (final RegExpMatch m in RegExp(
        r'^\| (C\d+[a-z]?) \|',
        multiLine: true,
      ).allMatches(checklist))
        m[1]!,
    };
    expect(listed, isNotEmpty);
    final Set<String> named = <String>{
      for (final OracleCase c in cases.cases) ...c.checks,
    };
    expect(listed.difference(named), isEmpty, reason: 'without a case');
    expect(named.difference(listed), isEmpty, reason: 'not on the checklist');
  });

  test('every Owner Excel check test has a case', () {
    final Set<String> checked = <String>{
      for (final FileSystemEntity f in Directory(
        'test',
      ).listSync(recursive: true))
        if (f is File && f.path.endsWith('_test.dart'))
          for (final RegExpMatch m in RegExp(
            r'Owner Excel check (C\d+[a-z]?)',
          ).allMatches(f.readAsStringSync()))
            m[1]!,
    };
    expect(checked, isNotEmpty);
    final Set<String> named = <String>{
      for (final OracleCase c in cases.cases) ...c.checks,
    };
    expect(checked.difference(named), isEmpty);
  });

  test('every Unknown settled in docs/number-format.md has a case', () {
    final String unknowns = doc.substring(
      doc.indexOf('## Settled by Excel'),
      doc.indexOf('Own rules of N1 and N2'),
    );
    final Set<int> listed = <int>{
      for (final RegExpMatch m in RegExp(
        r'^(\d+)\. ',
        multiLine: true,
      ).allMatches(unknowns))
        int.parse(m[1]!),
    };
    expect(listed, containsAll(<int>[for (int i = 1; i <= 20; i++) i]));
    final Set<int> covered = <int>{
      for (final OracleCase c in cases.cases)
        if (c.unknown != null) c.unknown!,
    };
    expect(listed.difference(covered), isEmpty);
  });

  test('every workbook builds and every case is in it once', () {
    expect(cases.cases.length, greaterThan(100));
    final Map<String, int> perFile = <String, int>{};
    for (final OracleCase c in cases.cases) {
      final String file = cases.workbooks[c.workbook]!.file;
      perFile[file] = (perFile[file] ?? 0) + 1;
    }
    expect(buildOracleWorkbooks(cases).keys.toSet(), perFile.keys.toSet());
  });
}
