// Golden images of JetChart's default loading, empty and error looks.
//
// Pixels differ by platform, so these run on macOS only (tag `golden`,
// decision 0016); the fonts load with `dart:io`, so the file is VM only.
// After a deliberate change: `flutter test --update-goldens --tags golden`,
// then look at every image.
@TestOn('vm')
@Tags(<String>['golden'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_flutter/jet_charts_flutter.dart';

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
}
