// The core's layout fuzz, seeds 1 to 4 with 100 cases each, laid out with
// FlutterTextMeasurer on the generator's theme with every text in Roboto
// (test/fonts/), so real glyph widths reach the layout. The fonts load with
// `dart:io`, so the file is VM only; test/measurer_fuzz_test.dart runs the
// same cases in the default font on the VM and in Chrome.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_flutter/jet_charts_flutter.dart';

import 'support/charts.dart';
import 'support/fonts.dart';
import 'support/measurer_fuzz.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadTestFonts);
  test('the text is measured in Roboto, not the test font', () {
    final FlutterTextMeasurer measurer = FlutterTextMeasurer();
    addTearDown(measurer.dispose);
    final ChartTextStyle office = ChartTheme.office.axisLabels;
    final ChartTextStyle roboto = robotoOfficeTheme.axisLabels;
    // The test font draws every glyph one em wide; Roboto's `i` is far
    // narrower.
    expect(measurer.measure('iiii', office).width, 4 * office.size);
    expect(measurer.measure('iiii', roboto).width, lessThan(2 * roboto.size));
  });

  measurerFuzzTests('Roboto', theme: robotoTheme);
}
