// The core's layout fuzz, seeds 1 to 4 with 100 cases each, laid out with
// FlutterTextMeasurer in the platform's default font: flutter_test's test font
// on the VM (every glyph one em square), Chrome's own fallback in a browser.
// test/measurer_fuzz_roboto_test.dart runs the same cases in Roboto (VM only).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_flutter/jet_charts_flutter.dart';

import 'support/measurer_fuzz.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the check', () {
    late FlutterTextMeasurer measurer;
    final ChartTextStyle style = ChartTheme.office.axisLabels;
    const ChartSize size = ChartSize(200, 100);

    setUp(() => measurer = FlutterTextMeasurer());
    tearDown(() => measurer.dispose());

    TextPrimitive text(String id, double left, ChartSize box) =>
        TextPrimitive(id, id, ChartRect(left, 1, box.width, box.height), style);

    test('passes texts of their painters\' size', () {
      final ChartSize a = measurer.measure('a', style);
      final ChartSize b = measurer.measure('b', style);
      expect(
        measuredLayoutProblems(
          ChartLayout(
            size: size,
            primitives: <ChartPrimitive>[text('a', 1, a), text('b', 50, b)],
          ),
          measurer,
        ),
        isEmpty,
      );
    });

    test('finds a text wider than its painter, even in a clip', () {
      final ChartSize a = measurer.measure('a', style);
      final List<String> problems = measuredLayoutProblems(
        ChartLayout(
          size: size,
          primitives: <ChartPrimitive>[
            ClipPrimitive(
              'clip',
              const ChartRect(0, 0, 200, 100),
              <ChartPrimitive>[
                text('a', 1, ChartSize(a.width + 0.02, a.height)),
              ],
            ),
          ],
        ),
        measurer,
      );
      expect(problems, hasLength(1));
      expect(problems.single, startsWith('a: text "a" has rect'));
    });

    test('reports what the core\'s check finds', () {
      final ChartSize a = measurer.measure('a', style);
      expect(
        measuredLayoutProblems(
          ChartLayout(
            size: size,
            primitives: <ChartPrimitive>[text('a', 1, a), text('b', 1, a)],
          ),
          measurer,
        ),
        isNotEmpty,
      );
    });
  });

  measurerFuzzTests('default font');
}
