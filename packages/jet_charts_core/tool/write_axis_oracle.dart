/// Writes the Excel oracle workbook of axis scaling.
///
/// ```bash
/// dart run packages/jet_charts_core/tool/write_axis_oracle.dart build/axis_oracle
/// ```
///
/// It reads the case list, `test/fixtures/owner/axis/cases.json` of this
/// package wherever it is run from, and writes `axis_oracle.xlsx` to the
/// directory given. `tool/axis_oracle/run_excel.applescript` then reads the
/// axes from Excel for Mac, as `TALIMATLAR.md` beside the case list says.
/// `tool/src/axis_oracle.dart` holds the workbook layout.
library;

import 'dart:io';

import 'src/axis_oracle.dart';

void main(List<String> args) {
  if (args.length != 1 || args.single.startsWith('-')) {
    stderr.writeln('Usage: dart run tool/write_axis_oracle.dart <dir>');
    exitCode = 2;
    return;
  }
  final File source = File.fromUri(
    Platform.script.resolve('../test/fixtures/owner/axis/cases.json'),
  );
  final AxisOracleCases cases;
  try {
    cases = parseAxisCases(source.readAsStringSync());
  } on Exception catch (e) {
    stderr.writeln('${source.path}: $e');
    exitCode = 2;
    return;
  }
  final Directory dir = Directory(args.single)..createSync(recursive: true);
  File(
    '${dir.path}/$axisWorkbookName',
  ).writeAsBytesSync(buildAxisWorkbook(cases));
  stdout.writeln(
    'Wrote $axisWorkbookName with ${cases.cases.length} charts to ${dir.path}.',
  );
}
