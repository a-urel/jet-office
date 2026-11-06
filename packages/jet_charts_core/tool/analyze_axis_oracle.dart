/// Prints what the owner's Excel results say about axis scaling.
///
/// ```bash
/// dart run packages/jet_charts_core/tool/analyze_axis_oracle.dart [folder]
/// ```
///
/// The folder defaults to this package's `test/fixtures/owner/axis`. For every
/// region of its `manifest.json` it prints, per data set, whether the minimum,
/// maximum or major unit differ across height and across font, and last the
/// answer; with no results it prints `no results`. It exits 0, or 2 on
/// unusable input: a file that does not read, or a CSV with problems, which it
/// prints.
library;

import 'dart:io';

import 'src/axis_oracle.dart';

void main(List<String> args) {
  if (args.length > 1 || (args.isNotEmpty && args.single.startsWith('-'))) {
    stderr.writeln('Usage: dart run tool/analyze_axis_oracle.dart [folder]');
    exitCode = 2;
    return;
  }
  final String folder = args.isEmpty
      ? File.fromUri(
          Platform.script.resolve('../test/fixtures/owner/axis'),
        ).path
      : args.single;
  try {
    final AxisOracleCases cases = parseAxisCases(
      File('$folder/cases.json').readAsStringSync(),
    );
    final Map<String, List<AxisSetFinding>> byRegion =
        <String, List<AxisSetFinding>>{};
    for (final AxisManifestEntry entry in parseAxisManifest(
      File('$folder/manifest.json').readAsStringSync(),
    )) {
      final AxisCsv csv = readAxisCsv(
        cases,
        File('$folder/${entry.csv}').readAsStringSync(),
      );
      if (csv.problems.isNotEmpty) {
        for (final String problem in csv.problems) {
          stderr.writeln('${entry.csv}: $problem');
        }
        exitCode = 2;
        return;
      }
      byRegion[entry.region] = analyzeAxisRows(cases, csv.rows);
    }
    stdout.write(axisOracleReport(byRegion));
  } on Exception catch (e) {
    stderr.writeln('$folder: $e');
    exitCode = 2;
  }
}
