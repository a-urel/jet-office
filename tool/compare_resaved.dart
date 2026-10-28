/// Reads LibreOffice's re-save of every fixture with `XlsxReader` and
/// compares it with the fixture's expected values.
///
/// ```bash
/// dart run tool/compare_resaved.dart build/fixtures build/resaved
/// ```
///
/// For every `<name>.expected.json` in the first directory (written by
/// `tool/write_fixtures.dart`) it reads `<resaved>/<name>.xlsx` and compares
/// each expected sheet, matched by name or by its `_xHHHH_`-decoded name (as
/// `tool/compare_csv.dart` does), with `compareReadSheet` from
/// `tool/src/read_compare.dart`, whose library comment states the contract.
/// A sheet in the re-save that no expected sheet names is a mismatch, as is
/// a missing or unreadable re-saved file. Every reader warning on a re-save
/// is a mismatch unless `resaveAllowedWarnings` names the fixture and the
/// code, and a value differs only where `resaveAllowedValues` names it. It
/// prints every mismatch and exits with 1 on any, with 2 when
/// there is nothing to compare, or with 64 on a usage error.
///
/// The CI job re-saves the fixtures with LibreOffice headless:
///
/// ```bash
/// LC_ALL=C.UTF-8 soffice --headless \
///   --convert-to 'xlsx:Calc MS Excel 2007 XML' \
///   --outdir build/resaved build/fixtures/*.xlsx
/// ```
///
/// LibreOffice recalculates on load and saves the values it computed, so
/// the re-save is compared with `expectedValues`, not with what the writer
/// stored.
library;

import 'dart:convert';
import 'dart:io';

import 'package:jet_office/jet_office.dart';

import 'src/read_compare.dart';

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/compare_resaved.dart <fixtures dir> '
      '<resaved dir>',
    );
    exitCode = 64;
    return;
  }
  final Directory dir = Directory(args[0]);
  final String resaved = args[1];
  final List<File> expectations = !dir.existsSync()
      ? <File>[]
      : (dir
            .listSync()
            .whereType<File>()
            .where((File f) => f.path.endsWith('.expected.json'))
            .toList()
          ..sort((File a, File b) => a.path.compareTo(b.path)));
  if (expectations.isEmpty) {
    stderr.writeln('Nothing to compare: no .expected.json in ${dir.path}.');
    exitCode = 2;
    return;
  }
  int failed = 0;
  for (final File file in expectations) {
    final String name = _basename(
      file.path,
    ).replaceFirst(RegExp(r'\.expected\.json$'), '');
    List<String> messages;
    try {
      messages = _compareFixture(
        name,
        _readExpected(file),
        File('$resaved/$name.xlsx'),
      );
    } on Exception catch (e) {
      messages = <String>['could not compare $name: $e'];
    }
    if (messages.isEmpty) {
      stdout.writeln('ok    $name');
    } else {
      failed++;
      stdout.writeln('FAIL  $name');
      messages.map((String m) => '      $m').forEach(stdout.writeln);
    }
  }
  stdout.writeln(
    failed == 0
        ? 'All ${expectations.length} re-saved fixtures match.'
        : '$failed of ${expectations.length} re-saved fixtures differ.',
  );
  exitCode = failed == 0 ? 0 : 1;
}

/// The mismatches of the re-saved workbook [file] of fixture [name] against
/// its [expected] sheets.
List<String> _compareFixture(
  String name,
  Map<String, List<List<Object?>>> expected,
  File file,
) {
  if (!file.existsSync()) return <String>['missing ${file.path}'];
  final XlsxReader reader;
  try {
    reader = XlsxReader(file.readAsBytesSync());
  } on XlsxReadException catch (e) {
    return <String>['the reader refused ${file.path}: $e'];
  } on Exception catch (e) {
    return <String>['could not read ${file.path}: $e'];
  }
  final List<String> messages = <String>[];
  final Set<int> matched = <int>{};
  expected.forEach((String sheet, List<List<Object?>> rows) {
    final String decoded = decodeXstring(sheet);
    final int index = reader.sheets.indexWhere(
      (XlsxReadSheet s) => s.name == sheet,
    );
    final int found = index >= 0
        ? index
        : reader.sheets.indexWhere((XlsxReadSheet s) => s.name == decoded);
    if (found < 0) {
      messages.add('sheet "$sheet" is missing from the re-save');
      return;
    }
    matched.add(found);
    if (index < 0) {
      messages.add(
        'note: the reader named sheet "$sheet" "${reader.sheets[found].name}"',
      );
    }
    messages.addAll(<String>[
      for (final String m in compareReadSheet(
        rows,
        reader.rowsAt(found),
        date1904: reader.date1904,
        allowedValues: allowedValuesFor(name, sheet),
      ))
        '$sheet!$m',
    ]);
  });
  for (final XlsxReadSheet sheet in reader.sheets) {
    if (!matched.contains(sheet.index)) {
      messages.add('unexpected sheet "${sheet.name}" in the re-save');
    }
  }
  final Map<XlsxWarningCode, String> allowed =
      resaveAllowedWarnings[name] ?? const <XlsxWarningCode, String>{};
  for (final XlsxWarning warning in reader.warnings) {
    if (!allowed.containsKey(warning.code)) {
      messages.add('warning ${warning.code.name}: $warning');
    }
  }
  // The "note:" line explains a sheet name; it is not a mismatch by itself.
  return messages.every((String m) => m.startsWith('note: '))
      ? <String>[]
      : messages;
}

String _basename(String path) =>
    path.substring(path.replaceAll(r'\', '/').lastIndexOf('/') + 1);

/// The sheets of the `.expected.json` [file], typed for `compareReadSheet`.
Map<String, List<List<Object?>>> _readExpected(File file) {
  final Map<String, Object?> json =
      jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  return <String, List<List<Object?>>>{
    for (final MapEntry<String, Object?> sheet in json.entries)
      sheet.key: <List<Object?>>[
        for (final Object? row in sheet.value as List<Object?>)
          row as List<Object?>,
      ],
  };
}
