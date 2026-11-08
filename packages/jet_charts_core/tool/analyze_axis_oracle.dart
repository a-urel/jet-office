/// Prints what the owner's Excel results say about axis scaling.
///
/// ```bash
/// dart run packages/jet_charts_core/tool/analyze_axis_oracle.dart [folder]
/// dart run packages/jet_charts_core/tool/analyze_axis_oracle.dart --full [folder]
/// ```
///
/// The folder defaults to this package's `test/fixtures/owner/axis`. For every
/// region of its `manifest.json` it prints, per data set, whether the minimum,
/// maximum or major unit differ across height and across font, and last the
/// answer; with no results it prints `no results`.
///
/// With `--full` the folder defaults to `test/fixtures/owner/axis_full`, and
/// it prints per group what the data shows (`axisFullReport` in
/// `tool/src/axis_oracle.dart`): for L and B the plot length at which the
/// unit coarsens, for W whether width changed anything, for M, G and F
/// Excel's scale beside the fitted rule's, and for C the label spacing
/// per width.
///
/// It exits 0, or 2 on unusable input: a file that does not read, or a CSV
/// with problems, which it prints.
library;

import 'dart:io';

import 'src/axis_oracle.dart';

void main(List<String> args) {
  final bool full = args.isNotEmpty && args.first == '--full';
  final List<String> rest = full ? args.sublist(1) : args;
  if (rest.length > 1 || (rest.isNotEmpty && rest.single.startsWith('-'))) {
    stderr.writeln(
      'Usage: dart run tool/analyze_axis_oracle.dart [--full] [folder]',
    );
    exitCode = 2;
    return;
  }
  final String folder = rest.isEmpty
      ? File.fromUri(
          Platform.script.resolve(
            '../test/fixtures/owner/${full ? 'axis_full' : 'axis'}',
          ),
        ).path
      : rest.single;
  try {
    final String casesText = File('$folder/cases.json').readAsStringSync();
    final List<AxisManifestEntry> manifest = parseAxisManifest(
      File('$folder/manifest.json').readAsStringSync(),
      csvStem: full ? axisFullCsvStem : 'axis_oracle',
    );
    bool usable(String csv, List<String> problems) {
      for (final String problem in problems) {
        stderr.writeln('$csv: $problem');
      }
      if (problems.isNotEmpty) exitCode = 2;
      return problems.isEmpty;
    }

    if (full) {
      final AxisFullCases cases = parseAxisFullCases(casesText);
      final Map<String, List<AxisFullRow>> byRegion =
          <String, List<AxisFullRow>>{};
      for (final AxisManifestEntry entry in manifest) {
        final AxisFullCsv csv = readAxisFullCsv(
          cases,
          File('$folder/${entry.csv}').readAsStringSync(),
        );
        if (!usable(entry.csv, csv.problems)) return;
        byRegion[entry.region] = csv.rows;
      }
      stdout.write(axisFullReport(cases, byRegion));
      return;
    }
    final AxisOracleCases cases = parseAxisCases(casesText);
    final Map<String, List<AxisSetFinding>> byRegion =
        <String, List<AxisSetFinding>>{};
    for (final AxisManifestEntry entry in manifest) {
      final AxisCsv csv = readAxisCsv(
        cases,
        File('$folder/${entry.csv}').readAsStringSync(),
      );
      if (!usable(entry.csv, csv.problems)) return;
      byRegion[entry.region] = analyzeAxisRows(cases, csv.rows);
    }
    stdout.write(axisOracleReport(byRegion));
  } on Exception catch (e) {
    stderr.writeln('$folder: $e');
    exitCode = 2;
  }
}
