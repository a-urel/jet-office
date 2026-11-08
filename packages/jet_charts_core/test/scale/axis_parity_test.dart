/// The automatic value scale against the owner's run of Excel for Mac
/// (2026-11-08, `tr-TR`): every row of `axis_oracle.tr-TR.csv` must come out
/// as Excel reported it.
///
/// The CSV has no plot length, so the interval limit is a stand-in: 9 at a
/// chart height of 150, 10 above (Task 11 replaces it).
@TestOn('vm')
library;

import 'dart:io';

import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:test/test.dart';

import '../../tool/src/axis_oracle.dart';

const String _folder = 'test/fixtures/owner/axis';

void main() {
  final AxisOracleCases cases = parseAxisCases(
    File('$_folder/cases.json').readAsStringSync(),
  );
  final AxisCsv csv = readAxisCsv(
    cases,
    File('$_folder/axis_oracle.tr-TR.csv').readAsStringSync(),
  );
  final Map<String, AxisCase> byId = <String, AxisCase>{
    for (final AxisCase kase in cases.cases) kase.id: kase,
  };

  test('the CSV reads without problems and has every case', () {
    expect(csv.problems, isEmpty);
    expect(csv.rows, hasLength(60));
  });

  for (final AxisRow row in csv.rows) {
    test('${row.id} matches Excel', () {
      final List<double> values = <double>[
        for (final String text in byId[row.id]!.set.values) double.parse(text),
      ];
      final ValueScale scale = autoValueScale(
        dataMin: values.reduce((double a, double b) => a < b ? a : b),
        dataMax: values.reduce((double a, double b) => a > b ? a : b),
        maxIntervals: row.height <= 150 ? 9 : 10,
      );
      expect(
        (scale.min, scale.max, scale.majorUnit),
        (row.min, row.max, row.major),
      );
    });
  }
}
