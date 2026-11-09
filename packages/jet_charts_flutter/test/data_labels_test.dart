// The owner's J3 gallery check: in `column_data_labels` the label 18 of
// North, Q2 (axis maximum 20) went inside its bar, dark grey on dark blue,
// at the gallery's 360 by 216. Laid out with FlutterTextMeasurer in Roboto
// (test/fonts/), which loads with `dart:io`, so the file is VM only.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_flutter/jet_charts_flutter.dart';

import 'support/charts.dart';
import 'support/fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadTestFonts);

  for (final ChartSize size in const <ChartSize>[
    ChartSize(360, 240),
    ChartSize(360, 216),
  ]) {
    test('column_data_labels at ${size.width.toInt()} by '
        '${size.height.toInt()} puts 18 above its bar', () {
      final FlutterTextMeasurer measurer = FlutterTextMeasurer();
      addTearDown(measurer.dispose);
      final Chart chart = goldenCharts()
          .firstWhere(
            ((String, Chart, ChartSize) g) => g.$1 == 'column_data_labels',
          )
          .$2;
      final ChartLayout layout = layoutChart(
        chart,
        theme: robotoOfficeTheme,
        size: size,
        measurer: measurer,
      );
      final List<ChartPrimitive> flat = <ChartPrimitive>[
        for (final ChartPrimitive p in layout.primitives)
          ...(p is ClipPrimitive ? p.children : <ChartPrimitive>[p]),
      ];
      final RectPrimitive bar =
          flat.firstWhere((ChartPrimitive p) => p.id == 'series/0/bar/1')
              as RectPrimitive;
      final TextPrimitive label =
          flat.firstWhere((ChartPrimitive p) => p.id == 'label/0/1')
              as TextPrimitive;
      expect(label.text, '18');
      expect(
        label.rect.bottom,
        closeTo(bar.rect.top - robotoOfficeTheme.spacing.labelGap, 1e-9),
      );
      expect(label.style, robotoOfficeTheme.dataLabels);
      expect(findOverlaps(layout.primitives, size), isEmpty);
    });
  }
}
