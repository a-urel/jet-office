// FlutterTextMeasurer measures with the TextPainter it paints with.
//
// These tests run in `flutter test`, whose default test font gives every glyph
// a box one em wide and one em high. Each expectation also holds for a real
// font: it compares sizes rather than naming them.
library;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_flutter/jet_charts_flutter.dart';

final ChartTextStyle _style = ChartTextStyle(
  fontFamily: 'Aptos Narrow',
  size: 9,
  color: ChartColor.rgb(0x595959),
);

void main() {
  late FlutterTextMeasurer measurer;

  setUp(() {
    measurer = FlutterTextMeasurer();
  });

  tearDown(() {
    measurer.dispose();
  });

  test('an empty text is zero wide and one line high', () {
    final ChartSize empty = measurer.measure('', _style);
    expect(empty.width, 0);
    expect(empty.height, greaterThan(0));
    expect(empty.height, measurer.measure('A', _style).height);
  });

  test('two lines are about twice as high as one', () {
    final double one = measurer.measure('a', _style).height;
    final double two = measurer.measure('a\nb', _style).height;
    expect(two, closeTo(2 * one, 1));
  });

  test('bold is not narrower than regular', () {
    final double regular = measurer.measure('Revenue', _style).width;
    final double bold = measurer
        .measure('Revenue', _style.copyWith(bold: true))
        .width;
    expect(regular, greaterThan(0));
    expect(bold, greaterThanOrEqualTo(regular));
  });

  test('a text scaler of 2 doubles the height', () {
    final FlutterTextMeasurer scaled = FlutterTextMeasurer(
      textScaler: const TextScaler.linear(2),
    );
    addTearDown(scaled.dispose);
    expect(scaled.textScaler, const TextScaler.linear(2));
    expect(
      scaled.measure('Revenue', _style).height,
      closeTo(2 * measurer.measure('Revenue', _style).height, 1),
    );
  });

  test('measure is the size of the painter it paints with', () {
    for (final String text in <String>['', 'Revenue', '1.234,5', 'a\nbb']) {
      final ChartSize size = measurer.measure(text, _style);
      final TextPainter painter = measurer.textPainter(text, _style);
      expect(size, ChartSize(painter.width, painter.height), reason: text);
    }
  });

  test('the painter is laid out as the dartdoc says', () {
    final ChartTextStyle style = _style.copyWith(bold: true);
    final FlutterTextMeasurer withFallback = FlutterTextMeasurer(
      fontFamilyFallback: <String>['Roboto'],
    );
    addTearDown(withFallback.dispose);
    final TextPainter painter = withFallback.textPainter('Revenue', style);
    expect(painter.textDirection, TextDirection.ltr);
    expect(painter.textAlign, TextAlign.center);
    final TextStyle textStyle = painter.text!.style!;
    expect(textStyle.fontFamily, 'Aptos Narrow');
    expect(textStyle.fontFamilyFallback, <String>['Roboto']);
    expect(textStyle.fontSize, 9);
    expect(textStyle.fontWeight, FontWeight.w700);
    expect(textStyle.color, const Color(0xFF595959));
    expect(
      measurer.textPainter('Revenue', _style).text!.style!.fontWeight,
      FontWeight.w400,
    );
  });

  test('an unknown font family measures and paints alike', () {
    final ChartTextStyle style = _style.copyWith(
      fontFamily: 'No Such Font 7f3a',
    );
    final ChartSize size = measurer.measure('Revenue', style);
    expect(size.width.isFinite, isTrue);
    expect(size.height.isFinite, isTrue);
    expect(size.width, greaterThan(0));
    final TextPainter painter = measurer.textPainter('Revenue', style);
    expect(size, ChartSize(painter.width, painter.height));
  });

  test('a second measure of the same input comes from the cache', () {
    final TextPainter first = measurer.textPainter('Revenue', _style);
    measurer.measure('Revenue', _style);
    expect(identical(measurer.textPainter('Revenue', _style), first), isTrue);
    // An equal style is the same input.
    expect(
      identical(
        measurer.textPainter('Revenue', _style.copyWith(size: 9)),
        first,
      ),
      isTrue,
    );
    expect(
      identical(
        measurer.textPainter('Revenue', _style.copyWith(bold: true)),
        first,
      ),
      isFalse,
    );
  });

  test('the least recently used painter leaves a full cache', () {
    final TextPainter first = measurer.textPainter('text 0', _style);
    for (int i = 1; i <= 2048; i++) {
      measurer.measure('text $i', _style);
    }
    expect(identical(measurer.textPainter('text 0', _style), first), isFalse);
  });

  test('using an entry keeps it in the cache', () {
    final FlutterTextMeasurer small = FlutterTextMeasurer(cacheSize: 2);
    addTearDown(small.dispose);
    final TextPainter a = small.textPainter('a', _style);
    final TextPainter b = small.textPainter('b', _style);
    small.measure('a', _style);
    small.measure('c', _style);
    expect(identical(small.textPainter('a', _style), a), isTrue);
    expect(identical(small.textPainter('b', _style), b), isFalse);
  });

  test('a cache size below one is a programmer error', () {
    expect(() => FlutterTextMeasurer(cacheSize: 0), throwsArgumentError);
  });
}
