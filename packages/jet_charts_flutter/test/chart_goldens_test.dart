// Golden images of the gallery's charts painted by ChartLayoutPainter.
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

void main() {
  setUpAll(loadTestFonts);

  for (final (String name, Chart _, ChartSize _) in goldenCharts()) {
    testWidgets(name, (WidgetTester tester) async {
      final FlutterTextMeasurer measurer = FlutterTextMeasurer();
      addTearDown(measurer.dispose);
      final (String _, ChartSize size, ChartLayout layout) = galleryForGoldens(
        measurer,
      ).firstWhere(((String, ChartSize, ChartLayout) g) => g.$1 == name);
      expect(findOverlaps(layout.primitives, size), isEmpty);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              child: CustomPaint(
                size: Size(size.width, size.height),
                painter: ChartLayoutPainter(
                  primitives: layout.primitives,
                  measurer: measurer,
                ),
              ),
            ),
          ),
        ),
      );
      await expectLater(
        find.byType(RepaintBoundary).first,
        matchesGoldenFile('goldens/$name.png'),
      );
    });
  }
}
