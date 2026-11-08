/// The automatic value scale against the owner's runs of Excel for Mac
/// (2026-11-08, `tr-TR`).
///
/// The first run (`axis_oracle.tr-TR.csv`, 60 rows) recorded no plot length,
/// so its interval limit stays a stand-in: 9 at a chart height of 150, 10
/// above.
///
/// The full run (`axis_oracle_full.tr-TR.csv`, 239 rows) recorded the plot
/// area's inside box, so every row is checked with `excelMaxIntervals` at
/// Excel's own plot length (the plot height of a column, line or area chart,
/// the plot width of a bar chart) and the case's font size: min and max
/// exactly, and the major unit. The rule takes the tick labels' font size,
/// as the layout passes `theme.axisLabels.size`, and no measured width, so
/// no stand-in character width is needed for Excel's labels (Excel's own
/// font metrics are not ours). A row the rule cannot meet is listed in
/// [_knownDifferences] with its reason, and in `docs/parity.md`; it is never
/// adjusted.
@TestOn('vm')
library;

import 'dart:io';

import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_core/src/scale/value_scale.dart'
    show excelMaxIntervals;
import 'package:test/test.dart';

import '../../tool/src/axis_oracle.dart';

const String _folder = 'test/fixtures/owner/axis';
const String _fullFolder = 'test/fixtures/owner/axis_full';

/// The full run's rows the rule does not meet, each with its reason.
const Map<String, String> _knownDifferences = <String, String>{
  'F05-w360-h300-f10':
      'the case fixes the minimum and the maximum both to 5; Excel keeps '
      'them and reports 5 to 5 by 0.5, an axis of no length, which cannot be '
      'drawn. The rule ignores a fixed maximum not above the minimum (step '
      '6) and gives 5 to 11 by 1, a defined picture.',
};

void main() {
  group('first run', () {
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
          for (final String text in byId[row.id]!.set.values)
            double.parse(text),
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
  });

  group('full run', () {
    final AxisFullCases cases = parseAxisFullCases(
      File('$_fullFolder/cases.json').readAsStringSync(),
    );
    final AxisFullCsv csv = readAxisFullCsv(
      cases,
      File('$_fullFolder/axis_oracle_full.tr-TR.csv').readAsStringSync(),
    );
    final Map<String, AxisFullCase> byId = <String, AxisFullCase>{
      for (final AxisFullCase kase in cases.cases) kase.id: kase,
    };

    ValueScale ruleFor(AxisFullRow row) {
      final AxisFullCase kase = byId[row.id]!;
      final bool horizontal = kase.valueAxisIsHorizontal;
      final ({double min, double max}) extent = dataExtent(<List<double?>>[
        for (final List<String> values in kase.series)
          <double?>[
            for (final String v in values) v.isEmpty ? null : double.parse(v),
          ],
      ], ChartGrouping.values.byName(kase.grouping));
      return autoValueScale(
        dataMin: extent.min,
        dataMax: extent.max,
        maxIntervals: excelMaxIntervals(
          horizontal ? row.plotWidth : row.plotHeight,
          horizontal: horizontal,
          fontSize: row.font,
        ),
        fixedMin: kase.fixedMin,
        fixedMax: kase.fixedMax,
        fixedMajorUnit: kase.fixedMajor,
        percent: kase.grouping == 'percentStacked',
      );
    }

    test('the CSV reads without problems and has every case', () {
      expect(csv.problems, isEmpty);
      expect(csv.rows, hasLength(239));
    });

    test('every known difference names a row of the run', () {
      final Set<String> ids = <String>{
        for (final AxisFullRow row in csv.rows) row.id,
      };
      expect(ids, containsAll(_knownDifferences.keys));
    });

    for (final AxisFullRow row in csv.rows) {
      final String? known = _knownDifferences[row.id];
      if (known != null) {
        test('${row.id} differs from Excel, as known: $known', () {
          final ValueScale scale = ruleFor(row);
          expect((
            scale.min,
            scale.max,
            scale.majorUnit,
          ), isNot((row.min, row.max, row.major)));
        });
        continue;
      }
      test('${row.id} matches Excel', () {
        final ValueScale scale = ruleFor(row);
        expect(
          (scale.min, scale.max, scale.majorUnit),
          (row.min, row.max, row.major),
        );
      });
    }
  });
}
