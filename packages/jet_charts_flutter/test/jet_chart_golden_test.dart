// Golden images of JetChart's default loading, empty and error looks, and
// of a chart with its tooltip box open.
//
// Pixels differ by platform, so these run on macOS only (tag `golden`,
// decision 0016); the fonts load with `dart:io`, so the file is VM only.
// After a deliberate change: `flutter test --update-goldens --tags golden`,
// then look at every image.
@TestOn('vm')
@Tags(<String>['golden'])
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_flutter/jet_charts_flutter.dart';
import 'package:jet_charts_flutter/src/jet_chart.dart' show JetChartState;

import 'support/charts.dart';
import 'support/fonts.dart';

Future<void> _pump(WidgetTester tester, JetChart chart) async {
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            child: SizedBox(width: 360, height: 240, child: chart),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(loadTestFonts);

  testWidgets('jet_chart_loading', (WidgetTester tester) async {
    await _pump(tester, JetChart(theme: robotoOfficeTheme, loading: true));
    // A quarter of the 1.2 s pulse: the columns at opacity 0.7.
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byType(RepaintBoundary).first,
      matchesGoldenFile('goldens/jet_chart_loading.png'),
    );
  });

  testWidgets('jet_chart_empty', (WidgetTester tester) async {
    await _pump(
      tester,
      JetChart(
        theme: robotoOfficeTheme,
        chart: Chart(
          kind: ChartKind.column,
          title: const ChartTitle(text: 'Sales by quarter'),
          series: <ChartSeries>[],
        ),
      ),
    );
    await expectLater(
      find.byType(RepaintBoundary).first,
      matchesGoldenFile('goldens/jet_chart_empty.png'),
    );
  });

  testWidgets('jet_chart_error', (WidgetTester tester) async {
    await _pump(
      tester,
      JetChart(theme: robotoOfficeTheme, error: StateError('x')),
    );
    await expectLater(
      find.byType(RepaintBoundary).first,
      matchesGoldenFile('goldens/jet_chart_error.png'),
    );
  });

  testWidgets('jet_chart_tooltip', (WidgetTester tester) async {
    final Chart chart = goldenCharts()
        .firstWhere(
          ((String, Chart, ChartSize) g) => g.$1 == 'column_clustered',
        )
        .$2;
    await _pump(tester, JetChart(theme: robotoOfficeTheme, chart: chart));
    final ChartLayout layout = tester
        .state<JetChartState>(find.byType(JetChart))
        .currentLayout!;
    final ChartRect bar = layout.primitives
        .expand(
          (ChartPrimitive p) =>
              p is ClipPrimitive ? p.children : <ChartPrimitive>[p],
        )
        .whereType<RectPrimitive>()
        .firstWhere((RectPrimitive p) => p.id == 'series/1/bar/2')
        .rect;
    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(
      Offset(bar.left + bar.width / 2, bar.top + bar.height / 2),
    );
    await tester.pump();
    await expectLater(
      find.byType(RepaintBoundary).first,
      matchesGoldenFile('goldens/jet_chart_tooltip.png'),
    );
  });
}
