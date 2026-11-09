// The default state looks never draw one text over another.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_flutter/jet_charts_flutter.dart';
import 'package:jet_charts_flutter/src/states.dart' show placeMessage;

void _expectInside(Rect? r, Size size) {
  if (r == null) return;
  expect(r.left, greaterThanOrEqualTo(0));
  expect(r.top, greaterThanOrEqualTo(0));
  expect(r.right, lessThanOrEqualTo(size.width + 1e-9));
  expect(r.bottom, lessThanOrEqualTo(size.height + 1e-9));
}

void main() {
  final FlutterTextMeasurer large = FlutterTextMeasurer(
    textScaler: const TextScaler.linear(2),
  );
  final FlutterTextMeasurer normal = FlutterTextMeasurer();
  tearDownAll(() {
    large.dispose();
    normal.dispose();
  });

  for (final Size size in <Size>[const Size(160, 100), const Size(360, 40)]) {
    test('empty with a title at text scale 2 in $size does not overlap', () {
      final (Rect? title, Rect? message) = placeMessage(
        size: size,
        theme: ChartTheme.office,
        measurer: large,
        message: 'No data',
        title: 'Sales by quarter',
      );
      _expectInside(title, size);
      _expectInside(message, size);
      if (title != null && message != null) {
        expect(title.overlaps(message), isFalse);
      }
      expect(title != null || message != null, isTrue);
    });
  }

  test('the title is dropped first when both do not fit', () {
    final (Rect? title, Rect? message) = placeMessage(
      size: const Size(360, 40),
      theme: ChartTheme.office,
      measurer: large,
      message: 'No data',
      title: 'Sales by quarter',
    );
    expect(title, isNull);
    expect(message, isNotNull);
  });

  test('a message wider than the box is dropped', () {
    final (Rect? title, Rect? message) = placeMessage(
      size: const Size(60, 100),
      theme: ChartTheme.office,
      measurer: normal,
      message: 'The chart could not be shown',
    );
    expect(title, isNull);
    expect(message, isNull);
  });

  test('both show, title above, in a box that holds them', () {
    final (Rect? title, Rect? message) = placeMessage(
      size: const Size(360, 240),
      theme: ChartTheme.office,
      measurer: normal,
      message: 'No data',
      title: 'Sales by quarter',
    );
    expect(title, isNotNull);
    expect(message, isNotNull);
    expect(
      title!.bottom + ChartTheme.office.spacing.titleGap,
      lessThanOrEqualTo(message!.top),
    );
  });

  testWidgets('the empty look paints at text scale 2 in a small box', (
    WidgetTester tester,
  ) async {
    for (final Size size in <Size>[const Size(160, 100), const Size(360, 40)]) {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Center(
            child: SizedBox.fromSize(
              size: size,
              child: JetChart(
                chart: Chart(
                  kind: ChartKind.column,
                  title: const ChartTitle(text: 'Sales by quarter'),
                  series: <ChartSeries>[],
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    }
  });
}
