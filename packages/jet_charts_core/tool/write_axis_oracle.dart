/// Writes the Excel oracle workbook of axis scaling.
///
/// ```bash
/// dart run packages/jet_charts_core/tool/write_axis_oracle.dart build/axis_oracle
/// dart run packages/jet_charts_core/tool/write_axis_oracle.dart --full build/axis_oracle_full
/// ```
///
/// It reads the case list, `test/fixtures/owner/axis/cases.json` of this
/// package wherever it is run from, and writes `axis_oracle.xlsx` to the
/// directory given. With `--full` it reads `test/fixtures/owner/axis_full/
/// cases.json` (version 2) and writes `axis_oracle_full.xlsx`.
/// `tool/axis_oracle/run_excel.applescript` then reads the axes from Excel
/// for Mac, as `TALIMATLAR.md` beside the case list says.
/// `tool/src/axis_oracle.dart` holds the workbook layout.
library;

import 'dart:io';
import 'dart:typed_data';

import 'src/axis_oracle.dart';

void main(List<String> args) {
  final bool full = args.isNotEmpty && args.first == '--full';
  final List<String> rest = full ? args.sublist(1) : args;
  if (rest.length != 1 || rest.single.startsWith('-')) {
    stderr.writeln(
      'Usage: dart run tool/write_axis_oracle.dart [--full] <dir>',
    );
    exitCode = 2;
    return;
  }
  final File source = File.fromUri(
    Platform.script.resolve(
      '../test/fixtures/owner/${full ? 'axis_full' : 'axis'}/cases.json',
    ),
  );
  final Uint8List bytes;
  final int charts;
  try {
    final String text = source.readAsStringSync();
    if (full) {
      final AxisFullCases cases = parseAxisFullCases(text);
      bytes = buildAxisFullWorkbook(cases);
      charts = cases.cases.length;
    } else {
      final AxisOracleCases cases = parseAxisCases(text);
      bytes = buildAxisWorkbook(cases);
      charts = cases.cases.length;
    }
  } on Exception catch (e) {
    stderr.writeln('${source.path}: $e');
    exitCode = 2;
    return;
  }
  final String name = full ? axisFullWorkbookName : axisWorkbookName;
  final Directory dir = Directory(rest.single)..createSync(recursive: true);
  File('${dir.path}/$name').writeAsBytesSync(bytes);
  stdout.writeln('Wrote $name with $charts charts to ${dir.path}.');
}
