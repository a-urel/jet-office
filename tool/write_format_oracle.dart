/// Writes the Excel oracle workbooks of the number format engine.
///
/// ```bash
/// dart run tool/write_format_oracle.dart build/format_oracle
/// ```
///
/// It reads the case list, `test/fixtures/owner/number_format/cases.json`,
/// and writes one `.xlsx` per workbook the list defines and a case names
/// (`format_oracle.xlsx`, `format_oracle_1904.xlsx`,
/// `format_oracle_invalid.xlsx`) to the directory given. The owner opens
/// them in Excel for Mac in each region and saves the CSVs, as the README
/// beside the case list says. `tool/src/format_oracle.dart` holds the case
/// format and the workbook layout.
library;

import 'dart:io';
import 'dart:typed_data';

import 'src/format_oracle.dart';

void main(List<String> args) {
  if (args.length != 1 || args.single.startsWith('-')) {
    stderr.writeln('Usage: dart run tool/write_format_oracle.dart <dir>');
    exitCode = 64;
    return;
  }
  final OracleCases cases;
  try {
    cases = parseOracleCases(File(oracleCasesPath).readAsStringSync());
  } on FormatException catch (e) {
    stderr.writeln('$oracleCasesPath: ${e.message}');
    exitCode = 65;
    return;
  }
  final Directory dir = Directory(args.single)..createSync(recursive: true);
  final Map<String, Uint8List> files = buildOracleWorkbooks(cases);
  files.forEach((String name, Uint8List bytes) {
    File('${dir.path}/$name').writeAsBytesSync(bytes);
  });
  stdout.writeln(
    'Wrote ${files.length} workbooks with ${cases.cases.length} cases to '
    '${dir.path}.',
  );
}
