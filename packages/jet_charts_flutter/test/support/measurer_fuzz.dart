/// The core's layout fuzz (`packages/jet_charts_core/test/layout/fuzz_test.dart`)
/// run with [FlutterTextMeasurer] in place of its fixed-width measurer.
///
/// The cases and the check come from the core's own generator, `chart_fuzz.dart`,
/// copied unchanged into this folder: Flutter's browser tests compile only
/// files under this package's `test/`, so a relative import of the core's file
/// fails in Chrome. `test/fuzz_copy_test.dart` keeps the copy equal to it.
library;

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_flutter/jet_charts_flutter.dart';

import 'chart_fuzz.dart';

/// The seeds the core's gate fuzzes, each with [measurerFuzzCases] cases.
const List<int> measurerFuzzSeeds = <int>[1, 2, 3, 4];

/// The cases per seed in the core's gate.
const int measurerFuzzCases = 100;

/// How far a text's rectangle may differ from its painter's size.
const double _sizeTolerance = 0.01;

/// How many texts [measuredLayoutProblems] compared with their painters, so
/// a fuzz run can prove it measured some.
int checkedTexts = 0;

/// Every broken promise of case [index] of [seed] laid out with [measurer],
/// on the generator's theme passed through [theme]: a throw from
/// `layoutChart` or from painting, what the core's `layoutProblems` finds, or
/// a text whose rectangle is not the size of the painter that draws it.
List<String> measurerFuzzProblems(
  int seed,
  int index,
  FlutterTextMeasurer measurer, {
  ChartTheme Function(ChartTheme theme)? theme,
}) {
  final LayoutFuzzCase c = layoutFuzzCase(seed, index);
  final ChartLayout layout;
  try {
    layout = layoutChart(
      c.chart,
      theme: theme == null ? c.theme : theme(c.theme),
      size: c.size,
      measurer: measurer,
      locale: c.locale,
    );
  } catch (e, stack) {
    final String top = stack.toString().split('\n').take(6).join('\n');
    return <String>['layoutChart threw ${e.runtimeType}: $e\n$top'];
  }
  return measuredLayoutProblems(layout, measurer);
}

/// Every broken promise of [layout], measured by [measurer]: what the core's
/// `layoutProblems` finds, a text whose rectangle is not within 0.01 of the
/// size of the painter that draws it, or a throw from painting into a
/// `PictureRecorder`.
List<String> measuredLayoutProblems(
  ChartLayout layout,
  FlutterTextMeasurer measurer,
) {
  final List<String> problems = <String>[...layoutProblems(layout)];

  void texts(List<ChartPrimitive> list) {
    for (final ChartPrimitive p in list) {
      switch (p) {
        case TextPrimitive():
          checkedTexts++;
          final ui.Size painted = measurer.textPainter(p.text, p.style).size;
          if ((painted.width - p.rect.width).abs() > _sizeTolerance ||
              (painted.height - p.rect.height).abs() > _sizeTolerance) {
            problems.add(
              '${p.id}: text "${p.text}" has rect ${p.rect}, painter '
              '${painted.width} x ${painted.height}',
            );
          }
        case ClipPrimitive():
          texts(p.children);
        case RectPrimitive() || PathPrimitive() || ArcPrimitive():
          break;
      }
    }
  }

  texts(layout.primitives);

  final ui.PictureRecorder recorder = ui.PictureRecorder();
  try {
    paintChartPrimitives(ui.Canvas(recorder), layout.primitives, measurer);
  } catch (e) {
    problems.add('painting threw ${e.runtimeType}: $e');
  } finally {
    recorder.endRecording().dispose();
  }
  return problems;
}

/// Registers one test per seed that runs [measurerFuzzCases] cases with a
/// fresh [FlutterTextMeasurer] and fails with `seed <s> case <i>: <problem>`
/// lines and the chart.
void measurerFuzzTests(
  String font, {
  ChartTheme Function(ChartTheme theme)? theme,
}) {
  for (final int seed in measurerFuzzSeeds) {
    test('seed $seed, $font: $measurerFuzzCases charts lay out with the '
        'Flutter measurer without overlap, inside the size, and paint', () {
      final FlutterTextMeasurer measurer = FlutterTextMeasurer();
      addTearDown(measurer.dispose);
      final List<String> failures = <String>[];
      final int textsBefore = checkedTexts;
      for (int i = 0; i < measurerFuzzCases; i++) {
        final List<String> problems = measurerFuzzProblems(
          seed,
          i,
          measurer,
          theme: theme,
        );
        if (problems.isNotEmpty) {
          failures.add(
            'seed $seed case $i: ${problems.join('\n  ')}\n'
            '${layoutFuzzCase(seed, i).describe()}',
          );
        }
      }
      expect(failures, isEmpty, reason: failures.take(3).join('\n'));
      expect(checkedTexts - textsBefore, greaterThan(measurerFuzzCases));
    });
  }
}
