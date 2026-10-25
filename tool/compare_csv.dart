/// Compares LibreOffice's CSV export of every fixture with its expected
/// values.
///
/// ```bash
/// dart run tool/compare_csv.dart build/fixtures
/// ```
///
/// For every `<name>.expected.json` in the directory (written by
/// `tool/write_fixtures.dart`) it reads `<name>-<sheet>.csv` for each sheet
/// and compares it on raw values with `compareSheet` from
/// `tool/src/csv_compare.dart`, whose library comment states the contract.
/// A one-sheet workbook may also be exported as `<name>.csv`. A sheet name
/// that holds an `_xHHHH_` escape may be decoded by the reader (see
/// `decodeXstring`), so `<name>-<decoded sheet>.csv` is accepted too, with a
/// note naming the decoded name. It prints
/// every mismatch and exits with 1 on any, or 2 when there is nothing to
/// compare. A `.xlsx` with no `.expected.json` is a mismatch
/// (`no expectations for <name>.xlsx`), not skipped.
///
/// The CI job exports the CSV files with LibreOffice headless:
///
/// ```bash
/// LC_ALL=C.UTF-8 soffice --headless \
///   --convert-to 'csv:Text - txt - csv (StarCalc):44,34,UTF8,1,,0,false,true,false,false,false,-1' \
///   --outdir build/fixtures build/fixtures/*.xlsx
/// ```
///
/// The filter options are positional tokens, as LibreOffice's help page
/// "CSV Filter Options" documents them (LibreOffice 7.2 or later, for the
/// last token):
///
/// 1. `44`: comma as the field separator.
/// 2. `34`: `"` as the text delimiter.
/// 3. `UTF8`: the character set is UTF-8 (`decodeCsv` rejects anything else).
/// 4. `1`: first line to read (import only).
/// 5. empty: column formats (import only).
/// 6. `0`: language, the system default. `LC_ALL=C.UTF-8` makes that en-US,
///    whose date text `compareSheet` reads; a Turkish or German locale would
///    print `24.10.2026`.
/// 7. `false`: do not quote every text cell, only those that need it.
/// 8. `true`: detect special numbers (import only).
/// 9. `false`: **do not** save cell contents as shown, so a number is
///    written at full precision without its number format (`1234.5`, not
///    `1,234.50`). LibreOffice still writes a date-formatted number as date
///    text in its edit form (`10/24/2026 13:45:00` in en-US), a percent as
///    `123450%` and an elapsed time as `29628:00:00`, which `compareSheet`
///    turns back into numbers.
/// 10. `false`: write formula results, not formula text.
/// 11. `false`: do not remove spaces (import only).
/// 12. `-1`: export every sheet, each to its own `<name>-<sheet>.csv`.
library;

import 'dart:convert';
import 'dart:io';

import 'src/csv_compare.dart';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run tool/compare_csv.dart <dir>');
    exitCode = 64;
    return;
  }
  final Directory dir = Directory(args.single);
  final List<File> expectations = !dir.existsSync()
      ? <File>[]
      : (dir
            .listSync()
            .whereType<File>()
            .where((File f) => f.path.endsWith('.expected.json'))
            .toList()
          ..sort((File a, File b) => a.path.compareTo(b.path)));
  final List<String> unexpected = xlsxWithoutExpectations(<String>[
    for (final File f
        in dir.existsSync() ? dir.listSync().whereType<File>() : <File>[])
      _basename(f.path),
  ]);
  int mismatches = 0;
  for (final String message in unexpected) {
    stdout.writeln('FAIL  $message');
    mismatches++;
  }
  if (expectations.isEmpty) {
    stderr.writeln('No .expected.json files in ${dir.path}.');
    exitCode = 2;
    return;
  }
  for (final File file in expectations) {
    final String name = _basename(
      file.path,
    ).replaceFirst(RegExp(r'\.expected\.json$'), '');
    final Map<String, List<List<Object?>>> sheets = _readExpected(file);
    sheets.forEach((String sheet, List<List<Object?>> rows) {
      File csv = File('${dir.path}/$name-$sheet.csv');
      final String decoded = decodeXstring(sheet);
      if (!csv.existsSync() && decoded != sheet) {
        final File renamed = File('${dir.path}/$name-$decoded.csv');
        if (renamed.existsSync()) {
          stdout.writeln(
            'note  $name / $sheet: the reader named the sheet "$decoded"',
          );
          csv = renamed;
        }
      }
      if (!csv.existsSync() && sheets.length == 1) {
        csv = File('${dir.path}/$name.csv');
      }
      final List<String> messages = csv.existsSync()
          ? compareSheet(rows, decodeCsv(csv.readAsBytesSync()))
          : <String>['missing ${dir.path}/$name-$sheet.csv'];
      if (messages.isEmpty) {
        stdout.writeln('ok    $name / $sheet');
      } else {
        mismatches += messages.length;
        stdout.writeln('FAIL  $name / $sheet');
        for (final String message in messages) {
          stdout.writeln('      $message');
        }
      }
    });
  }
  if (mismatches > 0) {
    stdout.writeln('$mismatches mismatch(es).');
    exitCode = 1;
  } else {
    stdout.writeln('All sheets match.');
  }
}

String _basename(String path) =>
    path.substring(path.replaceAll(r'\', '/').lastIndexOf('/') + 1);

/// The sheets of the `.expected.json` [file], typed for `compareSheet`.
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
